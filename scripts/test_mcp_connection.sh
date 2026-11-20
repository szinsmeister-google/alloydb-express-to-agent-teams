#!/usr/bin/env bash
# Quick verification of AlloyDB Remote MCP Server tools/list & fill-rate query
set -euo pipefail

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
export REGION="${REGION:-asia-southeast1}"
export CLUSTER_ID="${CLUSTER_ID:-summit-trail-cluster}"
export PRIMARY_ID="${PRIMARY_ID:-summit-trail-primary}"

echo "==> Listing tools from https://alloydb.googleapis.com/mcp..."
curl -sf -X POST https://alloydb.googleapis.com/mcp \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Mcp-Method: tools/list" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | grep -o '"name":"[^"]*"' | head -n 16

echo ""
echo "==> Running monthly YTD fill-rate check against inventory_db..."
INSTANCE_URI="projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_ID}/instances/${PRIMARY_ID}"
SQL="SELECT TO_CHAR(DATE_TRUNC('month', o.order_date), 'YYYY-MM') AS order_month, SUM(l.qty_ordered) AS ordered_units, SUM(l.qty_shipped) AS shipped_units, ROUND(100.0 * SUM(l.qty_shipped) / SUM(l.qty_ordered), 1) AS unit_fill_rate_pct FROM sales_orders o JOIN sales_order_lines l ON o.order_id = l.order_id GROUP BY 1 ORDER BY 1;"
PAYLOAD=$(python3 -c 'import json,sys; print(json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"execute_sql_read_only","arguments":{"instance":sys.argv[1],"database":"inventory_db","sqlStatement":sys.argv[2]}}}))' "${INSTANCE_URI}" "${SQL}")

curl -sf -X POST https://alloydb.googleapis.com/mcp \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "${PAYLOAD}"
echo ""
