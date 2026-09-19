"""Load validated SAP CSV extracts into the raw database layer."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path

from sap_bom_analytics.db import run_psql
from sap_bom_analytics.sap.contracts import SAP_CONTRACTS
from sap_bom_analytics.sap.csv_ingestion import prepare_sap_csv


@dataclass(frozen=True, slots=True)
class SapIngestionResult:
    """Result of one SAP CSV ingestion operation."""

    ingestion_run_id: int
    table: str
    source_file: str
    row_count: int
    quarantine_count: int = 0
    source_format: str | None = None
    skipped: bool = False


def _sql_literal(value: str) -> str:
    """Return a PostgreSQL single-quoted text literal."""
    if not isinstance(value, str):
        raise TypeError("value must be a string")
    return "'" + value.replace("'", "''") + "'"


def _find_existing_ingestion(table: str, digest: str) -> int | None:
    """Return a successful ingestion run for the same entity and content hash."""
    table_literal = _sql_literal(table)
    digest_literal = _sql_literal(digest)
    output = run_psql(
        "SELECT ingestion_run_id FROM audit.ingestion_run "
        "WHERE source_system = 'SAP_CSV' "
        f"AND source_entity = {table_literal} "
        f"AND source_sha256 = {digest_literal} "
        "AND status = 'succeeded' "
        "ORDER BY ingestion_run_id DESC LIMIT 1;",
        tuples_only=True,
    ).strip()
    return int(output) if output else None


def _create_ingestion_run(table: str, path: Path, digest: str) -> int:
    """Create an audit record and return its identifier."""
    source_reference = str(path.resolve())
    output = run_psql(
        "WITH inserted AS ("
        "INSERT INTO audit.ingestion_run "
        "(source_system, source_entity, source_reference, source_sha256, status) VALUES ("
        f"'SAP_CSV', {_sql_literal(table)}, {_sql_literal(source_reference)}, "
        f"'{digest}', 'running') "
        "RETURNING ingestion_run_id"
        ") SELECT ingestion_run_id FROM inserted;",
        tuples_only=True,
    ).strip()
    if not output:
        raise RuntimeError("Failed to create ingestion run")
    return int(output.splitlines()[-1])


def _mark_ingestion_run(ingestion_run_id: int, status: str) -> None:
    """Finalize an ingestion audit record."""
    if not isinstance(ingestion_run_id, int) or isinstance(ingestion_run_id, bool):
        raise TypeError("ingestion_run_id must be an int")
    if status not in {"succeeded", "failed"}:
        raise ValueError("status must be succeeded or failed")
    run_psql(
        "UPDATE audit.ingestion_run "
        f"SET status = '{status}', completed_at = CURRENT_TIMESTAMP "
        f"WHERE ingestion_run_id = {ingestion_run_id};"
    )


def ingest_sap_csv(table: str, path: Path) -> SapIngestionResult:
    """Validate and ingest one supported SAP CSV extract.

    Args:
        table: Supported SAP table key such as ``mara`` or ``stpo``.
        path: CSV file to ingest.

    Returns:
        Structured ingestion metadata.
    """
    if not isinstance(table, str):
        raise TypeError("table must be a string")
    if not isinstance(path, Path):
        raise TypeError("path must be a pathlib.Path")
    table_key = table.strip().lower()
    if table_key not in SAP_CONTRACTS:
        supported = ", ".join(sorted(SAP_CONTRACTS))
        raise ValueError(f"Unsupported SAP table {table!r}; expected one of: {supported}")
    if not path.is_file():
        raise FileNotFoundError(path)

    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    existing_run_id = _find_existing_ingestion(table_key, digest)
    contract = SAP_CONTRACTS[table_key]
    if existing_run_id is not None:
        return SapIngestionResult(
            ingestion_run_id=existing_run_id,
            table=contract.target_table,
            source_file=path.name,
            row_count=0,
            quarantine_count=0,
            source_format=None,
            skipped=True,
        )

    ingestion_run_id = _create_ingestion_run(table_key, path, digest)
    try:
        prepared = prepare_sap_csv(path, contract, ingestion_run_id)
        columns = ", ".join(prepared.columns)
        copy_sql = (
            f"COPY {prepared.table} ({columns}) "
            "FROM STDIN WITH (FORMAT CSV, HEADER TRUE);\n"
            + prepared.csv_text
        )
        if prepared.row_count > 0:
            run_psql(copy_sql)

        if prepared.quarantine_count > 0:
            quarantine_columns = ", ".join(prepared.quarantine_columns)
            quarantine_sql = (
                f"COPY raw.quarantine ({quarantine_columns}) "
                "FROM STDIN WITH (FORMAT CSV, HEADER TRUE);\n"
                + prepared.quarantine_csv_text
            )
            run_psql(quarantine_sql)
    except Exception:
        _mark_ingestion_run(ingestion_run_id, "failed")
        raise

    _mark_ingestion_run(ingestion_run_id, "succeeded")
    return SapIngestionResult(
        ingestion_run_id=ingestion_run_id,
        table=prepared.table,
        source_file=path.name,
        row_count=prepared.row_count,
        quarantine_count=prepared.quarantine_count,
        source_format=prepared.format_name,
        skipped=False,
    )
