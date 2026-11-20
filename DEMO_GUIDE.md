# Build Multi-Agent Teams with AlloyDB for PostgreSQL — Seller Demo Guide

## Executive Summary & Pitch Context

- **Target Buyer Personas:** VP of Engineering, Chief Data Officer (CDO), VP of Supply Chain & Operations, Head of Platform Architecture, and Chief Information Security Officer (CISO).
- **Customer Pain Point:** Engineering teams building autonomous AI agents face a painful compromise: pointing agents at stale data warehouses misses live operational events on the warehouse floor, while pointing concurrent multi-agent teams directly at a transactional PostgreSQL primary spikes CPU, saturates connections, and risks checkout downtime—while prompt-based security rules fail CISO audits.
- **Value Proposition:** With **AlloyDB Express** and **AlloyDB PostgreSQL for Agents**, developers prototype on PostgreSQL 18 in under 2 seconds via Remote MCP, graduate in place with zero migration to enterprise AlloyDB, run a 10-agent ADK diagnostic team over serverless microVMs (`0 → 10 → 0`) with zero primary CPU impact (`~15%` flat), recover **$1.25M+ (+11,846 units)** in cut orders, and enforce strict database isolation at the PostgreSQL engine layer (`SQLSTATE 42501`).
- **Estimated Demo Duration:** 10–15 minutes live walkthrough (or 57 minutes as a full hands-on CE/FDE workshop).
- **Author & Owner:** Sean Zinsmeister (`szinsmeister`, Databases Outbound Product Management & DevRel).

---

## How to Build

This section explains how the **Summit Trail Supply** multi-agent architecture is constructed end-to-end on Google Cloud using **AlloyDB for PostgreSQL (Express & Agent Mode)**, **Knowledge Catalog (Dataplex)**, **Google Agent Development Kit (ADK) / Vertex AI Agent Engine**, and **Cloud Monitoring**.

### Step 1: Scaffold the Project, Networking & Dependencies

- **Infrastructure as Code (`click-to-deploy/`):** [`click-to-deploy/main.tf`](click-to-deploy/main.tf) and [`click-to-deploy/variables.tf`](click-to-deploy/variables.tf) enable the required Google Cloud APIs (`alloydb`, `compute`, `servicenetworking`, `networkconnectivity`, `aiplatform`, `dataplex`, `monitoring`, `dns`, `secretmanager`), generate a dynamic PostgreSQL password stored in Secret Manager (`random_password`), create `agents-vpc` with a Private Service Connect service connection policy (`google-cloud-alloydb`), and provision two least-privilege IAM service accounts: `warehouse-agent` and `finance-agent`.
- **Python Environment (`agents/requirements.txt`):** Uses `google-adk`, `google-genai`, `google-auth`, `httpx`, and `mcp` to talk directly to AlloyDB over Streamable HTTP MCP with live OAuth 2.0 Bearer token refresh.

### Step 2: Provision AlloyDB Express & Build the Dual-Database Data Layer (`data/sql/`, `scripts/setup_express_and_seed.sh`)

- **2-Second Prototyping (`scripts/setup_express_and_seed.sh`):** Calls the AlloyDB v1beta REST API (or AlloyDB Remote MCP Server `https://alloydb.googleapis.com/mcp`) to create a scale-to-zero PostgreSQL 18 **AlloyDB Express** cluster (`summit-trail-cluster`) and 1-vCPU primary instance (`summit-trail-primary`) with Public DNS and IAM authentication enabled.
- **Schema & Seed Data (`data/sql/` & `data/csv/`):**
  - `data/sql/02_seed_inventory_db.sql`: Seeds **11 operational supply-chain tables** in `inventory_db` (`distribution_centers`, `suppliers`, `products`, `customers`, `inventory_snapshots`, `purchase_orders`, `purchase_order_lines`, `sales_orders`, `sales_order_lines`, `cycle_counts` [325 audits at `98.62%` accuracy], and `demand_forecasts` [`< 1.8%` variance]) modeling Summit Trail Supply's YTD fill-rate drop from `96.2%` (Jan) to `83.9%` (July) and `12,340` cut units across Reno (`RNO`), Fort Worth (`DFW`), and Columbus (`CMH`).
  - `data/sql/03_seed_finance_db.sql`: Seeds **2 restricted vendor finance tables** (`vendor_contracts`, `supplier_invoices`, including disputed invoice `INV-2026-0718` billed at `$89.25` vs. `$84.50` contract) in `finance_db`.
  - `data/sql/04a_setup_authz_inventory_db.sql` & `04b_setup_authz_finance_db.sql`: Enforces the **2×2 PostgreSQL Engine Authorization Matrix** (`REVOKE ALL ... FROM PUBLIC`, granting `CONNECT` + `SELECT` on `inventory_db` strictly to `priya_warehouse_agent` and `finance_db` strictly to `diego_finance_agent`).

