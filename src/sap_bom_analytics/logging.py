"""Structured JSON logging for command-line and pipeline operations."""

from __future__ import annotations

import json
import logging
import sys
from datetime import UTC, datetime
from typing import Final

_STANDARD_FIELDS: Final[frozenset[str]] = frozenset({
    "name", "msg", "args", "levelname", "levelno", "pathname", "filename",
    "module", "exc_info", "exc_text", "stack_info", "lineno", "funcName",
    "created", "msecs", "relativeCreated", "thread", "threadName",
    "processName", "process", "taskName",
})


class JsonFormatter(logging.Formatter):
    """Render log records as one JSON object per line."""

    def format(self, record: logging.LogRecord) -> str:
        """Serialize a log record while preserving structured extras."""
        payload: dict[str, object] = {
            "timestamp": datetime.fromtimestamp(record.created, tz=UTC).isoformat(),
            "level": record.levelname.lower(),
            "logger": record.name,
            "message": record.getMessage(),
        }
        for key, value in record.__dict__.items():
            if key.startswith("_") or key in _STANDARD_FIELDS:
                continue
            payload[key] = value

        if record.exc_info is not None:
            payload["exception"] = self.formatException(record.exc_info)

        return json.dumps(payload, ensure_ascii=False, sort_keys=True, default=str)


def configure_logging(level: str = "INFO") -> None:
    """Configure application logging to stderr using JSON lines."""
    if not isinstance(level, str):
        raise TypeError("level must be a string")
    normalized = level.strip().upper()
    numeric_level = logging.getLevelNamesMapping().get(normalized)
    if not isinstance(numeric_level, int):
        raise ValueError(f"Unknown logging level: {level}")

    root = logging.getLogger()
    root.handlers.clear()
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(JsonFormatter())
    root.addHandler(handler)
    root.setLevel(numeric_level)
