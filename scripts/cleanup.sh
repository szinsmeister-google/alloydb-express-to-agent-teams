#!/usr/bin/env bash
# ============================================================================
# Clean Teardown: Removes AlloyDB Cluster (Primary + Agent Pool), VPC/PSC & SAs
# ============================================================================
set -euo pipefail

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
export REGION="${REGION:-asia-southeast1}"
export CLUSTER_ID="${CLUSTER_ID:-summit-trail-cluster}"
export WAREHOUSE_SA_EMAIL="warehouse-agent@${PROJECT_ID}.iam.gserviceaccount.com"
export FINANCE_SA_EMAIL="finance-agent@${PROJECT_ID}.iam.gserviceaccount.com"

echo "==> [1/3] Deleting AlloyDB cluster (${CLUSTER_ID}) including Primary and Agent Pool..."
gcloud beta alloydb clusters delete "${CLUSTER_ID}" \
  --region="${REGION}" \
  --force \
  --quiet \
  --project="${PROJECT_ID}" 2>/dev/null || echo "    (Cluster already deleted)"

echo "==> [2/3] Deleting PSC service connection policy, subnet, and agents-vpc..."
gcloud network-connectivity service-connection-policies delete alloydb-agents-policy \
  --region="${REGION}" --quiet --project="${PROJECT_ID}" 2>/dev/null || true

gcloud compute networks subnets delete agents-subnet \
  --region="${REGION}" --quiet --project="${PROJECT_ID}" 2>/dev/null || true

gcloud compute networks delete agents-vpc \
  --quiet --project="${PROJECT_ID}" 2>/dev/null || true

echo "==> [3/3] Deleting IAM service accounts..."
gcloud iam service-accounts delete "${WAREHOUSE_SA_EMAIL}" --quiet --project="${PROJECT_ID}" 2>/dev/null || true
gcloud iam service-accounts delete "${FINANCE_SA_EMAIL}" --quiet --project="${PROJECT_ID}" 2>/dev/null || true

echo "==> Cleanup complete."
