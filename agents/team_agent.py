"""10-Agent Root-Cause Investigation Team on AlloyDB (9 Specialists + Devil's Advocate)."""

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
    (
        "s01_sku_pareto",
        "Quantify cut units (qty_ordered - qty_shipped) and lost revenue by SKU and category from sales_order_lines and products.",
    ),
    (
        "s02_dc_imbalance",
        "Compare available_qty across RNO (1), DFW (2), and CMH (3) in inventory_snapshots to detect stranded surplus stock.",
    ),
    (
        "s03_supplier_lead_times",
        "Compare configured products.lead_time_days against actual_lead_time_days in purchase_order_lines by supplier.",
    ),
    (
        "s04_po_shortfalls",
        "Identify purchase orders in purchase_orders and purchase_order_lines where qty_received < qty_ordered or status = 'received_late'.",
    ),
    (
        "s05_safety_stock_audit",
        "Check whether products.reorder_point and safety_stock buffers are calibrated for actual supplier lead times.",
    ),
    (
        "s06_channel_impact",
        "Analyze which wholesale distributors in customers experienced cut orders.",
    ),
    (
        "s07_seasonal_cadence",
        "Trace month-over-month cut_units = SUM(qty_ordered - qty_shipped) from January through July 2026 by joining sales_orders.order_date and sales_order_lines.",
    ),
    (
        "s08_lateral_routing_sim",
        "Calculate how many cut units in CMH and DFW could be recovered by lateral transshipment from surplus available_qty in inventory_snapshots.",
    ),
    (
        "s09_lead_time_recalibration_sim",
        "Query products where supplier_id IN ('SUP-001', 'SUP-002') and quantify the impact of recalibrating lead_time_days for SUP-002 (7d -> 21d) and SUP-001 (14d -> 34d).",
    ),
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
            parts=[
                types.Part.from_text(
                    text="Investigate the fill-rate drop with 10 agents, including a devil's advocate."
                )
            ],
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
