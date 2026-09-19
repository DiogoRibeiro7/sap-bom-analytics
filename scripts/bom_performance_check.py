"""Generate a deep synthetic BOM and enforce a coarse performance ceiling."""

from __future__ import annotations

import json
import time
from decimal import Decimal

from sap_bom_analytics.db import run_psql

_DEPTH = 250
_MAX_SECONDS = 5.0


def main() -> None:
    """Create a deep linear BOM, execute recursion, and roll test data back."""
    setup_sql = f"""
BEGIN;

CREATE TEMP TABLE perf_material_map (
    level_no INTEGER PRIMARY KEY,
    material_id BIGINT NOT NULL
) ON COMMIT DROP;

DO $$
DECLARE
    run_id BIGINT;
    current_level INTEGER;
    current_material_id BIGINT;
    previous_material_id BIGINT;
    new_bom_id BIGINT;
    new_version_id BIGINT;
BEGIN
    INSERT INTO audit.ingestion_run (source_system, source_entity, status)
    VALUES ('PERFORMANCE_TEST', 'deep-bom', 'succeeded')
    RETURNING ingestion_run_id INTO run_id;

    previous_material_id := NULL;

    FOR current_level IN 0..{_DEPTH} LOOP
        INSERT INTO core.material (
            source_system, sap_material_id, description, base_unit,
            valid_from, ingestion_run_id
        )
        VALUES (
            'PERFORMANCE_TEST',
            'PERF-' || lpad(current_level::TEXT, 4, '0'),
            'Performance material ' || current_level,
            'EA',
            DATE '1900-01-01',
            run_id
        )
        RETURNING material_id INTO current_material_id;

        INSERT INTO perf_material_map (level_no, material_id)
        VALUES (current_level, current_material_id);

        IF previous_material_id IS NOT NULL THEN
            INSERT INTO core.bom (
                source_system, sap_bom_id, parent_material_id, plant,
                usage_code, ingestion_run_id
            )
            VALUES (
                'PERFORMANCE_TEST',
                'PERF-BOM-' || lpad((current_level - 1)::TEXT, 4, '0'),
                previous_material_id,
                'PERF',
                '1',
                run_id
            )
            RETURNING bom_id INTO new_bom_id;

            INSERT INTO core.bom_version (
                bom_id, alternative, revision, valid_from,
                ingestion_run_id, base_quantity, base_unit
            )
            VALUES (
                new_bom_id, '01', '1', DATE '1900-01-01',
                run_id, 1, 'EA'
            )
            RETURNING bom_version_id INTO new_version_id;

            INSERT INTO core.bom_component (
                bom_version_id, component_material_id, item_number,
                quantity, unit, ingestion_run_id, quantity_base_unit, base_unit
            )
            VALUES (
                new_version_id, current_material_id, '0010',
                1, 'EA', run_id, 1, 'EA'
            );
        END IF;

        previous_material_id := current_material_id;
    END LOOP;
END
$$;
"""
    run_psql(setup_sql)

    root_id = int(
        run_psql(
            "SELECT material_id FROM perf_material_map WHERE level_no = 0;",
            tuples_only=True,
        ).strip()
    )

    started = time.perf_counter()
    count = int(
        run_psql(
            "SELECT COUNT(*) FROM core.explode_bom("
            f"{root_id}, DATE '2026-01-01', 'PERF');",
            tuples_only=True,
        ).strip()
    )
    elapsed = time.perf_counter() - started

    run_psql("ROLLBACK;")

    if count != _DEPTH:
        raise RuntimeError(f"Expected {_DEPTH} exploded rows, found {count}")
    if elapsed > _MAX_SECONDS:
        raise RuntimeError(
            f"BOM explosion exceeded {_MAX_SECONDS:.1f}s ceiling: {elapsed:.3f}s"
        )

    print(
        json.dumps(
            {
                "depth": _DEPTH,
                "rows": count,
                "elapsed_seconds": str(Decimal(str(round(elapsed, 6)))),
                "ceiling_seconds": _MAX_SECONDS,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
