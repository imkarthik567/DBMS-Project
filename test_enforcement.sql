-- =============================================================================
-- Multi-Tenant Digital Asset & License Management System
-- Artifact: Comprehensive Enforcement & Transaction Test Suite
-- Description: Verification script validating RLS isolation, seat quotas, and business rules.
-- =============================================================================

\echo '====================================================================='
\echo 'STARTING DATABASE ENFORCEMENT VERIFICATION TEST SUITE'
\echo '====================================================================='

-- -----------------------------------------------------------------------------
-- TEST 1: Valid Seat Allocation Within Allowed Quota
-- Scenario: Tenant A has 3/5 seats used. Allocating 4th seat (David Miller).
-- Expected Result: SUCCESS
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '[TEST 1] Testing valid seat allocation within quota...';
    
    -- Set session context for Tenant A (Acme Corp)
    PERFORM set_config('app.current_tenant_id', 'a0000000-0000-0000-0000-000000000001', true);
    
    -- Insert 4th allocation for David Miller
    INSERT INTO seat_allocations (id, license_id, user_id, is_active) VALUES
    ('a3000000-0000-0000-0000-000000000004', 'a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000004', TRUE);

    RAISE NOTICE '[TEST 1 PASSED] Successfully allocated 4th seat out of 5 allowed for Tenant A.';
END $$;

-- -----------------------------------------------------------------------------
-- TEST 2: Seat Quota Exceeded Violation (Quota Breach Guard)
-- Scenario: Tenant B has 2/2 seats used. Attempting 3rd allocation (Ian Goodfellow).
-- Expected Result: EXCEPTION caught, allocation blocked and transaction rolled back.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '[TEST 2] Testing seat quota breach attempt (Tenant B 2/2 max seats)...';
    
    -- Set session context for Tenant B (Beta LLC)
    PERFORM set_config('app.current_tenant_id', 'b0000000-0000-0000-0000-000000000002', true);
    
    BEGIN
        -- Attempt to allocate 3rd seat (Max allowed: 2)
        INSERT INTO seat_allocations (id, license_id, user_id, is_active) VALUES
        ('b3000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000003', TRUE);

        RAISE EXCEPTION '[TEST 2 FAILED] Trigger failed to block seat quota breach!';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '[TEST 2 PASSED] Caught expected exception: %', SQLERRM;
    END;
END $$;

-- -----------------------------------------------------------------------------
-- TEST 3: Strict Tenant Isolation (PostgreSQL Row-Level Security)
-- Scenario: Query users table under Tenant A context, then Tenant B context.
-- Expected Result: Zero cross-tenant leakage.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_tenant_a_user_count INT;
    v_tenant_b_user_count INT;
BEGIN
    RAISE NOTICE '[TEST 3] Testing Row-Level Security (RLS) data isolation...';

    -- Switch to non-superuser application role for active RLS enforcement
    EXECUTE 'SET ROLE tenant_app_user';

    -- Switch to Tenant A Context
    PERFORM set_config('app.current_tenant_id', 'a0000000-0000-0000-0000-000000000001', true);
    SELECT COUNT(*) INTO v_tenant_a_user_count FROM users;
    
    -- Switch to Tenant B Context
    PERFORM set_config('app.current_tenant_id', 'b0000000-0000-0000-0000-000000000002', true);
    SELECT COUNT(*) INTO v_tenant_b_user_count FROM users;

    -- Reset Role to Superuser
    EXECUTE 'RESET ROLE';

    IF v_tenant_a_user_count = 6 AND v_tenant_b_user_count = 3 THEN
        RAISE NOTICE '[TEST 3 PASSED] RLS verified: Tenant A sees % users, Tenant B sees % users.',
            v_tenant_a_user_count, v_tenant_b_user_count;
    ELSE
        RAISE EXCEPTION '[TEST 3 FAILED] RLS leak detected! Tenant A sees %, Tenant B sees %',
            v_tenant_a_user_count, v_tenant_b_user_count;
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- TEST 4: Cross-Tenant Seat Allocation Prevention Guard
-- Scenario: Attempt to assign Tenant A User (Alice) to Tenant B License.
-- Expected Result: Trigger intercepts and raises cross-tenant exception.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '[TEST 4] Testing cross-tenant seat assignment prevention...';

    -- Clear tenant filter to attempt cross-tenant manipulation
    PERFORM set_config('app.current_tenant_id', '', true);

    BEGIN
        -- Assign Tenant A User (Alice) to Tenant B License
        INSERT INTO seat_allocations (id, license_id, user_id, is_active) VALUES
        ('a3000000-0000-0000-0000-000000000099', 'b2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', TRUE);

        RAISE EXCEPTION '[TEST 4 FAILED] Trigger allowed cross-tenant seat assignment!';
    EXCEPTION
        WHEN integrity_constraint_violation THEN
            RAISE NOTICE '[TEST 4 PASSED] Caught expected exception: %', SQLERRM;
    END;
END $$;

-- -----------------------------------------------------------------------------
-- TEST 5: Expired License Allocation Blocking
-- Scenario: Attempt to allocate seat on an expired license (Tenant B Security Shield).
-- Expected Result: Trigger intercepts and raises inactive/expired license exception.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '[TEST 5] Testing seat allocation on an expired license...';

    PERFORM set_config('app.current_tenant_id', 'b0000000-0000-0000-0000-000000000002', true);

    BEGIN
        -- Attempt to allocate seat on expired license (b2000000-0000-0000-0000-000000000002)
        INSERT INTO seat_allocations (id, license_id, user_id, is_active) VALUES
        ('b3000000-0000-0000-0000-000000000099', 'b2000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000003', TRUE);

        RAISE EXCEPTION '[TEST 5 FAILED] Trigger allowed allocation on expired license!';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '[TEST 5 PASSED] Caught expected exception: %', SQLERRM;
    END;
END $$;

-- -----------------------------------------------------------------------------
-- TEST 6: Automated License Status Updater Stored Procedure
-- Scenario: Execute maintenance procedure and verify expired license transition.
-- Expected Result: Status updated to 'EXPIRED'.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_expired_status VARCHAR(20);
BEGIN
    RAISE NOTICE '[TEST 6] Testing automated license status maintenance procedure...';

    -- Run maintenance stored procedure
    CALL sp_update_license_statuses();

    -- Check updated status of license b2000000-0000-0000-0000-000000000002
    PERFORM set_config('app.current_tenant_id', '', true); -- Admin context to view
    SELECT status INTO v_expired_status
    FROM licenses
    WHERE id = 'b2000000-0000-0000-0000-000000000002';

    IF v_expired_status = 'EXPIRED' THEN
        RAISE NOTICE '[TEST 6 PASSED] License status successfully updated to EXPIRED.';
    ELSE
        RAISE EXCEPTION '[TEST 6 FAILED] License status was not updated. Expected EXPIRED, got %', v_expired_status;
    END IF;
END $$;

-- Reset Session Context
RESET app.current_tenant_id;

\echo '====================================================================='
\echo 'ALL ENFORCEMENT & INTEGRITY TESTS COMPLETED SUCCESSFULLY'
\echo '====================================================================='
