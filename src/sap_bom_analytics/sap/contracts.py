"""Contracts for SAP CSV extracts used by the BOM analytics pipeline."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Final, Sequence


@dataclass(frozen=True, slots=True)
class SapExtractContract:
    """Describe the supported fields for one SAP extract.

    Required fields must be present in the input CSV. Optional fields may be
    omitted. Additional fields are accepted and preserved in ``raw_payload``.
    """

    name: str
    target_table: str
    required_columns: tuple[str, ...]
    optional_columns: tuple[str, ...] = ()

    @property
    def selected_columns(self) -> tuple[str, ...]:
        """Return fields promoted to dedicated raw-table columns."""
        return self.required_columns + self.optional_columns

    def validate_headers(self, headers: Sequence[str]) -> tuple[str, ...]:
        """Validate and normalize CSV headers.

        Args:
            headers: Header names read from the CSV file.

        Returns:
            Normalized lower-case header names.

        Raises:
            ValueError: If headers are empty, duplicated, or required fields are missing.
        """
        if not headers:
            raise ValueError(f"{self.name}: CSV has no header")

        normalized = tuple(header.strip().lower() for header in headers)
        if any(not header for header in normalized):
            raise ValueError(f"{self.name}: CSV contains an empty column name")
        if len(set(normalized)) != len(normalized):
            raise ValueError(f"{self.name}: CSV contains duplicate column names")

        missing = tuple(
            column for column in self.required_columns if column not in normalized
        )
        if missing:
            missing_text = ", ".join(missing)
            raise ValueError(f"{self.name}: missing required columns: {missing_text}")
        return normalized


SAP_CONTRACTS: Final[dict[str, SapExtractContract]] = {
    "mara": SapExtractContract(
        name="MARA",
        target_table="raw.mara",
        required_columns=("matnr",),
        optional_columns=("mtart", "matkl", "meins", "brgew", "ntgew", "gewei"),
    ),
    "makt": SapExtractContract(
        name="MAKT",
        target_table="raw.makt",
        required_columns=("matnr", "spras"),
        optional_columns=("maktx", "maktg"),
    ),
    "mast": SapExtractContract(
        name="MAST",
        target_table="raw.mast",
        required_columns=("matnr", "werks", "stlan", "stlnr"),
        optional_columns=("stlal",),
    ),
    "stko": SapExtractContract(
        name="STKO",
        target_table="raw.stko",
        required_columns=("stlty", "stlnr"),
        optional_columns=("stlal", "stkoz", "datuv", "aennr", "bmeng", "bmein"),
    ),
    "stpo": SapExtractContract(
        name="STPO",
        target_table="raw.stpo",
        required_columns=("stlty", "stlnr", "idnrk"),
        optional_columns=(
            "stlkn", "stpoz", "posnr", "menge", "meins", "datuv", "aennr"
        ),
    ),
    "marm": SapExtractContract(
        name="MARM",
        target_table="raw.marm",
        required_columns=("matnr", "meinh"),
        optional_columns=("umrez", "umren", "ean11"),
    ),
    "t001w": SapExtractContract(
        name="T001W",
        target_table="raw.t001w",
        required_columns=("werks",),
        optional_columns=("name1", "bwkey", "land1"),
    ),
}
