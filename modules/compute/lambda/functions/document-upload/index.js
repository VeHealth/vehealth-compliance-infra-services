/**
 * Driver Document Upload Lambda
 *
 * Handles document upload requests by:
 * 1. Generating presigned S3 URL for direct upload
 * 2. Creating metadata record in driver_documents table
 * 3. Returning upload URL and document ID to client
 *
 * API Routes:
 * - POST /drivers/documents/upload - Generate presigned URL
 * - GET /drivers/documents - List driver documents
 * - GET /drivers/documents/{documentId} - Get document details
 * - GET /drivers/{driverId}/verification - Get verification status
 */

const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
const { Client } = require('pg');

const ENVIRONMENT = process.env.ENVIRONMENT || 'dev';
const DOCUMENTS_BUCKET = process.env.DOCUMENTS_BUCKET || `vehealth-${ENVIRONMENT}-driver-documents`;
const RDS_PROXY_ENDPOINT = process.env.RDS_PROXY_ENDPOINT;
const RDS_SECRET_ARN = process.env.RDS_SECRET_ARN;
const DATABASE_NAME = process.env.DATABASE_NAME || 'vehealth';
const LOG_LEVEL = process.env.LOG_LEVEL || 'INFO';

const s3Client = new S3Client({ region: process.env.AWS_REGION || 'us-east-2' });
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
        tenantId: claims['custom:tenant_id'] || null,
    };
}

/**
 * Generate presigned S3 URL for document upload
 */
async function generatePresignedUrl(driverId, documentType, fileName, contentType, tenantId) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-').split('T')[0] + '_' + Date.now();
    const sanitizedFileName = fileName.replace(/[^a-zA-Z0-9._-]/g, '_');

    // S3 key format: {tenant_id}/{driver_id}/{document_type}/{timestamp}_{filename}
    const s3Key = tenantId
        ? `${tenantId}/${driverId}/${documentType}/${timestamp}_${sanitizedFileName}`
        : `${driverId}/${documentType}/${timestamp}_${sanitizedFileName}`;

    const metadata = {
        'driver-id': driverId,
        'document-type': documentType,
        'uploaded-at': new Date().toISOString(),
    };

    // Only add tenant-id if it exists (S3 metadata values must be strings, not null)
    if (tenantId) {
        metadata['tenant-id'] = tenantId;
    }

    const command = new PutObjectCommand({
        Bucket: DOCUMENTS_BUCKET,
        Key: s3Key,
        ContentType: contentType,
        Metadata: metadata
    });

    // Generate presigned URL valid for 15 minutes
    const presignedUrl = await getSignedUrl(s3Client, command, { expiresIn: 900 });

    return { presignedUrl, s3Key };
}

/**
 * Create document metadata record in database
 */
async function createDocumentRecord(db, documentData) {
    const query = `
        INSERT INTO driver_documents (
            driver_id, tenant_id, document_type, document_category,
            s3_key, s3_bucket, file_name, file_size_bytes, mime_type,
            status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        RETURNING id, created_at
    `;

    const values = [
        documentData.driverId,
        documentData.tenantId,
        documentData.documentType,
        documentData.documentCategory,
        documentData.s3Key,
        DOCUMENTS_BUCKET,
        documentData.fileName,
        documentData.fileSize || 0,
        documentData.mimeType,
        'pending'
    ];

    const result = await db.query(query, values);
    return result.rows[0];
}

/**
 * Get document category from type
 */
function getDocumentCategory(documentType) {
    const categoryMap = {
        'license': 'identity',
        'license_back': 'identity',
        'profile_photo': 'identity',
        'insurance': 'vehicle',
        'registration': 'vehicle',
        'inspection': 'compliance',
    };

    return categoryMap[documentType] || 'identity';
}

/**
 * Handle POST /drivers/documents/upload
 */
async function handleUploadRequest(event, user) {
    const body = JSON.parse(event.body || '{}');

    // Validate required fields - support both snake_case (from client) and camelCase
    const documentType = body.documentType || body.document_type;
    const fileName = body.fileName || body.file_name;
    const contentType = body.contentType || body.content_type;
    const fileSize = body.fileSize || body.file_size;

    if (!documentType || !fileName || !contentType) {
        return {
            statusCode: 400,
            body: JSON.stringify({
                error: 'Missing required fields: document_type, file_name, content_type'
            })
        };
    }

    // Validate document type
    const validTypes = ['license', 'license_back', 'insurance', 'registration', 'inspection', 'profile_photo'];
    if (!validTypes.includes(documentType)) {
        return {
            statusCode: 400,
            body: JSON.stringify({
                error: `Invalid documentType. Must be one of: ${validTypes.join(', ')}`
            })
        };
    }

    // Validate file size (max 10MB)
    if (fileSize && fileSize > 10 * 1024 * 1024) {
        return {
            statusCode: 400,
            body: JSON.stringify({ error: 'File size exceeds 10MB limit' })
        };
    }

    // Generate presigned URL
    const { presignedUrl, s3Key } = await generatePresignedUrl(
        user.userId,
        documentType,
        fileName,
        contentType,
        user.tenantId
    );

    // Create database record
    const db = await getDbConnection();
    const document = await createDocumentRecord(db, {
        driverId: user.userId,
        tenantId: user.tenantId,
        documentType,
        documentCategory: getDocumentCategory(documentType),
        s3Key,
        fileName,
        fileSize: fileSize || 0,
        mimeType: contentType,
    });

    console.log(`Document record created: ${document.id} for driver ${user.userId}`);

    return {
        statusCode: 200,
        body: JSON.stringify({
            presigned_url: presignedUrl,
            upload_url: presignedUrl, // Alias for backward compatibility
            document_id: document.id,
            s3_key: s3Key,
            expires_in: 900,
            instructions: 'Use PUT method to upload file to presigned_url'
        })
    };
}

