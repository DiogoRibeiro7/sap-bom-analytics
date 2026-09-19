"""Execute one SQL file against the local development database."""

from __future__ import annotations

import argparse
from pathlib import Path

from _postgres import run_psql


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Execute a SQL file against the Docker Compose PostgreSQL service."
    )
    parser.add_argument("path", type=Path, help="Path to the SQL file to execute.")
    return parser.parse_args()


def main() -> None:
    """Load and execute the requested SQL file."""
    args = parse_args()
    path: Path = args.path

    if not path.is_file():
        raise FileNotFoundError(f"SQL file does not exist: {path}")
    if path.suffix.lower() != ".sql":
        raise ValueError(f"Expected a .sql file: {path}")

    run_psql(path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
