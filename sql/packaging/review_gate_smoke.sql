BEGIN;

DO $$
DECLARE
    root_id BIGINT;
    run_id BIGINT;
    demo_rule_set_id BIGINT;
    decision_value TEXT;
    review_count INTEGER;
BEGIN
    SELECT material_id INTO root_id
    FROM core.material WHERE sap_material_id = 'FG-1000';

    DELETE FROM classification.material_override
    WHERE material_id IN (
        SELECT material_id FROM core.material
        WHERE sap_material_id IN ('PKG-1100', 'PKG-1200', 'PKG-1300')
    );
    DELETE FROM packaging.recycled_content_evidence
    WHERE material_id IN (
        SELECT material_id FROM core.material
        WHERE sap_material_id IN ('PKG-1100', 'PKG-1200', 'PKG-1300')
    );

    PERFORM classification.refresh_material_classification();
    run_id := packaging.assess_product(root_id, DATE '2026-01-01', 'GB01');

    SELECT COUNT(*) INTO review_count
    FROM packaging.component_assessment
    WHERE assessment_run_id = run_id
      AND assessment_status = 'review';

    IF review_count = 0 THEN
        RAISE EXCEPTION 'Expected unresolved components to block automatic assessment';
    END IF;

    SELECT rule_set_id INTO demo_rule_set_id
    FROM tax.rule_set
    WHERE rule_set_code = 'DEMO_RECYCLED_CONTENT_TAX'
      AND version = '1.0.0';

    PERFORM tax.assess_packaging(run_id, demo_rule_set_id);

    SELECT decision INTO decision_value
    FROM tax.assessment
    WHERE assessment_run_id = run_id
      AND rule_set_id = demo_rule_set_id;

    IF decision_value <> 'review' THEN
        RAISE EXCEPTION 'Expected tax assessment review gate, found %', decision_value;
    END IF;
END
$$;

ROLLBACK;
