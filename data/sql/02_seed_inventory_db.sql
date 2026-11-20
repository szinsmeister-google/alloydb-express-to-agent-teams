-- ============================================================================
-- Step 2: Seed Summit Trail Supply Operational Schema (11 Tables)
-- Target database: inventory_db
-- ============================================================================

SET ROLE postgres;

-- 1. Distribution Centers
CREATE TABLE IF NOT EXISTS distribution_centers (
    dc_id SERIAL PRIMARY KEY,
    dc_code VARCHAR(10) UNIQUE NOT NULL,
    dc_name VARCHAR(100) NOT NULL,
    region VARCHAR(50) NOT NULL,
    capacity_units INT NOT NULL
);

INSERT INTO distribution_centers (dc_code, dc_name, region, capacity_units) VALUES
('RNO', 'Reno West Coast Hub', 'West', 250000),
('DFW', 'Fort Worth Central Hub', 'South Central', 300000),
('CMH', 'Columbus Midwest Hub', 'Midwest/East', 280000)
ON CONFLICT (dc_code) DO NOTHING;

-- 2. Suppliers
CREATE TABLE IF NOT EXISTS suppliers (
    supplier_id VARCHAR(20) PRIMARY KEY,
    supplier_name VARCHAR(120) NOT NULL,
    country VARCHAR(60) NOT NULL,
    reliability_tier VARCHAR(20) NOT NULL
);

INSERT INTO suppliers VALUES
('SUP-001', 'Cascade Ridge Manufacturing', 'USA', 'Tier-2 Watch'),
('SUP-002', 'Pacific Trail Imports', 'Vietnam', 'Tier-3 Delinquent'),
('SUP-003', 'Sierra Alpine Textiles', 'USA', 'Tier-1 Preferred'),
('SUP-004', 'Highland Gear Works', 'Taiwan', 'Tier-1 Preferred')
ON CONFLICT (supplier_id) DO NOTHING;

-- 3. Products (Item Master with Configured ERP Lead Times)
CREATE TABLE IF NOT EXISTS products (
    sku VARCHAR(20) PRIMARY KEY,
    product_name VARCHAR(120) NOT NULL,
    category VARCHAR(60) NOT NULL,
    supplier_id VARCHAR(20) REFERENCES suppliers(supplier_id),
    unit_cost NUMERIC(10,2) NOT NULL,
    list_price NUMERIC(10,2) NOT NULL,
    lead_time_days INT NOT NULL,
    reorder_point INT NOT NULL,
    safety_stock INT NOT NULL
);

INSERT INTO products VALUES
('STS-0001', 'Apex 4-Season Expedition Tent', 'Tents & Shelters', 'SUP-002', 112.00, 249.99, 7, 400, 150),
('STS-0002', 'SolarFlare 1000L Rechargeable Lantern', 'Lighting & Electronics', 'SUP-002', 24.50, 59.99, 7, 800, 250),
('STS-0003', 'GlacierVault 45Qt Rotomolded Cooler', 'Hydration & Coolers', 'SUP-002', 88.00, 199.99, 7, 500, 180),
('STS-0004', 'Titanium Dual-Fuel Backcountry Stove', 'Camp Kitchen', 'SUP-002', 31.00, 79.99, 7, 600, 200),
('STS-0005', 'TrailBeam 450 Headlamp Pro', 'Lighting & Electronics', 'SUP-002', 18.20, 44.99, 7, 900, 300),
('STS-0006', 'Northfork Dome Tent Lite', 'Tents & Shelters', 'SUP-001', 67.34, 154.57, 14, 450, 160),
('STS-0007', 'Basin Backpacking Tent', 'Tents & Shelters', 'SUP-001', 71.64, 159.96, 14, 420, 150),
('STS-0008', 'Juniper Tarp Shelter Lite', 'Tents & Shelters', 'SUP-001', 27.15, 49.81, 14, 700, 220),
('STS-0009', 'Northfork Bivy', 'Tents & Shelters', 'SUP-001', 59.75, 129.89, 14, 520, 180),
('STS-0010', 'Basin Canopy Lite', 'Tents & Shelters', 'SUP-001', 35.91, 74.91, 14, 600, 200),
('STS-0011', 'Sierra Down Sleeping Bag 20F', 'Sleep Systems', 'SUP-003', 95.00, 219.00, 10, 350, 120),
('STS-0012', 'Highland Carbon Trekking Poles', 'Packs & Poles', 'SUP-004', 42.00, 99.50, 12, 500, 160)
ON CONFLICT (sku) DO NOTHING;

-- 4. Customers
CREATE TABLE IF NOT EXISTS customers (
    customer_id SERIAL PRIMARY KEY,
    customer_name VARCHAR(120) NOT NULL,
    channel VARCHAR(40) NOT NULL,
    preferred_dc_id INT REFERENCES distribution_centers(dc_id)
);

