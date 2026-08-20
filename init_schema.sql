-- =============================================================================
-- Multi-Tenant Digital Asset & License Management System
-- Database Engine: PostgreSQL (13+)
-- Artifact: Schema DDL, Constraints, RLS Policies, & PL/pgSQL Business Rules
-- =============================================================================

-- gen_random_uuid() is native in PostgreSQL 13+
-- CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- -----------------------------------------------------------------------------
-- Clean Up Existing Database Objects (For Re-runnable Migrations)
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_enforce_seat_allocation_limits ON seat_allocations;
DROP FUNCTION IF EXISTS fn_enforce_seat_allocation_limits();
DROP PROCEDURE IF EXISTS sp_update_license_statuses();
DROP VIEW IF EXISTS v_active_licenses;
DROP TABLE IF EXISTS seat_allocations CASCADE;
DROP TABLE IF EXISTS licenses CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS tenants CASCADE;

-- -----------------------------------------------------------------------------
-- 1. Normalized Relational Schema (3NF)
-- -----------------------------------------------------------------------------

-- Tenants Table
-- 1NF: Atomic values. 2NF: All non-key attributes fully depend on PK (id). 3NF: No transitive dependencies.
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    subscription_tier VARCHAR(50) NOT NULL CHECK (subscription_tier IN ('FREE', 'PRO', 'ENTERPRISE')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Products Table (Global Software/Asset Catalog)
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    sku VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Users Table (Tenant-Scoped)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('Admin', 'Member')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_tenant_user_email UNIQUE (tenant_id, email)
);

-- Licenses Table (Tenant-Scoped Digital Asset Purchases)
CREATE TABLE licenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    max_seats INTEGER NOT NULL CHECK (max_seats > 0),
    expires_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('ACTIVE', 'EXPIRED', 'SUSPENDED')) DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- SeatAllocations Table (Tenant-Scoped Junction Table)
CREATE TABLE seat_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    license_id UUID NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    allocated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_license_user_allocation UNIQUE (license_id, user_id)
);

-- Indexes for Foreign Keys & Frequent Queries
CREATE INDEX idx_users_tenant ON users(tenant_id);
CREATE INDEX idx_licenses_tenant ON licenses(tenant_id);
CREATE INDEX idx_licenses_product ON licenses(product_id);
CREATE INDEX idx_seat_allocations_license ON seat_allocations(license_id);
CREATE INDEX idx_seat_allocations_user ON seat_allocations(user_id);
CREATE INDEX idx_seat_allocations_active ON seat_allocations(license_id, is_active);

-- -----------------------------------------------------------------------------
-- 2. Strict Tenant Isolation (PostgreSQL Row-Level Security)
-- -----------------------------------------------------------------------------

-- Enable & Force RLS on all tenant-scoped tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;

ALTER TABLE licenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE licenses FORCE ROW LEVEL SECURITY;

ALTER TABLE seat_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE seat_allocations FORCE ROW LEVEL SECURITY;

-- Create non-superuser application role for strict RLS enforcement
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'tenant_app_user') THEN
        CREATE ROLE tenant_app_user NOSUPERUSER NOBYPASSRLS;
    END IF;
END $$;

GRANT ALL ON ALL TABLES IN SCHEMA public TO tenant_app_user;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO tenant_app_user;

-- Helper Function for Safe Tenant Session Variable Parsing
CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS UUID AS $$
BEGIN
    RETURN NULLIF(current_setting('app.current_tenant_id', true), '')::UUID;
EXCEPTION
    WHEN invalid_text_representation THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE;

-- RLS Policy for Users Table
CREATE POLICY tenant_isolation_users ON users
    FOR ALL
    TO PUBLIC
    USING (
        tenant_id = current_tenant_id()
        OR current_tenant_id() IS NULL
    )
    WITH CHECK (
        tenant_id = current_tenant_id()
        OR current_tenant_id() IS NULL
    );

-- RLS Policy for Licenses Table
CREATE POLICY tenant_isolation_licenses ON licenses
    FOR ALL
    TO PUBLIC
    USING (
        tenant_id = current_tenant_id()
        OR current_tenant_id() IS NULL
    )
    WITH CHECK (
        tenant_id = current_tenant_id()
        OR current_tenant_id() IS NULL
    );

-- RLS Policy for SeatAllocations Table
CREATE POLICY tenant_isolation_seat_allocations ON seat_allocations
    FOR ALL
    TO PUBLIC
    USING (
        EXISTS (
            SELECT 1 FROM licenses l
            WHERE l.id = seat_allocations.license_id
              AND (l.tenant_id = current_tenant_id() OR current_tenant_id() IS NULL)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM licenses l
            WHERE l.id = seat_allocations.license_id
              AND (l.tenant_id = current_tenant_id() OR current_tenant_id() IS NULL)
        )
    );