### Step 3: Upgrade In Place to Agent Mode & Wire the Multi-Agent Team (`scripts/upgrade_to_agent_mode.sh`, `agents/`)

- **Zero-Migration Upgrade (`scripts/upgrade_to_agent_mode.sh`):** Runs `gcloud beta alloydb clusters update --no-enable-express` to preserve all databases, schemas, and IAM identities in place, enables **Agent mode**, and creates a serverless **Agent Pool** (`summit-trail-agent-pool`, `minPoolSize: 0`, `maxPoolSize: 10`) that reads shared **Google Colossus** storage with zero primary CPU overhead.
- **Single Operations Agent (`agents/operations_agent.py` & `agents/run_ops_prompts.py`):** Connects Google ADK (`gemini-2.5-flash`) via `McpToolset` (`StreamableHTTPConnectionParams`) to `execute_sql_read_only` with OAuth 2.0 Bearer auth and `AlloyDB-User` header binding.
- **10-Agent Investigation Team (`agents/team_agent.py`):** Uses `google.adk.agents.ParallelAgent` to fan out **9 supply-chain specialists (`s01`–`s09`)** and **1 adversarial Devil's Advocate agent (`s10_devils_advocate`)** concurrently over MCP.

### Step 4: Test, Verify Telemetry & Enforce 2×2 Isolation (`agents/verify_2x2_authz.py`)

- Execute `python3 agents/run_ops_prompts.py`, `python3 agents/team_agent.py`, and `python3 agents/verify_2x2_authz.py` to validate live SQL answers, 10-agent parallel synthesis, Cloud Monitoring `0 → 10 → 0` scaling, and engine-level `SQLSTATE 42501` refusal.

---

## Pillar 1: Setup & Deployment Instructions

### 1.1 Prerequisites & IAM Permissions

- **GCP Environment:** An Argolis project or Google Cloud project with billing enabled (estimated cost `< $5 USD` when cleaned up after the session).
- **Region Choice:** Use `asia-southeast1` for full end-to-end **AlloyDB Express → In-Place Agent Mode Upgrade** in the same region. (Express-only fast-track also runs in `us-west1`, `europe-west2`, `asia-east1`, `asia-northeast1`, `australia-southeast1`; Agent Mode direct creation runs in `us-central1`, `us-east1`, `us-east4`, `us-east5`, `us-south1`, `us-west4`, `europe-west1`, `asia-southeast1`.)
- **Required IAM Roles for the Deployer:** `roles/owner` or (`roles/alloydb.admin`, `roles/compute.networkUser`, `roles/mcp.toolUser`, `roles/iam.serviceAccountAdmin`, `roles/resourcemanager.projectIamAdmin`, `roles/secretmanager.admin`).
- **Required APIs:** `alloydb.googleapis.com`, `compute.googleapis.com`, `servicenetworking.googleapis.com`, `networkconnectivity.googleapis.com`, `aiplatform.googleapis.com`, `dataplex.googleapis.com`, `monitoring.googleapis.com`, `dns.googleapis.com`, `secretmanager.googleapis.com`.
- **Local Tooling:** Google Cloud Shell, Cloudtop, or local terminal with `gcloud`, `python3` (3.11+), `curl`, and optionally **Antigravity** or **Claude Code** for live MCP coding-agent demos.

### 1.2 Option A: One-Command Fast-Track Deployment (Express + Seed + 2×2 Authz — ~2 Minutes)

```bash
git clone https://github.com/szinsmeister-google/alloydb-express-to-agent-teams.git
cd alloydb-express-to-agent-teams

export PROJECT_ID="your-gcp-project-id"
export REGION="asia-southeast1"

# Authenticate ADC with AlloyDB & Cloud Platform scopes
gcloud config set project "${PROJECT_ID}"
gcloud auth application-default login \
  --scopes="https://www.googleapis.com/auth/alloydb,https://www.googleapis.com/auth/cloud-platform"

# Provision AlloyDB Express (<2s), seed inventory_db + finance_db, and configure 2x2 IAM isolation
./scripts/setup_express_and_seed.sh
```

### 1.3 Option B: Terraform (`click-to-deploy/`) + In-Place Upgrade to Agent Mode

