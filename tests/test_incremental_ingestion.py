"""Unit tests for incremental-ingestion result semantics."""

from __future__ import annotations

from sap_bom_analytics.sap.loader import SapIngestionResult


def test_ingestion_result_defaults_to_not_skipped() -> None:
    """New ingestion results should represent performed work by default."""
    result = SapIngestionResult(
        ingestion_run_id=7,
        table="raw.mara",
        source_file="mara.csv",
        row_count=4,
    )
    assert result.skipped is False


def test_skipped_ingestion_can_report_zero_new_rows() -> None:
    """Skipped results should explicitly expose that no new rows were inserted."""
    result = SapIngestionResult(
        ingestion_run_id=7,
        table="raw.mara",
        source_file="mara.csv",
        row_count=0,
        skipped=True,
    )
    assert result.skipped is True
    assert result.row_count == 0
