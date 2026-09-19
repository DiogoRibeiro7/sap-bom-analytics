BEGIN;

CREATE SCHEMA IF NOT EXISTS packaging;

ALTER TABLE core.material
    ADD COLUMN material_type TEXT,
    ADD COLUMN gross_weight NUMERIC(20, 8),
    ADD COLUMN net_weight NUMERIC(20, 8),
    ADD COLUMN weight_unit TEXT;

CREATE TABLE packaging.mass_unit (
    unit_code TEXT PRIMARY KEY,
    factor_to_kg NUMERIC(20, 12) NOT NULL CHECK (factor_to_kg > 0),
    description TEXT NOT NULL
);

INSERT INTO packaging.mass_unit (unit_code, factor_to_kg, description)
VALUES
    ('KG', 1.000000000000, 'kilogram'),
    ('G', 0.001000000000, 'gram'),
    ('MG', 0.000001000000, 'milligram'),
    ('T', 1000.000000000000, 'metric tonne'),
    ('LB', 0.453592370000, 'international avoirdupois pound')
ON CONFLICT (unit_code) DO NOTHING;

CREATE TABLE packaging.scope_rule (
    scope_rule_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rule_name TEXT NOT NULL UNIQUE,
    field_name TEXT NOT NULL CHECK (
        field_name IN ('material_group', 'material_type', 'description', 'sap_material_id')
    ),
    pattern TEXT NOT NULL,
    match_type TEXT NOT NULL CHECK (match_type IN ('exact', 'contains', 'regex')),
    is_packaging BOOLEAN NOT NULL,
    confidence NUMERIC(5, 4) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    priority INTEGER NOT NULL DEFAULT 10,
    rationale TEXT NOT NULL,
    rule_version TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE packaging.scope_evidence (
    scope_evidence_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    material_id BIGINT NOT NULL REFERENCES core.material(material_id) ON DELETE CASCADE,
    scope_rule_id BIGINT NOT NULL REFERENCES packaging.scope_rule(scope_rule_id),
    matched_field TEXT NOT NULL,
    matched_value TEXT NOT NULL,
    is_packaging BOOLEAN NOT NULL,
    confidence NUMERIC(5, 4) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    priority INTEGER NOT NULL,
    rule_version TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE packaging.scope_override (
    scope_override_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    material_id BIGINT NOT NULL REFERENCES core.material(material_id) ON DELETE CASCADE,
    is_packaging BOOLEAN NOT NULL,
    reason TEXT NOT NULL,
    reviewer TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX idx_scope_override_one_active
    ON packaging.scope_override (material_id)
    WHERE active;

CREATE TABLE packaging.material_profile (
    material_id BIGINT PRIMARY KEY REFERENCES core.material(material_id) ON DELETE CASCADE,
    is_packaging BOOLEAN,
    confidence NUMERIC(5, 4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
    status TEXT NOT NULL CHECK (
        status IN ('identified', 'excluded', 'review', 'conflict', 'overridden')
    ),
    method TEXT NOT NULL,
    selected_rule_id BIGINT REFERENCES packaging.scope_rule(scope_rule_id),
    override_id BIGINT REFERENCES packaging.scope_override(scope_override_id),
    evidence_count INTEGER NOT NULL DEFAULT 0 CHECK (evidence_count >= 0),
    conflict_count INTEGER NOT NULL DEFAULT 0 CHECK (conflict_count >= 0),
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE packaging.recycled_content_evidence (
    recycled_content_evidence_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    material_id BIGINT NOT NULL REFERENCES core.material(material_id) ON DELETE CASCADE,
    recycled_fraction NUMERIC(7, 6) NOT NULL CHECK (recycled_fraction BETWEEN 0 AND 1),
    evidence_type TEXT NOT NULL CHECK (
        evidence_type IN (
            'supplier_declaration', 'certificate', 'sap_attribute',
            'manual_review', 'synthetic'
        )
    ),
    source_reference TEXT NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE,
    confidence NUMERIC(5, 4) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    reviewed BOOLEAN NOT NULL DEFAULT FALSE,
    reviewer TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CHECK (reviewed = FALSE OR reviewer IS NOT NULL)
);

CREATE INDEX idx_recycled_content_material_date
    ON packaging.recycled_content_evidence (material_id, effective_from, effective_to);

CREATE TABLE packaging.assessment_run (
    assessment_run_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    root_material_id BIGINT NOT NULL REFERENCES core.material(material_id),
    as_of_date DATE NOT NULL,
    plant TEXT,
    status TEXT NOT NULL CHECK (status IN ('running', 'completed', 'review', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ
);

CREATE TABLE packaging.component_assessment (
    component_assessment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    assessment_run_id BIGINT NOT NULL
        REFERENCES packaging.assessment_run(assessment_run_id) ON DELETE CASCADE,
    depth INTEGER NOT NULL CHECK (depth > 0),
    bom_component_id BIGINT NOT NULL REFERENCES core.bom_component(bom_component_id),
    material_id BIGINT NOT NULL REFERENCES core.material(material_id),
    material_path BIGINT[] NOT NULL,
    cumulative_quantity NUMERIC(28, 12),
    quantity_unit TEXT,
    is_packaging BOOLEAN,
    packaging_status TEXT,
    material_family TEXT,
    polymer TEXT,
    classification_status TEXT,
    unit_weight NUMERIC(20, 8),
    weight_unit TEXT,
    weight_factor_to_kg NUMERIC(20, 12),
    component_weight_kg NUMERIC(28, 12),
    plastic_weight_kg NUMERIC(28, 12),
    recycled_content_fraction NUMERIC(7, 6),
    recycled_plastic_weight_kg NUMERIC(28, 12),
    recycled_content_evidence_id BIGINT
        REFERENCES packaging.recycled_content_evidence(recycled_content_evidence_id),
    assessment_status TEXT NOT NULL CHECK (
        assessment_status IN ('assessed', 'review', 'excluded')
    ),
    trace JSONB NOT NULL,
    UNIQUE (assessment_run_id, bom_component_id, material_path)
);

CREATE INDEX idx_component_assessment_run
    ON packaging.component_assessment (assessment_run_id, assessment_status);

CREATE TABLE tax.rule_set (
    rule_set_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rule_set_code TEXT NOT NULL,
    version TEXT NOT NULL,
    jurisdiction_code TEXT NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE,
    description TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
    UNIQUE (rule_set_code, version)
);

CREATE TABLE tax.rule_parameter (
    rule_parameter_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rule_set_id BIGINT NOT NULL REFERENCES tax.rule_set(rule_set_id) ON DELETE CASCADE,
    parameter_name TEXT NOT NULL,
    numeric_value NUMERIC(28, 12),
    text_value TEXT,
    unit TEXT,
    description TEXT NOT NULL,
    CHECK (numeric_value IS NOT NULL OR text_value IS NOT NULL),
    UNIQUE (rule_set_id, parameter_name)
);

CREATE TABLE tax.assessment (
    tax_assessment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    assessment_run_id BIGINT NOT NULL
        REFERENCES packaging.assessment_run(assessment_run_id) ON DELETE CASCADE,
    rule_set_id BIGINT NOT NULL REFERENCES tax.rule_set(rule_set_id),
    total_plastic_weight_kg NUMERIC(28, 12),
    recycled_plastic_weight_kg NUMERIC(28, 12),
    recycled_fraction NUMERIC(12, 10),
    decision TEXT NOT NULL CHECK (
        decision IN ('taxable', 'not_taxable', 'not_applicable', 'review')
    ),
    tax_amount NUMERIC(28, 12),
    currency_code TEXT,
    trace JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (assessment_run_id, rule_set_id)
);

INSERT INTO packaging.scope_rule (
    rule_name, field_name, pattern, match_type, is_packaging, confidence,
    priority, rationale, rule_version
)
VALUES
    ('material-group-packaging', 'material_group', 'PACKAGING', 'exact', TRUE, 0.9900,
        100, 'SAP material group explicitly identifies packaging.', 'scope-0.1.0'),
    ('material-type-packaging', 'material_type', 'VERP', 'exact', TRUE, 0.9900,
        95, 'SAP material type VERP identifies packaging materials.', 'scope-0.1.0'),
    ('material-group-finished-good', 'material_group', 'FINISHED_GOOD', 'exact',
        FALSE, 0.9900, 100, 'Finished goods are not packaging components themselves.',
        'scope-0.1.0')
ON CONFLICT (rule_name) DO NOTHING;

INSERT INTO tax.rule_set (
    rule_set_code, version, jurisdiction_code, effective_from, description
)
VALUES (
    'DEMO_RECYCLED_CONTENT_TAX', '1.0.0', 'DEMO', DATE '1900-01-01',
    'Synthetic rule set for end-to-end testing only; it is not legislation.'
)
ON CONFLICT (rule_set_code, version) DO NOTHING;

INSERT INTO tax.rule_parameter (
    rule_set_id, parameter_name, numeric_value, text_value, unit, description
)
SELECT rule_set_id, parameter_name, numeric_value, text_value, unit, description
FROM tax.rule_set
CROSS JOIN (
    VALUES
        ('minimum_recycled_fraction', 0.500000000000::NUMERIC, NULL::TEXT, 'fraction',
            'Synthetic minimum recycled fraction used by the demo evaluator.'),
        ('rate_per_kg', 2.000000000000::NUMERIC, NULL::TEXT, 'TEST_CURRENCY/kg',
            'Synthetic rate used only to prove configurable evaluation.'),
        ('currency_code', NULL::NUMERIC, 'TEST', NULL::TEXT,
            'Synthetic currency code used only in tests.')
) AS parameter(parameter_name, numeric_value, text_value, unit, description)
WHERE rule_set_code = 'DEMO_RECYCLED_CONTENT_TAX'
  AND version = '1.0.0'
ON CONFLICT (rule_set_id, parameter_name) DO NOTHING;

CREATE OR REPLACE FUNCTION packaging.refresh_component_scope()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE packaging.scope_evidence, packaging.material_profile
    RESTART IDENTITY;

    INSERT INTO packaging.scope_evidence (
        material_id, scope_rule_id, matched_field, matched_value, is_packaging,
        confidence, priority, rule_version
    )
    SELECT
        material.material_id,
        rule.scope_rule_id,
        rule.field_name,
        source.value,
        rule.is_packaging,
        rule.confidence,
        rule.priority,
        rule.rule_version
    FROM core.material AS material
    JOIN packaging.scope_rule AS rule ON rule.active
    CROSS JOIN LATERAL (
        SELECT CASE rule.field_name
            WHEN 'material_group' THEN material.material_group
            WHEN 'material_type' THEN material.material_type
            WHEN 'description' THEN material.description
            WHEN 'sap_material_id' THEN material.sap_material_id
        END AS value
    ) AS source
    WHERE source.value IS NOT NULL
      AND CASE rule.match_type
            WHEN 'exact' THEN lower(trim(source.value)) = lower(trim(rule.pattern))
            WHEN 'contains' THEN position(lower(rule.pattern) in lower(source.value)) > 0
            WHEN 'regex' THEN source.value ~* rule.pattern
            ELSE FALSE
          END;

    WITH ranked AS (
        SELECT
            evidence.*,
            ROW_NUMBER() OVER (
                PARTITION BY evidence.material_id
                ORDER BY evidence.priority DESC, evidence.confidence DESC,
                         evidence.scope_evidence_id ASC
            ) AS evidence_rank
        FROM packaging.scope_evidence AS evidence
    ),
    selected AS (
        SELECT * FROM ranked WHERE evidence_rank = 1
    ),
    summary AS (
        SELECT
            material_id,
            COUNT(*)::INTEGER AS evidence_count,
            GREATEST(
                COUNT(DISTINCT is_packaging) FILTER (WHERE confidence >= 0.8000) - 1,
                0
            )::INTEGER AS conflict_count
        FROM packaging.scope_evidence
        GROUP BY material_id
    ),
    active_override AS (
        SELECT * FROM packaging.scope_override WHERE active
    )
    INSERT INTO packaging.material_profile (
        material_id, is_packaging, confidence, status, method, selected_rule_id,
        override_id, evidence_count, conflict_count
    )
    SELECT
        material.material_id,
        COALESCE(override.is_packaging, selected.is_packaging),
        CASE WHEN override.scope_override_id IS NOT NULL THEN NULL ELSE selected.confidence END,
        CASE
            WHEN override.scope_override_id IS NOT NULL THEN 'overridden'
            WHEN COALESCE(summary.conflict_count, 0) > 0 THEN 'conflict'
            WHEN selected.scope_evidence_id IS NULL THEN 'review'
            WHEN selected.confidence < 0.8000 THEN 'review'
            WHEN selected.is_packaging THEN 'identified'
            ELSE 'excluded'
        END,
        CASE
            WHEN override.scope_override_id IS NOT NULL THEN 'manual-override'
            WHEN selected.scope_evidence_id IS NULL THEN 'no-evidence'
            ELSE 'rule'
        END,
        selected.scope_rule_id,
        override.scope_override_id,
        COALESCE(summary.evidence_count, 0),
        COALESCE(summary.conflict_count, 0)
    FROM core.material AS material
    LEFT JOIN selected ON selected.material_id = material.material_id
    LEFT JOIN summary ON summary.material_id = material.material_id
    LEFT JOIN active_override AS override ON override.material_id = material.material_id;
END;
$$;

CREATE OR REPLACE FUNCTION packaging.assess_product(
    requested_root_material_id BIGINT,
    requested_as_of_date DATE DEFAULT CURRENT_DATE,
    requested_plant TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    new_run_id BIGINT;
    review_count INTEGER;
BEGIN
    PERFORM packaging.refresh_component_scope();

    INSERT INTO packaging.assessment_run (
        root_material_id, as_of_date, plant, status
    )
    VALUES (requested_root_material_id, requested_as_of_date, requested_plant, 'running')
    RETURNING assessment_run_id INTO new_run_id;

    INSERT INTO packaging.component_assessment (
        assessment_run_id, depth, bom_component_id, material_id, material_path,
        cumulative_quantity, quantity_unit, is_packaging, packaging_status,
        material_family, polymer, classification_status, unit_weight, weight_unit,
        weight_factor_to_kg, component_weight_kg, plastic_weight_kg,
        recycled_content_fraction, recycled_plastic_weight_kg,
        recycled_content_evidence_id, assessment_status, trace
    )
    SELECT
        new_run_id,
        explosion.depth,
        explosion.bom_component_id,
        explosion.component_material_id,
        explosion.material_path,
        explosion.cumulative_quantity,
        explosion.unit,
        profile.is_packaging,
        profile.status,
        classification.material_family,
        classification.polymer,
        classification.status,
        COALESCE(material.net_weight, material.gross_weight),
        material.weight_unit,
        mass.factor_to_kg,
        CASE
            WHEN profile.is_packaging IS TRUE
             AND COALESCE(material.net_weight, material.gross_weight) IS NOT NULL
             AND mass.factor_to_kg IS NOT NULL
            THEN explosion.cumulative_quantity
                 * COALESCE(material.net_weight, material.gross_weight)
                 * mass.factor_to_kg
        END,
        CASE
            WHEN profile.is_packaging IS TRUE
             AND classification.material_family = 'plastic'
             AND classification.status IN ('classified', 'overridden')
             AND COALESCE(material.net_weight, material.gross_weight) IS NOT NULL
             AND mass.factor_to_kg IS NOT NULL
            THEN explosion.cumulative_quantity
                 * COALESCE(material.net_weight, material.gross_weight)
                 * mass.factor_to_kg
        END,
        recycled.recycled_fraction,
        CASE
            WHEN profile.is_packaging IS TRUE
             AND classification.material_family = 'plastic'
             AND classification.status IN ('classified', 'overridden')
             AND recycled.recycled_fraction IS NOT NULL
             AND COALESCE(material.net_weight, material.gross_weight) IS NOT NULL
             AND mass.factor_to_kg IS NOT NULL
            THEN explosion.cumulative_quantity
                 * COALESCE(material.net_weight, material.gross_weight)
                 * mass.factor_to_kg
                 * recycled.recycled_fraction
        END,
        recycled.recycled_content_evidence_id,
        CASE
            WHEN explosion.cycle_detected THEN 'review'
            WHEN profile.status IN ('review', 'conflict') OR profile.status IS NULL THEN 'review'
            WHEN profile.is_packaging IS FALSE THEN 'excluded'
            WHEN classification.status NOT IN ('classified', 'overridden')
                 OR classification.status IS NULL THEN 'review'
            WHEN COALESCE(material.net_weight, material.gross_weight) IS NULL
                 OR mass.factor_to_kg IS NULL THEN 'review'
            WHEN classification.material_family = 'plastic'
             AND (recycled.recycled_content_evidence_id IS NULL
                  OR (NOT recycled.reviewed AND recycled.confidence < 0.8000)) THEN 'review'
            ELSE 'assessed'
        END,
        jsonb_build_object(
            'material_source_staging_id', material.source_staging_material_id,
            'bom_component_id', explosion.bom_component_id,
            'material_path', explosion.material_path,
            'cycle_detected', explosion.cycle_detected,
            'packaging_profile_status', profile.status,
            'packaging_rule_id', profile.selected_rule_id,
            'classification_id', classification.material_classification_id,
            'classification_status', classification.status,
            'classification_method', classification.method,
            'recycled_content_evidence_id', recycled.recycled_content_evidence_id,
            'weight_source', CASE
                WHEN material.net_weight IS NOT NULL THEN 'net_weight'
                WHEN material.gross_weight IS NOT NULL THEN 'gross_weight'
                ELSE NULL
            END
        )
    FROM core.explode_bom(
        requested_root_material_id, requested_as_of_date, requested_plant
    ) AS explosion
    JOIN core.material AS material
      ON material.material_id = explosion.component_material_id
    LEFT JOIN packaging.material_profile AS profile
      ON profile.material_id = material.material_id
    LEFT JOIN classification.material_classification AS classification
      ON classification.material_id = material.material_id
    LEFT JOIN packaging.mass_unit AS mass
      ON mass.unit_code = upper(material.weight_unit)
    LEFT JOIN LATERAL (
        SELECT evidence.*
        FROM packaging.recycled_content_evidence AS evidence
        WHERE evidence.material_id = material.material_id
          AND evidence.effective_from <= requested_as_of_date
          AND (evidence.effective_to IS NULL
               OR evidence.effective_to >= requested_as_of_date)
        ORDER BY evidence.reviewed DESC, evidence.confidence DESC,
                 evidence.created_at DESC, evidence.recycled_content_evidence_id DESC
        LIMIT 1
    ) AS recycled ON TRUE;

    SELECT COUNT(*) INTO review_count
    FROM packaging.component_assessment
    WHERE assessment_run_id = new_run_id
      AND assessment_status = 'review';

    UPDATE packaging.assessment_run
    SET status = CASE WHEN review_count > 0 THEN 'review' ELSE 'completed' END,
        completed_at = CURRENT_TIMESTAMP
    WHERE assessment_run_id = new_run_id;

    RETURN new_run_id;
EXCEPTION WHEN OTHERS THEN
    IF new_run_id IS NOT NULL THEN
        UPDATE packaging.assessment_run
        SET status = 'failed', completed_at = CURRENT_TIMESTAMP
        WHERE assessment_run_id = new_run_id;
    END IF;
    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION tax.assess_packaging(
    requested_assessment_run_id BIGINT,
    requested_rule_set_id BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    threshold_value NUMERIC;
    rate_value NUMERIC;
    currency_value TEXT;
    run_date DATE;
    unresolved_count INTEGER;
    total_plastic NUMERIC;
    total_recycled NUMERIC;
    weighted_fraction NUMERIC;
    outcome TEXT;
    amount_value NUMERIC;
    new_assessment_id BIGINT;
BEGIN
    SELECT as_of_date INTO run_date
    FROM packaging.assessment_run
    WHERE assessment_run_id = requested_assessment_run_id;

    IF run_date IS NULL THEN
        RAISE EXCEPTION 'Unknown packaging assessment run %', requested_assessment_run_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM tax.rule_set
        WHERE rule_set_id = requested_rule_set_id
          AND active
          AND effective_from <= run_date
          AND (effective_to IS NULL OR effective_to >= run_date)
    ) THEN
        RAISE EXCEPTION 'Rule set % is not effective for %', requested_rule_set_id, run_date;
    END IF;

    SELECT numeric_value INTO threshold_value
    FROM tax.rule_parameter
    WHERE rule_set_id = requested_rule_set_id
      AND parameter_name = 'minimum_recycled_fraction';

    SELECT numeric_value INTO rate_value
    FROM tax.rule_parameter
    WHERE rule_set_id = requested_rule_set_id
      AND parameter_name = 'rate_per_kg';

    SELECT text_value INTO currency_value
    FROM tax.rule_parameter
    WHERE rule_set_id = requested_rule_set_id
      AND parameter_name = 'currency_code';

    IF threshold_value IS NULL OR rate_value IS NULL OR currency_value IS NULL THEN
        RAISE EXCEPTION 'Rule set % is missing required evaluator parameters',
            requested_rule_set_id;
    END IF;

    SELECT
        COUNT(*) FILTER (WHERE assessment_status = 'review'),
        COALESCE(SUM(plastic_weight_kg), 0),
        COALESCE(SUM(recycled_plastic_weight_kg), 0)
    INTO unresolved_count, total_plastic, total_recycled
    FROM packaging.component_assessment
    WHERE assessment_run_id = requested_assessment_run_id;

    weighted_fraction := CASE
        WHEN total_plastic > 0 THEN total_recycled / total_plastic
        ELSE NULL
    END;

    outcome := CASE
        WHEN unresolved_count > 0 THEN 'review'
        WHEN total_plastic = 0 THEN 'not_applicable'
        WHEN weighted_fraction IS NULL THEN 'review'
        WHEN weighted_fraction >= threshold_value THEN 'not_taxable'
        ELSE 'taxable'
    END;

    amount_value := CASE
        WHEN outcome = 'taxable' THEN total_plastic * rate_value
        WHEN outcome IN ('not_taxable', 'not_applicable') THEN 0
        ELSE NULL
    END;

    INSERT INTO tax.assessment (
        assessment_run_id, rule_set_id, total_plastic_weight_kg,
        recycled_plastic_weight_kg, recycled_fraction, decision,
        tax_amount, currency_code, trace
    )
    VALUES (
        requested_assessment_run_id,
        requested_rule_set_id,
        total_plastic,
        total_recycled,
        weighted_fraction,
        outcome,
        amount_value,
        currency_value,
        jsonb_build_object(
            'minimum_recycled_fraction', threshold_value,
            'rate_per_kg', rate_value,
            'currency_code', currency_value,
            'unresolved_component_count', unresolved_count,
            'component_count', (
                SELECT COUNT(*)
                FROM packaging.component_assessment
                WHERE assessment_run_id = requested_assessment_run_id
            ),
            'rule_set_id', requested_rule_set_id
        )
    )
    ON CONFLICT (assessment_run_id, rule_set_id)
    DO UPDATE SET
        total_plastic_weight_kg = EXCLUDED.total_plastic_weight_kg,
        recycled_plastic_weight_kg = EXCLUDED.recycled_plastic_weight_kg,
        recycled_fraction = EXCLUDED.recycled_fraction,
        decision = EXCLUDED.decision,
        tax_amount = EXCLUDED.tax_amount,
        currency_code = EXCLUDED.currency_code,
        trace = EXCLUDED.trace,
        created_at = CURRENT_TIMESTAMP
    RETURNING tax_assessment_id INTO new_assessment_id;

    RETURN new_assessment_id;
END;
$$;

CREATE OR REPLACE VIEW packaging.assessment_trace AS
SELECT
    run.assessment_run_id,
    root.sap_material_id AS root_sap_material_id,
    run.as_of_date,
    run.plant,
    run.status AS run_status,
    component.component_assessment_id,
    material.sap_material_id AS component_sap_material_id,
    material.description AS component_description,
    component.depth,
    component.is_packaging,
    component.packaging_status,
    component.material_family,
    component.polymer,
    component.classification_status,
    component.component_weight_kg,
    component.plastic_weight_kg,
    component.recycled_content_fraction,
    component.recycled_plastic_weight_kg,
    component.assessment_status,
    component.trace
FROM packaging.assessment_run AS run
JOIN core.material AS root ON root.material_id = run.root_material_id
JOIN packaging.component_assessment AS component
  ON component.assessment_run_id = run.assessment_run_id
JOIN core.material AS material ON material.material_id = component.material_id;

CREATE OR REPLACE VIEW tax.assessment_trace AS
SELECT
    assessment.tax_assessment_id,
    assessment.assessment_run_id,
    rule_set.rule_set_code,
    rule_set.version AS rule_set_version,
    rule_set.jurisdiction_code,
    assessment.total_plastic_weight_kg,
    assessment.recycled_plastic_weight_kg,
    assessment.recycled_fraction,
    assessment.decision,
    assessment.tax_amount,
    assessment.currency_code,
    assessment.trace
FROM tax.assessment AS assessment
JOIN tax.rule_set AS rule_set ON rule_set.rule_set_id = assessment.rule_set_id;

-- Use canonical component quantities when unit conversion is available.
CREATE OR REPLACE FUNCTION core.explode_bom(
    root_material_id BIGINT,
    as_of_date DATE DEFAULT CURRENT_DATE,
    plant_filter TEXT DEFAULT NULL
)
RETURNS TABLE (
    depth INTEGER,
    parent_material_id BIGINT,
    component_material_id BIGINT,
    bom_id BIGINT,
    bom_version_id BIGINT,
    bom_component_id BIGINT,
    item_number TEXT,
    direct_quantity NUMERIC,
    cumulative_quantity NUMERIC,
    unit TEXT,
    material_path BIGINT[],
    cycle_detected BOOLEAN
)
LANGUAGE sql
STABLE
AS $$
WITH RECURSIVE explosion AS (
    SELECT
        1 AS depth,
        b.parent_material_id,
        bc.component_material_id,
        b.bom_id,
        bv.bom_version_id,
        bc.bom_component_id,
        bc.item_number,
        COALESCE(bc.quantity_base_unit, bc.quantity) AS direct_quantity,
        (
            COALESCE(bc.quantity_base_unit, bc.quantity)
            / NULLIF(COALESCE(bv.base_quantity, 1), 0)
        )::NUMERIC AS cumulative_quantity,
        COALESCE(bc.base_unit, bc.unit) AS unit,
        ARRAY[b.parent_material_id, bc.component_material_id]::BIGINT[] AS material_path,
        bc.component_material_id = b.parent_material_id AS cycle_detected
    FROM core.bom AS b
    JOIN core.bom_version AS bv ON bv.bom_id = b.bom_id
    JOIN core.bom_component AS bc ON bc.bom_version_id = bv.bom_version_id
    WHERE b.parent_material_id = root_material_id
      AND (plant_filter IS NULL OR b.plant = plant_filter)
      AND bv.valid_from <= as_of_date
      AND (bv.valid_to IS NULL OR bv.valid_to >= as_of_date)

    UNION ALL

    SELECT
        parent.depth + 1,
        b.parent_material_id,
        bc.component_material_id,
        b.bom_id,
        bv.bom_version_id,
        bc.bom_component_id,
        bc.item_number,
        COALESCE(bc.quantity_base_unit, bc.quantity),
        (
            parent.cumulative_quantity
            * COALESCE(bc.quantity_base_unit, bc.quantity)
            / NULLIF(COALESCE(bv.base_quantity, 1), 0)
        )::NUMERIC,
        COALESCE(bc.base_unit, bc.unit),
        parent.material_path || bc.component_material_id,
        bc.component_material_id = ANY(parent.material_path)
    FROM explosion AS parent
    JOIN core.bom AS b ON b.parent_material_id = parent.component_material_id
    JOIN core.bom_version AS bv ON bv.bom_id = b.bom_id
    JOIN core.bom_component AS bc ON bc.bom_version_id = bv.bom_version_id
    WHERE NOT parent.cycle_detected
      AND (plant_filter IS NULL OR b.plant = plant_filter)
      AND bv.valid_from <= as_of_date
      AND (bv.valid_to IS NULL OR bv.valid_to >= as_of_date)
)
SELECT * FROM explosion;
$$;

COMMIT;