If deploying via `go/demos` Click-to-Deploy or Terraform first, provision the VPC, PSC Service Connection Policy, Secret Manager password, and IAM service accounts via Terraform, then run the Express bootstrap and optional Agent Mode upgrade:

```bash
cd click-to-deploy
terraform init
terraform apply \
  -var="project_id=${PROJECT_ID}" \
  -var="data_location=${REGION}" \
  -var="gcp_account_name=$(gcloud config get-value account)"
cd ..

# Seed Express cluster & databases
./scripts/setup_express_and_seed.sh

# Optional (~10-15 min background provisioning; requires Agent Mode Preview allowlist):
# Upgrade Express in place (--no-enable-express) and attach the 0->10 serverless Agent Pool
./scripts/upgrade_to_agent_mode.sh
```

### 1.4 Install Python Agent Dependencies & Verify Deployment

```bash
cd agents
python3 -m venv .venv
source .venv/bin/activate
pip install --quiet -r requirements.txt
cd ..

# Verify AlloyDB Remote MCP tools/list & monthly fill-rate baseline (96.2% Jan -> 83.9% Jul)
./scripts/test_mcp_connection.sh
```

Expected verification output: `16` MCP tools listed (`create_cluster`, `execute_sql_read_only`, etc.) and 7 monthly rows showing `2026-01: 96.2%` declining to `2026-07: 83.9%`.

### 1.5 Teardown & Cost Cleanup

Always run cleanup after your customer meeting or workshop to prevent ongoing AlloyDB compute charges:

```bash
PROJECT_ID="${PROJECT_ID}" REGION="${REGION}" ./scripts/cleanup.sh

# If you also deployed click-to-deploy Terraform resources:
cd click-to-deploy && terraform destroy -var="project_id=${PROJECT_ID}" -var="data_location=${REGION}"
```

---

## Pillar 2: How to Access the Demo

### 2.1 Entry Points & Surfaces (Open Left-to-Right Before the Call)

1. **Terminal / Antigravity / Claude Code:** Connected to `https://alloydb.googleapis.com/mcp` with `PROJECT_ID` and `REGION` exported and `agents/.venv` activated.
2. **Google Cloud Console — AlloyDB Clusters:** `https://console.cloud.google.com/alloydb/clusters?project=<PROJECT_ID>` (shows `summit-trail-cluster`, `summit-trail-primary`, and `summit-trail-agent-pool` + Knowledge Catalog status).
3. **Google Cloud Console — AlloyDB Studio:** `https://console.cloud.google.com/alloydb/locations/<REGION>/clusters/summit-trail-cluster/studio?project=<PROJECT_ID>` (for live `has_database_privilege` 2×2 matrix and authorized `finance_db` verification).
4. **Google Cloud Console — Knowledge Catalog Studio:** `https://console.cloud.google.com/dataplex/studio?project=<PROJECT_ID>` (shows the connected Supply Chain & Finance Context Graph).
5. **Google Cloud Console — Cloud Monitoring:** `https://console.cloud.google.com/monitoring?project=<PROJECT_ID>` (shows flat `~15%` primary CPU vs. Agent Pool `0 → 10 → 0` scaling).

### 2.2 Credentials & Test Personas

- **Authentication Method:** Passwordless **Google Cloud IAM Database Authentication** (`gcloud auth application-default login` with `alloydb` + `cloud-platform` scopes). No static passwords are embedded in agent code.
- **Demo Personas & Database Identities:**
  - **Priya (VP of Warehouse Operations):** `warehouse-agent@<PROJECT_ID>.iam` mapped to PostgreSQL role `priya_warehouse_agent` — **ALLOW** on `inventory_db`, **DENY (`SQLSTATE 42501`)** on `finance_db`.
  - **Diego (VP of Vendor Finance):** `finance-agent@<PROJECT_ID>.iam` mapped to PostgreSQL role `diego_finance_agent` — **DENY (`SQLSTATE 42501`)** on `inventory_db`, **ALLOW** on `finance_db`.
- **Break-Glass `postgres` Password (Terraform Deployments):** Retrieve from Secret Manager via `gcloud secrets versions access latest --secret="summit-trail-cluster-postgres-password" --project="${PROJECT_ID}"`.

### 2.3 Expected Initial Landing State

Before starting the customer pitch, confirm:
- `summit-trail-primary` shows green **READY** status on PostgreSQL 18.
- `./scripts/test_mcp_connection.sh` returns `2026-01 (96.2%)` through `2026-07 (83.9%)` in `< 1s`.
- `python3 agents/verify_2x2_authz.py` prints `[PASS]` for all 4 cells of the 2×2 authorization matrix.

