#!/usr/bin/env bash
# ============================================================================
# One-Command CE/FDE Bootstrap: AlloyDB Express (<2s) + Seed + 2x2 Authz
#
# Provisions:
#   1. Required Google Cloud APIs & user IAM roles
#   2. AlloyDB Express PostgreSQL 18 cluster & 1-vCPU primary (Public DNS + IAM)
#   3. Databases `inventory_db` (11 tables) & `finance_db` (2 tables) via MCP
#   4. Dedicated IAM service accounts (`warehouse-agent`, `finance-agent`)
#   5. PostgreSQL engine-level 2x2 privilege matrix (SQLSTATE 42501 isolation)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "ERROR: Set PROJECT_ID or run 'gcloud config set project YOUR_PROJECT_ID' first." >&2
  exit 1
fi

export REGION="${REGION:-asia-southeast1}"
export CLUSTER_ID="${CLUSTER_ID:-summit-trail-cluster}"
export PRIMARY_ID="${PRIMARY_ID:-summit-trail-primary}"
export USER_EMAIL="${USER_EMAIL:-$(gcloud config get-value account)}"
export DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9!@#' | head -c 20)}"

export WAREHOUSE_SA_NAME="warehouse-agent"
export WAREHOUSE_SA_EMAIL="${WAREHOUSE_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export WAREHOUSE_DB_USER="${WAREHOUSE_SA_NAME}@${PROJECT_ID}.iam"

export FINANCE_SA_NAME="finance-agent"
export FINANCE_SA_EMAIL="${FINANCE_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export FINANCE_DB_USER="${FINANCE_SA_NAME}@${PROJECT_ID}.iam"

INSTANCE_URI="projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_ID}/instances/${PRIMARY_ID}"

alloydb_sql() {
  local db="$1"
  local sql="$2"
  local payload
  payload=$(python3 -c 'import json,sys; print(json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"execute_sql","arguments":{"instance":sys.argv[1],"database":sys.argv[2],"sqlStatement":sys.argv[3]}}}))' "${INSTANCE_URI}" "${db}" "${sql}")
  curl -sf -X POST "https://alloydb.googleapis.com/mcp" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "${payload}"
  echo ""
}

alloydb_sql_file() {
  local db="$1"
  local file_path="$2"
  local sql_content
  sql_content="$(cat "${file_path}")"
  alloydb_sql "${db}" "${sql_content}"
}

echo "==> [1/6] Enabling required Google Cloud APIs in ${PROJECT_ID}..."
gcloud services enable \
  alloydb.googleapis.com \
  compute.googleapis.com \
  servicenetworking.googleapis.com \
  networkconnectivity.googleapis.com \
  aiplatform.googleapis.com \
  dataplex.googleapis.com \
  monitoring.googleapis.com \
  dns.googleapis.com \
  --project="${PROJECT_ID}"

echo "==> [2/6] Granting AlloyDB & MCP IAM roles to ${USER_EMAIL}..."
for ROLE in roles/alloydb.admin roles/compute.networkUser roles/mcp.toolUser; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${USER_EMAIL}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet >/dev/null
done

echo "==> [3/6] Creating AlloyDB Express cluster (${CLUSTER_ID}) & 1-vCPU primary (${PRIMARY_ID}) in ${REGION}..."
curl -sf -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://alloydb.googleapis.com/v1beta/projects/${PROJECT_ID}/locations/${REGION}/clusters?clusterId=${CLUSTER_ID}" \
  -d "{
    \"databaseVersion\": \"POSTGRES_18\",
    \"expressConfig\": {\"enabled\": true},
    \"initialUser\": {\"user\": \"postgres\", \"password\": \"${DB_PASSWORD}\"}
  }" >/dev/null || echo "    (Cluster may already exist; continuing)"

sleep 3

curl -sf -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://alloydb.googleapis.com/v1beta/projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_ID}/instances?instanceId=${PRIMARY_ID}" \
  -d "{
    \"instanceType\": \"PRIMARY\",
    \"availabilityType\": \"ZONAL\",
    \"machineConfig\": {\"cpuCount\": 1},
    \"databaseFlags\": {\"alloydb.iam_authentication\": \"on\"},
    \"networkConfig\": {\"publicDnsEnabled\": true},
    \"pscInstanceConfig\": {\"allowedConsumerProjects\": [\"${PROJECT_ID}\"]}
  }" >/dev/null || echo "    (Primary instance may already exist; continuing)"