-- -----------------------------------------------------------------------------
-- 3. Database-Enforced Business Rules (Triggers & Procedures)
-- -----------------------------------------------------------------------------

-- PL/pgSQL Trigger Function: Seat Quota & Tenant Integrity Validator
CREATE OR REPLACE FUNCTION fn_enforce_seat_allocation_limits()
RETURNS TRIGGER AS $$
DECLARE
    v_license_tenant_id UUID;
    v_user_tenant_id UUID;
    v_max_seats INTEGER;
    v_license_status VARCHAR(20);
    v_expires_at TIMESTAMPTZ;
    v_current_active_seats INTEGER;
BEGIN
    -- Only evaluate quota and integrity if the allocation is marked active
    IF NEW.is_active = TRUE THEN
        
        -- 1. Fetch license details and lock the license row to prevent concurrent race conditions
        SELECT tenant_id, max_seats, status, expires_at
        INTO v_license_tenant_id, v_max_seats, v_license_status, v_expires_at
        FROM licenses
        WHERE id = NEW.license_id
        FOR UPDATE;

        IF v_license_tenant_id IS NULL THEN
            RAISE EXCEPTION 'Invalid license ID: License % does not exist', NEW.license_id
                USING ERRCODE = 'foreign_key_violation';
        END IF;

        -- 2. Verify License Expiration & Status
        IF v_license_status != 'ACTIVE' OR v_expires_at <= CURRENT_TIMESTAMP THEN
            RAISE EXCEPTION 'Cannot allocate seat: License % is % (Expires at: %)', 
                NEW.license_id, v_license_status, v_expires_at
                USING ERRCODE = 'check_violation';
        END IF;

        -- 3. Fetch User Tenant ID and verify Cross-Tenant Integrity
        SELECT tenant_id INTO v_user_tenant_id
        FROM users
        WHERE id = NEW.user_id;

        IF v_user_tenant_id IS NULL THEN
            RAISE EXCEPTION 'Invalid user ID: User % does not exist', NEW.user_id
                USING ERRCODE = 'foreign_key_violation';
        END IF;

        IF v_user_tenant_id != v_license_tenant_id THEN
            RAISE EXCEPTION 'Cross-tenant seat allocation prohibited: User % (Tenant: %) cannot be assigned License % (Tenant: %)',
                NEW.user_id, v_user_tenant_id, NEW.license_id, v_license_tenant_id
                USING ERRCODE = 'integrity_constraint_violation';
        END IF;

        -- 4. Count current active seats (excluding the current record if updating)
        SELECT COUNT(*)
        INTO v_current_active_seats
        FROM seat_allocations
        WHERE license_id = NEW.license_id
          AND is_active = TRUE
          AND id IS DISTINCT FROM NEW.id;

        -- 5. Enforce Max Seat Allocation Quota
        IF (v_current_active_seats + 1) > v_max_seats THEN
            RAISE EXCEPTION 'Seat allocation limit exceeded for License %. Max seats allowed: %, Currently active: %',
                NEW.license_id, v_max_seats, v_current_active_seats
                USING ERRCODE = 'check_violation';
        END IF;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Bind Trigger to SeatAllocations
CREATE TRIGGER trg_enforce_seat_allocation_limits
BEFORE INSERT OR UPDATE ON seat_allocations
FOR EACH ROW
EXECUTE FUNCTION fn_enforce_seat_allocation_limits();

-- Stored Procedure: Automated License Status Updater
CREATE OR REPLACE PROCEDURE sp_update_license_statuses()
LANGUAGE plpgsql
AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    UPDATE licenses
    SET status = 'EXPIRED'
    WHERE expires_at <= CURRENT_TIMESTAMP
      AND status = 'ACTIVE';
      
    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    RAISE NOTICE 'Automated Maintenance: Updated % licenses to EXPIRED state.', v_updated_count;
END;
$$;

-- View: Active Licenses with Real-Time Seat Utilization
CREATE OR REPLACE VIEW v_active_licenses AS
SELECT 
    l.id AS license_id,
    l.tenant_id,
    t.name AS tenant_name,
    p.name AS product_name,
    p.sku AS product_sku,
    l.max_seats,
    COUNT(sa.id) FILTER (WHERE sa.is_active = TRUE) AS active_seats_allocated,
    (l.max_seats - COUNT(sa.id) FILTER (WHERE sa.is_active = TRUE)) AS available_seats,
    l.expires_at,
    l.status
FROM licenses l
JOIN tenants t ON l.tenant_id = t.id
JOIN products p ON l.product_id = p.id
LEFT JOIN seat_allocations sa ON l.id = sa.license_id
WHERE l.status = 'ACTIVE' AND l.expires_at > CURRENT_TIMESTAMP
GROUP BY l.id, l.tenant_id, t.name, p.name, p.sku, l.max_seats, l.expires_at, l.status;

-- Grant permissions (if standard application role exists)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_role;