---

## Demo Walkthrough (Pillar 3 & Pillar 4: Step-by-Step Walkthrough & Seller Talking Script)

### Opening Discovery Hook (Before Sharing Screen)

> **What to Say:** *"Every engineering leader we talk to wants autonomous AI agents acting on live business data—not yesterday's warehouse export. But the moment you point ten concurrent agents at your live PostgreSQL primary, CPU spikes and checkout slows down, and your CISO shuts it down because prompt guardrails aren't a real security boundary. How are your teams currently isolating agent workloads from live transactional databases?"*

---

### Step 1: Prototype in 2 Seconds with AlloyDB Express & Remote MCP

- **What to Do:**
  1. Open **Antigravity** (or **Claude Code**) configured with `https://alloydb.googleapis.com/mcp` and paste:
     ```text
     In project $PROJECT_ID and location $REGION, create an AlloyDB Express cluster named summit-trail-cluster, create a 1-vCPU primary instance named summit-trail-primary with publicDnsEnabled set to true, and create an IAM database user for my email with databaseRoles ["alloydbiamuser", "postgres"].
     ```
  2. Switch to the **AlloyDB Clusters** console tab to show the `Express` badge, PostgreSQL 18, and green `READY` health check (or show the pre-seeded cluster provisioned via `./scripts/setup_express_and_seed.sh`).
- **Expected Visual Outcome:** Cluster and primary instance provision in **~1.6–2 seconds** over managed MCP with zero VPC peering wait, and auto-pause to `$0` compute after 15 minutes of inactivity.
- **What to Say (Seller Script):**
  > *"Coding agents write full apps in seconds, yet enterprise databases still make developers wait 15 minutes for VPC peering. With AlloyDB Express over our managed Remote MCP server, your coding agent spins up real PostgreSQL 18 in under two seconds—and when the prototype takes off, one command upgrades it in place to full enterprise AlloyDB with zero data migration."*
- **Why Google Cloud:** Unlike standalone serverless Postgres forks that require a migration when you hit enterprise scale, AlloyDB Express upgrades in place to full AlloyDB (`99.99%` SLA, Columnar Engine, ScaNN, Agent Mode) keeping the exact same DNS endpoints and schemas.

---

### Step 2: Live Operations Check & Launching the 10-Agent Root-Cause Team

