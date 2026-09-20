BEGIN;

DO $$
DECLARE
    run_id BIGINT;
    root_id BIGINT;
    variable_id BIGINT;
    fixed_id BIGINT;
    deleted_id BIGINT;
    bom_id_value BIGINT;
    version_id_value BIGINT;
    variable_qty NUMERIC;
    fixed_qty NUMERIC;
    exploded_count INTEGER;
BEGIN
    INSERT INTO audit.ingestion_run (source_system, source_entity, status)
    VALUES ('SEMANTICS_TEST', 'stpo-semantics', 'succeeded')
    RETURNING ingestion_run_id INTO run_id;

    INSERT INTO core.material (
        source_system, sap_material_id, description, base_unit, valid_from, ingestion_run_id
    )
    VALUES ('SEMANTICS_TEST', 'SEM-ROOT', 'Semantic root', 'EA', DATE '1900-01-01', run_id)
    RETURNING material_id INTO root_id;

    INSERT INTO core.material (
        source_system, sap_material_id, description, base_unit, valid_from, ingestion_run_id
    )
    VALUES ('SEMANTICS_TEST', 'SEM-VAR', 'Variable item', 'EA', DATE '1900-01-01', run_id)
    RETURNING material_id INTO variable_id;

    INSERT INTO core.material (
        source_system, sap_material_id, description, base_unit, valid_from, ingestion_run_id
    )
    VALUES ('SEMANTICS_TEST', 'SEM-FIX', 'Fixed item', 'EA', DATE '1900-01-01', run_id)
    RETURNING material_id INTO fixed_id;

    INSERT INTO core.material (
        source_system, sap_material_id, description, base_unit, valid_from, ingestion_run_id
    )
    VALUES ('SEMANTICS_TEST', 'SEM-DEL', 'Deleted item', 'EA', DATE '1900-01-01', run_id)
    RETURNING material_id INTO deleted_id;

    INSERT INTO core.bom (
        source_system, sap_bom_id, parent_material_id, plant, usage_code, ingestion_run_id
    )
    VALUES ('SEMANTICS_TEST', 'SEM-BOM', root_id, 'SEM', '1', run_id)
    RETURNING bom_id INTO bom_id_value;

    INSERT INTO core.bom_version (
        bom_id, alternative, revision, valid_from, ingestion_run_id, base_quantity, base_unit
    )
    VALUES (bom_id_value, '01', '1', DATE '1900-01-01', run_id, 10, 'EA')
    RETURNING bom_version_id INTO version_id_value;

    INSERT INTO core.bom_component (
        bom_version_id, component_material_id, item_number, quantity, unit,
        ingestion_run_id, quantity_base_unit, base_unit,
        item_category, is_deleted, is_fixed_quantity, component_scrap_percent
    )
    VALUES
        (version_id_value, variable_id, '0010', 20, 'EA', run_id, 20, 'EA',
         'L', FALSE, FALSE, 10),
        (version_id_value, fixed_id, '0020', 3, 'EA', run_id, 3, 'EA',
         'L', FALSE, TRUE, 0),
        (version_id_value, deleted_id, '0030', 5, 'EA', run_id, 5, 'EA',
         'L', TRUE, FALSE, 0);

    SELECT COUNT(*) INTO exploded_count
    FROM core.explode_bom(root_id, DATE '2026-01-01', 'SEM');

    IF exploded_count <> 2 THEN
        RAISE EXCEPTION 'Expected 2 active components, found %', exploded_count;
    END IF;

    SELECT cumulative_quantity INTO variable_qty
    FROM core.explode_bom(root_id, DATE '2026-01-01', 'SEM')
    WHERE component_material_id = variable_id;

    IF abs(variable_qty - 2.2) > 0.000000001 THEN
        RAISE EXCEPTION 'Expected variable quantity 2.2, found %', variable_qty;
    END IF;

    SELECT cumulative_quantity INTO fixed_qty
    FROM core.explode_bom(root_id, DATE '2026-01-01', 'SEM')
    WHERE component_material_id = fixed_id;

    IF fixed_qty <> 3 THEN
        RAISE EXCEPTION 'Expected fixed quantity 3, found %', fixed_qty;
    END IF;
END
$$;

ROLLBACK;
