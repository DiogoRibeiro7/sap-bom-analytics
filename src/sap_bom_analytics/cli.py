"""Command-line interface for SAP BOM analytics workflows."""

from __future__ import annotations

import argparse
import json
from datetime import date
from pathlib import Path

from sap_bom_analytics.analytics import ANALYTICS_DATASETS, dataset_csv, export_dataset
from sap_bom_analytics.db import execute_sql_file, repository_root, run_psql
from sap_bom_analytics.logging import configure_logging
from sap_bom_analytics.observability import processing_run
from sap_bom_analytics.sap.contracts import SAP_CONTRACTS
from sap_bom_analytics.sap.loader import ingest_sap_csv


def _parser() -> argparse.ArgumentParser:
    """Build the command-line parser."""
    parser = argparse.ArgumentParser(prog="sap-bom")
    parser.add_argument(
        "--log-level", default="INFO", choices=("DEBUG", "INFO", "WARNING", "ERROR"),
        help="Structured JSON log level written to stderr.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    ingest = subparsers.add_parser("ingest", help="Ingest one SAP CSV extract.")
    ingest.add_argument("table", choices=sorted(SAP_CONTRACTS))
    ingest.add_argument("path", type=Path)

    reconcile = subparsers.add_parser(
        "reconcile", help="Refresh staging, core, and classification layers."
    )
    reconcile.add_argument(
        "--skip-classification", action="store_true",
        help="Stop after refreshing the canonical core model.",
    )

    explode = subparsers.add_parser("explode", help="Explode a canonical BOM.")
    explode.add_argument("material", help="SAP material ID of the root product.")
    explode.add_argument("--date", dest="as_of_date", type=date.fromisoformat)
    explode.add_argument("--plant")

    quality = subparsers.add_parser("quality", help="Show the data-quality scorecard.")
    quality.add_argument("--details", action="store_true")

    summary = subparsers.add_parser("summary", help="Print a named analytics dataset.")
    summary.add_argument("dataset", choices=sorted(ANALYTICS_DATASETS))

    export = subparsers.add_parser("export", help="Export a named analytics dataset.")
    export.add_argument("dataset", choices=sorted(ANALYTICS_DATASETS))
    export.add_argument("output", type=Path)
    export.add_argument("--format", choices=("csv", "parquet"), required=True)

    return parser


def _sql_literal(value: str) -> str:
    """Return a PostgreSQL text literal."""
    if not isinstance(value, str):
        raise TypeError("value must be a string")
    return "'" + value.replace("'", "''") + "'"


def _run_reconciliation(skip_classification: bool) -> None:
    """Refresh deterministic derived layers in dependency order."""
    root = repository_root()
    stages: list[tuple[str, Path]] = [
        ("staging", root / "sql" / "staging" / "refresh_staging.sql"),
        ("core", root / "sql" / "core" / "refresh_core.sql"),
    ]
    if not skip_classification:
        stages.append(
            ("classification", root / "sql" / "classification" / "refresh_classification.sql")
        )

    for stage_name, path in stages:
        with processing_run(
            "reconciliation",
            stage_name,
            metadata={"sql_file": str(path.relative_to(root))},
        ):
            execute_sql_file(path)


def _explode(material: str, as_of_date: date | None, plant: str | None) -> str:
    """Return one BOM explosion as CSV text."""
    resolved_date = as_of_date or date.today()
    plant_sql = "NULL" if plant is None else _sql_literal(plant)
    material_sql = _sql_literal(material)
    query = (
        "SELECT explosion.depth, parent.sap_material_id AS parent_material, "
        "child.sap_material_id AS component_material, child.description, "
        "explosion.item_number, explosion.direct_quantity, "
        "explosion.cumulative_quantity, explosion.unit, "
        "explosion.material_path, explosion.cycle_detected "
        "FROM core.material AS root "
        "CROSS JOIN LATERAL core.explode_bom("
        f"root.material_id, DATE '{resolved_date.isoformat()}', {plant_sql}"
        ") AS explosion "
        "JOIN core.material AS parent ON parent.material_id = explosion.parent_material_id "
        "JOIN core.material AS child ON child.material_id = explosion.component_material_id "
        f"WHERE root.sap_material_id = {material_sql} "
        "ORDER BY explosion.depth, explosion.material_path"
    )
    return run_psql(f"COPY ({query}) TO STDOUT WITH (FORMAT CSV, HEADER TRUE);")


def main() -> None:
    """Run the SAP BOM analytics CLI."""
    args = _parser().parse_args()
    configure_logging(args.log_level)

    if args.command == "ingest":
        result = ingest_sap_csv(args.table, args.path)
        print(json.dumps({
            "ingestion_run_id": result.ingestion_run_id,
            "table": result.table,
            "source_file": result.source_file,
            "row_count": result.row_count,
            "quarantine_count": result.quarantine_count,
            "source_format": result.source_format,
            "skipped": result.skipped,
        }, sort_keys=True))
        return

    if args.command == "reconcile":
        _run_reconciliation(args.skip_classification)
        print("reconciliation completed")
        return

    if args.command == "explode":
        print(_explode(args.material, args.as_of_date, args.plant), end="")
        return

    if args.command == "quality":
        dataset = "quality" if args.details else "quality-scorecard"
        print(dataset_csv(dataset), end="")
        return

    if args.command == "summary":
        print(dataset_csv(args.dataset), end="")
        return

    if args.command == "export":
        output = export_dataset(args.dataset, args.output, args.format)
        print(output)
        return

    raise RuntimeError(f"Unhandled command: {args.command}")


if __name__ == "__main__":
    main()
