-- ============================================================================
-- Step 3: Seed Summit Trail Restricted Vendor Finance Schema (2 Tables)
-- Target database: finance_db
-- ============================================================================

SET ROLE postgres;

CREATE TABLE IF NOT EXISTS vendor_contracts (
    contract_id VARCHAR(30) PRIMARY KEY,
    supplier_id VARCHAR(20) NOT NULL,
    supplier_name VARCHAR(120) NOT NULL,
    payment_terms VARCHAR(60) NOT NULL,
    late_delivery_sla_penalty_pct NUMERIC(5,2) NOT NULL,
    contract_status VARCHAR(30) NOT NULL
);

INSERT INTO vendor_contracts VALUES
('CTR-2026-001', 'SUP-001', 'Cascade Ridge Manufacturing', 'Net 45 (2% 10-Day Early Pay)', 5.00, 'Active - Under SLA Review'),
('CTR-2026-002', 'SUP-002', 'Pacific Trail Imports', 'Net 60 Letter of Credit', 7.50, 'Breach Notice Issued')
ON CONFLICT (contract_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS supplier_invoices (
    invoice_id VARCHAR(30) PRIMARY KEY,
    supplier_id VARCHAR(20) NOT NULL,
    invoice_date DATE NOT NULL,
    sku VARCHAR(20) NOT NULL,
    product_name VARCHAR(120) NOT NULL,
    units_billed INT NOT NULL,
    contract_unit_cost_usd NUMERIC(10,2) NOT NULL,
    billed_unit_cost_usd NUMERIC(10,2) NOT NULL,
    sla_penalty_credit_usd NUMERIC(10,2) NOT NULL,
    payment_status VARCHAR(60) NOT NULL
);

INSERT INTO supplier_invoices VALUES
('INV-2026-0718', 'SUP-001', '2026-07-18', 'STS-0009', 'Northfork Bivy', 1100, 84.50, 89.25, 5355.00, 'Disputed - Late Delivery + Surcharge'),
('INV-2026-0624', 'SUP-001', '2026-06-24', 'STS-0006', 'Northfork Dome Tent Lite', 1000, 142.00, 146.00, 6935.00, 'Approved with 5% SLA Credit'),
('INV-2026-0529', 'SUP-001', '2026-05-29', 'STS-0010', 'Basin Canopy Lite', 950, 118.00, 118.00, 0.00, 'Paid (2% Early Pay Discount)')
ON CONFLICT (invoice_id) DO NOTHING;
