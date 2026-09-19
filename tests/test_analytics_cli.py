"""Tests for analytics dataset and CLI helpers."""

from __future__ import annotations

from pathlib import Path

import pytest

from sap_bom_analytics.analytics import ANALYTICS_DATASETS, dataset_query
from sap_bom_analytics.cli import _sql_literal


def test_named_datasets_are_select_only() -> None:
    """Export datasets should remain fixed SELECT statements."""
    assert ANALYTICS_DATASETS
    for query in ANALYTICS_DATASETS.values():
        assert query.lstrip().upper().startswith("SELECT ")
        assert ";" not in query


def test_unknown_dataset_is_rejected() -> None:
    """Unknown export names must fail rather than becoming arbitrary SQL."""
    with pytest.raises(ValueError, match="Unknown dataset"):
        dataset_query("drop-everything")


def test_sql_literal_escapes_quotes() -> None:
    """User-supplied identifiers used as values must be SQL escaped."""
    assert _sql_literal("O'Brien") == "'O''Brien'"


def test_path_type_check_is_explicit() -> None:
    """Keep static path expectations visible for downstream exporters."""
    path = Path("report.csv")
    assert isinstance(path, Path)
