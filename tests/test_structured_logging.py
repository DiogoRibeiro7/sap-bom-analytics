"""Tests for structured JSON logging."""

from __future__ import annotations

import json
import logging

from sap_bom_analytics.logging import JsonFormatter


def test_json_formatter_preserves_structured_fields() -> None:
    """Extra log fields should survive as machine-readable JSON."""
    record = logging.LogRecord(
        name="sap_bom_analytics.test",
        level=logging.INFO,
        pathname=__file__,
        lineno=12,
        msg="stage completed",
        args=(),
        exc_info=None,
    )
    record.event = "stage_completed"
    record.processing_run_id = 42

    payload = json.loads(JsonFormatter().format(record))

    assert payload["level"] == "info"
    assert payload["message"] == "stage completed"
    assert payload["event"] == "stage_completed"
    assert payload["processing_run_id"] == 42
