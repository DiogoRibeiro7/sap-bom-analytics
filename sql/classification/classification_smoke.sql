DO $$
DECLARE
    result_count INTEGER;
    bottle_status TEXT;
    closure_status TEXT;
    label_family TEXT;
    label_status TEXT;
BEGIN
    PERFORM classification.refresh_material_classification();

    SELECT COUNT(*) INTO result_count
    FROM classification.material_classification;
    IF result_count <> (SELECT COUNT(*) FROM core.material) THEN
        RAISE EXCEPTION 'Expected one classification per material, found %', result_count;
    END IF;

    SELECT c.status INTO bottle_status
    FROM classification.material_classification AS c
    JOIN core.material AS m ON m.material_id = c.material_id
    WHERE m.sap_material_id = 'PKG-1100';
    IF bottle_status <> 'review' THEN
        RAISE EXCEPTION 'Expected bottle heuristic to require review, got %', bottle_status;
    END IF;

    SELECT c.status INTO closure_status
    FROM classification.material_classification AS c
    JOIN core.material AS m ON m.material_id = c.material_id
    WHERE m.sap_material_id = 'PKG-1200';
    IF closure_status <> 'review' THEN
        RAISE EXCEPTION 'Expected closure heuristic to require review, got %', closure_status;
    END IF;

    SELECT c.material_family, c.status
    INTO label_family, label_status
    FROM classification.material_classification AS c
    JOIN core.material AS m ON m.material_id = c.material_id
    WHERE m.sap_material_id = 'PKG-1300';
    IF label_family <> 'unknown' OR label_status <> 'review' THEN
        RAISE EXCEPTION
            'Expected unresolved label to remain unknown/review, got %/%',
            label_family, label_status;
    END IF;
END
$$;
