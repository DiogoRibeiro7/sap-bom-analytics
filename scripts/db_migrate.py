"""Apply versioned SQL migrations to the local development database."""

from __future__ import annotations

import hashlib
from pathlib import Path

from _postgres import run_psql

_MIGRATIONS_DIR = Path(__file__).resolve().parents[1] / "migrations"


def _checksum(content: str) -> str:
    """Return a SHA-256 checksum for migration content."""
    if not isinstance(content, str):
        raise TypeError("content must be a string")
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def _ensure_migration_table() -> None:
    """Create the migration metadata table when it does not exist."""
    run_psql("""
    CREATE SCHEMA IF NOT EXISTS audit;
    CREATE TABLE IF NOT EXISTS audit.schema_migration (
        version TEXT PRIMARY KEY,
        checksum TEXT NOT NULL,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
    """)


def _applied_checksum(version: str) -> str | None:
    """Return the stored checksum for a migration version, if present."""
    if not isinstance(version, str) or not version:
        raise TypeError("version must be a non-empty string")
    escaped = version.replace("'", "''")
    sql = f"SELECT checksum FROM audit.schema_migration WHERE version = '{escaped}';"
    value = run_psql(sql, tuples_only=True).strip()
    return value or None


def main() -> None:
    """Apply unapplied migrations in lexical order and verify checksums."""
    _ensure_migration_table()
    migration_paths = sorted(_MIGRATIONS_DIR.glob("*.sql"))
    if not migration_paths:
        raise RuntimeError(f"No migrations found in {_MIGRATIONS_DIR}")

    for path in migration_paths:
        version = path.stem
        content = path.read_text(encoding="utf-8")
        checksum = _checksum(content)
        applied = _applied_checksum(version)
        if applied is not None:
            if applied != checksum:
                raise RuntimeError(f"Migration {version} was modified after application")
            print(f"skip {version}: already applied")
            continue

        escaped_version = version.replace("'", "''")
        escaped_checksum = checksum.replace("'", "''")
        run_psql(content)
        run_psql(
            "INSERT INTO audit.schema_migration (version, checksum) "
            f"VALUES ('{escaped_version}', '{escaped_checksum}');"
        )
        print(f"applied {version}")


if __name__ == "__main__":
    main()
