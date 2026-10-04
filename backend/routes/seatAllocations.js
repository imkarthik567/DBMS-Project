const express = require('express');
const router = express.Router();
const db = require('../config/db');
const { getTenantId } = require('../middleware/tenantContext');

/**
 * POST /seat-allocations
 * Allocate a seat on a software license to a user.
 * Database-level PL/pgSQL triggers automatically enforce seat quota limits,
 * cross-tenant integrity, and license expiration rules.
 */
router.post('/', async (req, res, next) => {
    try {
        const tenantId = getTenantId();

        if (!tenantId) {
            return res.status(400).json({
                error: 'Bad Request',
                message: 'Missing required tenant context header (x-tenant-id).'
            });
        }

        const { license_id, user_id, is_active } = req.body;

        if (!license_id || !user_id) {
            return res.status(400).json({
                error: 'Bad Request',
                message: 'Both license_id and user_id are required fields.'
            });
        }

        const activeStatus = is_active !== undefined ? Boolean(is_active) : true;

        const insertQuery = `
            INSERT INTO seat_allocations (license_id, user_id, is_active)
            VALUES ($1, $2, $3)
            RETURNING id, license_id, user_id, is_active, allocated_at;
        `;

        const result = await db.query(insertQuery, [license_id, user_id, activeStatus]);

        res.status(201).json({
            success: true,
            message: 'Seat allocated successfully.',
            data: result.rows[0]
        });
    } catch (err) {
        // Map PostgreSQL Trigger & Constraint Exceptions to HTTP 400 Bad Request
        if (
            err.code === '23514' || // check_violation (Seat limit exceeded / Expired license)
            err.code === '23505' || // unique_violation (Duplicate seat allocation)
            err.code === '23503' || // foreign_key_violation
            err.code === 'P0001'    // raise_exception (Custom PL/pgSQL error)
        ) {
            let userFriendlyMessage = err.message;
            if (err.code === '23505') {
                userFriendlyMessage = 'Seat allocation conflict: User already has an active seat on this license.';
            }

            return res.status(400).json({
                error: 'Business Rule Violation',
                code: err.code,
                message: userFriendlyMessage
            });
        }

        next(err);
    }
});

module.exports = router;
