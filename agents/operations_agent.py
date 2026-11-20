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
    "Domain formulas: `cut_units = (qty_ordered - qty_shipped)`, "
    "`fill_rate_pct = ROUND(100.0 * SUM(qty_shipped) / SUM(qty_ordered), 2)`. "
    "Always join `sales_orders` and `sales_order_lines` on `order_id` and group/filter dates by `sales_orders.order_date`.\n"
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
