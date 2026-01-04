/**
 * Driver Document Review Lambda
 *
 * Handles admin document review workflow:
 * 1. Approve or reject uploaded documents
 * 2. Update document status in database
 * 3. Update driver_profiles when all docs approved
 * 4. Send notifications to drivers (future enhancement)
 *
 * API Route:
 * - PUT /admin/documents/{documentId}/review
 */

const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
const { Client } = require('pg');

const ENVIRONMENT = process.env.ENVIRONMENT || 'dev';
const RDS_PROXY_ENDPOINT = process.env.RDS_PROXY_ENDPOINT;
const RDS_SECRET_ARN = process.env.RDS_SECRET_ARN;
const DATABASE_NAME = process.env.DATABASE_NAME || 'vehealth';
const LOG_LEVEL = process.env.LOG_LEVEL || 'INFO';

const secretsClient = new SecretsManagerClient({ region: process.env.AWS_REGION || 'us-east-2' });

// Database connection pool
let dbClient = null;

/**
 * Get database credentials from Secrets Manager
 */
async function getDbCredentials() {
    try {
        const response = await secretsClient.send(new GetSecretValueCommand({
            SecretId: RDS_SECRET_ARN
        }));
        return JSON.parse(response.SecretString);
    } catch (error) {
        console.error('Error fetching DB credentials:', error);
        throw error;
    }
}

/**
 * Get or create database connection
 */
async function getDbConnection() {
    if (!dbClient || dbClient._ending) {
        const credentials = await getDbCredentials();

        dbClient = new Client({
            host: RDS_PROXY_ENDPOINT,
            port: 5432,
            database: DATABASE_NAME,
            user: credentials.username,
            password: credentials.password,
            ssl: { rejectUnauthorized: false },
            connectionTimeoutMillis: 5000,
            query_timeout: 10000,
        });

        await dbClient.connect();
        console.log('Database connection established');
    }

    return dbClient;
}

/**
 * Extract user info from JWT claims
 */
function extractUserFromEvent(event) {
    const claims = event.requestContext?.authorizer?.jwt?.claims;
    if (!claims) {
        throw new Error('Missing JWT claims');
    }

    return {
        userId: claims.sub,
        email: claims.email,
        roles: claims['custom:roles'] ? claims['custom:roles'].split(',') : [],
        isAdmin: claims['custom:roles']?.includes('admin') || false,
    };
}

/**
 * Update document status
 */
async function updateDocumentStatus(db, documentId, reviewData) {
    const query = `
        UPDATE driver_documents
        SET
            status = $1,
            verified_at = CASE WHEN $1 IN ('approved', 'rejected') THEN NOW() ELSE verified_at END,
            verified_by = $2,
            rejection_reason = $3,
            notes = $4,
            document_number = COALESCE($5, document_number),
            issuing_authority = COALESCE($6, issuing_authority),
            issue_date = COALESCE($7, issue_date),
            expiry_date = COALESCE($8, expiry_date),
            updated_at = NOW()
        WHERE id = $9
        RETURNING
            id, driver_id, document_type, status, verified_at,
            rejection_reason, notes, created_at, updated_at
    `;

    const values = [
        reviewData.status,
        reviewData.reviewerId,
        reviewData.rejectionReason || null,
        reviewData.notes || null,
        reviewData.documentNumber || null,
        reviewData.issuingAuthority || null,
        reviewData.issueDate || null,
        reviewData.expiryDate || null,
        documentId
    ];

    const result = await db.query(query, values);

    if (result.rows.length === 0) {
        throw new Error('Document not found');
    }

    return result.rows[0];
}

/**
 * Update driver_profiles with document references
 */
async function updateDriverProfile(db, driverId, documentType, documentId) {
    // Map document types to driver_profiles columns
    const columnMap = {
        'license': 'license_document_id',
        'insurance': 'insurance_document_id',
        'registration': 'registration_document_id',
        'inspection': 'inspection_document_id',
        'profile_photo': 'profile_photo_document_id',
    };

    const column = columnMap[documentType];

    if (!column) {
        console.log(`No profile column for document type: ${documentType}`);
        return;
    }

    const query = `
        UPDATE driver_profiles
        SET ${column} = $1, updated_at = NOW()
        WHERE user_id = $2
    `;

    await db.query(query, [documentId, driverId]);
    console.log(`Updated driver_profiles.${column} for driver ${driverId}`);
}

/**
 * Check if all required documents are approved and update driver profile
 */
