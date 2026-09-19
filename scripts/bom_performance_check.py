"""Generate a deep synthetic BOM and enforce a coarse performance ceiling."""

from __future__ import annotations

import json
import time

from sap_bom_analytics.db import run_psql

_DEPTH = 250
_MAX_SECONDS = 5.0
_SOURCE_SYSTEM = "PERFORMANCE_TEST"


def _cleanup() -> None:
    """Delete synthetic performance data without affecting real repository state."""
    run_psql(
        """
        DELETE FROM core.bom_component
        WHERE bom_version_id IN (
            SELECT version.bom_version_id
            FROM core.bom_version AS version
            JOIN core.bom AS bom ON bom.bom_id = version.bom_id
            WHERE bom.source_system = 'PERFORMANCE_TEST'
        );

        DELETE FROM core.bom_version
        WHERE bom_id IN (
            SELECT bom_id
            FROM core.bom
            WHERE source_system = 'PERFORMANCE_TEST'
        );

        DELETE FROM core.bom
        WHERE source_system = 'PERFORMANCE_TEST';

        DELETE FROM core.material
        WHERE source_system = 'PERFORMANCE_TEST';

        DELETE FROM audit.ingestion_run
        WHERE source_system = 'PERFORMANCE_TEST';
        """
    )


def _setup() -> int:
    """Create a linear synthetic BOM and return its root material identifier."""
    _cleanup()
    run_psql(
        f"""
        DO $$
        DECLARE
            run_id BIGINT;
            current_level INTEGER;
            current_material_id BIGINT;
            previous_material_id BIGINT;
            new_bom_id BIGINT;
            new_version_id BIGINT;
        BEGIN
            INSERT INTO audit.ingestion_run (
                source_system, source_entity, status
            )
            VALUES ('{_SOURCE_SYSTEM}', 'deep-bom', 'succeeded')
            RETURNING ingestion_run_id INTO run_id;

            previous_material_id := NULL;

            FOR current_level IN 0..{_DEPTH} LOOP
                INSERT INTO core.material (
                    source_system, sap_material_id, description, base_unit,
                    valid_from, ingestion_run_id
                )
                VALUES (
                    '{_SOURCE_SYSTEM}',
                    'PERF-' || lpad(current_level::TEXT, 4, '0'),
                    'Performance material ' || current_level,
                    'EA',
                    DATE '1900-01-01',
                    run_id
                )
                RETURNING material_id INTO current_material_id;

                IF previous_material_id IS NOT NULL THEN
                    INSERT INTO core.bom (
                        source_system, sap_bom_id, parent_material_id, plant,
                        usage_code, ingestion_run_id
                    )
                    VALUES (
                        '{_SOURCE_SYSTEM}',
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
                        quantity, unit, ingestion_run_id,
                        quantity_base_unit, base_unit
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
    )
    output = run_psql(
        "SELECT material_id FROM core.material "
        "WHERE source_system = 'PERFORMANCE_TEST' "
        "AND sap_material_id = 'PERF-0000';",
        tuples_only=True,
    ).strip()
    if not output:
        raise RuntimeError("Performance root material was not created")
    return int(output)


def main() -> None:
    """Measure recursive explosion over a deep linear BOM."""
    root_id = _setup()
    try:
        started = time.perf_counter()
        output = run_psql(
            "SELECT COUNT(*) FROM core.explode_bom("
            f"{root_id}, DATE '2026-01-01', 'PERF');",
            tuples_only=True,
        ).strip()
        elapsed = time.perf_counter() - started
        count = int(output)
    finally:
        _cleanup()

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
                "elapsed_seconds": round(elapsed, 6),
                "ceiling_seconds": _MAX_SECONDS,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