echo "    Waiting for primary instance READY state..."
for _ in $(seq 1 30); do
  STATE=$(gcloud alloydb instances describe "${PRIMARY_ID}" \
    --cluster="${CLUSTER_ID}" --region="${REGION}" --project="${PROJECT_ID}" \
    --format="value(state)" 2>/dev/null || echo "PENDING")
  [[ "${STATE}" == "READY" ]] && break
  sleep 3
done
echo "    Primary instance state: ${STATE}"

echo "==> [4/6] Registering IAM database user (${USER_EMAIL}) and creating databases..."
gcloud alloydb users create "${USER_EMAIL}" \
  --cluster="${CLUSTER_ID}" \
  --region="${REGION}" \
  --type=IAM_BASED \
  --db-roles=alloydbiamuser,postgres \
  --project="${PROJECT_ID}" 2>/dev/null || true

alloydb_sql postgres "SET ROLE postgres; ALTER ROLE session_user CREATEDB CREATEROLE;"
alloydb_sql postgres "CREATE DATABASE inventory_db;" || true
alloydb_sql postgres "CREATE DATABASE finance_db;" || true

echo "==> [5/6] Seeding inventory_db (11 tables) and finance_db (2 tables)..."
alloydb_sql_file inventory_db "${REPO_ROOT}/data/sql/02_seed_inventory_db.sql"
alloydb_sql_file finance_db "${REPO_ROOT}/data/sql/03_seed_finance_db.sql"

echo "==> [6/6] Creating warehouse-agent & finance-agent IAM identities and 2x2 SQL privilege matrix..."
for SA in "${WAREHOUSE_SA_NAME}" "${FINANCE_SA_NAME}"; do
  gcloud iam service-accounts create "${SA}" \
    --project="${PROJECT_ID}" \
    --display-name="Summit Trail ${SA}" 2>/dev/null || true
done
sleep 5

for SA_EMAIL in "${WAREHOUSE_SA_EMAIL}" "${FINANCE_SA_EMAIL}"; do
  for ROLE in roles/aiplatform.user roles/alloydb.databaseUser roles/alloydb.client roles/mcp.toolUser roles/serviceusage.serviceUsageConsumer roles/logging.logWriter; do
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="${ROLE}" \
      --condition=None \
      --quiet >/dev/null
  done
  gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
    --member="user:${USER_EMAIL}" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --project="${PROJECT_ID}" \
    --quiet >/dev/null
done

alloydb_sql_file inventory_db "${REPO_ROOT}/data/sql/04a_setup_authz_inventory_db.sql"
alloydb_sql_file finance_db "${REPO_ROOT}/data/sql/04b_setup_authz_finance_db.sql"

gcloud alloydb users create "${WAREHOUSE_DB_USER}" \
  --cluster="${CLUSTER_ID}" --region="${REGION}" --type=IAM_BASED \
  --db-roles=alloydbiamuser,priya_warehouse_agent --project="${PROJECT_ID}" 2>/dev/null || true

gcloud alloydb users create "${FINANCE_DB_USER}" \
  --cluster="${CLUSTER_ID}" --region="${REGION}" --type=IAM_BASED \
  --db-roles=alloydbiamuser,diego_finance_agent --project="${PROJECT_ID}" 2>/dev/null || true

echo ""
echo "============================================================================"
echo "Summit Trail AlloyDB Express environment is READY!"
echo "  Project:  ${PROJECT_ID}"
echo "  Region:   ${REGION}"
echo "  Cluster:  ${CLUSTER_ID} / Primary: ${PRIMARY_ID}"
echo "  Next:     cd agents && python3 -m venv .venv && source .venv/bin/activate"
echo "            pip install -r requirements.txt"
echo "            PROJECT_ID=${PROJECT_ID} REGION=${REGION} python3 run_ops_prompts.py"
echo "            PROJECT_ID=${PROJECT_ID} REGION=${REGION} python3 team_agent.py"
echo "            PROJECT_ID=${PROJECT_ID} REGION=${REGION} python3 verify_2x2_authz.py"
echo "============================================================================"
