"""Database helpers for the local Docker Compose PostgreSQL service."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Final

_PACKAGE_REPOSITORY_ROOT: Final[Path] = Path(__file__).resolve().parents[2]


def repository_root() -> Path:
    """Return the repository root used for Docker Compose commands."""
    configured = os.environ.get("SAP_BOM_REPOSITORY_ROOT")
    if configured:
        root = Path(configured).expanduser().resolve()
    elif (Path.cwd() / "docker-compose.yml").is_file():
        root = Path.cwd().resolve()
    else:
        root = _PACKAGE_REPOSITORY_ROOT

    if not (root / "docker-compose.yml").is_file():
        raise RuntimeError(
            "Could not locate docker-compose.yml. Run from the repository root or set "
            "SAP_BOM_REPOSITORY_ROOT."
        )
    return root


def database_name() -> str:
    """Return the configured development database name."""
    return os.environ.get("POSTGRES_DB", "sap_bom")


def database_user() -> str:
    """Return the configured development database user."""
    return os.environ.get("POSTGRES_USER", "sap_bom")


def run_psql(sql: str, *, tuples_only: bool = False) -> str:
    """Execute SQL through psql inside the Docker Compose database service.

    Args:
        sql: SQL text, including COPY data when required.
        tuples_only: Request unaligned tuple output without headers.

    Returns:
        Captured stdout.

    Raises:
        TypeError: If arguments have invalid types.
        RuntimeError: If Docker Compose or psql fails.
    """
    if not isinstance(sql, str) or not sql.strip():
        raise TypeError("sql must be a non-empty string")
    if not isinstance(tuples_only, bool):
        raise TypeError("tuples_only must be a bool")

    command: list[str] = [
        "docker", "compose", "exec", "-T", "db", "psql",
        "-X", "-v", "ON_ERROR_STOP=1",
        "-U", database_user(), "-d", database_name(),
    ]
    if tuples_only:
        command.extend(["-A", "-t"])

    process = subprocess.run(
        command,
        cwd=repository_root(),
        input=sql,
        capture_output=True,
        check=False,
        text=True,
    )
    if process.returncode != 0:
        detail = process.stderr.strip() or process.stdout.strip()
        raise RuntimeError(f"psql failed with exit code {process.returncode}: {detail}")
    return process.stdout


def execute_sql_file(path: Path) -> None:
    """Execute a UTF-8 SQL file against the local database."""
    if not isinstance(path, Path):
        raise TypeError("path must be a pathlib.Path")
    if not path.is_file():
        raise FileNotFoundError(path)
    if path.suffix.lower() != ".sql":
        raise ValueError(f"Expected a .sql file: {path}")
    run_psql(path.read_text(encoding="utf-8"))
