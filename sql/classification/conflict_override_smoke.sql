BEGIN;

DO $$
DECLARE
    run_id BIGINT;
    test_material_id BIGINT;
    result_status TEXT;
    result_family TEXT;
    result_polymer TEXT;
    result_evidence INTEGER;
BEGIN
    INSERT INTO audit.ingestion_run (source_system, status)
    VALUES ('CLASSIFICATION_TEST', 'succeeded')
    RETURNING ingestion_run_id INTO run_id;

    INSERT INTO core.material (
        source_system, sap_material_id, description, material_group, base_unit,
        valid_from, ingestion_run_id
    )
    VALUES (
        'CLASSIFICATION_TEST', 'TEST-HDPE-BOTTLE', 'HDPE bottle',
        'PACKAGING', 'EA', DATE '1900-01-01', run_id
    )
    RETURNING material_id INTO test_material_id;

    PERFORM classification.refresh_material_classification();

    SELECT status, material_family, polymer, evidence_count
    INTO result_status, result_family, result_polymer, result_evidence
    FROM classification.material_classification
    WHERE material_id = test_material_id;

    IF result_status <> 'classified'
       OR result_family <> 'plastic'
       OR result_polymer <> 'HDPE'
       OR result_evidence < 2 THEN
        RAISE EXCEPTION
            'Dictionary resolution failed: status=%, family=%, polymer=%, evidence=%',
            result_status, result_family, result_polymer, result_evidence;
    END IF;

    INSERT INTO classification.rule (
        rule_name, field_name, pattern, match_type, family_code, polymer_code,
        confidence, priority, rationale, classifier_version
    )
    VALUES (
        'test-conflicting-paper-rule', 'description', 'HDPE bottle', 'exact',
        'paper', NULL, 0.9500, 90,
        'Synthetic rule used only to verify contradiction detection.',
        'smoke-test'
    );

    PERFORM classification.refresh_material_classification();

    SELECT status INTO result_status
    FROM classification.material_classification
    WHERE material_id = test_material_id;

    IF result_status <> 'conflict' THEN
        RAISE EXCEPTION 'Expected conflicting strong evidence, got %', result_status;
    END IF;

    INSERT INTO classification.material_override (
        material_id, family_code, polymer_code, reason, reviewer
    )
    VALUES (
        test_material_id, 'plastic', 'HDPE',
        'Synthetic reviewed override for smoke testing.', 'smoke-test'
    );

    PERFORM classification.refresh_material_classification();

    SELECT status, material_family, polymer
    INTO result_status, result_family, result_polymer
    FROM classification.material_classification
    WHERE material_id = test_material_id;

    IF result_status <> 'overridden'
       OR result_family <> 'plastic'
       OR result_polymer <> 'HDPE' THEN
        RAISE EXCEPTION
            'Override resolution failed: status=%, family=%, polymer=%',
            result_status, result_family, result_polymer;
    END IF;
END
$$;

ROLLBACK;
