DO $$
DECLARE
    material_count INTEGER;
    bom_count INTEGER;
    component_count INTEGER;
    lineage_missing INTEGER;
    explosion_count INTEGER;
    cycle_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO material_count FROM core.material;
    IF material_count <> 4 THEN
        RAISE EXCEPTION 'Expected 4 core materials, found %', material_count;
    END IF;

    SELECT COUNT(*) INTO bom_count FROM core.bom;
    IF bom_count <> 1 THEN
        RAISE EXCEPTION 'Expected 1 core BOM, found %', bom_count;
    END IF;

    SELECT COUNT(*) INTO component_count FROM core.bom_component;
    IF component_count <> 3 THEN
        RAISE EXCEPTION 'Expected 3 core BOM components, found %', component_count;
    END IF;

    SELECT COUNT(*) INTO lineage_missing
    FROM core.bom_component
    WHERE source_staging_bom_component_id IS NULL
       OR source_record_id IS NULL;
    IF lineage_missing <> 0 THEN
        RAISE EXCEPTION 'Found % core components without lineage', lineage_missing;
    END IF;

    SELECT COUNT(*) INTO explosion_count
    FROM core.explode_bom(
        (SELECT material_id FROM core.material WHERE sap_material_id = 'FG-1000'),
        DATE '2026-01-01',
        'GB01'
    );
    IF explosion_count <> 3 THEN
        RAISE EXCEPTION 'Expected 3 exploded components, found %', explosion_count;
    END IF;

    SELECT COUNT(*) INTO cycle_count
    FROM core.explode_bom(
        (SELECT material_id FROM core.material WHERE sap_material_id = 'FG-1000'),
        DATE '2026-01-01',
        'GB01'
    )
    WHERE cycle_detected;
    IF cycle_count <> 0 THEN
        RAISE EXCEPTION 'Unexpected cycle detected in synthetic BOM';
    END IF;
END
$$;
