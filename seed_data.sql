-- =============================================================================
-- Multi-Tenant Digital Asset & License Management System
-- Artifact: Seed Data Script
-- Description: Realistic test dataset for Tenant A (5-seat quota) & Tenant B (2-seat quota)
-- =============================================================================

-- Clear existing data cleanly (Order respects foreign key dependencies)
TRUNCATE TABLE seat_allocations, licenses, users, products, tenants CASCADE;

-- Reset tenant context for unrestricted seed data insertion
RESET app.current_tenant_id;

-- -----------------------------------------------------------------------------
-- 1. Insert Global Products Catalog
-- -----------------------------------------------------------------------------
INSERT INTO products (id, name, sku, description) VALUES
('c0000000-0000-0000-0000-000000000001', 'Enterprise Cloud Suite', 'SKU-ECS-2026', 'Full-stack enterprise productivity and cloud management platform'),
('c0000000-0000-0000-0000-000000000002', 'Analytics Pro', 'SKU-APR-2026', 'Advanced business intelligence and predictive data analytics engine'),
('c0000000-0000-0000-0000-000000000003', 'Security Shield', 'SKU-SSH-2026', 'Real-time threat monitoring and digital asset encryption service');

-- -----------------------------------------------------------------------------
-- 2. Insert Tenants
-- -----------------------------------------------------------------------------
-- Tenant A: Acme Corp (PRO Tier)
-- Tenant B: Beta LLC (FREE Tier)
INSERT INTO tenants (id, name, subscription_tier) VALUES
('a0000000-0000-0000-0000-000000000001', 'Acme Corp', 'PRO'),
('b0000000-0000-0000-0000-000000000002', 'Beta LLC', 'FREE');

-- -----------------------------------------------------------------------------
-- 3. Insert Users
-- -----------------------------------------------------------------------------
-- Tenant A Users (Acme Corp)
INSERT INTO users (id, tenant_id, email, full_name, role) VALUES
('a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'alice@acme.com', 'Alice Smith', 'Admin'),
('a1000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'bob@acme.com', 'Bob Jones', 'Member'),
('a1000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'charlie@acme.com', 'Charlie Brown', 'Member'),
('a1000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'david@acme.com', 'David Miller', 'Member'),
('a1000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'eve@acme.com', 'Eve Davis', 'Member'),
('a1000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001', 'frank@acme.com', 'Frank Wilson', 'Member');

-- Tenant B Users (Beta LLC)
INSERT INTO users (id, tenant_id, email, full_name, role) VALUES
('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'grace@beta.io', 'Grace Hopper', 'Admin'),
('b1000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002', 'heidi@beta.io', 'Heidi Lamarr', 'Member'),
('b1000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000002', 'ian@beta.io', 'Ian Goodfellow', 'Member');

-- -----------------------------------------------------------------------------
-- 4. Insert Licenses
-- -----------------------------------------------------------------------------
-- Tenant A License: Enterprise Cloud Suite with 5 Seats Quota (Active, valid 1 year)
INSERT INTO licenses (id, tenant_id, product_id, max_seats, expires_at, status) VALUES
('a2000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 5, CURRENT_TIMESTAMP + INTERVAL '1 year', 'ACTIVE');

-- Tenant B Licenses:
-- 1. Analytics Pro with 2 Seats Quota (Active, valid 6 months)
-- 2. Security Shield with 5 Seats Quota (Expired yesterday for testing auto-updater)
INSERT INTO licenses (id, tenant_id, product_id, max_seats, expires_at, status) VALUES
('b2000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002', 2, CURRENT_TIMESTAMP + INTERVAL '6 months', 'ACTIVE'),
('b2000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000003', 5, CURRENT_TIMESTAMP - INTERVAL '1 day', 'ACTIVE');

-- -----------------------------------------------------------------------------
-- 5. Insert Initial Seat Allocations
-- -----------------------------------------------------------------------------
-- Tenant A Allocations: 3 seats used out of 5 allowed
INSERT INTO seat_allocations (id, license_id, user_id, is_active) VALUES
('a3000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', TRUE),
('a3000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002', TRUE),
('a3000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000003', TRUE);

-- Tenant B Allocations: 2 seats used out of 2 allowed (AT CAPACITY MAX LIMIT)
INSERT INTO seat_allocations (id, license_id, user_id, is_active) VALUES
('b3000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', TRUE),
('b3000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002', TRUE);

-- -----------------------------------------------------------------------------
-- Seed Verification Summary
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_tenant_count INT;
    v_user_count INT;
    v_license_count INT;
    v_allocation_count INT;
BEGIN
    SELECT COUNT(*) INTO v_tenant_count FROM tenants;
    SELECT COUNT(*) INTO v_user_count FROM users;
    SELECT COUNT(*) INTO v_license_count FROM licenses;
    SELECT COUNT(*) INTO v_allocation_count FROM seat_allocations;
    
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'SEED DATA INGESTION COMPLETED SUCCESSFULLY';
    RAISE NOTICE 'Tenants Loaded:          %', v_tenant_count;
    RAISE NOTICE 'Users Loaded:            %', v_user_count;
    RAISE NOTICE 'Licenses Loaded:         %', v_license_count;
    RAISE NOTICE 'Seat Allocations Loaded: %', v_allocation_count;
    RAISE NOTICE '==================================================';
END $$;
