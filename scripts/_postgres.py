"""Helpers for executing SQL against the local PostgreSQL container."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Final

_REPOSITORY_ROOT: Final[Path] = Path(__file__).resolve().parents[1]


def _database_name() -> str:
    """Return the configured development database name."""
    return os.environ.get("POSTGRES_DB", "sap_bom")


def _database_user() -> str:
    """Return the configured development database user."""
    return os.environ.get("POSTGRES_USER", "sap_bom")


def run_psql(sql: str, *, tuples_only: bool = False) -> str:
    """Execute SQL through psql inside the Docker Compose database service.

    Args:
        sql: SQL text to execute.
        tuples_only: Return unaligned tuple output without headers when True.

    Returns:
        Captured standard output from psql.

    Raises:
        RuntimeError: If Docker Compose or psql returns a non-zero exit status.
    """
    if not isinstance(sql, str) or not sql.strip():
        raise TypeError("sql must be a non-empty string")
    if not isinstance(tuples_only, bool):
        raise TypeError("tuples_only must be a bool")

    command: list[str] = [
        "docker",
        "compose",
        "exec",
        "-T",
        "db",
        "psql",
        "-X",
        "-v",
        "ON_ERROR_STOP=1",
        "-U",
        _database_user(),
        "-d",
        _database_name(),
    ]
    if tuples_only:
        command.extend(["-A", "-t"])

    process = subprocess.run(
        command,
        cwd=_REPOSITORY_ROOT,
        input=sql,
        capture_output=True,
        check=False,
        text=True,
    )
    if process.returncode != 0:
        detail = process.stderr.strip() or process.stdout.strip()
        raise RuntimeError(f"psql failed with exit code {process.returncode}: {detail}")

    return process.stdout
