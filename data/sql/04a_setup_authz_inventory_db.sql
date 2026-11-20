-- ============================================================================
-- Step 4: Enforce 2x2 Database Authorization Boundary ("Grants Are the Boundary")
-- Part A: Run against `inventory_db`
-- ============================================================================

REASSIGN OWNED BY session_user TO postgres;
ALTER DATABASE inventory_db OWNER TO postgres;
ALTER DATABASE finance_db OWNER TO postgres;
SET ROLE postgres;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'priya_warehouse_agent') THEN
    CREATE ROLE priya_warehouse_agent LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'diego_finance_agent') THEN
    CREATE ROLE diego_finance_agent LOGIN;
  END IF;
END
$$;

-- 1. Lock down inventory_db: ALLOW priya_warehouse_agent, DENY diego_finance_agent
REVOKE ALL ON DATABASE inventory_db FROM PUBLIC;
GRANT CONNECT ON DATABASE inventory_db TO postgres, priya_warehouse_agent;
REVOKE CONNECT ON DATABASE inventory_db FROM diego_finance_agent;

GRANT USAGE ON SCHEMA public TO priya_warehouse_agent;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO priya_warehouse_agent;

-- 2. Lock down finance_db: DENY priya_warehouse_agent, ALLOW diego_finance_agent
REVOKE ALL ON DATABASE finance_db FROM PUBLIC;
GRANT CONNECT ON DATABASE finance_db TO postgres, diego_finance_agent;
REVOKE CONNECT ON DATABASE finance_db FROM priya_warehouse_agent;
