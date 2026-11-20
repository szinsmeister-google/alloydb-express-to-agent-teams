-- ============================================================================
-- Step 4 (Part B): Grant Read-Only Table Access on `finance_db` to Diego's Role
-- Target database: finance_db
-- ============================================================================

REASSIGN OWNED BY session_user TO postgres;
SET ROLE postgres;

GRANT USAGE ON SCHEMA public TO diego_finance_agent;
GRANT SELECT ON TABLE supplier_invoices, vendor_contracts TO diego_finance_agent;
