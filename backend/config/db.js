const { Pool } = require('pg');
const { getTenantId } = require('../middleware/tenantContext');
require('dotenv').config();

const pool = new Pool({
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    database: process.env.DB_NAME || 'postgres',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || 'postgres',
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 2000,
});

pool.on('error', (err) => {
    console.error('Unexpected PostgreSQL Pool Error:', err);
});

/**
 * Executes a single database query inside an isolated transaction block
 * where session configuration `app.current_tenant_id` is set automatically.
 *
 * @param {string} text - SQL Query String
 * @param {Array} params - Query Parameters
 * @returns {Promise<import('pg').QueryResult>}
 */
async function query(text, params) {
    const tenantId = getTenantId();
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        // Execute SET LOCAL app.current_tenant_id for transaction-scoped RLS isolation
        if (tenantId) {
            await client.query("SELECT set_config('app.current_tenant_id', $1, true)", [tenantId]);
        } else {
            await client.query("SELECT set_config('app.current_tenant_id', '', true)");
        }

        const result = await client.query(text, params);
        await client.query('COMMIT');
        return result;
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

/**
 * Execute multiple database operations inside a single tenant-scoped transaction.
 *
 * @param {function(import('pg').PoolClient): Promise<any>} callback
 * @returns {Promise<any>}
 */
async function withTransaction(callback) {
    const tenantId = getTenantId();
    const client = await pool.connect();

    try {
        await client.query('BEGIN');
        if (tenantId) {
            await client.query("SELECT set_config('app.current_tenant_id', $1, true)", [tenantId]);
        } else {
            await client.query("SELECT set_config('app.current_tenant_id', '', true)");
        }

        const result = await callback(client);
        await client.query('COMMIT');
        return result;
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

module.exports = {
    pool,
    query,
    withTransaction
};
