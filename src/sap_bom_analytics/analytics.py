"""Named analytics datasets and export helpers."""

from __future__ import annotations

import io
from pathlib import Path
from typing import Final

from sap_bom_analytics.db import run_psql

ANALYTICS_DATASETS: Final[dict[str, str]] = {
    "materials": "SELECT * FROM analytics.material_summary ORDER BY sap_material_id",
    "boms": "SELECT * FROM analytics.bom_summary ORDER BY sap_bom_id, plant",
    "bom-components": (
        "SELECT * FROM analytics.bom_component_detail "
        "ORDER BY sap_bom_id, valid_from, item_number"
    ),
    "ingestion-runs": (
        "SELECT * FROM analytics.ingestion_run_summary ORDER BY ingestion_run_id"
    ),
    "quality": (
        "SELECT * FROM analytics.data_quality_dashboard "
        "ORDER BY observed_at DESC, quality_layer, issue_type"
    ),
    "quality-scorecard": (
        "SELECT * FROM analytics.quality_scorecard "
        "ORDER BY quality_layer, severity, issue_type"
    ),
    "assessments": (
        "SELECT * FROM analytics.product_assessment_summary "
        "ORDER BY assessment_run_id"
    ),
    "processing-runs": (
        "SELECT * FROM analytics.processing_run_metrics "
        "ORDER BY processing_run_id"
    ),
    "processing-summary": (
        "SELECT * FROM analytics.processing_stage_summary "
        "ORDER BY pipeline_name, stage_name"
    ),
}


def dataset_query(dataset: str) -> str:
    """Return the SQL backing a named analytical dataset."""
    if not isinstance(dataset, str):
        raise TypeError("dataset must be a string")
    key = dataset.strip().lower()
    try:
        return ANALYTICS_DATASETS[key]
    except KeyError as exc:
        supported = ", ".join(sorted(ANALYTICS_DATASETS))
        raise ValueError(f"Unknown dataset {dataset!r}; expected one of: {supported}") from exc


def dataset_csv(dataset: str) -> str:
    """Return a named dataset as CSV text."""
    query = dataset_query(dataset)
    return run_psql(f"COPY ({query}) TO STDOUT WITH (FORMAT CSV, HEADER TRUE);")


def export_dataset(dataset: str, output: Path, file_format: str) -> Path:
    """Export a named dataset to CSV or Parquet.

    Args:
        dataset: Dataset key from ``ANALYTICS_DATASETS``.
        output: Destination path.
        file_format: ``csv`` or ``parquet``.

    Returns:
        Resolved output path.
    """
    if not isinstance(output, Path):
        raise TypeError("output must be a pathlib.Path")
    if not isinstance(file_format, str):
        raise TypeError("file_format must be a string")

    normalized_format = file_format.strip().lower()
    if normalized_format not in {"csv", "parquet"}:
        raise ValueError("file_format must be csv or parquet")

    csv_text = dataset_csv(dataset)
    destination = output.expanduser().resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)

    if normalized_format == "csv":
        destination.write_text(csv_text, encoding="utf-8")
        return destination

    import pyarrow.csv as pa_csv
    import pyarrow.parquet as pa_parquet

    table = pa_csv.read_csv(io.BytesIO(csv_text.encode("utf-8")))
    pa_parquet.write_table(table, destination)
    return destination