async function checkAllDocumentsApproved(db, driverId) {
    const requiredDocs = ['license', 'insurance', 'registration', 'profile_photo'];

    // Check if all required documents are approved
    const query = `
        SELECT document_type, status
        FROM driver_documents
        WHERE driver_id = $1
          AND document_type = ANY($2)
          AND status = 'approved'
    `;

    const result = await db.query(query, [driverId, requiredDocs]);

    const approvedDocs = result.rows.map(r => r.document_type);
    const allApproved = requiredDocs.every(doc => approvedDocs.includes(doc));

    if (allApproved) {
        // Update driver_profiles to mark documents as complete
        const updateQuery = `
            UPDATE driver_profiles
            SET
                documents_complete = TRUE,
                documents_verified_at = NOW(),
                status = CASE
                    WHEN status = 'pending_documents' THEN 'active'
                    ELSE status
                END,
                updated_at = NOW()
            WHERE user_id = $1
            RETURNING documents_complete, documents_verified_at, status
        `;

        const updateResult = await db.query(updateQuery, [driverId]);
        console.log(`All documents approved for driver ${driverId}. Profile updated:`, updateResult.rows[0]);

        return {
            allDocumentsApproved: true,
            profileUpdated: true,
            profileStatus: updateResult.rows[0]
        };
    }

    return {
        allDocumentsApproved: false,
        profileUpdated: false,
        missingDocuments: requiredDocs.filter(doc => !approvedDocs.includes(doc))
    };
}

/**
 * Handle PUT /admin/documents/{documentId}/review
 */
async function handleReviewDocument(event, user) {
    // Check if user is admin
    if (!user.isAdmin) {
        return {
            statusCode: 403,
            body: JSON.stringify({
                error: 'Forbidden: Admin access required'
            })
        };
    }

    const documentId = event.pathParameters?.documentId;

    if (!documentId) {
        return {
            statusCode: 400,
            body: JSON.stringify({ error: 'Missing documentId' })
        };
    }

    const body = JSON.parse(event.body || '{}');
    const { status, rejectionReason, notes, documentNumber, issuingAuthority, issueDate, expiryDate } = body;

    // Validate status
    const validStatuses = ['approved', 'rejected', 'pending', 'processing'];
    if (!status || !validStatuses.includes(status)) {
        return {
            statusCode: 400,
            body: JSON.stringify({
                error: `Invalid status. Must be one of: ${validStatuses.join(', ')}`
            })
        };
    }

    // Validate rejection reason if status is rejected
    if (status === 'rejected' && !rejectionReason) {
        return {
            statusCode: 400,
            body: JSON.stringify({
                error: 'rejectionReason is required when status is rejected'
            })
        };
    }

    const db = await getDbConnection();

    try {
        await db.query('BEGIN');

        // Update document status
        const document = await updateDocumentStatus(db, documentId, {
            status,
            reviewerId: user.userId,
            rejectionReason,
            notes,
            documentNumber,
            issuingAuthority,
            issueDate,
            expiryDate
        });

        // If approved, update driver_profiles with document reference
        if (status === 'approved') {
            await updateDriverProfile(db, document.driver_id, document.document_type, documentId);

            // Check if all required documents are now approved
            const verificationStatus = await checkAllDocumentsApproved(db, document.driver_id);

            await db.query('COMMIT');

            return {
                statusCode: 200,
                body: JSON.stringify({
                    message: 'Document reviewed successfully',
                    document,
                    verificationStatus
                })
            };
        }

        await db.query('COMMIT');

        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Document reviewed successfully',
                document
            })
        };

    } catch (error) {
        await db.query('ROLLBACK');
        throw error;
    }
}

/**
 * Main Lambda handler
 */
exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event, null, 2));

    try {
        // Extract user from JWT
        const user = extractUserFromEvent(event);

        // Route based on HTTP method and path
        const method = event.requestContext.http.method;
        const path = event.rawPath || event.requestContext.http.path;

        let response;

        if (method === 'PUT' && path.match(/\/admin\/documents\/[^/]+\/review$/)) {
            response = await handleReviewDocument(event, user);
        } else {
            response = {
                statusCode: 404,
                body: JSON.stringify({ error: 'Not found' })
            };
        }

        return {
            ...response,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
            }
        };

    } catch (error) {
        console.error('Error:', error);

        return {
            statusCode: 500,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
            },
            body: JSON.stringify({
                error: 'Internal server error',
                message: LOG_LEVEL === 'DEBUG' ? error.message : undefined
            })
        };
    }
};
