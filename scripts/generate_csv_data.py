#!/usr/bin/env python3
"""Deterministically generates CSV exports of all 13 Summit Trail Supply tables.

Matches data/sql/02_seed_inventory_db.sql (11 tables) and
data/sql/03_seed_finance_db.sql (2 tables) row-for-row so CEs and FDEs can
inspect, audit, or load the dataset into BigLake / Cloud Storage / Looker.
"""

import csv
import datetime
import pathlib

OUT_DIR = pathlib.Path(__file__).resolve().parent.parent / "data" / "csv"


def write_csv(filename: str, headers: list[str], rows: list[tuple]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / filename
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        writer.writerows(rows)
    print(f"Wrote {len(rows):>3} rows -> {path.relative_to(OUT_DIR.parent.parent)}")


def main() -> None:
    # 1. distribution_centers
    write_csv(
        "distribution_centers.csv",
        ["dc_id", "dc_code", "dc_name", "region", "capacity_units"],
        [
            (1, "RNO", "Reno West Coast Hub", "West", 250000),
            (2, "DFW", "Fort Worth Central Hub", "South Central", 300000),
            (3, "CMH", "Columbus Midwest Hub", "Midwest/East", 280000),
        ],
    )

    # 2. suppliers
    write_csv(
        "suppliers.csv",
        ["supplier_id", "supplier_name", "country", "reliability_tier"],
        [
            ("SUP-001", "Cascade Ridge Manufacturing", "USA", "Tier-2 Watch"),
            ("SUP-002", "Pacific Trail Imports", "Vietnam", "Tier-3 Delinquent"),
            ("SUP-003", "Sierra Alpine Textiles", "USA", "Tier-1 Preferred"),
            ("SUP-004", "Highland Gear Works", "Taiwan", "Tier-1 Preferred"),
        ],
    )

    # 3. products
    write_csv(
        "products.csv",
        [
            "sku",
            "product_name",
            "category",
            "supplier_id",
            "unit_cost",
            "list_price",
            "lead_time_days",
            "reorder_point",
            "safety_stock",
        ],
        [
            ("STS-0001", "Apex 4-Season Expedition Tent", "Tents & Shelters", "SUP-002", "112.00", "249.99", 7, 400, 150),
            ("STS-0002", "SolarFlare 1000L Rechargeable Lantern", "Lighting & Electronics", "SUP-002", "24.50", "59.99", 7, 800, 250),
            ("STS-0003", "GlacierVault 45Qt Rotomolded Cooler", "Hydration & Coolers", "SUP-002", "88.00", "199.99", 7, 500, 180),
            ("STS-0004", "Titanium Dual-Fuel Backcountry Stove", "Camp Kitchen", "SUP-002", "31.00", "79.99", 7, 600, 200),
            ("STS-0005", "TrailBeam 450 Headlamp Pro", "Lighting & Electronics", "SUP-002", "18.20", "44.99", 7, 900, 300),
            ("STS-0006", "Northfork Dome Tent Lite", "Tents & Shelters", "SUP-001", "67.34", "154.57", 14, 450, 160),
            ("STS-0007", "Basin Backpacking Tent", "Tents & Shelters", "SUP-001", "71.64", "159.96", 14, 420, 150),
            ("STS-0008", "Juniper Tarp Shelter Lite", "Tents & Shelters", "SUP-001", "27.15", "49.81", 14, 700, 220),
            ("STS-0009", "Northfork Bivy", "Tents & Shelters", "SUP-001", "59.75", "129.89", 14, 520, 180),
            ("STS-0010", "Basin Canopy Lite", "Tents & Shelters", "SUP-001", "35.91", "74.91", 14, 600, 200),
            ("STS-0011", "Sierra Down Sleeping Bag 20F", "Sleep Systems", "SUP-003", "95.00", "219.00", 10, 350, 120),
            ("STS-0012", "Highland Carbon Trekking Poles", "Packs & Poles", "SUP-004", "42.00", "99.50", 12, 500, 160),
        ],
    )

    # 4. customers
    write_csv(
        "customers.csv",
        ["customer_id", "customer_name", "channel", "preferred_dc_id"],
        [
            (1, "Outfitter Collective Midwest", "Wholesale Distributor", 3),
            (2, "Lone Star Outdoor Co-op", "Wholesale Distributor", 2),
            (3, "Sierra Crest Retail Group", "Wholesale Distributor", 1),
            (4, "Great Lakes Adventure Supply", "Regional Chain", 3),
            (5, "Red River Outfitters", "Regional Chain", 2),
        ],
    )

    # 5. inventory_snapshots
    write_csv(
        "inventory_snapshots.csv",
        ["snapshot_id", "snapshot_date", "dc_id", "sku", "on_hand_qty", "reserved_qty", "available_qty"],
        [
            (1, "2026-07-28", 3, "STS-0001", 12, 12, 0),
            (2, "2026-07-28", 2, "STS-0001", 1420, 180, 1240),
            (3, "2026-07-28", 1, "STS-0001", 610, 110, 500),
            (4, "2026-07-28", 3, "STS-0006", 8, 8, 0),
            (5, "2026-07-28", 2, "STS-0006", 1180, 140, 1040),
            (6, "2026-07-28", 3, "STS-0009", 0, 0, 0),
            (7, "2026-07-28", 1, "STS-0009", 980, 120, 860),
            (8, "2026-07-28", 2, "STS-0003", 15, 15, 0),
            (9, "2026-07-28", 1, "STS-0003", 1120, 150, 970),
        ],
    )

    # 6. purchase_orders
    write_csv(
        "purchase_orders.csv",
        ["po_id", "supplier_id", "dc_id", "order_date", "promised_date", "status"],
        [
            (101, "SUP-002", 3, "2026-06-01", "2026-06-08", "received_late"),
            (102, "SUP-002", 2, "2026-06-15", "2026-06-22", "received_late"),
            (103, "SUP-001", 3, "2026-06-05", "2026-06-19", "received_late"),
            (104, "SUP-001", 2, "2026-07-01", "2026-07-15", "received_late"),
            (105, "SUP-003", 1, "2026-06-10", "2026-06-20", "received_on_time"),
        ],
    )

    # 7. purchase_order_lines
    write_csv(
        "purchase_order_lines.csv",
        ["po_line_id", "po_id", "sku", "qty_ordered", "qty_received", "received_date", "actual_lead_time_days"],
        [
            (1, 101, "STS-0001", 1200, 1200, "2026-06-22", 21),
            (2, 101, "STS-0002", 1500, 1500, "2026-06-22", 21),
            (3, 102, "STS-0003", 900, 900, "2026-07-06", 21),
            (4, 103, "STS-0006", 1000, 820, "2026-07-18", 33),
            (5, 104, "STS-0009", 1100, 880, "2026-08-05", 35),
            (6, 105, "STS-0011", 800, 800, "2026-06-20", 10),
        ],
    )

    # 8. sales_orders
    write_csv(
        "sales_orders.csv",
        ["order_id", "customer_id", "dc_id", "order_date", "promised_ship_date", "status"],
        [
            (1, 3, 1, "2026-01-15", "2026-01-18", "shipped"),
            (2, 2, 2, "2026-02-15", "2026-02-18", "shipped"),
            (3, 3, 1, "2026-03-15", "2026-03-18", "shipped"),
            (4, 1, 3, "2026-04-15", "2026-04-18", "partial"),
            (5, 2, 2, "2026-05-15", "2026-05-18", "partial"),
            (6, 3, 1, "2026-06-12", "2026-06-15", "partial"),
            (7, 2, 2, "2026-06-20", "2026-06-23", "partial"),
            (8, 1, 3, "2026-07-10", "2026-07-13", "cut"),
            (9, 2, 2, "2026-07-18", "2026-07-21", "partial"),
            (10, 3, 1, "2026-07-24", "2026-07-27", "partial"),
        ],
    )

    # 9. sales_order_lines
    write_csv(
        "sales_order_lines.csv",
        ["line_id", "order_id", "sku", "qty_ordered", "qty_shipped", "unit_price", "ship_date"],
        [
            (1, 1, "STS-0011", 5000, 4810, "219.00", "2026-01-18"),
            (2, 2, "STS-0012", 5000, 4790, "99.50", "2026-02-18"),
            (3, 3, "STS-0001", 5000, 4770, "249.99", "2026-03-18"),
            (4, 4, "STS-0001", 6000, 5472, "249.99", "2026-04-18"),
            (5, 5, "STS-0003", 10000, 8800, "199.99", "2026-05-18"),
            (6, 6, "STS-0002", 14340, 12260, "59.99", "2026-06-15"),
            (7, 7, "STS-0004", 12300, 10517, "79.99", "2026-06-23"),
            (8, 8, "STS-0006", 20720, 17363, "154.57", "2026-07-13"),
            (9, 9, "STS-0003", 7280, 5640, "199.99", "2026-07-21"),
            (10, 10, "STS-0009", 10000, 8878, "129.89", "2026-07-27"),
        ],
    )

    # 10. cycle_counts (325 warehouse audits at 98.62% accuracy)
    base_date = datetime.date(2026, 5, 1)
    cycle_rows = [
        (
            g,
            (g % 3) + 1,
            "STS-0001" if g % 2 == 0 else "STS-0006",
            (base_date + datetime.timedelta(days=g % 85)).isoformat(),
            500,
            493,
            "98.62",
        )
        for g in range(1, 326)
    ]
    write_csv(
        "cycle_counts.csv",
        ["audit_id", "dc_id", "sku", "audit_date", "system_qty", "physical_qty", "accuracy_pct"],
        cycle_rows,
    )

    # 11. demand_forecasts
    write_csv(
        "demand_forecasts.csv",
        ["forecast_id", "forecast_month", "sku", "forecast_units", "actual_ordered_units", "variance_pct"],
        [
            (1, "2026-05-01", "STS-0001", 11800, 12000, "1.69"),
            (2, "2026-06-01", "STS-0006", 11850, 12000, "1.27"),
            (3, "2026-07-01", "STS-0006", 11790, 12000, "1.78"),
        ],
    )

    # 12. vendor_contracts (finance_db)
    write_csv(
        "vendor_contracts.csv",
        [
            "contract_id",
            "supplier_id",
            "supplier_name",
            "payment_terms",
            "late_delivery_sla_penalty_pct",
            "contract_status",
        ],
        [
            ("CTR-2026-001", "SUP-001", "Cascade Ridge Manufacturing", "Net 45 (2% 10-Day Early Pay)", "5.00", "Active - Under SLA Review"),
            ("CTR-2026-002", "SUP-002", "Pacific Trail Imports", "Net 60 Letter of Credit", "7.50", "Breach Notice Issued"),
        ],
    )

    # 13. supplier_invoices (finance_db)
    write_csv(
        "supplier_invoices.csv",
        [
            "invoice_id",
            "supplier_id",
            "invoice_date",
            "sku",
            "product_name",
            "units_billed",
            "contract_unit_cost_usd",
            "billed_unit_cost_usd",
            "sla_penalty_credit_usd",
            "payment_status",
        ],
        [
            ("INV-2026-0718", "SUP-001", "2026-07-18", "STS-0009", "Northfork Bivy", 1100, "84.50", "89.25", "5355.00", "Disputed - Late Delivery + Surcharge"),
            ("INV-2026-0624", "SUP-001", "2026-06-24", "STS-0006", "Northfork Dome Tent Lite", 1000, "142.00", "146.00", "6935.00", "Approved with 5% SLA Credit"),
            ("INV-2026-0529", "SUP-001", "2026-05-29", "STS-0010", "Basin Canopy Lite", 950, "118.00", "118.00", "0.00", "Paid (2% Early Pay Discount)"),
        ],
    )


if __name__ == "__main__":
    main()