/**
 * Handle GET /drivers/documents
 */
async function handleListDocuments(event, user) {
    const db = await getDbConnection();

    const query = `
        SELECT
            id, driver_id, tenant_id, document_type, document_category,
            s3_key, s3_bucket, file_name, file_size_bytes, mime_type,
            document_number, issuing_authority, issue_date, expiry_date,
            status, verified_at, verified_by, auto_verified, confidence_score,
            rejection_reason, notes, created_at, updated_at
        FROM driver_documents
        WHERE driver_id = $1
        ORDER BY created_at DESC
    `;

    const result = await db.query(query, [user.userId]);

    // Ensure proper type casting for JSON serialization
    const documents = result.rows.map(doc => ({
        ...doc,
        file_size_bytes: parseInt(doc.file_size_bytes) || 0,
        auto_verified: doc.auto_verified === true || doc.auto_verified === 'true',
        confidence_score: doc.confidence_score ? parseFloat(doc.confidence_score) : null
    }));

    return {
        statusCode: 200,
        body: JSON.stringify({
            documents: documents,
            total: documents.length
        })
    };
}

/**
 * Handle GET /drivers/documents/{documentId}
 */
async function handleGetDocument(event, user) {
    const documentId = event.pathParameters?.documentId;

    if (!documentId) {
        return {
            statusCode: 400,
            body: JSON.stringify({ error: 'Missing documentId' })
        };
    }

    const db = await getDbConnection();

    const query = `
        SELECT
            id, driver_id, tenant_id, document_type, document_category,
            s3_key, s3_bucket, file_name, file_size_bytes, mime_type,
            document_number, issuing_authority, issue_date, expiry_date,
            status, verified_at, verified_by, auto_verified, confidence_score,
            rejection_reason, notes, created_at, updated_at
        FROM driver_documents
        WHERE id = $1 AND driver_id = $2
    `;

    const result = await db.query(query, [documentId, user.userId]);

    if (result.rows.length === 0) {
        return {
            statusCode: 404,
            body: JSON.stringify({ error: 'Document not found' })
        };
    }

    const document = result.rows[0];

    // Generate presigned GET URL for viewing the document (valid for 1 hour)
    const command = new PutObjectCommand({
        Bucket: document.s3_bucket,
        Key: document.s3_key,
    });

    const viewUrl = await getSignedUrl(s3Client, command, { expiresIn: 3600 });

    return {
        statusCode: 200,
        body: JSON.stringify({
            ...document,
            viewUrl,
            viewUrlExpiresIn: 3600
        })
    };
}

/**
 * Handle GET /drivers/{driverId}/verification
 */
async function handleGetVerificationStatus(event, user) {
    const driverId = event.pathParameters?.driverId;

    // Users can only check their own verification status
    if (driverId !== user.userId) {
        return {
            statusCode: 403,
            body: JSON.stringify({ error: 'Forbidden' })
        };
    }

    const db = await getDbConnection();

    // Get all documents with their statuses
    const docsQuery = `
        SELECT document_type, status, expiry_date, verified_at
        FROM driver_documents
        WHERE driver_id = $1
        ORDER BY created_at DESC
    `;

    const docsResult = await db.query(docsQuery, [driverId]);

    // Get driver profile verification status
    const profileQuery = `
        SELECT
            documents_complete,
            documents_verified_at,
            status as profile_status
        FROM driver_profiles
        WHERE user_id = $1
    `;

    const profileResult = await db.query(profileQuery, [driverId]);

    // Calculate overall verification status
    const requiredDocs = ['license', 'insurance', 'registration', 'profile_photo'];
    const docStatuses = {};
    const missingDocs = [];

    requiredDocs.forEach(docType => {
        const doc = docsResult.rows.find(d => d.document_type === docType);
        docStatuses[docType] = doc ? doc.status : 'missing';
        if (!doc || doc.status !== 'approved') {
            missingDocs.push(docType);
        }
    });

    const allDocsApproved = missingDocs.length === 0;

    return {
        statusCode: 200,
        body: JSON.stringify({
            driverId,
            verificationComplete: allDocsApproved,
            documentsComplete: profileResult.rows[0]?.documents_complete || false,
            verifiedAt: profileResult.rows[0]?.documents_verified_at,
            profileStatus: profileResult.rows[0]?.profile_status,
            requiredDocuments: docStatuses,
            missingDocuments: missingDocs,
            totalDocuments: docsResult.rows.length,
            allDocuments: docsResult.rows
        })
    };
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

        if (method === 'POST' && path === '/drivers/documents/upload') {
            response = await handleUploadRequest(event, user);
        } else if (method === 'GET' && path === '/drivers/documents') {
            response = await handleListDocuments(event, user);
        } else if (method === 'GET' && path.match(/\/drivers\/documents\/[^/]+$/)) {
            response = await handleGetDocument(event, user);
        } else if (method === 'GET' && path.match(/\/drivers\/[^/]+\/verification$/)) {
            response = await handleGetVerificationStatus(event, user);
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
    } finally {
        // Don't close connection in Lambda - reuse for warm starts
        // dbClient will be reused in subsequent invocations
    }
};
