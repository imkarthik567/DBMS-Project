const express = require('express');
const router = express.Router();
const db = require('../config/db');
const { getTenantId } = require('../middleware/tenantContext');

/**
 * GET /licenses
 * Retrieve active software licenses and seat utilization metrics for the current tenant.
 */
router.get('/', async (req, res, next) => {
    try {
        const tenantId = getTenantId();

        if (!tenantId) {
            return res.status(400).json({
                error: 'Bad Request',
                message: 'Missing required tenant context header (x-tenant-id).'
            });
        }

        const queryText = `
            SELECT 
                l.id AS license_id,
                l.tenant_id,
                p.name AS product_name,
                p.sku AS product_sku,
                p.description AS product_description,
                l.max_seats,
                COUNT(sa.id) FILTER (WHERE sa.is_active = TRUE)::int AS active_seats_allocated,
                (l.max_seats - COUNT(sa.id) FILTER (WHERE sa.is_active = TRUE))::int AS available_seats,
                l.expires_at,
                l.status,
                l.created_at
            FROM licenses l
            JOIN products p ON l.product_id = p.id
            LEFT JOIN seat_allocations sa ON l.id = sa.license_id
            GROUP BY l.id, l.tenant_id, p.name, p.sku, p.description, l.max_seats, l.expires_at, l.status, l.created_at
            ORDER BY l.created_at DESC;
        `;

        const result = await db.query(queryText);

        res.json({
            success: true,
            tenant_id: tenantId,
            count: result.rows.length,
            data: result.rows
        });
    } catch (err) {
        next(err);
    }
});

module.exports = router;
