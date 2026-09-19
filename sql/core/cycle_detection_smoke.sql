BEGIN;

DO $$
DECLARE
    root_id BIGINT;
    child_id BIGINT;
    run_id BIGINT;
    root_bom_id BIGINT;
    child_bom_id BIGINT;
    root_version_id BIGINT;
    child_version_id BIGINT;
    detected_cycles INTEGER;
BEGIN
    INSERT INTO audit.ingestion_run (source_system, status)
    VALUES ('CYCLE_TEST', 'succeeded')
    RETURNING ingestion_run_id INTO run_id;

    INSERT INTO core.material (
        source_system, sap_material_id, description, base_unit, valid_from, ingestion_run_id
    ) VALUES
        ('CYCLE_TEST', 'CYCLE-A', 'Cycle A', 'EA', DATE '1900-01-01', run_id)
    RETURNING material_id INTO root_id;

    INSERT INTO core.material (
        source_system, sap_material_id, description, base_unit, valid_from, ingestion_run_id
    ) VALUES
        ('CYCLE_TEST', 'CYCLE-B', 'Cycle B', 'EA', DATE '1900-01-01', run_id)
    RETURNING material_id INTO child_id;

    INSERT INTO core.bom (
        source_system, sap_bom_id, parent_material_id, plant, usage_code, ingestion_run_id
    ) VALUES
        ('CYCLE_TEST', 'CYCLE-BOM-A', root_id, 'TEST', '1', run_id)
    RETURNING bom_id INTO root_bom_id;

    INSERT INTO core.bom (
        source_system, sap_bom_id, parent_material_id, plant, usage_code, ingestion_run_id
    ) VALUES
        ('CYCLE_TEST', 'CYCLE-BOM-B', child_id, 'TEST', '1', run_id)
    RETURNING bom_id INTO child_bom_id;

    INSERT INTO core.bom_version (
        bom_id, alternative, revision, valid_from, ingestion_run_id, base_quantity, base_unit
    ) VALUES
        (root_bom_id, '01', '1', DATE '1900-01-01', run_id, 1, 'EA')
    RETURNING bom_version_id INTO root_version_id;

    INSERT INTO core.bom_version (
        bom_id, alternative, revision, valid_from, ingestion_run_id, base_quantity, base_unit
    ) VALUES
        (child_bom_id, '01', '1', DATE '1900-01-01', run_id, 1, 'EA')
    RETURNING bom_version_id INTO child_version_id;

    INSERT INTO core.bom_component (
        bom_version_id, component_material_id, item_number, quantity, unit,
        ingestion_run_id
    ) VALUES
        (root_version_id, child_id, '0010', 1, 'EA', run_id),
        (child_version_id, root_id, '0010', 1, 'EA', run_id);

    SELECT COUNT(*) INTO detected_cycles
    FROM core.explode_bom(root_id, CURRENT_DATE, 'TEST')
    WHERE cycle_detected;

    IF detected_cycles <> 1 THEN
        RAISE EXCEPTION 'Expected one detected cycle, found %', detected_cycles;
    END IF;
END
$$;

ROLLBACK;
