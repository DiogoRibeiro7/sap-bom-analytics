"""Tests for SAP export parsing, quarantine, and raw-payload preservation."""

from __future__ import annotations

import csv
import io
import json
from pathlib import Path

import pytest
from openpyxl import Workbook

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
    assert prepared.quarantine_count == 0
    assert rows[0]["matnr"] == "PKG-1"
    payload = json.loads(rows[0]["raw_payload"])
    assert payload["zz_custom"] == "legacy-value"


def test_empty_required_key_is_quarantined(tmp_path: Path) -> None:
    """Rows missing required SAP keys should be quarantined, not abort the file."""
    path = tmp_path / "mara.csv"
    path.write_text(
        "MATNR,MTART\nPKG-1,VERP\n,VERP\nPKG-2,VERP\n",
        encoding="utf-8",
    )

    prepared = prepare_sap_csv(path, SAP_CONTRACTS["mara"], 1)
    valid_rows = list(csv.DictReader(io.StringIO(prepared.csv_text)))
    quarantine_rows = list(csv.DictReader(io.StringIO(prepared.quarantine_csv_text)))

    assert prepared.row_count == 2
    assert prepared.quarantine_count == 1
    assert [row["matnr"] for row in valid_rows] == ["PKG-1", "PKG-2"]
    assert quarantine_rows[0]["source_row_number"] == "3"
    assert quarantine_rows[0]["reason_code"] == "missing_required_value"
    assert quarantine_rows[0]["reason_detail"] == "matnr"


def test_all_invalid_rows_are_quarantined(tmp_path: Path) -> None:
    """An extract may complete with only quarantined data rows."""
    path = tmp_path / "mara.csv"
    path.write_text("MATNR,MTART\n,VERP\n", encoding="utf-8")

    prepared = prepare_sap_csv(path, SAP_CONTRACTS["mara"], 1)

    assert prepared.row_count == 0
    assert prepared.quarantine_count == 1


def test_empty_extract_is_rejected(tmp_path: Path) -> None:
    """Header-only extracts still fail because there is no row-level evidence."""
    path = tmp_path / "mara.csv"
    path.write_text("MATNR,MTART\n", encoding="utf-8")

    with pytest.raises(ValueError, match="contains no data rows"):
        prepare_sap_csv(path, SAP_CONTRACTS["mara"], 1)


def test_semicolon_export_is_auto_detected(tmp_path: Path) -> None:
    """Semicolon-delimited SAP exports should use the same contracts."""
    path = tmp_path / "mara.txt"
    path.write_text("MATNR;MTART\nPKG-1;VERP\n", encoding="utf-8")

    prepared = prepare_sap_csv(path, SAP_CONTRACTS["mara"], 1)

    assert prepared.row_count == 1
    assert prepared.format_name == "text:';'"


def test_tsv_export_is_supported(tmp_path: Path) -> None:
    """TSV exports should be recognized from their suffix."""
    path = tmp_path / "mara.tsv"
    path.write_text("MATNR\tMTART\nPKG-1\tVERP\n", encoding="utf-8")

    prepared = prepare_sap_csv(path, SAP_CONTRACTS["mara"], 1)

    assert prepared.row_count == 1
    assert prepared.format_name == "text:'\\t'"


def test_xlsx_export_is_supported(tmp_path: Path) -> None:
    """XLSX worksheets should normalize into the same ingestion payload."""
    path = tmp_path / "mara.xlsx"
    workbook = Workbook()
    worksheet = workbook.active
    worksheet.append(["MATNR", "MTART", "ZZ_CUSTOM"])
    worksheet.append(["PKG-1", "VERP", "xlsx-value"])
    workbook.save(path)
    workbook.close()

    prepared = prepare_sap_csv(path, SAP_CONTRACTS["mara"], 1)
    rows = list(csv.DictReader(io.StringIO(prepared.csv_text)))

    assert prepared.row_count == 1
    assert prepared.format_name == "xlsx"
    assert json.loads(rows[0]["raw_payload"])["zz_custom"] == "xlsx-value"