INSERT INTO customers (customer_id, customer_name, channel, preferred_dc_id) VALUES
(1, 'Outfitter Collective Midwest', 'Wholesale Distributor', 3),
(2, 'Lone Star Outdoor Co-op', 'Wholesale Distributor', 2),
(3, 'Sierra Crest Retail Group', 'Wholesale Distributor', 1),
(4, 'Great Lakes Adventure Supply', 'Regional Chain', 3),
(5, 'Red River Outfitters', 'Regional Chain', 2)
ON CONFLICT (customer_id) DO NOTHING;

SELECT setval('customers_customer_id_seq', (SELECT COALESCE(MAX(customer_id), 1) FROM customers));

-- 5. Inventory Snapshots (Showing Surplus in DFW vs Stockouts in CMH for Top Cut SKUs)
CREATE TABLE IF NOT EXISTS inventory_snapshots (
    snapshot_id SERIAL PRIMARY KEY,
    snapshot_date DATE NOT NULL,
    dc_id INT REFERENCES distribution_centers(dc_id),
    sku VARCHAR(20) REFERENCES products(sku),
    on_hand_qty INT NOT NULL,
    reserved_qty INT NOT NULL,
    available_qty INT NOT NULL
);

TRUNCATE TABLE inventory_snapshots RESTART IDENTITY CASCADE;

INSERT INTO inventory_snapshots (snapshot_date, dc_id, sku, on_hand_qty, reserved_qty, available_qty) VALUES
('2026-07-28', 3, 'STS-0001', 12, 12, 0),
('2026-07-28', 2, 'STS-0001', 1420, 180, 1240),
('2026-07-28', 1, 'STS-0001', 610, 110, 500),
('2026-07-28', 3, 'STS-0006', 8, 8, 0),
('2026-07-28', 2, 'STS-0006', 1180, 140, 1040),
('2026-07-28', 3, 'STS-0009', 0, 0, 0),
('2026-07-28', 1, 'STS-0009', 980, 120, 860),
('2026-07-28', 2, 'STS-0003', 15, 15, 0),
('2026-07-28', 1, 'STS-0003', 1120, 150, 970);

-- 6. Purchase Orders & 7. Purchase Order Lines (Configured vs Actual Lead-Time Slippage)
CREATE TABLE IF NOT EXISTS purchase_orders (
    po_id SERIAL PRIMARY KEY,
    supplier_id VARCHAR(20) REFERENCES suppliers(supplier_id),
    dc_id INT REFERENCES distribution_centers(dc_id),
    order_date DATE NOT NULL,
    promised_date DATE NOT NULL,
    status VARCHAR(30) NOT NULL
);

CREATE TABLE IF NOT EXISTS purchase_order_lines (
    po_line_id SERIAL PRIMARY KEY,
    po_id INT REFERENCES purchase_orders(po_id),
    sku VARCHAR(20) REFERENCES products(sku),
    qty_ordered INT NOT NULL,
    qty_received INT NOT NULL,
    received_date DATE NOT NULL,
    actual_lead_time_days INT NOT NULL
);

TRUNCATE TABLE purchase_order_lines, purchase_orders RESTART IDENTITY CASCADE;

INSERT INTO purchase_orders (po_id, supplier_id, dc_id, order_date, promised_date, status) VALUES
(101, 'SUP-002', 3, '2026-06-01', '2026-06-08', 'received_late'),
(102, 'SUP-002', 2, '2026-06-15', '2026-06-22', 'received_late'),
(103, 'SUP-001', 3, '2026-06-05', '2026-06-19', 'received_late'),
(104, 'SUP-001', 2, '2026-07-01', '2026-07-15', 'received_late'),
(105, 'SUP-003', 1, '2026-06-10', '2026-06-20', 'received_on_time');

INSERT INTO purchase_order_lines (po_id, sku, qty_ordered, qty_received, received_date, actual_lead_time_days) VALUES
(101, 'STS-0001', 1200, 1200, '2026-06-22', 21),
(101, 'STS-0002', 1500, 1500, '2026-06-22', 21),
(102, 'STS-0003', 900, 900, '2026-07-06', 21),
(103, 'STS-0006', 1000, 820, '2026-07-18', 33),
(104, 'STS-0009', 1100, 880, '2026-08-05', 35),
(105, 'STS-0011', 800, 800, '2026-06-20', 10);

-- 8. Sales Orders & 9. Sales Order Lines (Monthly YTD Fill Rate: 96.2% Jan -> 83.9% July; 12,340 Cut Units)
CREATE TABLE IF NOT EXISTS sales_orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(customer_id),
    dc_id INT REFERENCES distribution_centers(dc_id),
    order_date DATE NOT NULL,
    promised_ship_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL -- shipped = every line complete, partial = some shipped, cut = nothing shipped
);

COMMENT ON TABLE sales_orders IS 'Customer order headers. status: shipped = every line complete, partial = some quantity shipped, cut = nothing shipped.';

