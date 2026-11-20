#!/usr/bin/env bash
# ============================================================================
# In-Place Upgrade: AlloyDB Express -> Enterprise AlloyDB + Agent Mode (0 -> 10)
#
# Preserves all databases, schemas, IAM users, and endpoints with zero migration.
# Requires a region supporting both Express and Agent Mode (e.g., asia-southeast1)
# and project enrollment in the AlloyDB PostgreSQL for Agents Preview allowlist.
# ============================================================================
set -euo pipefail

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
export REGION="${REGION:-asia-southeast1}"
export CLUSTER_ID="${CLUSTER_ID:-summit-trail-cluster}"
export POOL_ID="${POOL_ID:-summit-trail-agent-pool}"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "ERROR: Set PROJECT_ID first." >&2
  exit 1
fi

echo "==> [1/4] Upgrading ${CLUSTER_ID} in place (--no-enable-express)..."
gcloud beta alloydb clusters update "${CLUSTER_ID}" \
  --region="${REGION}" \
  --no-enable-express \
  --project="${PROJECT_ID}"

echo "==> [2/4] Creating agents-vpc, agents-subnet, and PSC Service Connection Policy..."
gcloud compute networks create agents-vpc \
  --project="${PROJECT_ID}" \
  --subnet-mode=custom 2>/dev/null || true

gcloud compute networks subnets create agents-subnet \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --network=agents-vpc \
  --range=10.20.0.0/24 2>/dev/null || true

gcloud network-connectivity service-connection-policies create alloydb-agents-policy \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --service-class=google-cloud-alloydb \
  --network=agents-vpc \
  --subnets=agents-subnet \
  --psc-connection-limit=10 2>/dev/null || true

echo "==> [3/4] Enabling Agent mode on ${CLUSTER_ID} and waiting for ACTIVE..."
curl -sf -X PATCH \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://alloydb.googleapis.com/v1beta/projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_ID}?updateMask=agentModeConfig.mode" \
  -d '{"agentModeConfig": {"mode": "ENABLED"}}' >/dev/null

while true; do
  STATE=$(curl -sf -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    "https://alloydb.googleapis.com/v1beta/projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_ID}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('agentModeInfo',{}).get('state','NONE'))")
  echo "    Agent mode state: ${STATE}"
  [[ "${STATE}" == "ACTIVE" ]] && break
  [[ "${STATE}" == "NONE" ]] && { echo "ERROR: Agent mode not enabled. Check Preview allowlist."; exit 1; }
  sleep 10
done

echo "==> [4/4] Creating serverless Agent Pool (${POOL_ID}: 0 -> 10 microVMs)..."
curl -sf -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://alloydb.googleapis.com/v1beta/projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_ID}/instances?instanceId=${POOL_ID}" \
  -d "{
    \"instanceType\": \"AGENT_POOL\",
    \"agentPoolConfig\": {
      \"minPoolSize\": 0,
      \"maxPoolSize\": 10,
      \"pscAutoConnections\": [{
        \"consumerProject\": \"${PROJECT_ID}\",
        \"consumerNetwork\": \"projects/${PROJECT_ID}/global/networks/agents-vpc\"
      }]
    }
  }" >/dev/null || echo "    (Agent Pool may already exist; continuing)"

echo "    Waiting for Agent Pool READY state..."
for _ in $(seq 1 60); do
  PSTATE=$(curl -sf -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    "https://alloydb.googleapis.com/v1beta/projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_ID}/instances/${POOL_ID}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('state','PENDING'))")
  [[ "${PSTATE}" == "READY" ]] && break
  sleep 10
done

MCP_HOST=$(curl -sf -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://alloydb.googleapis.com/v1beta/projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_ID}/instances/${POOL_ID}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('agentPoolInfo',{}).get('dnsName','').rstrip('.'))")

gcloud beta alloydb clusters describe "${CLUSTER_ID}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --format='value(certificateAuthorityInfo.rootCaCert)' > ca.pem

echo ""
echo "============================================================================"
echo "Agent Pool READY!"
echo "  Private MCP Endpoint: https://${MCP_HOST}/mcp"
echo "  Root CA Certificate:  $(pwd)/ca.pem"
echo "============================================================================"
