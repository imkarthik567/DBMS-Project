# Multi-Tenant Digital Asset & License Management System

A enterprise-grade PostgreSQL database system built to demonstrate **Multi-Tenancy**, **3rd Normal Form (3NF) Relational Design**, **Row-Level Security (RLS)**, and **Database-Enforced Business Rules (PL/pgSQL Triggers & Stored Procedures)**.

---

## 📐 Relational Schema (3NF) Architecture

The system models a SaaS enterprise application where multiple **Tenants** purchase software **Licenses** for **Products**, and allocate **Seats** to their respective **Users**.

```
+------------------+         +-------------------+         +--------------------+
|     Tenants      | 1     * |       Users       | 1     * |  SeatAllocations   |
|------------------|---------|-------------------|---------|--------------------|
| id (PK, UUID)    |         | id (PK, UUID)     |         | id (PK, UUID)      |
| name             |         | tenant_id (FK)    |         | license_id (FK)    |
| subscription_tier|         | email             |         | user_id (FK)       |
| created_at       |         | full_name         |         | is_active          |
+------------------+         | role              |         | allocated_at       |
         |                   +-------------------+         +--------------------+
         | 1                                                         | *
         |                                                           |
         | *                                                         | 1
+------------------+         +--------------------------------------------------+
|     Licenses     | *     1 |                     Products                     |
|------------------|---------|--------------------------------------------------|
| id (PK, UUID)    |         | id (PK, UUID)                                    |
| tenant_id (FK)   |         | name                                             |
| product_id (FK)  |         | sku (UNIQUE)                                     |
| max_seats        |         | description                                      |
| expires_at       |         +--------------------------------------------------+
| status           |
+------------------+
```

### Key Integrity Constraints:
- **Tenant Isolation:** `users.tenant_id` and `licenses.tenant_id` bind records to a specific tenant.
- **Natural Key Uniqueness:** `UNIQUE (tenant_id, email)` prevents user email conflicts within a tenant.
- **Allocation Uniqueness:** `UNIQUE (license_id, user_id)` ensures a user cannot be granted duplicate active seats on the same license.
- **Foreign Key Actions:** `ON DELETE CASCADE` cleans up dependent records upon tenant/license deletion; `ON DELETE RESTRICT` protects catalog products from accidental removal.

---

## 🔒 Security Architecture: Row-Level Security (RLS)

PostgreSQL **Row-Level Security (RLS)** is enabled with `FORCE ROW LEVEL SECURITY` on all tenant-scoped tables (`users`, `licenses`, `seat_allocations`).

### Setting Tenant Session Context
Application servers set the tenant scope per session or transaction:

```sql
-- Set active tenant session to Acme Corp
SET LOCAL app.current_tenant_id = 'a0000000-0000-0000-0000-000000000001';

-- Clear context (Admin / Superuser mode)
RESET app.current_tenant_id;
```

---

## ⚙️ Database-Enforced Business Rules

### 1. Concurrency-Safe Seat Quota Trigger (`fn_enforce_seat_allocation_limits`)
Fired `BEFORE INSERT OR UPDATE` on `seat_allocations`:
- **Cross-Tenant Integrity:** Validates that `users.tenant_id = licenses.tenant_id`. Throws `integrity_constraint_violation` if mismatched.
- **License Status & Expiration Guard:** Validates that license status is `'ACTIVE'` and `expires_at > CURRENT_TIMESTAMP`. Throws `check_violation` if inactive/expired.
- **Race-Condition Protection:** Locks the target row in `licenses` (`FOR UPDATE`) during quota calculation to prevent race conditions under high concurrent requests.
- **Seat Quota Enforcement:** Counts active allocations against `licenses.max_seats`. Throws `check_violation` if limit is exceeded.

### 2. Maintenance Stored Procedure (`sp_update_license_statuses`)
Automated procedure that batch-transitions licenses past their `expires_at` timestamp from `'ACTIVE'` to `'EXPIRED'`.

---

## 🚀 Execution & Quick Start Guide

### Prerequisites
- PostgreSQL 13 or higher
- `psql` command-line tool, pgAdmin 4, or Docker PostgreSQL container.

### Option A: Using `psql` Command Line
Execute the files in order:

```bash
# 1. Initialize Relational Schema, RLS Policies, Functions, & Triggers
psql -U postgres -d postgres -f init_schema.sql

# 2. Ingest Realistic Seed Data (Tenant A & Tenant B)
psql -U postgres -d postgres -f seed_data.sql

# 3. Execute Enforcement Verification Test Harness
psql -U postgres -d postgres -f test_enforcement.sql
```

### Option B: Docker Setup (Quick Sandbox)
Run a temporary PostgreSQL container:

```bash
# Run PostgreSQL container
docker run --name pg-license-db -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16-alpine

# Execute scripts inside container
docker exec -i pg-license-db psql -U postgres < init_schema.sql
docker exec -i pg-license-db psql -U postgres < seed_data.sql
docker exec -i pg-license-db psql -U postgres < test_enforcement.sql
```

---

## 🧪 Verification & Test Suite Summary

The included `test_enforcement.sql` executes 6 automated test scenarios:

| Test Case | Scenario | Expected Behavior |
| :--- | :--- | :--- |
| **TEST 1** | Valid seat allocation (Tenant A: 4th seat on 5-seat license) | `SUCCESS` |
| **TEST 2** | Quota breach attempt (Tenant B: 3rd seat on 2-seat license) | `RAISE EXCEPTION` (check_violation) |
| **TEST 3** | RLS Tenant Data Isolation query | Tenant A sees 6 users; Tenant B sees 3 users |
| **TEST 4** | Cross-tenant seat assignment (Tenant A User -> Tenant B License) | `RAISE EXCEPTION` (integrity_constraint_violation) |
| **TEST 5** | Seat allocation on expired license | `RAISE EXCEPTION` (check_violation) |
| **TEST 6** | Execution of `sp_update_license_statuses()` procedure | License status updated to `'EXPIRED'` |
