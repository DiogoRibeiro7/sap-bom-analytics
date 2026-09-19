"""Parse SAP CSV extracts into rows suitable for PostgreSQL COPY."""

from __future__ import annotations

import csv
import io
import json
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from sap_bom_analytics.sap.contracts import SapExtractContract


@dataclass(frozen=True, slots=True)
class PreparedSapExtract:
    """Validated SAP extract prepared for bulk insertion."""

    table: str
    columns: tuple[str, ...]
    csv_text: str
    row_count: int


def prepare_sap_csv(
    path: Path,
    contract: SapExtractContract,
    ingestion_run_id: int,
) -> PreparedSapExtract:
    """Validate a SAP CSV and prepare a COPY-compatible CSV payload.

    Args:
        path: CSV extract to parse.
        contract: SAP table contract defining promoted fields.
        ingestion_run_id: Audit run owning the imported rows.

    Returns:
        A normalized CSV payload including lineage and the original row as JSON.

    Raises:
        FileNotFoundError: If ``path`` does not exist.
        TypeError: If argument types are invalid.
        ValueError: If the extract violates its contract.
    """
    if not isinstance(path, Path):
        raise TypeError("path must be a pathlib.Path")
    if not isinstance(contract, SapExtractContract):
        raise TypeError("contract must be a SapExtractContract")
    if not isinstance(ingestion_run_id, int) or isinstance(ingestion_run_id, bool):
        raise TypeError("ingestion_run_id must be an int")
    if ingestion_run_id <= 0:
        raise ValueError("ingestion_run_id must be positive")
    if not path.is_file():
        raise FileNotFoundError(path)

    output = io.StringIO(newline="")
    copy_columns = (
        "ingestion_run_id",
        "source_file",
        "source_row_number",
        *contract.selected_columns,
        "raw_payload",
    )
    writer = csv.DictWriter(output, fieldnames=copy_columns, lineterminator="\n")
    writer.writeheader()

    row_count = 0
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"{contract.name}: CSV has no header")
        normalized_headers = contract.validate_headers(reader.fieldnames)
        header_map = dict(zip(reader.fieldnames, normalized_headers, strict=True))

        for source_row_number, row in enumerate(reader, start=2):
            normalized_row = _normalize_row(row, header_map)
            if not any(value for value in normalized_row.values()):
                continue

            _validate_required_values(contract, normalized_row, source_row_number)
            output_row: dict[str, object] = {
                "ingestion_run_id": ingestion_run_id,
                "source_file": path.name,
                "source_row_number": source_row_number,
                "raw_payload": json.dumps(
                    normalized_row, ensure_ascii=False, sort_keys=True, separators=(",", ":")
                ),
            }
            for column in contract.selected_columns:
                output_row[column] = normalized_row.get(column, "")
            writer.writerow(output_row)
            row_count += 1

    if row_count == 0:
        raise ValueError(f"{contract.name}: CSV contains no data rows")

    return PreparedSapExtract(
        table=contract.target_table,
        columns=copy_columns,
        csv_text=output.getvalue(),
        row_count=row_count,
    )


def _normalize_row(
    row: Mapping[str | None, str | None],
    header_map: Mapping[str, str],
) -> dict[str, str]:
    """Normalize one CSV row while retaining all named input fields."""
    result: dict[str, str] = {}
    for source_header, normalized_header in header_map.items():
        value = row.get(source_header)
        result[normalized_header] = "" if value is None else value.strip()
    return result


def _validate_required_values(
    contract: SapExtractContract,
    row: Mapping[str, str],
    source_row_number: int,
) -> None:
    """Reject rows where a required SAP key field is empty."""
    missing = tuple(column for column in contract.required_columns if not row.get(column))
    if missing:
        missing_text = ", ".join(missing)
        raise ValueError(
            f"{contract.name}: row {source_row_number} has empty required values: "
            f"{missing_text}"
        )
