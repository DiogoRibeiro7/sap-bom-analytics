BEGIN;

DO $$
DECLARE
    root_id BIGINT;
    bottle_id BIGINT;
    closure_id BIGINT;
    label_id BIGINT;
    run_id BIGINT;
    tax_id BIGINT;
    demo_rule_set_id BIGINT;
    plastic_weight NUMERIC;
    recycled_weight NUMERIC;
    recycled_fraction NUMERIC;
    decision_value TEXT;
    tax_amount_value NUMERIC;
    review_count INTEGER;
BEGIN
    SELECT material_id INTO root_id
    FROM core.material WHERE sap_material_id = 'FG-1000';
    SELECT material_id INTO bottle_id
    FROM core.material WHERE sap_material_id = 'PKG-1100';
    SELECT material_id INTO closure_id
    FROM core.material WHERE sap_material_id = 'PKG-1200';
    SELECT material_id INTO label_id
    FROM core.material WHERE sap_material_id = 'PKG-1300';

    INSERT INTO classification.material_override (
        material_id, family_code, polymer_code, reason, reviewer
    ) VALUES
        (bottle_id, 'plastic', 'HDPE',
         'Synthetic end-to-end packaging fixture.', 'smoke-test'),
        (closure_id, 'plastic', 'PP',
         'Synthetic end-to-end packaging fixture.', 'smoke-test'),
        (label_id, 'paper', NULL,
         'Synthetic end-to-end packaging fixture.', 'smoke-test');

    PERFORM classification.refresh_material_classification();

    INSERT INTO packaging.recycled_content_evidence (
        material_id, recycled_fraction, evidence_type, source_reference,
        effective_from, confidence, reviewed, reviewer, notes
    ) VALUES
        (bottle_id, 0.600000, 'synthetic', 'fixture://bottle-recycled-content',
         DATE '2026-01-01', 1.0000, TRUE, 'smoke-test',
         'Synthetic evidence for deterministic end-to-end testing.'),
        (closure_id, 0.250000, 'synthetic', 'fixture://closure-recycled-content',
         DATE '2026-01-01', 1.0000, TRUE, 'smoke-test',
         'Synthetic evidence for deterministic end-to-end testing.');

    run_id := packaging.assess_product(root_id, DATE '2026-01-01', 'GB01');

    SELECT COUNT(*) INTO review_count
    FROM packaging.component_assessment
    WHERE assessment_run_id = run_id
      AND assessment_status = 'review';

    IF review_count <> 0 THEN
        RAISE EXCEPTION 'Expected no component reviews, found %', review_count;
    END IF;

    SELECT SUM(plastic_weight_kg), SUM(recycled_plastic_weight_kg)
    INTO plastic_weight, recycled_weight
    FROM packaging.component_assessment
    WHERE assessment_run_id = run_id;

    IF abs(plastic_weight - 0.043000000000) > 0.000000001 THEN
        RAISE EXCEPTION 'Expected 0.043 kg plastic, found %', plastic_weight;
    END IF;

    IF abs(recycled_weight - 0.023000000000) > 0.000000001 THEN
        RAISE EXCEPTION 'Expected 0.023 kg recycled plastic, found %', recycled_weight;
    END IF;

    SELECT rule_set_id INTO demo_rule_set_id
    FROM tax.rule_set
    WHERE rule_set_code = 'DEMO_RECYCLED_CONTENT_TAX'
      AND version = '1.0.0';

    tax_id := tax.assess_packaging(run_id, demo_rule_set_id);

    SELECT recycled_fraction, decision, tax_amount
    INTO recycled_fraction, decision_value, tax_amount_value
    FROM tax.assessment
    WHERE tax_assessment_id = tax_id;

    IF abs(recycled_fraction - (0.023::NUMERIC / 0.043::NUMERIC)) > 0.000000001 THEN
        RAISE EXCEPTION 'Unexpected recycled fraction %', recycled_fraction;
    END IF;

    IF decision_value <> 'not_taxable' THEN
        RAISE EXCEPTION 'Expected demo decision not_taxable, found %', decision_value;
    END IF;

    IF tax_amount_value <> 0 THEN
        RAISE EXCEPTION 'Expected zero demo tax amount, found %', tax_amount_value;
    END IF;
END
$$;

ROLLBACK;
