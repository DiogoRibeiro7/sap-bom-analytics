"""Run smoke checks against the local development database."""

from __future__ import annotations

from _postgres import run_psql


def _scalar(sql: str) -> int:
    """Execute a scalar integer query."""
    value = run_psql(sql, tuples_only=True).strip()
    if not value:
        raise RuntimeError("Expected scalar query to return a value")
    return int(value)


def main() -> None:
    """Validate that the synthetic BOM and lineage are present."""
    material_count = _scalar("SELECT COUNT(*) FROM core.material;")
    component_count = _scalar("SELECT COUNT(*) FROM core.bom_component;")
    orphan_count = _scalar("""
        SELECT COUNT(*)
        FROM core.bom_component AS bc
        LEFT JOIN core.material AS m
          ON m.material_id = bc.component_material_id
        WHERE m.material_id IS NULL;
    """)
    missing_lineage = _scalar("""
        SELECT COUNT(*)
        FROM core.bom_component
        WHERE source_record_id IS NULL
           OR ingestion_run_id IS NULL;
    """)

    if material_count < 4:
        raise RuntimeError(f"Expected at least 4 materials, found {material_count}")
    if component_count != 3:
        raise RuntimeError(f"Expected 3 BOM components, found {component_count}")
    if orphan_count != 0:
        raise RuntimeError(f"Found {orphan_count} orphan BOM components")
    if missing_lineage != 0:
        raise RuntimeError(f"Found {missing_lineage} components without lineage")

    print(f"smoke checks passed: materials={material_count}, components={component_count}")


if __name__ == "__main__":
    main()
