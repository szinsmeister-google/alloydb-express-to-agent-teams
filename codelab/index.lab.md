---
id: alloydb-express-to-agent-teams
summary: Build an end-to-end multi-agent root-cause investigation system from scratch using AlloyDB Express, AlloyDB PostgreSQL for Agents, Knowledge Catalog, and Google ADK.
authors: Sean Zinsmeister
duration: 57
keywords: docType:Codelab, category:Cloud, product:AlloyDbForPostgresql, product:VertexAi
layout: paginated

---
{# disableFinding(HEADING_NO_ID_H2) #}
{# disableFinding(HEADING_NO_ID_H3) #}
{# disableFinding(LINE_OVER_80_LINK) #}
{# disableFinding(IMAGE_IMG) #}

# Build Multi-Agent Teams with AlloyDB for PostgreSQL

## Introduction
Duration: 03:00

Every engineering team building with AI faces the same architectural dilemma: **how do you give autonomous agents direct access to live operational data without risking production stability?**

Traditional architectures force a painful compromise. If you point agents at a downstream analytical warehouse, they reason over stale ETL pipelines that miss what happened ten minutes ago on the warehouse floor. If you point a team of concurrent agents directly at your transactional PostgreSQL primary, an uncoordinated burst of diagnostic queries can spike CPU, exhaust connection pools, and slow down customer checkout.

With **AlloyDB Express** and **AlloyDB PostgreSQL for Agents**, you don't have to choose. You can spin up a scale-to-zero PostgreSQL 18 sandbox in under two seconds straight from your coding agent (**Antigravity** or **Claude Code**), graduate in place to enterprise **AlloyDB** with a single command, and attach a serverless, read-only **Agent Pool** of isolated microVMs that reads the exact same live **Google Colossus** storage blocks with sub-millisecond I/O freshness and zero load on your transactional primary—so your agents can **share the data, and share nothing else**.

![End-to-End Codelab Architecture](image/workflow.png)

### The scenario: Summit Trail Supply

In this codelab, you step into the role of Lead Data & AI Systems Architect at **Summit Trail Supply**, a national outdoor gear retailer operating three regional distribution centers in **Reno** (`RNO`), **Columbus** (`CMH`), and **Fort Worth** (`DFW`).

Summit Trail Supply held above its **95.0% unit fill-rate target** throughout Q1, but fill rates suddenly dropped to **83.9% in July**, costing **12,340 cut units (over $1.29M in lost distributor revenue)**. You will build the complete data and multi-agent investigation stack from scratch for two stakeholders:
1. **Priya (VP of Warehouse Operations)** — Needs an **Operations Agent** and a **10-agent root-cause investigation team** (including a **Devil's Advocate** agent) to pinpoint why fill rates dropped and simulate inventory routing fixes against `inventory_db`.
2. **Diego (VP of Vendor Finance)** — Manages restricted vendor contracts and disputed supplier invoices in `finance_db`, requiring strict, database-enforced isolation so warehouse agents can never read confidential invoice pricing.

### What you'll build

* **Stage 1 — Prototype in 2 seconds with AlloyDB Express & MCP**: Connect **Antigravity** or **Claude Code** to the **AlloyDB Remote MCP Server** (`https://alloydb.googleapis.com/mcp`), provision a scale-to-zero **AlloyDB Express** cluster running PostgreSQL 18, and seed two databases (`inventory_db` and `finance_db`).
* **Stage 2 — In-Place Upgrade, Agent Mode & Knowledge Catalog**: Upgrade your AlloyDB Express cluster in place with zero data movement, enable **Agent mode**, provision a serverless **Agent Pool** (`0 → 10` microVMs), and inspect the connected **Context Graph** (`sales_orders`) in **Knowledge Catalog Studio**.
* **Stage 3 — Google ADK Operations Agent & 10-Agent Investigation Team**: Build a Python agent using **Google ADK** connected to the Agent Pool's `/mcp` endpoint (`get_schema` and `execute_sql_read_only`), then fan out a **10-agent parallel investigation team** featuring 9 supply-chain specialists (`s01`–`s09`), a **Devil's Advocate** (`s10`), and counterfactual simulation queries.
* **Stage 4 — Scale-to-Zero Telemetry & 2×2 Database Authorization**: Verify in **Cloud Monitoring** that primary CPU holds flat (~15%) while the Agent Pool absorbs 200+ concurrent MCP queries and scales back to zero, then enforce and test a **2×2 IAM Database Privilege Matrix** (`has_database_privilege`) proving engine-level refusal (`SQLSTATE 42501`).

### What you'll need

* A Google Cloud project with billing enabled.
* **Antigravity**, **Claude Code**, or **Google Cloud Shell** (with `gcloud`, Python 3.11+, and `pip` installed).
* **Estimated Cost**: Designed to run within the **AlloyDB Express** free allowance and `< $5 USD` total consumption when you run the **Clean up** step at the end of the lab.

---

## Before you begin
Duration: 05:00

To prepare your environment, configure your Google Cloud project variables, enable the required APIs, and connect your AI coding assistant (**Antigravity** or **Claude Code**) to the **AlloyDB Remote MCP Server**.

### Choose a supported region and set environment variables

During Preview, **AlloyDB Express** and **AlloyDB PostgreSQL for Agents** are supported in specific regions:
* **Both AlloyDB Express + In-Place Agent Mode Upgrade**: `asia-southeast1` (Singapore).
* **AlloyDB Express Preview Regions**: `us-west1`, `europe-west2`, `asia-southeast1`, `asia-east1`, `asia-east2`, `asia-northeast1`, `australia-southeast1`.
* **AlloyDB PostgreSQL for Agents Preview Regions**: `us-central1`, `us-east1`, `us-east4`, `us-east5`, `us-south1`, `us-west4`, `europe-west1`, `asia-southeast1`.

In your terminal or Cloud Shell, update `gcloud` components and set your project ID, region (`asia-southeast1` for end-to-end Express-to-Agent Mode in place, or `us-central1` if creating an Agent Mode cluster directly), and resource identifiers:

```bash
# Set your active Google Cloud project ID first (if not already configured):
# gcloud config set project YOUR_PROJECT_ID

export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
export REGION="asia-southeast1"
export CLUSTER_ID="summit-trail-cluster"
export PRIMARY_ID="summit-trail-primary"
export POOL_ID="summit-trail-agent-pool"
export DB_PASSWORD="SummitTrail!2026"

gcloud config set project $PROJECT_ID
gcloud auth application-default set-quota-project $PROJECT_ID 2>/dev/null || true
```

Enable the required Google Cloud APIs for AlloyDB, Private Service Connect, Vertex AI, Knowledge Catalog (Dataplex), and Cloud Monitoring:

```bash
gcloud services enable \
  alloydb.googleapis.com \
  compute.googleapis.com \
  servicenetworking.googleapis.com \
  networkconnectivity.googleapis.com \
  aiplatform.googleapis.com \
  dataplex.googleapis.com \
  monitoring.googleapis.com \
  dns.googleapis.com
```

Expected output:

```console
Operation "operations/acf.p2-..." finished successfully.
```

### Grant IAM roles for AlloyDB and the Remote MCP Server

Grant your user account **AlloyDB Admin** (`roles/alloydb.admin`), **Compute Network User** (`roles/compute.networkUser`), and **MCP Tool User** (`roles/mcp.toolUser`) so your coding agent can provision clusters, manage IAM database users, and execute SQL over the AlloyDB Remote MCP Server:

```bash
export USER_EMAIL=$(gcloud config get-value account)

for ROLE in roles/alloydb.admin roles/compute.networkUser roles/mcp.toolUser; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="user:$USER_EMAIL" \
    --role="$ROLE" \
    --condition=None
done
```

### Connect Antigravity or Claude Code to the AlloyDB Remote MCP Server

The **AlloyDB Remote MCP Server** (`https://alloydb.googleapis.com/mcp`) is a managed, globally available Model Context Protocol endpoint that lets coding agents create clusters, inspect schemas, and run SQL without local database drivers.

Authenticate Application Default Credentials with the `alloydb` and `cloud-platform` scopes:

```bash
gcloud auth application-default login \
  --scopes="https://www.googleapis.com/auth/alloydb,https://www.googleapis.com/auth/cloud-platform"
```

Add the AlloyDB Remote MCP Server to your coding agent configuration:

* **Option A — Antigravity** (`mcp_config.json`):
  ```json
  {
    "mcpServers": {
      "alloydb": {
        "serverUrl": "https://alloydb.googleapis.com/mcp",
        "transport": "streamable-http"
      }
    }
  }
  ```
* **Option B — Claude Code CLI**:
  ```bash
  claude mcp add --transport http alloydb https://alloydb.googleapis.com/mcp \
    --header "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
    --header "X-Goog-User-Project: $PROJECT_ID"
  ```

Verify that the remote MCP server responds by listing its available tools with `curl`:

```bash
curl -s -X POST https://alloydb.googleapis.com/mcp \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "X-Goog-User-Project: $PROJECT_ID" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Mcp-Method: tools/list" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | grep -o '"name":"[^"]*"' | head -n 16
```

Expected output:

```console
"name":"list_clusters"
"name":"create_cluster"
"name":"get_cluster"
"name":"list_instances"
"name":"restore_cluster"
"name":"create_backup"
"name":"create_instance"
"name":"get_instance"
"name":"update_instance"
"name":"create_user"
"name":"get_user"
"name":"list_users"
"name":"execute_sql"
"name":"execute_sql_read_only"
"name":"export_data"
"name":"import_data"
```

> aside positive
> **Behind the scenes:** When you enable `alloydb.googleapis.com`, Google Cloud automatically exposes the managed AlloyDB Remote MCP Server at `https://alloydb.googleapis.com/mcp`. Your coding agent can now provision infrastructure and execute SQL using standard MCP tool calls governed by your Google Cloud IAM permissions.

---

## Prototype in seconds with AlloyDB Express and your coding agent
Duration: 08:00

When starting a new application or agent prototype, waiting 15 minutes for VPC peering and paying for always-on enterprise instances slows down iteration. **AlloyDB Express** is a lightweight configuration of AlloyDB for PostgreSQL 18 that provisions in **under two seconds** over public DNS, includes full AlloyDB AI capabilities on a 1-vCPU (`4 GB` RAM) footprint, and **scales compute to zero** automatically after 15 minutes of inactivity.

### Provision an AlloyDB Express cluster, primary instance, and IAM user

In **Antigravity** or **Claude Code**, enter the following natural-language prompt to spin up your AlloyDB Express cluster, its 1-vCPU primary instance, and your IAM database user:

```text
In project $PROJECT_ID and location $REGION, create an AlloyDB Express cluster named summit-trail-cluster, create a 1-vCPU primary instance named summit-trail-primary with publicDnsEnabled set to true, and create an IAM database user for my email with databaseRoles ["alloydbiamuser", "postgres"].
```

Your coding agent calls `create_cluster` (`expressConfig: {"enabled": true}`), polls `get_operation` (~1.2 seconds), calls `create_instance` (`type: "PRIMARY"`, `publicDnsEnabled: true`), and calls `create_user` (`databaseRoles: ["alloydbiamuser", "postgres"]`).

If you prefer to execute the exact same provisioning steps from your terminal using `curl` against the AlloyDB v1beta REST API (or `gcloud beta`), run:

```bash
# 1. Create the AlloyDB Express cluster (completes in ~1-2 seconds)
curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://alloydb.googleapis.com/v1beta/projects/$PROJECT_ID/locations/$REGION/clusters?clusterId=$CLUSTER_ID" \
  -d "{
    \"databaseVersion\": \"POSTGRES_18\",
    \"expressConfig\": {\"enabled\": true},
    \"initialUser\": {\"user\": \"postgres\", \"password\": \"$DB_PASSWORD\"}
  }"

# 2. Create the 1-vCPU Primary Instance with Public DNS & Data API enabled
curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://alloydb.googleapis.com/v1beta/projects/$PROJECT_ID/locations/$REGION/clusters/$CLUSTER_ID/instances?instanceId=$PRIMARY_ID" \
  -d "{
    \"instanceType\": \"PRIMARY\",
    \"availabilityType\": \"ZONAL\",
    \"machineConfig\": {\"cpuCount\": 1},
    \"databaseFlags\": {\"alloydb.iam_authentication\": \"on\"},
    \"networkConfig\": {\"publicDnsEnabled\": true},
    \"pscInstanceConfig\": {\"allowedConsumerProjects\": [\"$PROJECT_ID\"]}
  }"

# 3. Register your IAM database user (Data API access is enabled by default on AlloyDB Express)
gcloud alloydb users create "$USER_EMAIL" \
  --cluster=$CLUSTER_ID \
  --region=$REGION \
  --type=IAM_BASED \
  --db-roles=alloydbiamuser,postgres \
  --project=$PROJECT_ID
```

### Create the two databases (`inventory_db` and `finance_db`)

> aside negative
> **Important PostgreSQL 18 & MCP Note:**
> 1. In PostgreSQL 18, the `CREATEDB` and `CREATEROLE` role attributes are not inherited automatically by `INHERIT`. When running via MCP `execute_sql` as your IAM user, run `SET ROLE postgres; ALTER ROLE session_user CREATEDB CREATEROLE;` first (`session_user` targets your logged-in IAM identity, whereas `current_user` after `SET ROLE postgres` would target `postgres`).
> 2. In PostgreSQL, `CREATE DATABASE` cannot run inside a multi-statement transaction block. Always execute each `CREATE DATABASE` statement as its own separate query.

If you are working in **Cloud Shell** or your terminal, define this helper function (`alloydb_sql`) to execute SQL directly over the **AlloyDB Remote MCP Server** (`https://alloydb.googleapis.com/mcp`) without switching browser tabs (or run the SQL blocks below in **AlloyDB Studio**):

```bash
alloydb_sql() {
  local db="$1"
  local sql="$2"
  local instance="projects/$PROJECT_ID/locations/$REGION/clusters/$CLUSTER_ID/instances/$PRIMARY_ID"
  curl -s -X POST https://alloydb.googleapis.com/mcp \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "X-Goog-User-Project: $PROJECT_ID" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"execute_sql","arguments":{"instance":sys.argv[1],"database":sys.argv[2],"sqlStatement":sys.argv[3]}}}))' "$instance" "$db" "$sql")"
  echo ""
}

alloydb_sql postgres "SET ROLE postgres; ALTER ROLE session_user CREATEDB CREATEROLE;"
alloydb_sql postgres "CREATE DATABASE inventory_db;"
alloydb_sql postgres "CREATE DATABASE finance_db;"
```

Or run the equivalent three single-statement SQL calls in **AlloyDB Studio** (connected to `postgres`) or via your coding agent's `execute_sql` tool on `database: "postgres"`:

1. **Grant database creation roles** (`CREATEDB` and `CREATEROLE`) to your logged-in IAM user (`session_user`):
   ```sql
   SET ROLE postgres; ALTER ROLE session_user CREATEDB CREATEROLE;
   ```
2. **Create the operational warehouse database** (`inventory_db`, run as a single statement):
   ```sql
   CREATE DATABASE inventory_db;
   ```
3. **Create the vendor finance database** (`finance_db`, run as a single statement):
   ```sql
   CREATE DATABASE finance_db;
   ```

Expected output:

```console
{"sqlResults":[{}],"metadata":{"sqlStatementExecutionDuration":"0.123s","status":"OK"}}
```

### Seed `inventory_db` and `finance_db`

Switch your connection in **AlloyDB Studio** (or set `database: "inventory_db"` in your coding agent's `execute_sql` call) to `inventory_db` and run the following SQL script to create all **11 operational supply-chain tables** (under `SET ROLE postgres;` so `postgres` owns all tables uniformly across Studio and MCP) and load the 2026 YTD dataset:

```sql
SET ROLE postgres;

-- 1. Distribution Centers
CREATE TABLE distribution_centers (
    dc_id SERIAL PRIMARY KEY,
    dc_code VARCHAR(10) UNIQUE NOT NULL,
    dc_name VARCHAR(100) NOT NULL,
    region VARCHAR(50) NOT NULL,
    capacity_units INT NOT NULL
);

INSERT INTO distribution_centers (dc_code, dc_name, region, capacity_units) VALUES
('RNO', 'Reno West Coast Hub', 'West', 250000),
('DFW', 'Fort Worth Central Hub', 'South Central', 300000),
('CMH', 'Columbus Midwest Hub', 'Midwest/East', 280000);

-- 2. Suppliers
CREATE TABLE suppliers (
    supplier_id VARCHAR(20) PRIMARY KEY,
    supplier_name VARCHAR(120) NOT NULL,
    country VARCHAR(60) NOT NULL,
    reliability_tier VARCHAR(20) NOT NULL
);

INSERT INTO suppliers VALUES
('SUP-001', 'Cascade Ridge Manufacturing', 'USA', 'Tier-2 Watch'),
('SUP-002', 'Pacific Trail Imports', 'Vietnam', 'Tier-3 Delinquent'),
('SUP-003', 'Sierra Alpine Textiles', 'USA', 'Tier-1 Preferred'),
('SUP-004', 'Highland Gear Works', 'Taiwan', 'Tier-1 Preferred');

-- 3. Products (Item Master with Configured ERP Lead Times)
CREATE TABLE products (
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
('STS-0012', 'Highland Carbon Trekking Poles', 'Packs & Poles', 'SUP-004', 42.00, 99.50, 12, 500, 160);

-- 4. Customers
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    customer_name VARCHAR(120) NOT NULL,
    channel VARCHAR(40) NOT NULL,
    preferred_dc_id INT REFERENCES distribution_centers(dc_id)
);

INSERT INTO customers (customer_name, channel, preferred_dc_id) VALUES
('Outfitter Collective Midwest', 'Wholesale Distributor', 3),
('Lone Star Outdoor Co-op', 'Wholesale Distributor', 2),
('Sierra Crest Retail Group', 'Wholesale Distributor', 1),
('Great Lakes Adventure Supply', 'Regional Chain', 3),
('Red River Outfitters', 'Regional Chain', 2);

-- 5. Inventory Snapshots (Showing Surplus in DFW vs Stockouts in CMH for Top Cut SKUs)
CREATE TABLE inventory_snapshots (
    snapshot_id SERIAL PRIMARY KEY,
    snapshot_date DATE NOT NULL,
    dc_id INT REFERENCES distribution_centers(dc_id),
    sku VARCHAR(20) REFERENCES products(sku),
    on_hand_qty INT NOT NULL,
    reserved_qty INT NOT NULL,
    available_qty INT NOT NULL
);

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
CREATE TABLE purchase_orders (
    po_id SERIAL PRIMARY KEY,
    supplier_id VARCHAR(20) REFERENCES suppliers(supplier_id),
    dc_id INT REFERENCES distribution_centers(dc_id),
    order_date DATE NOT NULL,
    promised_date DATE NOT NULL,
    status VARCHAR(30) NOT NULL
);

CREATE TABLE purchase_order_lines (
    po_line_id SERIAL PRIMARY KEY,
    po_id INT REFERENCES purchase_orders(po_id),
    sku VARCHAR(20) REFERENCES products(sku),
    qty_ordered INT NOT NULL,
    qty_received INT NOT NULL,
    received_date DATE NOT NULL,
    actual_lead_time_days INT NOT NULL
);

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
CREATE TABLE sales_orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(customer_id),
    dc_id INT REFERENCES distribution_centers(dc_id),
    order_date DATE NOT NULL,
    promised_ship_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL -- shipped = every line complete, partial = some shipped, cut = nothing shipped
);

COMMENT ON TABLE sales_orders IS 'Customer order headers. status: shipped = every line complete, partial = some quantity shipped, cut = nothing shipped.';

CREATE TABLE sales_order_lines (
    line_id SERIAL PRIMARY KEY,
    order_id INT REFERENCES sales_orders(order_id),
    sku VARCHAR(20) REFERENCES products(sku),
    qty_ordered INT NOT NULL,
    qty_shipped INT NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL,
    ship_date DATE
);

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
CREATE TABLE cycle_counts (
    audit_id SERIAL PRIMARY KEY,
    dc_id INT REFERENCES distribution_centers(dc_id),
    sku VARCHAR(20) REFERENCES products(sku),
    audit_date DATE NOT NULL,
    system_qty INT NOT NULL,
    physical_qty INT NOT NULL,
    accuracy_pct NUMERIC(5,2) NOT NULL
);

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
CREATE TABLE demand_forecasts (
    forecast_id SERIAL PRIMARY KEY,
    forecast_month DATE NOT NULL,
    sku VARCHAR(20) REFERENCES products(sku),
    forecast_units INT NOT NULL,
    actual_ordered_units INT NOT NULL,
    variance_pct NUMERIC(5,2) NOT NULL
);

INSERT INTO demand_forecasts (forecast_month, sku, forecast_units, actual_ordered_units, variance_pct) VALUES
('2026-05-01', 'STS-0001', 11800, 12000, 1.69),
('2026-06-01', 'STS-0006', 11850, 12000, 1.27),
('2026-07-01', 'STS-0006', 11790, 12000, 1.78);
```

Now switch your connection to `finance_db` in AlloyDB Studio (or set `database: "finance_db"` in your coding agent's `execute_sql` call) and seed the **2 restricted vendor finance tables**:

```sql
SET ROLE postgres;

CREATE TABLE vendor_contracts (
    contract_id VARCHAR(30) PRIMARY KEY,
    supplier_id VARCHAR(20) NOT NULL,
    supplier_name VARCHAR(120) NOT NULL,
    payment_terms VARCHAR(60) NOT NULL,
    late_delivery_sla_penalty_pct NUMERIC(5,2) NOT NULL,
    contract_status VARCHAR(30) NOT NULL
);

INSERT INTO vendor_contracts VALUES
('CTR-2026-001', 'SUP-001', 'Cascade Ridge Manufacturing', 'Net 45 (2% 10-Day Early Pay)', 5.00, 'Active - Under SLA Review'),
('CTR-2026-002', 'SUP-002', 'Pacific Trail Imports', 'Net 60 Letter of Credit', 7.50, 'Breach Notice Issued');

CREATE TABLE supplier_invoices (
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
('INV-2026-0529', 'SUP-001', '2026-05-29', 'STS-0010', 'Basin Canopy Lite', 950, 118.00, 118.00, 0.00, 'Paid (2% Early Pay Discount)');
```

Verify your AlloyDB Express setup by running the following query against `inventory_db`:

```sql
SELECT
    TO_CHAR(DATE_TRUNC('month', o.order_date), 'YYYY-MM') AS order_month,
    SUM(l.qty_ordered) AS ordered_units,
    SUM(l.qty_shipped) AS shipped_units,
    ROUND(100.0 * SUM(l.qty_shipped) / SUM(l.qty_ordered), 1) AS unit_fill_rate_pct
FROM sales_orders o
JOIN sales_order_lines l ON o.order_id = l.order_id
GROUP BY 1
ORDER BY 1;
```

Expected output (`0.02s`):

```console
 order_month | ordered_units | shipped_units | unit_fill_rate_pct
-------------+---------------+---------------+--------------------
 2026-01     |          5000 |          4810 |               96.2
 2026-02     |          5000 |          4790 |               95.8
 2026-03     |          5000 |          4770 |               95.4
 2026-04     |          6000 |          5472 |               91.2
 2026-05     |         10000 |          8800 |               88.0
 2026-06     |         26640 |         22777 |               85.5
 2026-07     |         38000 |         31881 |               83.9
```

---

## Upgrade in place to AlloyDB and enable Agent mode
Duration: 08:00

Your prototype schemas and baseline data are ready on AlloyDB Express. Now you want to unleash a **10-agent parallel investigation team** to diagnose the July fill-rate drop.

If ten concurrent AI agents fire analytical joins and counterfactual simulations against a small primary instance, they compete directly with transactional writes. By upgrading in place to **AlloyDB** and enabling **Agent mode**, you attach a serverless, read-only **Agent Pool** of isolated microVMs that reads the shared **Colossus** storage layer without touching primary CPU.

> aside positive
> **Two ways to pace this step (Fast-Track on Express vs. Full In-Place Upgrade):**
> * **Option A — Fast-Track on AlloyDB Express (Zero Wait, No Preview Allowlist Required):** Because `operations_agent.py`, the 10-agent `team_agent.py`, and the 2×2 PostgreSQL privilege matrix in Steps `#5`–`#7` work over the **AlloyDB Remote MCP Server** (`https://alloydb.googleapis.com/mcp`), you can **run Steps `#4`–`#7` immediately against your 2-second AlloyDB Express cluster** (or if your project is not yet enrolled in the [AlloyDB PostgreSQL for Agents Preview allowlist](https://forms.gle/suyoiGCYdrhsqrR28)).
> * **Option B — Full In-Place Upgrade + Serverless Agent Pool (~10–15 mins background VM provisioning):** While AlloyDB Express provisions in ~2 seconds on shared scale-to-zero infrastructure, graduating to standard AlloyDB (`--no-enable-express`) provisions dedicated VM compute in the background (`~10–15 minutes`, during which the instance is in `UPGRADING` state). Run the upgrade in one terminal tab while you explore **Knowledge Catalog Studio** (Step `#4`) and create `operations_agent.py` and `team_agent.py` (Steps `#5`–`#6`) in a second terminal tab.

### Perform a one-command in-place upgrade from AlloyDB Express

In regions that support 1-vCPU `C4A` instances (such as `asia-southeast1`), you can upgrade a 1-vCPU AlloyDB Express cluster in place directly without resizing to `2 vCPUs` first. Run `gcloud beta alloydb clusters update --no-enable-express` so the CLI waits for the cluster upgrade operation (`UPGRADING` → `READY`, which takes ~10–15 minutes while dedicated compute provisions) to finish before you enable Agent mode:

```bash
# If your region does not support 1-vCPU C4A instances, resize to 2 vCPUs first and wait for completion:
# gcloud alloydb instances update $PRIMARY_ID --cluster=$CLUSTER_ID --region=$REGION --cpu-count=2 --project=$PROJECT_ID

# In-place upgrade from AlloyDB Express to Enterprise AlloyDB (waits until cluster is READY)
gcloud beta alloydb clusters update $CLUSTER_ID \
  --region=$REGION \
  --no-enable-express \
  --project=$PROJECT_ID
```

> aside positive
> **Behind the scenes:** An in-place upgrade from AlloyDB Express preserves all of your databases (`inventory_db` and `finance_db`), schemas, extensions, IAM users, and public DNS/PSC endpoints. You don't have to dump, restore, or change a single connection string in your application.

### Configure the VPC Service Connection Policy for the Agent Pool

When you create an Agent Pool, AlloyDB uses a Private Service Connect **service connection policy** (`google-cloud-alloydb`) to automatically place a private HTTPS `/mcp` endpoint inside your consumer VPC network.

Create a dedicated VPC network, subnet, and service connection policy for your agents:

```bash
gcloud compute networks create agents-vpc \
  --project=$PROJECT_ID \
  --subnet-mode=custom

gcloud compute networks subnets create agents-subnet \
  --project=$PROJECT_ID \
  --region=$REGION \
  --network=agents-vpc \
  --range=10.20.0.0/24

gcloud network-connectivity service-connection-policies create alloydb-agents-policy \
  --project=$PROJECT_ID \
  --region=$REGION \
  --service-class=google-cloud-alloydb \
  --network=agents-vpc \
  --subnets=agents-subnet \
  --psc-connection-limit=10
```

### Enable Agent mode, wait for `ACTIVE`, and create the serverless Agent Pool

Once your cluster upgrade finishes (`state: READY`), enable **Agent mode** on `summit-trail-cluster` via the AlloyDB v1beta REST API. Because enabling Agent mode provisions background storage mirroring asynchronously, poll `agentModeInfo.state` until it transitions from `PROVISIONING` to `ACTIVE` before creating the `AGENT_POOL` instance:

```bash
# 1. Enable Agent mode on the READY cluster
curl -s -X PATCH \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://alloydb.googleapis.com/v1beta/projects/$PROJECT_ID/locations/$REGION/clusters/$CLUSTER_ID?updateMask=agentModeConfig.mode" \
  -d '{"agentModeConfig": {"mode": "ENABLED"}}'

# 2. Wait until agentModeInfo.state is ACTIVE
while true; do
  STATE=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    "https://alloydb.googleapis.com/v1beta/projects/$PROJECT_ID/locations/$REGION/clusters/$CLUSTER_ID" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('agentModeInfo',{}).get('state','NONE'))")
  echo "Agent mode state: $STATE"
  [ "$STATE" = "ACTIVE" ] && break
  [ "$STATE" = "NONE" ] && { echo "Agent mode not enabled yet; ensure cluster state is READY."; break; }
  sleep 10
done

# 3. Create the serverless Agent Pool (scales 0 -> 10 nodes)
curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://alloydb.googleapis.com/v1beta/projects/$PROJECT_ID/locations/$REGION/clusters/$CLUSTER_ID/instances?instanceId=$POOL_ID" \
  -d "{
    \"instanceType\": \"AGENT_POOL\",
    \"agentPoolConfig\": {
      \"minPoolSize\": 0,
      \"maxPoolSize\": 10,
      \"pscAutoConnections\": [{
        \"consumerProject\": \"$PROJECT_ID\",
        \"consumerNetwork\": \"projects/$PROJECT_ID/global/networks/agents-vpc\"
      }]
    }
  }"
```

Once the Agent Pool reaches the `READY` state, retrieve its dedicated Private Service Connect DNS hostname (`MCP_HOST`) and fetch the cluster's PEM-encoded root CA certificate (`ca.pem`):

```bash
export MCP_HOST=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://alloydb.googleapis.com/v1beta/projects/$PROJECT_ID/locations/$REGION/clusters/$CLUSTER_ID/instances/$POOL_ID" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('agentPoolInfo',{}).get('dnsName','').rstrip('.'))")

echo "Agent Pool MCP Endpoint: https://$MCP_HOST/mcp"

gcloud beta alloydb clusters describe $CLUSTER_ID \
  --project=$PROJECT_ID \
  --region=$REGION \
  --format='value(certificateAuthorityInfo.rootCaCert)' > ca.pem
```

Expected output (`<INSTANCE_UID>.<CLUSTER_UID>.asia-southeast1.alloydb.goog`):

```console
Agent Pool MCP Endpoint: https://fa9fc622-fe1e-40e9-ba23-1930ece20883.9e5b60f2-b909-4190-8de2-c527b936d1db.asia-southeast1.alloydb.goog/mcp
```

> aside positive
> **Workload isolation by construction:** Open the **AlloyDB Cluster Overview** page in the Google Cloud Console. Below **Knowledge Catalog integration**, you'll see **Agent mode: Enabled** with its own dedicated endpoint (`...alloydb.goog`). Your primary endpoint serves transactional writes; this Agent Pool endpoint serves your AI agents—exposing only read-only MCP tools (`get_schema` and `execute_sql_read_only`) over shared Colossus storage and scaling compute back to zero when idle.

---

## Enrich semantic context with Knowledge Catalog
Duration: 06:00

Even when an agent can inspect table names and column types via `get_schema`, raw DDL doesn't explain domain semantics—such as what `status = 'cut'` means on a customer sales order, or how `inventory_db.products` links to `finance_db.supplier_invoices`.

With **Knowledge Catalog integration** enabled on your AlloyDB cluster, Google Cloud automatically indexes your PostgreSQL tables, column descriptions (`COMMENT ON`), primary/foreign keys, and schema-join relationships into a governed **Context Graph**.

### Explore the Supply Chain & Finance Context Graph in Knowledge Catalog Studio

1. In the Google Cloud Console, open your AlloyDB cluster `summit-trail-cluster` and verify on the **Overview** tab that **Knowledge Catalog integration** shows **Enabled**.
2. Navigate to **Knowledge Catalog > Studio** in the Google Cloud Console.
3. Start a new **Explore** chat and enter the following prompt to discover how your operational and financial tables connect across databases:

```text
Which tables in AlloyDB cluster summit-trail-cluster track customer order fill rates, supplier lead-time slippage, and supplier invoice billing variances, and how do they connect?
```

4. Follow up in **Knowledge Catalog Studio** to expand the full relational graph on the focus canvas:

```text
Add products, suppliers, distribution_centers, and inventory_snapshots from summit-trail-cluster to the focus canvas and expand all entry links to show how the supply chain and finance tables connect on the graph.
```

5. On the right-hand **Context graph**, click the `sales_orders` node to open its details drawer and verify the three layers of metadata that your agents inherit automatically:
   * **Description**: `Customer order headers. status: shipped = every line complete, partial = some quantity shipped, cut = nothing shipped.`
   * **Schema**: Displays `order_id` (`PK`), `customer_id` (`1 foreign key`), and `dc_id` (`1 foreign key`).
   * **Properties**: Confirms `System: ALLOYDB`, `Entry Type: AlloyDB Table`, and live synchronization timestamps.

---

## Build the Operations Agent connected to the Agent Pool
Duration: 08:00

Now you will build the **Summit Trail Agent** using the **Google Agent Development Kit (ADK)** and connect it to AlloyDB over the Model Context Protocol (MCP) using IAM database authentication.

### Create the Warehouse Operations IAM identity and PostgreSQL role

Rather than embedding static database passwords inside agent code, create a dedicated IAM service account for Priya's Warehouse Operations Agent (`warehouse-agent@$PROJECT_ID.iam.gserviceaccount.com`) and map it to a clean PostgreSQL role (`priya_warehouse_agent`) so all SQL grant statements remain 100% project-independent:

```bash
export WAREHOUSE_SA_NAME="warehouse-agent"
export WAREHOUSE_SA_EMAIL="${WAREHOUSE_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export WAREHOUSE_DB_USER="${WAREHOUSE_SA_NAME}@${PROJECT_ID}.iam"

gcloud iam service-accounts create $WAREHOUSE_SA_NAME \
  --project=$PROJECT_ID \
  --display-name="Summit Trail Warehouse Operations Agent"

sleep 5

for ROLE in roles/aiplatform.user roles/alloydb.databaseUser roles/alloydb.client roles/mcp.toolUser roles/serviceusage.serviceUsageConsumer roles/logging.logWriter; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$WAREHOUSE_SA_EMAIL" \
    --role="$ROLE" \
    --condition=None
done

gcloud iam service-accounts add-iam-policy-binding "$WAREHOUSE_SA_EMAIL" \
  --member="user:$USER_EMAIL" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --project=$PROJECT_ID --quiet
```

In **AlloyDB Studio** (connected to `inventory_db`), create the `priya_warehouse_agent` role, ensure `postgres` owns all tables created in the schema, and grant `priya_warehouse_agent` read-only `CONNECT` and `SELECT` privileges on `inventory_db`:

```sql
REASSIGN OWNED BY session_user TO postgres;
SET ROLE postgres;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'priya_warehouse_agent') THEN
    CREATE ROLE priya_warehouse_agent LOGIN;
  END IF;
END
$$;

GRANT CONNECT ON DATABASE inventory_db TO priya_warehouse_agent;
GRANT USAGE ON SCHEMA public TO priya_warehouse_agent;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO priya_warehouse_agent;
```

Register the IAM service account on your cluster and assign it the `priya_warehouse_agent` role:

```bash
gcloud alloydb users create "$WAREHOUSE_DB_USER" \
  --cluster=$CLUSTER_ID \
  --region=$REGION \
  --type=IAM_BASED \
  --db-roles=alloydbiamuser,priya_warehouse_agent \
  --project=$PROJECT_ID
```

### Install dependencies and write `operations_agent.py`

Create a Python virtual environment and install the Google ADK and MCP client dependencies:

```bash
mkdir -p summit-trail-agents && cd summit-trail-agents
cp ../ca.pem ./ca.pem 2>/dev/null || true

python3 -m venv .venv || uv venv .venv --seed
source .venv/bin/activate
pip install --quiet google-adk google-genai httpx mcp google-auth
```

> aside positive
> **Running inside the Agent VPC vs. Cloud Shell / Local Laptop:**
> * When deployed to **Vertex AI Agent Engine** (with `pscInterfaceConfig` + `dnsPeeringConfigs` for `alloydb.goog.`) or a VM inside `agents-vpc`, set `MCP_URL="https://$MCP_HOST"` to connect directly to the Agent Pool's private endpoint.
> * When testing locally from **Cloud Shell** or your laptop outside `agents-vpc`, set `MCP_URL="https://alloydb.googleapis.com"` to route `execute_sql_read_only` through the globally reachable **AlloyDB Remote MCP Server**.

Create `operations_agent.py`:

```bash
cat << 'EOF' > operations_agent.py
"""Summit Trail Operations Agent connected to AlloyDB over Streamable HTTP MCP."""

import asyncio
import logging
import os
import ssl
import threading
from google.adk import agents
from google.adk.models import google_llm
from google.adk.tools.mcp_tool import mcp_session_manager
from google.adk.tools.mcp_tool import mcp_toolset
import google.auth
import google.auth.transport.requests
import httpx

os.environ.setdefault("GOOGLE_API_USE_CLIENT_CERTIFICATE", "false")
logging.getLogger("google.auth").setLevel(logging.ERROR)

PROJECT_ID = os.environ["PROJECT_ID"]
REGION = os.environ.get("REGION", "asia-southeast1")
CLUSTER_ID = os.environ.get("CLUSTER_ID", "summit-trail-cluster")
PRIMARY_ID = os.environ.get("PRIMARY_ID", "summit-trail-primary")
MCP_URL = os.environ.get("MCP_URL", "https://alloydb.googleapis.com").rstrip("/")
CA_PEM_PATH = os.environ.get("CA_PEM_PATH", "ca.pem")
DATABASE = os.environ.get("DATABASE", "inventory_db")
DB_USER = os.environ.get("DB_USER", "")
INSTANCE_URI = (
    f"projects/{PROJECT_ID}/locations/{REGION}/"
    f"clusters/{CLUSTER_ID}/instances/{PRIMARY_ID}"
)

SCHEMA_CONTEXT = (
    f"Target AlloyDB instance: `{INSTANCE_URI}` | Database: `{DATABASE}`.\n"
    "Tables in `inventory_db`:\n"
    "- `distribution_centers(dc_id, dc_code, dc_name, region, capacity_units)`\n"
    "- `suppliers(supplier_id, supplier_name, country, reliability_tier)`\n"
    "- `products(sku, product_name, category, supplier_id, unit_cost, list_price, lead_time_days, reorder_point, safety_stock)`\n"
    "- `customers(customer_id, customer_name, channel, preferred_dc_id)`\n"
    "- `inventory_snapshots(snapshot_id, snapshot_date, dc_id, sku, on_hand_qty, reserved_qty, available_qty)`\n"
    "- `purchase_orders(po_id, supplier_id, dc_id, order_date, promised_date, status)`\n"
    "- `purchase_order_lines(po_line_id, po_id, sku, qty_ordered, qty_received, received_date, actual_lead_time_days)`\n"
    "- `sales_orders(order_id, customer_id, dc_id, order_date, promised_ship_date, status)`\n"
    "- `sales_order_lines(line_id, order_id, sku, qty_ordered, qty_shipped, unit_price, ship_date)`\n"
    "- `cycle_counts(audit_id, dc_id, sku, audit_date, system_qty, physical_qty, accuracy_pct)`\n"
    "- `demand_forecasts(forecast_id, forecast_month, sku, forecast_units, actual_ordered_units, variance_pct)`\n"
    "Domain formulas: `cut_units = (qty_ordered - qty_shipped)`, `fill_rate_pct = ROUND(100.0 * SUM(qty_shipped) / SUM(qty_ordered), 2)`. Always join `sales_orders` and `sales_order_lines` on `order_id` and group/filter dates by `sales_orders.order_date`.\n"
)


def _bind_connection(tool, args, tool_context):
    """Binds the target AlloyDB database and instance on read-only MCP tool calls."""
    del tool_context
    if tool.name in ("execute_sql_read_only", "get_schema", "execute_sql"):
        args["database"] = DATABASE
        if "alloydb.googleapis.com" in MCP_URL:
            args["instance"] = INSTANCE_URI
    return None


class _AlloyDBTokenAuth(httpx.Auth):
    """Attaches a fresh OAuth 2.0 Bearer token on every MCP request."""

    def __init__(self):
        self._creds, _ = google.auth.default(
            scopes=[
                "https://www.googleapis.com/auth/alloydb",
                "https://www.googleapis.com/auth/cloud-platform",
            ]
        )
        self._lock = threading.Lock()

    def _token(self) -> str:
        with self._lock:
            if not self._creds.valid:
                self._creds.refresh(google.auth.transport.requests.Request())
            return self._creds.token

    def auth_flow(self, request):
        request.headers["Authorization"] = f"Bearer {self._token()}"
        request.headers["X-Goog-User-Project"] = PROJECT_ID
        yield request

    async def async_auth_flow(self, request):
        token = await asyncio.to_thread(self._token)
        request.headers["Authorization"] = f"Bearer {token}"
        request.headers["X-Goog-User-Project"] = PROJECT_ID
        yield request


def _mcp_http_client(headers=None, timeout=None, auth=None):
    del auth
    ctx = ssl.create_default_context()
    if "alloydb.goog" in MCP_URL and os.path.exists(CA_PEM_PATH):
        ctx.load_verify_locations(cafile=CA_PEM_PATH)
    return httpx.AsyncClient(
        follow_redirects=True,
        verify=ctx,
        headers=headers,
        timeout=timeout or httpx.Timeout(30.0, read=120.0),
        auth=_AlloyDBTokenAuth(),
    )


root_agent = agents.Agent(
    name="summit_trail_agent",
    model=google_llm.Gemini(model="gemini-2.5-flash"),
    instruction=(
        "You are the Summit Trail Agent. You analyze Summit Trail Supply inventory, "
        "fill rates, warehouse performance, and supplier lead times on AlloyDB "
        f"PostgreSQL for Agents.\n\n{SCHEMA_CONTEXT}\n"
        "1. Always call `execute_sql_read_only` directly using the target instance and database above.\n"
        "2. Compare unit fill rates against our 95.0% target and highlight "
        "distribution center variances across RNO, DFW, and CMH."
    ),
    tools=[
        mcp_toolset.McpToolset(
            connection_params=mcp_session_manager.StreamableHTTPConnectionParams(
                url=f"{MCP_URL}/mcp",
                headers={"AlloyDB-User": DB_USER} if DB_USER else {},
                timeout=60.0,
                terminate_on_close=False,
                httpx_client_factory=_mcp_http_client,
            ),
            tool_filter=["execute_sql_read_only"],
        )
    ],
    before_tool_callback=_bind_connection,
)
EOF
```

### Run the live morning fill-rate and distribution center checks

Create and run `run_ops_prompts.py` to execute Priya's two opening prompts from your terminal:

```bash
cat << 'EOF' > run_ops_prompts.py
import asyncio
import os
from google.adk.runners import InMemoryRunner
from google.genai import types
from operations_agent import root_agent

os.environ.setdefault("GOOGLE_GENAI_USE_VERTEXAI", "true")
os.environ.setdefault("GOOGLE_CLOUD_PROJECT", os.environ["PROJECT_ID"])
os.environ.setdefault("GOOGLE_CLOUD_LOCATION", "us-central1")


async def ask(runner: InMemoryRunner, session_id: str, prompt: str):
    print(f"\n{'='*72}\nPROMPT: {prompt}\n{'='*72}")
    msg = types.Content(role="user", parts=[types.Part.from_text(text=prompt)])
    async for event in runner.run_async(
        user_id="priya", session_id=session_id, new_message=msg
    ):
        if event.content and event.content.parts:
            for part in event.content.parts:
                if part.function_call:
                    print(f"[MCP Tool Call] {part.function_call.name}({part.function_call.args})")
                elif part.text:
                    print(part.text)


async def main():
    runner = InMemoryRunner(agent=root_agent, app_name="summit_trail")
    try:
        session = await runner.session_service.create_session(
            app_name="summit_trail", user_id="priya"
        )
        await ask(
            runner,
            session.id,
            "Give me this morning's read on unit fill rate by month this year, against our 95% target.",
        )
        await ask(
            runner,
            session.id,
            "Which distribution center is driving the fill-rate decline?",
        )
    finally:
        await runner.close()


if __name__ == "__main__":
    asyncio.run(main())
EOF

python3 run_ops_prompts.py
```

Expected output:

```console
========================================================================
PROMPT: Give me this morning's read on unit fill rate by month this year, against our 95% target.
========================================================================
[MCP Tool Call] execute_sql_read_only({'database': 'inventory_db', 'sqlStatement': "SELECT TO_CHAR(DATE_TRUNC('month', o.order_date), 'YYYY-MM') AS month, SUM(l.qty_ordered) AS ordered, SUM(l.qty_shipped) AS shipped, ROUND(100.0 * SUM(l.qty_shipped) / SUM(l.qty_ordered), 1) AS fill_rate_pct FROM sales_orders o JOIN sales_order_lines l ON o.order_id = l.order_id GROUP BY 1 ORDER BY 1;"})
Summit Trail Supply held above the 95.0% target throughout Q1 (96.2% in Jan, 95.8% in Feb, 95.4% in Mar), then declined steadily to 91.2% in April, 88.0% in May, 85.5% in June, and 83.9% in July.

========================================================================
PROMPT: Which distribution center is driving the fill-rate decline?
========================================================================
[MCP Tool Call] execute_sql_read_only({'database': 'inventory_db', 'sqlStatement': 'SELECT dc.dc_code, dc.dc_name, SUM(l.qty_ordered - l.qty_shipped) AS cut_units, ROUND(100.0 * SUM(l.qty_shipped) / SUM(l.qty_ordered), 2) AS fill_rate_pct FROM sales_orders o JOIN sales_order_lines l ON o.order_id = l.order_id JOIN distribution_centers dc ON o.dc_id = dc.dc_id GROUP BY 1, 2 ORDER BY fill_rate_pct ASC;'})
Columbus (CMH at 85.46% YTD fill rate, 3,885 cut units) and Fort Worth (DFW at 86.02% YTD fill rate, 4,833 cut units) are driving the decline, lagging Reno (RNO at 89.45%, 3,622 cut units) across 12,340 total network cut units.
```

---

## Build and launch the 10-agent root-cause team (with a Devil's Advocate)
Duration: 10:00

Knowing *where* the fill-rate drop happened (Columbus and Fort Worth) still doesn't explain *why*. In a complex supply chain, a single-threaded prompt often latches onto the first plausible hypothesis—risking costly operational mistakes like emergency air-freight orders when stock is already sitting in a neighboring warehouse.

Because AlloyDB's serverless **Agent Pool** scales isolated microVMs automatically over shared Colossus storage, you can fan out a **10-agent parallel investigation team**:
* **9 Supply-Chain Specialist Agents** (`s01`–`s09`): Test specific hypotheses across SKU shortfall concentration, supplier lead times, PO receipt shortages, safety-stock thresholds, regional inventory imbalances, and counterfactual routing policies.
* **The 10th Agent — The Devil's Advocate** (`s10`): Assigned a single adversarial mission—use live SQL data (`cycle_counts` and `demand_forecasts`) to **disprove false leads** before Priya rebalances inventory.

### Create the 10-Agent Team Coordinator (`team_agent.py`)

Create `team_agent.py` in your `summit-trail-agents` directory to define the 10 specialist sub-agents and run them in parallel with `google.adk.agents.ParallelAgent`:

```bash
cat << 'EOF' > team_agent.py
"""10-Agent Root-Cause Investigation Team on AlloyDB."""

import asyncio
import os
import warnings
from google.adk import agents
from google.adk.models import google_llm
from google.adk.runners import InMemoryRunner
from google.adk.tools.mcp_tool import mcp_session_manager, mcp_toolset
from google.genai import types
from operations_agent import (
    _bind_connection,
    _mcp_http_client,
    DB_USER,
    MCP_URL,
    SCHEMA_CONTEXT,
)

warnings.filterwarnings("ignore", category=DeprecationWarning)
os.environ.setdefault("GOOGLE_GENAI_USE_VERTEXAI", "true")
os.environ.setdefault("GOOGLE_CLOUD_PROJECT", os.environ["PROJECT_ID"])
os.environ.setdefault("GOOGLE_CLOUD_LOCATION", "us-central1")


def _make_mcp_toolset():
    return mcp_toolset.McpToolset(
        connection_params=mcp_session_manager.StreamableHTTPConnectionParams(
            url=f"{MCP_URL}/mcp",
            headers={"AlloyDB-User": DB_USER} if DB_USER else {},
            timeout=60.0,
            terminate_on_close=False,
            httpx_client_factory=_mcp_http_client,
        ),
        tool_filter=["execute_sql_read_only"],
    )


TEAM_SPECS = [
    ("s01_sku_pareto", "Quantify cut units (qty_ordered - qty_shipped) and lost revenue by SKU and category from sales_order_lines and products."),
    ("s02_dc_imbalance", "Compare available_qty across RNO (1), DFW (2), and CMH (3) in inventory_snapshots to detect stranded surplus stock."),
    ("s03_supplier_lead_times", "Compare configured products.lead_time_days against actual_lead_time_days in purchase_order_lines by supplier."),
    ("s04_po_shortfalls", "Identify purchase orders in purchase_orders and purchase_order_lines where qty_received < qty_ordered or status = 'received_late'."),
    ("s05_safety_stock_audit", "Check whether products.reorder_point and safety_stock buffers are calibrated for actual supplier lead times."),
    ("s06_channel_impact", "Analyze which wholesale distributors in customers experienced cut orders."),
    ("s07_seasonal_cadence", "Trace month-over-month cut_units = SUM(qty_ordered - qty_shipped) from January through July 2026 by joining sales_orders.order_date and sales_order_lines."),
    ("s08_lateral_routing_sim", "Calculate how many cut units in CMH and DFW could be recovered by lateral transshipment from surplus available_qty in inventory_snapshots."),
    ("s09_lead_time_recalibration_sim", "Query products where supplier_id IN ('SUP-001', 'SUP-002') and quantify the impact of recalibrating lead_time_days for SUP-002 (7d -> 21d) and SUP-001 (14d -> 34d)."),
    (
        "s10_devils_advocate",
        "DEVIL'S ADVOCATE: Test and REFUTE two common scapegoats in one combined SQL query using scalar subqueries: "
        "(1) Query cycle_counts (COUNT and AVG(accuracy_pct)) to prove whether warehouse shrink caused stockouts. "
        "(2) Query demand_forecasts (AVG(variance_pct)) to prove whether surprise customer demand caused stockouts.",
    ),
]

specialist_agents = [
    agents.Agent(
        name=agent_id,
        model=google_llm.Gemini(model="gemini-2.5-flash"),
        instruction=(
            f"You are specialist agent `{agent_id}` in a 10-agent supply-chain team.\n"
            f"Mission: {mission}\n\n{SCHEMA_CONTEXT}\n"
            "Run 1 concise read-only SQL query via `execute_sql_read_only` on `inventory_db` and report your finding in 2 bullet points."
        ),
        tools=[_make_mcp_toolset()],
        before_tool_callback=_bind_connection,
    )
    for agent_id, mission in TEAM_SPECS
]

investigation_team = agents.ParallelAgent(
    name="summit_trail_10_agent_team",
    sub_agents=specialist_agents,
)


async def main():
    runner = InMemoryRunner(agent=investigation_team, app_name="summit_trail_team")
    try:
        session = await runner.session_service.create_session(
            app_name="summit_trail_team", user_id="priya"
        )
        msg = types.Content(
            role="user",
            parts=[types.Part.from_text(text="Investigate the fill-rate drop with 10 agents, including a devil's advocate.")],
        )
        async for event in runner.run_async(
            user_id="priya", session_id=session.id, new_message=msg
        ):
            if event.content and event.content.parts:
                for part in event.content.parts:
                    if part.text:
                        print(f"\n[{event.author}]\n{part.text.strip()}")
    finally:
        await runner.close()


if __name__ == "__main__":
    asyncio.run(main())
EOF

python3 team_agent.py
```

### Review the synthesized findings and supplier drilldown

As the 10 agents complete in parallel, verify the three key conclusions returned from live AlloyDB SQL:
* **What the Devil's Advocate Ruled Out** (`s10_devils_advocate`):
  * **Warehouse Operational / Picking Breakdown (REFUTED)**: Querying all **325 cycle-count audits** in `cycle_counts` proved **98.62% physical-to-system inventory fidelity** across all three DCs.
  * **Surprise Customer Demand Spike (REFUTED)**: Querying `demand_forecasts` proved actual customer orders tracked within **1.58%** of forecast (`< 1.8%` variance).
* **Corroborated Root Causes** (`s02_dc_imbalance`, `s03_supplier_lead_times`, `s04_po_shortfalls`):
  1. **Severe Supplier Lead-Time Slippage**: **Pacific Trail Imports** (`SUP-002`) delivered at **0.0% on-time**, taking **21.0 days** actual vs. **7 days** configured in ERP. **Cascade Ridge Manufacturing** (`SUP-001`) slipped from **14 days** configured to **34.0 days** actual (`0.0%` on-time).
  2. **Rigid Single-DC Order Routing**: Orders bound to **Columbus** (`CMH`) were cut (`0` available units of `STS-0001` and `STS-0006`) while **Fort Worth** (`DFW`) sat on **1,240 available units** of `STS-0001` and **1,040 available units** of `STS-0006`.

---

## Verify scale-to-zero telemetry and two-database authorization
Duration: 06:00

In this final technical step, you verify two enterprise guarantees in the Google Cloud Console:
1. **Workload Isolation & Scale-to-Zero Telemetry**: Did the 10-agent team impact your transactional primary (`summit-trail-primary`)?
2. **Database-Enforced Authorization ("Grants Are the Boundary")**: Can Priya's Warehouse Operations Agent access Diego's restricted vendor invoices in `finance_db`?

### Part 1: Verify primary CPU isolation and Agent Pool scale-to-zero

1. In the Google Cloud Console, go to **AlloyDB > Clusters** (`summit-trail-cluster`) and inspect the **Mean CPU utilization** chart on `summit-trail-primary`.
   * Even while 10 concurrent agents executed parallel MCP tool calls (`execute_sql_read_only`), `summit-trail-primary` **CPU remained calm and flat (~15%)**.
2. Open **Cloud Monitoring > Metrics Explorer** and inspect:
   * `alloydb.googleapis.com/instance/cpu/average_utilization` and `alloydb.googleapis.com/database/postgresql/backends` across `summit-trail-primary` vs. `summit-trail-agent-pool`.
   * Observe the **0 → Burst → 0** lifecycle: the serverless Agent Pool spun up isolated worker microVMs on demand to absorb the team's token and SQL burst, then scaled back to zero once the synthesis finished.

### Part 2: Enforce and verify the 2×2 PostgreSQL privilege matrix

Right after discovering that **Cascade Ridge Manufacturing** slipped three weeks past its promised delivery dates, Priya wants to check whether Cascade Ridge also overbilled Summit Trail Supply on recent invoices. However, supplier invoices and contract terms live in `finance_db`, which belongs to Diego's Finance team.

Create a separate IAM database identity for Diego's Finance Agent (`finance-agent@$PROJECT_ID.iam`) and lock down the **2×2 Database Privilege Matrix** at the PostgreSQL engine layer:

```bash
export FINANCE_SA_NAME="finance-agent"
export FINANCE_SA_EMAIL="${FINANCE_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export FINANCE_DB_USER="${FINANCE_SA_NAME}@${PROJECT_ID}.iam"

gcloud iam service-accounts create $FINANCE_SA_NAME \
  --project=$PROJECT_ID \
  --display-name="Summit Trail Vendor Finance Agent"
```

In **AlloyDB Studio** (connected to `inventory_db`), execute the following SQL block to create `diego_finance_agent`, assign database ownership to `postgres`, and lock down the `2×2` `CONNECT` privileges across `inventory_db` and `finance_db`:

```sql
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

-- 2. Lock down finance_db: DENY priya_warehouse_agent, ALLOW diego_finance_agent
REVOKE ALL ON DATABASE finance_db FROM PUBLIC;
GRANT CONNECT ON DATABASE finance_db TO postgres, diego_finance_agent;
REVOKE CONNECT ON DATABASE finance_db FROM priya_warehouse_agent;
```

> aside positive
> **Why reassigning database ownership matters:** When a database is created via MCP `execute_sql`, your IAM user owns the database and issues its default `PUBLIC` `CONNECT` grant. Assigning ownership to `postgres` (`ALTER DATABASE ... OWNER TO postgres`) before running `REVOKE ALL ON DATABASE ... FROM PUBLIC` ensures PostgreSQL revokes the default public grant cleanly.

Now switch to `finance_db` in AlloyDB Studio, ensure `postgres` owns the finance tables, and grant `SELECT` on the two finance tables to `diego_finance_agent`:

```sql
REASSIGN OWNED BY session_user TO postgres;
SET ROLE postgres;
GRANT USAGE ON SCHEMA public TO diego_finance_agent;
GRANT SELECT ON TABLE supplier_invoices, vendor_contracts TO diego_finance_agent;
```

Register `finance-agent` on your AlloyDB cluster mapped to `diego_finance_agent`:

```bash
gcloud alloydb users create "$FINANCE_DB_USER" \
  --cluster=$CLUSTER_ID \
  --region=$REGION \
  --type=IAM_BASED \
  --db-roles=alloydbiamuser,diego_finance_agent \
  --project=$PROJECT_ID
```

#### Test 1 — Verify the 2×2 privilege matrix in AlloyDB Studio (`~13.6 ms`)

In **AlloyDB Studio** (connected to `inventory_db`), run the following `has_database_privilege` query against `pg_database`:

```sql
SELECT
  d.datname AS database_name,
  has_database_privilege('priya_warehouse_agent', d.datname, 'CONNECT') AS priya_warehouse_agent,
  has_database_privilege('diego_finance_agent', d.datname, 'CONNECT') AS diego_finance_agent
FROM pg_database d
WHERE d.datname IN ('inventory_db', 'finance_db')
ORDER BY d.datname DESC;
```

Expected output (`13.6 ms`):

```console
 database_name | priya_warehouse_agent | diego_finance_agent
---------------+-----------------------+---------------------
 inventory_db  | true                  | false
 finance_db    | false                 | true
```

#### Test 2 — Attempt a cross-database finance query from the Warehouse Operations Agent

To verify that PostgreSQL enforces this boundary at the engine layer, impersonate `warehouse-agent` (`priya_warehouse_agent`) and attempt to query `finance_db` over MCP:

```bash
gcloud iam service-accounts add-iam-policy-binding "$WAREHOUSE_SA_EMAIL" \
  --member="user:$USER_EMAIL" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --project=$PROJECT_ID --quiet

SA_TOKEN=$(gcloud auth print-access-token --impersonate-service-account="$WAREHOUSE_SA_EMAIL" 2>/dev/null)
INSTANCE_URI="projects/$PROJECT_ID/locations/$REGION/clusters/$CLUSTER_ID/instances/$PRIMARY_ID"

curl -s -X POST https://alloydb.googleapis.com/mcp \
  -H "Authorization: Bearer $SA_TOKEN" \
  -H "X-Goog-User-Project: $PROJECT_ID" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"execute_sql_read_only\",\"arguments\":{\"instance\":\"$INSTANCE_URI\",\"database\":\"finance_db\",\"sqlStatement\":\"SELECT * FROM supplier_invoices;\"}}}"
```

Expected output:

```console
{"metadata":{"message":"postgresql error: permission denied for database \"finance_db\"","status":"ERROR"}}
```

When your **Summit Trail Agent** (running under `warehouse-agent` / `priya_warehouse_agent`) is asked:

```text
What did we pay Cascade Ridge per unit on the last three invoices, and what are our contract payment terms?
```

And attempts to connect to `finance_db`, PostgreSQL blocks the connection at the engine layer (`permission denied for database "finance_db"`, `SQLSTATE 42501`). Because the MCP server cryptographically binds the OAuth 2.0 bearer token to the IAM database identity, no prompt injection or agent retry can spoof another identity. Instead of crashing, the agent reports the refusal clearly and provides a safe fallback from `inventory_db.products` (standard planning unit costs for `STS-0006` through `STS-0010`).

#### Test 3 — Run the authorized invoice query in `finance_db`

In **AlloyDB Studio**, switch your database connection to `finance_db` (where Diego's Finance identity is authorized) and run:

```sql
SELECT
  invoice_id,
  sku,
  product_name,
  contract_unit_cost_usd,
  billed_unit_cost_usd,
  sla_penalty_credit_usd,
  payment_status
FROM supplier_invoices
WHERE supplier_id = 'SUP-001'
ORDER BY invoice_date DESC;
```

Expected output (`16.3 ms`):

```console
  invoice_id   |   sku    |      product_name       | contract_unit_cost_usd | billed_unit_cost_usd | sla_penalty_credit_usd |            payment_status
---------------+----------+-------------------------+------------------------+----------------------+------------------------+---------------------------------------
 INV-2026-0718 | STS-0009 | Northfork Bivy          |                  84.50 |                89.25 |                5355.00 | Disputed - Late Delivery + Surcharge
 INV-2026-0624 | STS-0006 | Northfork Dome Tent Lite|                 142.00 |               146.00 |                6935.00 | Approved with 5% SLA Credit
 INV-2026-0529 | STS-0010 | Basin Canopy Lite       |                 118.00 |               118.00 |                   0.00 | Paid (2% Early Pay Discount)
```

> aside positive
> **Why grants beat prompt guardrails:** Notice that you did not write a prompt instruction telling the Warehouse Agent *"Please pretend you can't see the finance database."* Who can see what is enforced by standard PostgreSQL `CONNECT` and `SELECT` privileges replicated automatically to every microVM in the AlloyDB Agent Pool.

---

## Clean up
Duration: 02:00

To avoid incurring ongoing charges to your Google Cloud account, delete the AlloyDB cluster (using `--force` to remove both the Agent Pool and Primary instance in one step) and remove the networking and IAM resources created during this codelab:

```bash
# 1. Delete the AlloyDB cluster, Agent Pool, and Primary instance
gcloud beta alloydb clusters delete $CLUSTER_ID \
  --region=$REGION \
  --force \
  --quiet \
  --project=$PROJECT_ID

# 2. Delete the Private Service Connect service connection policy, subnet, and VPC
gcloud network-connectivity service-connection-policies delete alloydb-agents-policy \
  --region=$REGION \
  --quiet \
  --project=$PROJECT_ID

gcloud compute networks subnets delete agents-subnet \
  --region=$REGION \
  --quiet \
  --project=$PROJECT_ID

gcloud compute networks delete agents-vpc \
  --quiet \
  --project=$PROJECT_ID

# 3. Delete the IAM service accounts
gcloud iam service-accounts delete $WAREHOUSE_SA_EMAIL --quiet --project=$PROJECT_ID
gcloud iam service-accounts delete $FINANCE_SA_EMAIL --quiet --project=$PROJECT_ID
```

---

## Congratulations!
Duration: 01:00

You have built an end-to-end, enterprise-governed multi-agent system from scratch using **AlloyDB Express**, **AlloyDB PostgreSQL for Agents**, **Knowledge Catalog**, and **Google ADK**!

### What we've covered

* **Rapid Prototyping with AlloyDB Express & Remote MCP**: Connected **Antigravity / Claude Code** to `https://alloydb.googleapis.com/mcp` to spin up a scale-to-zero PostgreSQL 18 cluster in seconds and seed multi-database schemas.
* **Zero-Migration Graduation to Agent Mode**: Performed an in-place upgrade (`expressConfig.enabled = false`) and attached a serverless **Agent Pool** (`0 → 10` isolated microVMs) over shared **Google Colossus** storage.
* **Governed Semantic Discovery**: Used **Knowledge Catalog Studio** to inspect cross-database schema-join relationships and table/column semantics (`sales_orders`).
* **Multi-Agent Team & Devil's Advocate Pattern**: Built a 10-agent **Google ADK** team where 9 supply-chain specialists investigated lead-time and routing bottlenecks while the 10th **Devil's Advocate** agent empirically refuted false leads using 325 cycle-count audits (`98.62%` accuracy).
* **Database-Enforced Authorization**: Configured a **2×2 IAM Database Privilege Matrix** (`priya_warehouse_agent` vs. `diego_finance_agent` across `inventory_db` and `finance_db`) proving that PostgreSQL grants—not prompts—are the security boundary.

### Reference docs

* [AlloyDB Express overview](https://cloud.google.com/alloydb/docs/express-overview)
* [Create and manage AlloyDB Express clusters](https://cloud.google.com/alloydb/docs/create-manage-express-clusters)
* [Use the AlloyDB for PostgreSQL remote MCP server](https://cloud.google.com/alloydb/docs/ai/use-alloydb-mcp)
* [Agent Development Kit (ADK) documentation](https://google.github.io/adk-docs/)
* [Create and connect to an AlloyDB agent pool (Preview)](https://cloud.google.com/alloydb/docs/postgresql-agents/create-agent-pool-connect)
* [Build a Gemini Enterprise agent that queries an AlloyDB agent pool (Preview)](https://cloud.google.com/alloydb/docs/postgresql-agents/build-gemini-agent-query-agent-pool)
