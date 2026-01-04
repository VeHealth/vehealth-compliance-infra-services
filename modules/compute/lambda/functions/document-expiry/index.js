/**
 * Driver Document Expiry Check Lambda
 *
 * Scheduled job that:
 * 1. Finds documents expiring in next 30 days
 * 2. Marks expired documents as 'expired'
 * 3. Updates driver_profiles status if docs become expired
 * 4. Sends notifications to drivers (future enhancement)
 *
 * Triggered by EventBridge rule (scheduled daily)
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
 * Find documents expiring in next N days
 */
async function findExpiringDocuments(db, daysAhead = 30) {
    const query = `
        SELECT
            id, driver_id, document_type, file_name,
            expiry_date, expiration_notified_at,
            (expiry_date - CURRENT_DATE) AS days_until_expiry
        FROM driver_documents
        WHERE status = 'approved'
          AND expiry_date IS NOT NULL
          AND expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '${daysAhead} days'
          AND expiration_notified_at IS NULL
        ORDER BY expiry_date ASC
    `;

    const result = await db.query(query);
    return result.rows;
}

/**
 * Mark documents as expired
 */
async function markExpiredDocuments(db) {
    const query = `
        UPDATE driver_documents
        SET status = 'expired', updated_at = NOW()
        WHERE status = 'approved'
          AND expiry_date IS NOT NULL
          AND expiry_date < CURRENT_DATE
        RETURNING id, driver_id, document_type, expiry_date
    `;

    const result = await db.query(query);
    return result.rows;
}

/**
 * Mark expiration notification as sent
 */
async function markNotificationSent(db, documentIds) {
    if (documentIds.length === 0) return;

    const query = `
        UPDATE driver_documents
        SET expiration_notified_at = NOW(), updated_at = NOW()
        WHERE id = ANY($1)
    `;

    await db.query(query, [documentIds]);
}

/**
 * Update driver profiles with expired document status
 */
async function updateDriverProfilesForExpiredDocs(db, expiredDocs) {
    if (expiredDocs.length === 0) return [];

    // Group by driver_id
    const driverIds = [...new Set(expiredDocs.map(d => d.driver_id))];

    const results = [];

    for (const driverId of driverIds) {
        // Check if driver still has all required docs approved
        const checkQuery = `
            SELECT document_type, status
            FROM driver_documents
            WHERE driver_id = $1
              AND document_type IN ('license', 'insurance', 'registration', 'profile_photo')
              AND status = 'approved'
        `;

        const checkResult = await db.query(checkQuery, [driverId]);
        const approvedDocs = checkResult.rows.map(r => r.document_type);
        const requiredDocs = ['license', 'insurance', 'registration', 'profile_photo'];
        const allApproved = requiredDocs.every(doc => approvedDocs.includes(doc));

        if (!allApproved) {
            // Mark documents as incomplete
            const updateQuery = `
                UPDATE driver_profiles
                SET
                    documents_complete = FALSE,
                    status = CASE
                        WHEN status = 'active' THEN 'pending_documents'
                        ELSE status
                    END,
                    updated_at = NOW()
                WHERE user_id = $1
                RETURNING user_id, documents_complete, status
            `;

            const updateResult = await db.query(updateQuery, [driverId]);
            results.push(updateResult.rows[0]);
        }
    }

    return results;
}

/**
 * Send expiration notifications (placeholder - integrate with SNS/SES later)
 */
async function sendExpirationNotifications(expiringDocs) {
    console.log(`Would send ${expiringDocs.length} expiration notifications`);

    // TODO: Integrate with SNS or SES to send emails/push notifications
    // For now, just log the notifications

    expiringDocs.forEach(doc => {
        console.log(`NOTIFICATION: Driver ${doc.driver_id} - ${doc.document_type} expires in ${doc.days_until_expiry} days (${doc.expiry_date})`);
    });

    return expiringDocs.length;
}

/**
 * Main Lambda handler
 */
exports.handler = async (event) => {
    console.log('Document Expiry Check - Starting');
    console.log('Event:', JSON.stringify(event, null, 2));

    const results = {
        expiringDocuments: 0,
        expiredDocuments: 0,
        notificationsSent: 0,
        profilesUpdated: 0,
        errors: []
    };

    try {
        const db = await getDbConnection();

        // Step 1: Find and mark expired documents
        console.log('Step 1: Marking expired documents');
        const expiredDocs = await markExpiredDocuments(db);
        results.expiredDocuments = expiredDocs.length;
        console.log(`Marked ${expiredDocs.length} documents as expired`);

        // Step 2: Update driver profiles for expired documents
        if (expiredDocs.length > 0) {
            console.log('Step 2: Updating driver profiles for expired documents');
            const updatedProfiles = await updateDriverProfilesForExpiredDocs(db, expiredDocs);
            results.profilesUpdated = updatedProfiles.length;
            console.log(`Updated ${updatedProfiles.length} driver profiles`);
        }

        // Step 3: Find documents expiring soon (30 days)
        console.log('Step 3: Finding documents expiring in next 30 days');
        const expiringDocs = await findExpiringDocuments(db, 30);
        results.expiringDocuments = expiringDocs.length;
        console.log(`Found ${expiringDocs.length} documents expiring in next 30 days`);

        // Step 4: Send notifications
        if (expiringDocs.length > 0) {
            console.log('Step 4: Sending expiration notifications');
            results.notificationsSent = await sendExpirationNotifications(expiringDocs);

            // Mark notifications as sent
            const documentIds = expiringDocs.map(d => d.id);
            await markNotificationSent(db, documentIds);
            console.log(`Marked ${documentIds.length} notifications as sent`);
        }

        console.log('Document Expiry Check - Completed');
        console.log('Results:', results);

        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Document expiry check completed',
                results
            })
        };

    } catch (error) {
        console.error('Error in document expiry check:', error);
        results.errors.push(error.message);

        return {
            statusCode: 500,
            body: JSON.stringify({
                error: 'Document expiry check failed',
                message: LOG_LEVEL === 'DEBUG' ? error.message : undefined,
                results
            })
        };
    }
};
