-- ============================================================================
-- Step 5: Verification Queries (Fill Rate, DC Breakdown, 2x2 Matrix, Finance)
-- ============================================================================

-- 1. Monthly YTD Unit Fill Rate (Run on inventory_db)
-- Expected: 96.2% (Jan) -> 95.8% (Feb) -> 95.4% (Mar) -> 91.2% (Apr) -> 88.0% (May) -> 85.5% (Jun) -> 83.9% (Jul)
SELECT
    TO_CHAR(DATE_TRUNC('month', o.order_date), 'YYYY-MM') AS order_month,
    SUM(l.qty_ordered) AS ordered_units,
    SUM(l.qty_shipped) AS shipped_units,
    ROUND(100.0 * SUM(l.qty_shipped) / SUM(l.qty_ordered), 1) AS unit_fill_rate_pct
FROM sales_orders o
JOIN sales_order_lines l ON o.order_id = l.order_id
GROUP BY 1
ORDER BY 1;

-- 2. Distribution Center Fill-Rate Variance & Cut Units (Run on inventory_db)
-- Expected: CMH (85.46%, 3,885 cut), DFW (86.02%, 4,833 cut), RNO (89.45%, 3,622 cut) = 12,340 total cut units
SELECT
    dc.dc_code,
    dc.dc_name,
    SUM(l.qty_ordered - l.qty_shipped) AS cut_units,
    ROUND(100.0 * SUM(l.qty_shipped) / SUM(l.qty_ordered), 2) AS fill_rate_pct
FROM sales_orders o
JOIN sales_order_lines l ON o.order_id = l.order_id
JOIN distribution_centers dc ON o.dc_id = dc.dc_id
GROUP BY 1, 2
ORDER BY fill_rate_pct ASC;

-- 3. 2x2 Engine-Level Database Privilege Matrix (Run on inventory_db)
-- Expected: inventory_db = (true, false) | finance_db = (false, true)
SELECT
    d.datname AS database_name,
    has_database_privilege('priya_warehouse_agent', d.datname, 'CONNECT') AS priya_warehouse_agent,
    has_database_privilege('diego_finance_agent', d.datname, 'CONNECT') AS diego_finance_agent
FROM pg_database d
WHERE d.datname IN ('inventory_db', 'finance_db')
ORDER BY d.datname DESC;

-- 4. Authorized Vendor Finance Query (Run on finance_db as diego_finance_agent / postgres)
-- Expected: INV-2026-0718 ($89.25 Disputed), INV-2026-0624 ($146.00 Approved w/ 5% Credit), INV-2026-0529 ($118.00 Paid)
-- SELECT
--     invoice_id,
--     sku,
--     product_name,
--     contract_unit_cost_usd,
--     billed_unit_cost_usd,
--     sla_penalty_credit_usd,
--     payment_status
-- FROM supplier_invoices
-- WHERE supplier_id = 'SUP-001'
-- ORDER BY invoice_date DESC;
