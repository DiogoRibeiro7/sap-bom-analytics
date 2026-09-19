"""Verify that deterministic reconciliation produces stable logical outputs."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Final

from sap_bom_analytics.db import execute_sql_file, repository_root, run_psql

_FINGERPRINTS: Final[dict[str, str]] = {
    "staging_material": (
        "SELECT sap_material_id, normalized_material_id, material_type, material_group, "
        "base_unit, gross_weight, net_weight, weight_unit, description "
        "FROM staging.material ORDER BY sap_material_id"
    ),
    "staging_bom_component": (
        "SELECT bom_number, parent_material_id, component_material_id, item_number, "
        "quantity, unit, valid_from, plant_code, bom_usage "
        "FROM staging.bom_component "
        "ORDER BY bom_number, parent_material_id, item_number, component_material_id"
    ),
    "core_material": (
        "SELECT sap_material_id, description, material_group, material_type, base_unit, "
        "gross_weight, net_weight, weight_unit, valid_from, valid_to "
        "FROM core.material ORDER BY sap_material_id"
    ),
    "core_bom_component": (
        "SELECT bom.sap_bom_id, parent.sap_material_id AS parent_material, "
        "child.sap_material_id AS component_material, component.item_number, "
        "component.quantity, component.unit, component.quantity_base_unit, "
        "component.base_unit "
        "FROM core.bom_component AS component "
        "JOIN core.bom_version AS version USING (bom_version_id) "
        "JOIN core.bom AS bom USING (bom_id) "
        "JOIN core.material AS parent ON parent.material_id = bom.parent_material_id "
        "JOIN core.material AS child ON child.material_id = component.component_material_id "
        "ORDER BY bom.sap_bom_id, parent.sap_material_id, component.item_number, "
        "child.sap_material_id"
    ),
    "classification": (
        "SELECT material.sap_material_id, result.material_family, result.polymer, "
        "result.confidence, result.method, result.classifier_version, result.reviewed, "
        "result.status, result.evidence_count, result.conflict_count "
        "FROM classification.material_classification AS result "
        "JOIN core.material AS material USING (material_id) "
        "ORDER BY material.sap_material_id"
    ),
}


def _fingerprint(query: str) -> str:
    """Return a stable MD5 fingerprint for an ordered logical dataset."""
    if not isinstance(query, str) or not query.strip():
        raise TypeError("query must be a non-empty string")
    sql = (
        "SELECT md5(COALESCE(string_agg(row_to_json(q)::TEXT, '|' "
        "ORDER BY row_to_json(q)::TEXT), '')) FROM ("
        + query
        + ") AS q;"
    )
    return run_psql(sql, tuples_only=True).strip()


def _snapshot() -> dict[str, str]:
    """Fingerprint all deterministic reconciliation outputs."""
    return {name: _fingerprint(query) for name, query in _FINGERPRINTS.items()}


def _refresh(root: Path) -> None:
    """Rebuild deterministic derived layers in dependency order."""
    execute_sql_file(root / "sql" / "staging" / "refresh_staging.sql")
    execute_sql_file(root / "sql" / "core" / "refresh_core.sql")
    execute_sql_file(root / "sql" / "classification" / "refresh_classification.sql")


def main() -> None:
    """Run two rebuilds and fail if logical outputs change."""
    root = repository_root()
    _refresh(root)
    first = _snapshot()
    _refresh(root)
    second = _snapshot()

    mismatches = {
        name: {"first": first[name], "second": second[name]}
        for name in first
        if first[name] != second[name]
    }
    result = {"first": first, "second": second, "mismatches": mismatches}
    print(json.dumps(result, indent=2, sort_keys=True))
    if mismatches:
        names = ", ".join(sorted(mismatches))
        raise RuntimeError(f"Non-idempotent logical outputs detected: {names}")


if __name__ == "__main__":
    main()
