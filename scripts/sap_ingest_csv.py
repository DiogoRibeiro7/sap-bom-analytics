"""Compatibility wrapper for SAP CSV ingestion."""

from __future__ import annotations

import argparse
from pathlib import Path

from sap_bom_analytics.sap.contracts import SAP_CONTRACTS
from sap_bom_analytics.sap.loader import ingest_sap_csv


def _parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Validate and ingest one SAP CSV extract into the raw schema."
    )
    parser.add_argument("table", choices=sorted(SAP_CONTRACTS))
    parser.add_argument("path", type=Path)
    return parser.parse_args()


def main() -> None:
    """Ingest one SAP extract through the package-level loader."""
    args = _parse_args()
    result = ingest_sap_csv(args.table, args.path)
    print(
        f"ingested {result.row_count} rows from {result.source_file} "
        f"into {result.table} (run={result.ingestion_run_id})"
    )


if __name__ == "__main__":
    main()
