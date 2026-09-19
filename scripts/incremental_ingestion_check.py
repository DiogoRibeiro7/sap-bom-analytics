"""Verify content-addressed SAP ingestion skips unchanged extracts."""

from __future__ import annotations

from pathlib import Path

from sap_bom_analytics.db import repository_root, run_psql
from sap_bom_analytics.sap.loader import ingest_sap_csv


def _count_raw_rows(table: str) -> int:
    """Return the row count for one trusted raw table name."""
    allowed = {"mara", "makt", "mast", "stko", "stpo", "marm", "t001w"}
    if table not in allowed:
        raise ValueError(f"Unsupported raw table: {table}")
    value = run_psql(f"SELECT COUNT(*) FROM raw.{table};", tuples_only=True).strip()
    return int(value)


def main() -> None:
    """Ingest the same MARA extract twice and verify the second pass is skipped."""
    path: Path = repository_root() / "examples" / "sap" / "mara.csv"
    before = _count_raw_rows("mara")

    first = ingest_sap_csv("mara", path)
    after_first = _count_raw_rows("mara")
    second = ingest_sap_csv("mara", path)
    after_second = _count_raw_rows("mara")

    if first.skipped:
        if after_first != before:
            raise RuntimeError("Skipped ingestion unexpectedly changed raw row count")
    elif after_first <= before:
        raise RuntimeError("First ingestion did not add raw rows")

    if not second.skipped:
        raise RuntimeError("Expected unchanged second ingestion to be skipped")
    if second.ingestion_run_id != first.ingestion_run_id:
        raise RuntimeError("Skipped ingestion should reuse the successful ingestion run")
    if after_second != after_first:
        raise RuntimeError("Skipped ingestion duplicated raw rows")

    print(
        "incremental ingestion passed: "
        f"run={second.ingestion_run_id}, rows={after_second}, skipped={second.skipped}"
    )


if __name__ == "__main__":
    main()
