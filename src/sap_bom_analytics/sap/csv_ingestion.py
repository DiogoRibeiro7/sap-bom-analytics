"""Parse SAP exports into valid and quarantined PostgreSQL COPY payloads."""

from __future__ import annotations

import csv
import io
import json
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from sap_bom_analytics.sap.contracts import SapExtractContract
from sap_bom_analytics.sap.export_adapter import read_sap_export


@dataclass(frozen=True, slots=True)
class PreparedSapExtract:
    """Validated SAP extract prepared for bulk insertion."""

    table: str
    columns: tuple[str, ...]
    csv_text: str
    row_count: int
    quarantine_columns: tuple[str, ...]
    quarantine_csv_text: str
    quarantine_count: int
    format_name: str


def prepare_sap_csv(
    path: Path,
    contract: SapExtractContract,
    ingestion_run_id: int,
) -> PreparedSapExtract:
    """Validate a SAP export and prepare valid/quarantine COPY payloads."""
    if not isinstance(path, Path):
        raise TypeError("path must be a pathlib.Path")
    if not isinstance(contract, SapExtractContract):
        raise TypeError("contract must be a SapExtractContract")
    if not isinstance(ingestion_run_id, int) or isinstance(ingestion_run_id, bool):
        raise TypeError("ingestion_run_id must be an int")
    if ingestion_run_id <= 0:
        raise ValueError("ingestion_run_id must be positive")

    export = read_sap_export(path)
    normalized_headers = contract.validate_headers(export.headers)
    header_map = dict(zip(export.headers, normalized_headers, strict=True))

    copy_columns = (
        "ingestion_run_id",
        "source_file",
        "source_row_number",
        *contract.selected_columns,
        "raw_payload",
    )
    valid_output = io.StringIO(newline="")
    valid_writer = csv.DictWriter(
        valid_output,
        fieldnames=copy_columns,
        lineterminator="\n",
    )
    valid_writer.writeheader()

    quarantine_columns = (
        "ingestion_run_id",
        "source_entity",
        "source_file",
        "source_row_number",
        "reason_code",
        "reason_detail",
        "raw_payload",
    )
    quarantine_output = io.StringIO(newline="")
    quarantine_writer = csv.DictWriter(
        quarantine_output,
        fieldnames=quarantine_columns,
        lineterminator="\n",
    )
    quarantine_writer.writeheader()

    row_count = 0
    quarantine_count = 0

    for source_row_number, source_row in export.rows:
        normalized_row = _normalize_row(source_row, header_map)
        if not any(value for value in normalized_row.values()):
            continue

        missing = _missing_required_values(contract, normalized_row)
        if missing:
            quarantine_writer.writerow(
                {
                    "ingestion_run_id": ingestion_run_id,
                    "source_entity": contract.name.lower(),
                    "source_file": path.name,
                    "source_row_number": source_row_number,
                    "reason_code": "missing_required_value",
                    "reason_detail": ", ".join(missing),
                    "raw_payload": json.dumps(
                        normalized_row,
                        ensure_ascii=False,
                        sort_keys=True,
                        separators=(",", ":"),
                    ),
                }
            )
            quarantine_count += 1
            continue

        output_row: dict[str, object] = {
            "ingestion_run_id": ingestion_run_id,
            "source_file": path.name,
            "source_row_number": source_row_number,
            "raw_payload": json.dumps(
                normalized_row,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ),
        }
        for column in contract.selected_columns:
            output_row[column] = normalized_row.get(column, "")
        valid_writer.writerow(output_row)
        row_count += 1

    if row_count == 0 and quarantine_count == 0:
        raise ValueError(f"{contract.name}: export contains no data rows")

    return PreparedSapExtract(
        table=contract.target_table,
        columns=copy_columns,
        csv_text=valid_output.getvalue(),
        row_count=row_count,
        quarantine_columns=quarantine_columns,
        quarantine_csv_text=quarantine_output.getvalue(),
        quarantine_count=quarantine_count,
        format_name=export.format_name,
    )


def _normalize_row(
    row: Mapping[str, str],
    header_map: Mapping[str, str],
) -> dict[str, str]:
    """Normalize one source row while retaining all named input fields."""
    result: dict[str, str] = {}
    for source_header, normalized_header in header_map.items():
        value = row.get(source_header)
        result[normalized_header] = "" if value is None else value.strip()
    return result


def _missing_required_values(
    contract: SapExtractContract,
    row: Mapping[str, str],
) -> tuple[str, ...]:
    """Return required SAP fields missing from a row."""
    return tuple(column for column in contract.required_columns if not row.get(column))
