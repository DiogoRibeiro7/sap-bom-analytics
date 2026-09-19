"""Load one SAP CSV extract into its raw PostgreSQL table."""

from __future__ import annotations

import argparse
import hashlib
import os
import subprocess
from pathlib import Path

from sap_bom_analytics.sap.contracts import SAP_CONTRACTS
from sap_bom_analytics.sap.csv_ingestion import prepare_sap_csv


def _parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Validate and ingest one SAP CSV extract into the raw schema."
    )
    parser.add_argument("table", choices=sorted(SAP_CONTRACTS))
    parser.add_argument("path", type=Path)
    return parser.parse_args()


def _db_user() -> str:
    """Return the configured PostgreSQL user."""
    return os.environ.get("POSTGRES_USER", "sap_bom")


def _db_name() -> str:
    """Return the configured PostgreSQL database name."""
    return os.environ.get("POSTGRES_DB", "sap_bom")


def _run_psql(sql: str, *, stdin: str | None = None) -> str:
    """Execute SQL through psql in the Compose database service."""
    command = [
        "docker", "compose", "exec", "-T", "db", "psql",
        "-X", "-v", "ON_ERROR_STOP=1", "-A", "-t",
        "-U", _db_user(), "-d", _db_name(),
    ]
    process = subprocess.run(
        command, input=stdin if stdin is not None else sql,
        capture_output=True, check=False, text=True,
    )
    if process.returncode != 0:
        detail = process.stderr.strip() or process.stdout.strip()
        raise RuntimeError(f"psql failed with exit code {process.returncode}: {detail}")
    return process.stdout.strip()


def _create_ingestion_run(path: Path) -> int:
    """Create and return an audit ingestion run for one source file."""
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    source_reference = str(path.resolve()).replace("'", "''")
    sql = (
        "INSERT INTO audit.ingestion_run "
        "(source_system, source_reference, source_sha256, status) VALUES "
        f"('SAP_CSV', '{source_reference}', '{digest}', 'running') "
        "RETURNING ingestion_run_id;"
    )
    value = _run_psql(sql)
    if not value:
        raise RuntimeError("Failed to create ingestion run")
    return int(value.splitlines()[-1])


def _mark_run(ingestion_run_id: int, status: str) -> None:
    """Mark an ingestion run as succeeded or failed."""
    if status not in {"succeeded", "failed"}:
        raise ValueError("status must be succeeded or failed")
    _run_psql(
        "UPDATE audit.ingestion_run "
        f"SET status = '{status}', completed_at = CURRENT_TIMESTAMP "
        f"WHERE ingestion_run_id = {ingestion_run_id};"
    )


def _copy_prepared(table: str, columns: tuple[str, ...], csv_text: str) -> None:
    """Bulk copy prepared CSV text into a raw SAP table."""
    column_list = ", ".join(columns)
    copy_sql = f"COPY {table} ({column_list}) FROM STDIN WITH (FORMAT CSV, HEADER TRUE);\n"
    _run_psql("", stdin=copy_sql + csv_text)


def main() -> None:
    """Validate and ingest one SAP extract."""
    args = _parse_args()
    path: Path = args.path
    contract = SAP_CONTRACTS[args.table]
    ingestion_run_id = _create_ingestion_run(path)

    try:
        prepared = prepare_sap_csv(path, contract, ingestion_run_id)
        _copy_prepared(prepared.table, prepared.columns, prepared.csv_text)
    except Exception:
        _mark_run(ingestion_run_id, "failed")
        raise

    _mark_run(ingestion_run_id, "succeeded")
    print(
        f"ingested {prepared.row_count} rows from {path.name} "
        f"into {prepared.table} (run={ingestion_run_id})"
    )


if __name__ == "__main__":
    main()
