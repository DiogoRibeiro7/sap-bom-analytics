"""Tests for SAP extract contracts."""

from __future__ import annotations

import pytest

from sap_bom_analytics.sap.contracts import SAP_CONTRACTS


def test_mara_headers_are_case_insensitive() -> None:
    """Contract validation should normalize SAP-style uppercase headers."""
    headers = SAP_CONTRACTS["mara"].validate_headers(["MATNR", "MTART"])
    assert headers == ("matnr", "mtart")


def test_missing_required_header_is_rejected() -> None:
    """Missing SAP keys should fail before row ingestion."""
    with pytest.raises(ValueError, match="missing required columns: matnr"):
        SAP_CONTRACTS["mara"].validate_headers(["MTART", "MEINS"])


def test_duplicate_headers_after_normalization_are_rejected() -> None:
    """Case-only duplicate headers should not be accepted."""
    with pytest.raises(ValueError, match="duplicate column names"):
        SAP_CONTRACTS["mara"].validate_headers(["MATNR", "matnr"])
