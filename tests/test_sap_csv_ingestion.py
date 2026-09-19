"""Tests for SAP CSV parsing and preservation of raw source rows."""

from __future__ import annotations

import csv
import io
import json
from pathlib import Path

import pytest

from sap_bom_analytics.sap.contracts import SAP_CONTRACTS
from sap_bom_analytics.sap.csv_ingestion import prepare_sap_csv


def test_extra_sap_fields_are_preserved_in_raw_payload(tmp_path: Path) -> None:
    """Fields outside the promoted contract must survive in raw JSON."""
    path = tmp_path / "mara.csv"
    path.write_text(
        "MATNR,MTART,ZZ_CUSTOM\nPKG-1,VERP,legacy-value\n",
        encoding="utf-8",
    )

    prepared = prepare_sap_csv(path, SAP_CONTRACTS["mara"], 17)
    rows = list(csv.DictReader(io.StringIO(prepared.csv_text)))

    assert prepared.row_count == 1
    assert rows[0]["matnr"] == "PKG-1"
    payload = json.loads(rows[0]["raw_payload"])
    assert payload["zz_custom"] == "legacy-value"


def test_empty_required_key_is_rejected(tmp_path: Path) -> None:
    """Rows missing required SAP keys should fail with source row context."""
    path = tmp_path / "mara.csv"
    path.write_text("MATNR,MTART\n,VERP\n", encoding="utf-8")

    with pytest.raises(ValueError, match=r"row 2.*matnr"):
        prepare_sap_csv(path, SAP_CONTRACTS["mara"], 1)


def test_empty_extract_is_rejected(tmp_path: Path) -> None:
    """Header-only extracts should not create successful ingestion runs."""
    path = tmp_path / "mara.csv"
    path.write_text("MATNR,MTART\n", encoding="utf-8")

    with pytest.raises(ValueError, match="contains no data rows"):
        prepare_sap_csv(path, SAP_CONTRACTS["mara"], 1)