- **What to Do:**
  1. Run Priya's opening operational checks:
     ```bash
     source agents/.venv/bin/activate
     PROJECT_ID="${PROJECT_ID}" REGION="${REGION}" python3 agents/run_ops_prompts.py
     ```
  2. Immediately launch the **10-Agent Parallel Investigation Team** (`s01`–`s09` specialists + `s10` Devil's Advocate):
     ```bash
     PROJECT_ID="${PROJECT_ID}" REGION="${REGION}" python3 agents/team_agent.py
     ```
  3. (Optional in Console) Open **Knowledge Catalog Studio** and click `sales_orders` in the Context Graph to show the governed `shipped | partial | cut` status semantics.
- **Expected Visual Outcome:**
  - `run_ops_prompts.py` reports fill rate dropping from **96.2% (Jan) → 83.9% (July)**, driven by **Columbus (`CMH`: 85.46%, 3,885 cut)** and **Fort Worth (`DFW`: 86.02%, 4,833 cut)** across **12,340 total cut units**.
  - `team_agent.py` streams 10 parallel findings:
    - **`s10_devils_advocate` REFUTES two false scapegoats:** **325 cycle-count audits** prove **98.62% inventory accuracy** (not warehouse shrink), and `demand_forecasts` prove orders tracked within **1.58% of forecast** (not a surprise demand spike).
    - **`s02`, `s03`, `s04`, `s08`, `s09` pinpoint two real root causes:** **Pacific Trail Imports (`SUP-002`)** slipped from `7d` configured to `21d` actual (`0%` on-time) and **Cascade Ridge (`SUP-001`)** slipped from `14d` to `34d` (`0%` on-time), while rigid single-DC routing cut orders in **Columbus (`0` available)** even though **Fort Worth sat on 1,240 units of `STS-0001` and 1,040 units of `STS-0006`**.
- **What to Say (Seller Script):**
  > *"Watch what happens when we move past a single chatbot to a 10-agent team. Nine specialists test lead times, PO shortfalls, and stranded stock in parallel, while the 10th agent—our Devil's Advocate—uses 325 real warehouse cycle counts to kill the wrong warehouse-shrink hypothesis before operations wastes money on emergency air freight. Lateral routing + lead-time recalibration recovers over 11,800 units and $1.25M in revenue."*
- **Why Google Cloud:** AlloyDB Agent Mode runs these concurrent agents on serverless microVMs (`0 → 10 → 0`) over shared **Google Colossus** storage—sub-millisecond freshness with **zero load** on the transactional primary.

---

### Step 3: Prove Primary CPU Isolation & Database-Enforced 2×2 Authorization ("Grants Are the Boundary")

- **What to Do:**
  1. Open **Cloud Monitoring** to show `summit-trail-primary` CPU remaining flat (`~15%`) while `summit-trail-agent-pool` absorbed the 10-agent burst and scaled back to zero.
  2. Run the automated **2×2 Engine-Level Database Authorization Verifier**:
     ```bash
     PROJECT_ID="${PROJECT_ID}" REGION="${REGION}" python3 agents/verify_2x2_authz.py
     ```
  3. Optionally run the `has_database_privilege` query from `data/sql/05_verify_queries.sql` in **AlloyDB Studio**.
- **Expected Visual Outcome:**
  ```text
  [PASS] warehouse-agent  -> inventory_db  | Expected: ALLOW | Actual: ALLOW
  [PASS] warehouse-agent  -> finance_db    | Expected: DENY  | Actual: DENY (SQLSTATE 42501)
  [PASS] finance-agent    -> inventory_db  | Expected: DENY  | Actual: DENY (SQLSTATE 42501)
  [PASS] finance-agent    -> finance_db    | Expected: ALLOW | Actual: ALLOW
  ```
- **What to Say (Seller Script):**
  > *"Now put on your CISO hat. Priya just saw Cascade Ridge slipped three weeks and asks her agent what we paid them on the last three invoices. Those invoices live in `finance_db`. Notice we did NOT write a fragile prompt rule saying 'please pretend you can't see finance.' Instead, the AlloyDB MCP server cryptographically binds the agent's OAuth token to its PostgreSQL IAM identity, and the PostgreSQL engine itself rejects the connection with `SQLSTATE 42501`. Even under prompt injection, grants are the boundary."*
- **Why Google Cloud:** Standard PostgreSQL `GRANT`/`REVOKE` policies replicate automatically to every serverless microVM in the Agent Pool—unifying enterprise DBA governance with autonomous AI agents.

---

### Closing & Next-Step Transition

- **Common Customer Objections & Responses:**
  - *Objection:* *"What if we already run Postgres on AWS Aurora or are evaluating Databricks Lakebase?"*
    - *Response:* *"AlloyDB delivers 4x transactional throughput, up to 100x faster analytical queries via its SIMD Columnar Engine, and serverless Agent Mode microVMs reading shared Colossus storage—eliminating both ETL lag and primary CPU contention without forcing a fork or proprietary lakehouse lock-in."*
  - *Objection:* *"Can we test this on our own PostgreSQL schema?"*
    - *Response:* *"Yes—we can clone this exact repo into a sandbox in your project, spin up AlloyDB Express in two seconds, load a sanitized slice of your operational tables, and run a 10-agent root-cause team + 2×2 security proof in a half-day technical workshop."*

---

## Troubleshooting & Live-Demo Recovery Tips

- **Express vs. Agent Mode Preview Allowlist:** If your project is not yet enrolled in the AlloyDB Agent Mode Preview allowlist, run the entire demo seamlessly in **Fast-Track mode** against AlloyDB Express using the default `MCP_URL=https://alloydb.googleapis.com`—every ADK agent, 10-agent team prompt, and 2×2 `SQLSTATE 42501` test works identically!
- **Cold-Start Auto-Pause Wakeup:** AlloyDB Express auto-pauses after 15 minutes of inactivity. Run `./scripts/test_mcp_connection.sh` 2 minutes before your customer call to wake the cluster cleanly.
- **IAM Propagation Delay:** If `verify_2x2_authz.py` returns a temporary IAM impersonation error right after initial creation, wait 30 seconds for `roles/iam.serviceAccountTokenCreator` to propagate and re-run.
- **Resetting Sample Data:** Re-run `scripts/setup_express_and_seed.sh` at any time—the SQL seed scripts are idempotent (`TRUNCATE ... RESTART IDENTITY` / `ON CONFLICT DO NOTHING`) and cleanly restore the exact baseline dataset.
