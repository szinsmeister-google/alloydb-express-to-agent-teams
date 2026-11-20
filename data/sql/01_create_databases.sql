-- ============================================================================
-- Step 1: Grant database creation roles and create Summit Trail databases
-- Target database: postgres
--
-- NOTE (PostgreSQL 18 + MCP):
--   1. CREATEDB and CREATEROLE are not automatically inherited via INHERIT.
--      Run statement 1 first using `session_user` (targets your IAM user).
--   2. CREATE DATABASE cannot run inside a multi-statement transaction block.
--      Execute statements 2 and 3 individually (see scripts/setup_express_and_seed.sh).
-- ============================================================================

-- Statement 1:
SET ROLE postgres;
ALTER ROLE session_user CREATEDB CREATEROLE;

-- Statement 2 (run individually):
-- CREATE DATABASE inventory_db;

-- Statement 3 (run individually):
-- CREATE DATABASE finance_db;