CREATE TABLE IF NOT EXISTS sales_order_lines (
    line_id SERIAL PRIMARY KEY,
    order_id INT REFERENCES sales_orders(order_id),
    sku VARCHAR(20) REFERENCES products(sku),
    qty_ordered INT NOT NULL,
    qty_shipped INT NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL,
    ship_date DATE
);

TRUNCATE TABLE sales_order_lines, sales_orders RESTART IDENTITY CASCADE;

INSERT INTO sales_orders (order_id, customer_id, dc_id, order_date, promised_ship_date, status) VALUES
(1,  3, 1, '2026-01-15', '2026-01-18', 'shipped'),
(2,  2, 2, '2026-02-15', '2026-02-18', 'shipped'),
(3,  3, 1, '2026-03-15', '2026-03-18', 'shipped'),
(4,  1, 3, '2026-04-15', '2026-04-18', 'partial'),
(5,  2, 2, '2026-05-15', '2026-05-18', 'partial'),
(6,  3, 1, '2026-06-12', '2026-06-15', 'partial'),
(7,  2, 2, '2026-06-20', '2026-06-23', 'partial'),
(8,  1, 3, '2026-07-10', '2026-07-13', 'cut'),
(9,  2, 2, '2026-07-18', '2026-07-21', 'partial'),
(10, 3, 1, '2026-07-24', '2026-07-27', 'partial');

INSERT INTO sales_order_lines (order_id, sku, qty_ordered, qty_shipped, unit_price, ship_date) VALUES
(1,  'STS-0011',  5000,  4810, 219.00, '2026-01-18'), -- Jan: 96.2% (RNO)
(2,  'STS-0012',  5000,  4790,  99.50, '2026-02-18'), -- Feb: 95.8% (DFW)
(3,  'STS-0001',  5000,  4770, 249.99, '2026-03-18'), -- Mar: 95.4% (RNO)
(4,  'STS-0001',  6000,  5472, 249.99, '2026-04-18'), -- Apr: 91.2% (CMH)
(5,  'STS-0003', 10000,  8800, 199.99, '2026-05-18'), -- May: 88.0% (DFW)
(6,  'STS-0002', 14340, 12260,  59.99, '2026-06-15'), -- Jun RNO
(7,  'STS-0004', 12300, 10517,  79.99, '2026-06-23'), -- Jun DFW (Total Jun: 85.5%)
(8,  'STS-0006', 20720, 17363, 154.57, '2026-07-13'), -- Jul CMH cut (CMH YTD: 85.46%, 3,885 cut)
(9,  'STS-0003',  7280,  5640, 199.99, '2026-07-21'), -- Jul DFW partial (DFW YTD: 86.02%, 4,833 cut)
(10, 'STS-0009', 10000,  8878, 129.89, '2026-07-27'); -- Jul RNO partial (RNO YTD: 89.45%, 3,622 cut; Jul Total: 83.9%)

-- 10. Cycle Counts (325 Warehouse Audits at 98.62% Accuracy — Used by Devil's Advocate s10)
CREATE TABLE IF NOT EXISTS cycle_counts (
    audit_id SERIAL PRIMARY KEY,
    dc_id INT REFERENCES distribution_centers(dc_id),
    sku VARCHAR(20) REFERENCES products(sku),
    audit_date DATE NOT NULL,
    system_qty INT NOT NULL,
    physical_qty INT NOT NULL,
    accuracy_pct NUMERIC(5,2) NOT NULL
);

TRUNCATE TABLE cycle_counts RESTART IDENTITY CASCADE;

INSERT INTO cycle_counts (dc_id, sku, audit_date, system_qty, physical_qty, accuracy_pct)
SELECT
    (g % 3) + 1,
    CASE WHEN g % 2 = 0 THEN 'STS-0001' ELSE 'STS-0006' END,
    DATE '2026-05-01' + (g % 85),
    500,
    493,
    98.62
FROM generate_series(1, 325) AS g;

-- 11. Demand Forecasts (Proving Customer Orders Tracked Within 1.8% of Forecast)
CREATE TABLE IF NOT EXISTS demand_forecasts (
    forecast_id SERIAL PRIMARY KEY,
    forecast_month DATE NOT NULL,
    sku VARCHAR(20) REFERENCES products(sku),
    forecast_units INT NOT NULL,
    actual_ordered_units INT NOT NULL,
    variance_pct NUMERIC(5,2) NOT NULL
);

TRUNCATE TABLE demand_forecasts RESTART IDENTITY CASCADE;

INSERT INTO demand_forecasts (forecast_month, sku, forecast_units, actual_ordered_units, variance_pct) VALUES
('2026-05-01', 'STS-0001', 11800, 12000, 1.69),
('2026-06-01', 'STS-0006', 11850, 12000, 1.27),
('2026-07-01', 'STS-0006', 11790, 12000, 1.78);
