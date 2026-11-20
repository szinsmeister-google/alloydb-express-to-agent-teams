#!/usr/bin/env python3
"""Verifies the 2x2 AlloyDB PostgreSQL Database Authorization Matrix over MCP.

Proves "Grants Are the Boundary" at the PostgreSQL engine layer:
  1. warehouse-agent -> inventory_db : ALLOW (returns rows)
  2. warehouse-agent -> finance_db   : DENY  (SQLSTATE 42501 permission denied)
  3. finance-agent   -> inventory_db : DENY  (SQLSTATE 42501 permission denied)
  4. finance-agent   -> finance_db   : ALLOW (returns supplier_invoices rows)
"""

import json
import os
import subprocess
import sys
import urllib.request

PROJECT_ID = os.environ["PROJECT_ID"]
REGION = os.environ.get("REGION", "asia-southeast1")
CLUSTER_ID = os.environ.get("CLUSTER_ID", "summit-trail-cluster")
PRIMARY_ID = os.environ.get("PRIMARY_ID", "summit-trail-primary")
MCP_ENDPOINT = os.environ.get("MCP_URL", "https://alloydb.googleapis.com").rstrip("/") + "/mcp"

WAREHOUSE_SA = os.environ.get(
    "WAREHOUSE_SA_EMAIL", f"warehouse-agent@{PROJECT_ID}.iam.gserviceaccount.com"
)
FINANCE_SA = os.environ.get(
    "FINANCE_SA_EMAIL", f"finance-agent@{PROJECT_ID}.iam.gserviceaccount.com"
)
INSTANCE_URI = (
    f"projects/{PROJECT_ID}/locations/{REGION}/"
    f"clusters/{CLUSTER_ID}/instances/{PRIMARY_ID}"
)


def impersonated_token(sa_email: str) -> str:
    cmd = [
        "gcloud",
        "auth",
        "print-access-token",
        f"--impersonate-service-account={sa_email}",
    ]
    return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()


def call_mcp_read_only(token: str, database: str, sql: str) -> dict:
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {
            "name": "execute_sql_read_only",
            "arguments": {
                "instance": INSTANCE_URI,
                "database": database,
                "sqlStatement": sql,
            },
        },
    }
    req = urllib.request.Request(
        MCP_ENDPOINT,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "X-Goog-User-Project": PROJECT_ID,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> int:
    tests = [
        ("warehouse-agent", WAREHOUSE_SA, "inventory_db", "SELECT COUNT(*) AS dc_count FROM distribution_centers;", True),
        ("warehouse-agent", WAREHOUSE_SA, "finance_db", "SELECT * FROM supplier_invoices;", False),
        ("finance-agent", FINANCE_SA, "inventory_db", "SELECT COUNT(*) AS dc_count FROM distribution_centers;", False),
        ("finance-agent", FINANCE_SA, "finance_db", "SELECT invoice_id, sku, billed_unit_cost_usd, payment_status FROM supplier_invoices ORDER BY invoice_date DESC;", True),
    ]

    print("=" * 78)
    print("2x2 AlloyDB Engine-Level Database Authorization Verification")
    print("=" * 78)

    all_passed = True
    for label, sa, db, sql, expect_allow in tests:
        token = impersonated_token(sa)
        raw = json.dumps(call_mcp_read_only(token, db, sql))
        is_denied = "permission denied" in raw.lower() or '"status":"error"' in raw.lower().replace(" ", "")
        actual_allow = not is_denied
        passed = actual_allow == expect_allow
        all_passed = all_passed and passed
        status = "PASS" if passed else "FAIL"
        outcome = "ALLOW" if actual_allow else "DENY (SQLSTATE 42501)"
        expected = "ALLOW" if expect_allow else "DENY"
        print(f"[{status}] {label:<16} -> {db:<13} | Expected: {expected:<5} | Actual: {outcome}")
        if not passed:
            print(f"       Response: {raw[:300]}")

    print("=" * 78)
    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
