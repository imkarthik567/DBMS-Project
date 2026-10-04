const express = require('express');
const router = express.Router();
const db = require('../config/db');
const { getTenantId } = require('../middleware/tenantContext');

/**
 * GET /users
 * Retrieve users scoped to the current tenant context.
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

        const result = await db.query(
            'SELECT id, tenant_id, email, full_name, role, created_at FROM users ORDER BY full_name ASC'
        );

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
