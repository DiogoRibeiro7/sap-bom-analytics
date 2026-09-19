"""Database-backed operational run tracking."""

from __future__ import annotations

import json
import logging
from collections.abc import Iterator, Mapping
from contextlib import contextmanager

from sap_bom_analytics.db import run_psql

_LOGGER = logging.getLogger(__name__)


def _sql_literal(value: str) -> str:
    """Return a PostgreSQL text literal."""
    if not isinstance(value, str):
        raise TypeError("value must be a string")
    return "'" + value.replace("'", "''") + "'"


def _json_literal(value: Mapping[str, object]) -> str:
    """Return a PostgreSQL JSONB literal."""
    encoded = json.dumps(dict(value), ensure_ascii=False, sort_keys=True, default=str)
    return _sql_literal(encoded) + "::JSONB"


def start_processing_run(
    pipeline_name: str,
    stage_name: str,
    *,
    metadata: Mapping[str, object] | None = None,
) -> int:
    """Create a running processing record and return its identifier."""
    if not isinstance(pipeline_name, str) or not pipeline_name.strip():
        raise TypeError("pipeline_name must be a non-empty string")
    if not isinstance(stage_name, str) or not stage_name.strip():
        raise TypeError("stage_name must be a non-empty string")
    metadata_value = {} if metadata is None else dict(metadata)
    result = run_psql(
        "INSERT INTO audit.processing_run "
        "(pipeline_name, stage_name, status, metadata) VALUES ("
        f"{_sql_literal(pipeline_name)}, {_sql_literal(stage_name)}, 'running', "
        f"{_json_literal(metadata_value)}) RETURNING processing_run_id;",
        tuples_only=True,
    ).strip()
    if not result:
        raise RuntimeError("Failed to create processing run")
    run_id = int(result.splitlines()[-1])
    _LOGGER.info(
        "processing stage started",
        extra={
            "event": "processing_run_started",
            "processing_run_id": run_id,
            "pipeline": pipeline_name,
            "stage": stage_name,
            "metadata": metadata_value,
        },
    )
    return run_id


def complete_processing_run(
    processing_run_id: int,
    *,
    rows_processed: int | None = None,
) -> None:
    """Mark a processing run as succeeded."""
    if not isinstance(processing_run_id, int) or isinstance(processing_run_id, bool):
        raise TypeError("processing_run_id must be an int")
    if rows_processed is not None:
        if not isinstance(rows_processed, int) or isinstance(rows_processed, bool):
            raise TypeError("rows_processed must be an int or None")
        if rows_processed < 0:
            raise ValueError("rows_processed must be non-negative")
    rows_sql = "NULL" if rows_processed is None else str(rows_processed)
    run_psql(
        "UPDATE audit.processing_run SET status = 'succeeded', "
        "completed_at = CURRENT_TIMESTAMP, "
        f"rows_processed = {rows_sql} WHERE processing_run_id = {processing_run_id};"
    )
    _LOGGER.info(
        "processing stage succeeded",
        extra={
            "event": "processing_run_succeeded",
            "processing_run_id": processing_run_id,
            "rows_processed": rows_processed,
        },
    )


def fail_processing_run(processing_run_id: int, error: BaseException) -> None:
    """Mark a processing run as failed and record the error text."""
    if not isinstance(processing_run_id, int) or isinstance(processing_run_id, bool):
        raise TypeError("processing_run_id must be an int")
    if not isinstance(error, BaseException):
        raise TypeError("error must be an exception")
    message = f"{type(error).__name__}: {error}"
    run_psql(
        "UPDATE audit.processing_run SET status = 'failed', "
        "completed_at = CURRENT_TIMESTAMP, "
        f"error_message = {_sql_literal(message)} "
        f"WHERE processing_run_id = {processing_run_id};"
    )
    _LOGGER.error(
        "processing stage failed",
        extra={
            "event": "processing_run_failed",
            "processing_run_id": processing_run_id,
            "error_type": type(error).__name__,
            "error": str(error),
        },
    )


@contextmanager
def processing_run(
    pipeline_name: str,
    stage_name: str,
    *,
    metadata: Mapping[str, object] | None = None,
) -> Iterator[int]:
    """Track one operational stage across success and failure paths."""
    run_id = start_processing_run(pipeline_name, stage_name, metadata=metadata)
    try:
        yield run_id
    except Exception as error:
        fail_processing_run(run_id, error)
        raise
    else:
        complete_processing_run(run_id)
