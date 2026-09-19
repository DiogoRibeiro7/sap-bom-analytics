BEGIN;

CREATE TABLE classification.material_family (
    family_code TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL
);

CREATE TABLE classification.polymer (
    polymer_code TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    family_code TEXT NOT NULL REFERENCES classification.material_family(family_code),
    description TEXT NOT NULL
);

INSERT INTO classification.material_family (family_code, display_name, description)
VALUES
    ('plastic', 'Plastic', 'Polymeric plastic materials.'),
    ('paper', 'Paper / board', 'Paper, paperboard, cardboard, and fibre-based materials.'),
    ('glass', 'Glass', 'Glass materials.'),
    ('metal', 'Metal', 'Metallic materials including aluminium and steel.'),
    ('wood', 'Wood', 'Wood and cork-based materials.'),
    ('other', 'Other', 'Known material outside the principal taxonomy.'),
    ('unknown', 'Unknown', 'Material family cannot yet be resolved.')
ON CONFLICT (family_code) DO NOTHING;

INSERT INTO classification.polymer (
    polymer_code, display_name, family_code, description
)
VALUES
    ('HDPE', 'High-density polyethylene', 'plastic', 'High-density polyethylene.'),
    ('LDPE', 'Low-density polyethylene', 'plastic', 'Low-density polyethylene.'),
    ('PE', 'Polyethylene', 'plastic', 'Polyethylene where density grade is unspecified.'),
    ('PET', 'Polyethylene terephthalate', 'plastic', 'Polyethylene terephthalate.'),
    ('PP', 'Polypropylene', 'plastic', 'Polypropylene.'),
    ('PS', 'Polystyrene', 'plastic', 'Polystyrene.'),
    ('PVC', 'Polyvinyl chloride', 'plastic', 'Polyvinyl chloride.'),
    ('PA', 'Polyamide', 'plastic', 'Polyamide / nylon.'),
    ('OTHER_PLASTIC', 'Other plastic', 'plastic', 'Plastic polymer not otherwise represented.')
ON CONFLICT (polymer_code) DO NOTHING;

CREATE TABLE classification.dictionary_term (
    dictionary_term_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    canonical_term TEXT NOT NULL,
    synonym TEXT NOT NULL,
    match_type TEXT NOT NULL CHECK (match_type IN ('exact', 'contains', 'word')),
    family_code TEXT NOT NULL REFERENCES classification.material_family(family_code),
    polymer_code TEXT REFERENCES classification.polymer(polymer_code),
    confidence NUMERIC(5, 4) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    priority INTEGER NOT NULL DEFAULT 50,
    source_note TEXT NOT NULL,
    classifier_version TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (synonym, match_type, family_code, polymer_code, classifier_version)
);

CREATE TABLE classification.rule (
    rule_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rule_name TEXT NOT NULL UNIQUE,
    field_name TEXT NOT NULL CHECK (
        field_name IN ('description', 'material_group', 'sap_material_id')
    ),
    pattern TEXT NOT NULL,
    match_type TEXT NOT NULL CHECK (match_type IN ('exact', 'contains', 'regex')),
    family_code TEXT NOT NULL REFERENCES classification.material_family(family_code),
    polymer_code TEXT REFERENCES classification.polymer(polymer_code),
    confidence NUMERIC(5, 4) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    priority INTEGER NOT NULL DEFAULT 10,
    rationale TEXT NOT NULL,
    classifier_version TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE classification.material_evidence (
    material_evidence_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    material_id BIGINT NOT NULL REFERENCES core.material(material_id) ON DELETE CASCADE,
    evidence_type TEXT NOT NULL CHECK (evidence_type IN ('dictionary', 'rule')),
    dictionary_term_id BIGINT REFERENCES classification.dictionary_term(dictionary_term_id),
    rule_id BIGINT REFERENCES classification.rule(rule_id),
    matched_field TEXT NOT NULL,
    matched_value TEXT NOT NULL,
    family_code TEXT NOT NULL REFERENCES classification.material_family(family_code),
    polymer_code TEXT REFERENCES classification.polymer(polymer_code),
    confidence NUMERIC(5, 4) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    priority INTEGER NOT NULL,
    classifier_version TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (
        (evidence_type = 'dictionary' AND dictionary_term_id IS NOT NULL AND rule_id IS NULL)
        OR
        (evidence_type = 'rule' AND rule_id IS NOT NULL AND dictionary_term_id IS NULL)
    )
);

CREATE TABLE classification.material_override (
    material_override_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    material_id BIGINT NOT NULL REFERENCES core.material(material_id) ON DELETE CASCADE,
    family_code TEXT NOT NULL REFERENCES classification.material_family(family_code),
    polymer_code TEXT REFERENCES classification.polymer(polymer_code),
    reason TEXT NOT NULL,
    reviewer TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX idx_material_override_one_active
    ON classification.material_override (material_id)
    WHERE active;

ALTER TABLE classification.material_classification
    ADD COLUMN status TEXT NOT NULL DEFAULT 'review'
        CHECK (status IN ('classified', 'review', 'conflict', 'overridden')),
    ADD COLUMN selected_rule_id BIGINT REFERENCES classification.rule(rule_id),
    ADD COLUMN selected_dictionary_term_id BIGINT
        REFERENCES classification.dictionary_term(dictionary_term_id),
    ADD COLUMN override_id BIGINT
        REFERENCES classification.material_override(material_override_id),
    ADD COLUMN evidence_count INTEGER NOT NULL DEFAULT 0 CHECK (evidence_count >= 0),
    ADD COLUMN conflict_count INTEGER NOT NULL DEFAULT 0 CHECK (conflict_count >= 0);

ALTER TABLE classification.material_classification
    ADD CONSTRAINT fk_material_classification_family
        FOREIGN KEY (material_family)
        REFERENCES classification.material_family(family_code),
    ADD CONSTRAINT fk_material_classification_polymer
        FOREIGN KEY (polymer)
        REFERENCES classification.polymer(polymer_code);

CREATE INDEX idx_material_evidence_material
    ON classification.material_evidence (material_id);
CREATE INDEX idx_material_evidence_family
    ON classification.material_evidence (family_code, confidence);
CREATE INDEX idx_material_classification_status
    ON classification.material_classification (status);

INSERT INTO classification.dictionary_term (
    canonical_term, synonym, match_type, family_code, polymer_code,
    confidence, priority, source_note, classifier_version
)
VALUES
    ('high-density polyethylene', 'hdpe', 'word', 'plastic', 'HDPE', 0.9900, 100,
        'Standard polymer abbreviation.', 'rules-0.1.0'),
    ('high-density polyethylene', 'high density polyethylene', 'contains',
        'plastic', 'HDPE', 0.9900, 100, 'Polymer name.', 'rules-0.1.0'),
    ('low-density polyethylene', 'ldpe', 'word', 'plastic', 'LDPE', 0.9900, 100,
        'Standard polymer abbreviation.', 'rules-0.1.0'),
    ('polyethylene terephthalate', 'pet', 'word', 'plastic', 'PET', 0.9900, 100,
        'Standard polymer abbreviation.', 'rules-0.1.0'),
    ('polypropylene', 'polypropylene', 'word', 'plastic', 'PP', 0.9900, 100,
        'Polymer name.', 'rules-0.1.0'),
    ('polypropylene', 'pp', 'word', 'plastic', 'PP', 0.9800, 95,
        'Standard polymer abbreviation.', 'rules-0.1.0'),
    ('polystyrene', 'polystyrene', 'word', 'plastic', 'PS', 0.9900, 100,
        'Polymer name.', 'rules-0.1.0'),
    ('polyvinyl chloride', 'pvc', 'word', 'plastic', 'PVC', 0.9900, 100,
        'Standard polymer abbreviation.', 'rules-0.1.0'),
    ('paper', 'paper', 'word', 'paper', NULL, 0.9500, 90,
        'Material-family term.', 'rules-0.1.0'),
    ('cardboard', 'cardboard', 'word', 'paper', NULL, 0.9500, 90,
        'Material-family term.', 'rules-0.1.0'),
    ('glass', 'glass', 'word', 'glass', NULL, 0.9800, 95,
        'Material-family term.', 'rules-0.1.0'),
    ('aluminium', 'aluminium', 'word', 'metal', NULL, 0.9800, 95,
        'Material-family term.', 'rules-0.1.0'),
    ('aluminium', 'aluminum', 'word', 'metal', NULL, 0.9800, 95,
        'US spelling.', 'rules-0.1.0'),
    ('steel', 'steel', 'word', 'metal', NULL, 0.9800, 95,
        'Material-family term.', 'rules-0.1.0')
ON CONFLICT DO NOTHING;

INSERT INTO classification.rule (
    rule_name, field_name, pattern, match_type, family_code, polymer_code,
    confidence, priority, rationale, classifier_version
)
VALUES
    ('description-bottle-plastic', 'description', '\\mbottle\\M', 'regex',
        'plastic', NULL, 0.6500, 20,
        'Packaging descriptions containing bottle often indicate plastic, but material evidence is required for high confidence.',
        'rules-0.1.0'),
    ('description-closure-plastic', 'description', '\\m(closure|cap)\\M', 'regex',
        'plastic', NULL, 0.6500, 20,
        'Closure terminology is a packaging heuristic and remains reviewable without polymer evidence.',
        'rules-0.1.0')
ON CONFLICT (rule_name) DO NOTHING;

CREATE OR REPLACE FUNCTION classification.refresh_material_classification()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE
        classification.material_evidence,
        classification.material_classification
    RESTART IDENTITY;

    INSERT INTO classification.material_evidence (
        material_id, evidence_type, dictionary_term_id, matched_field, matched_value,
        family_code, polymer_code, confidence, priority, classifier_version
    )
    SELECT
        material.material_id,
        'dictionary',
        term.dictionary_term_id,
        'description',
        material.description,
        term.family_code,
        term.polymer_code,
        term.confidence,
        term.priority,
        term.classifier_version
    FROM core.material AS material
    JOIN classification.dictionary_term AS term
      ON term.active
     AND material.description IS NOT NULL
     AND CASE term.match_type
            WHEN 'exact' THEN lower(trim(material.description)) = lower(trim(term.synonym))
            WHEN 'contains' THEN position(lower(term.synonym) in lower(material.description)) > 0
            WHEN 'word' THEN material.description ~* (
                '(^|[^[:alnum:]_])' ||
                regexp_replace(term.synonym, '([\\.\\+\\*\\?\\[\\]\\(\\)\\{\\}\\^\\$\\|])', '\\\\1', 'g') ||
                '([^[:alnum:]_]|$)'
            )
            ELSE FALSE
         END;

    INSERT INTO classification.material_evidence (
        material_id, evidence_type, rule_id, matched_field, matched_value,
        family_code, polymer_code, confidence, priority, classifier_version
    )
    SELECT
        material.material_id,
        'rule',
        rule.rule_id,
        rule.field_name,
        source.value,
        rule.family_code,
        rule.polymer_code,
        rule.confidence,
        rule.priority,
        rule.classifier_version
    FROM core.material AS material
    JOIN classification.rule AS rule
      ON rule.active
    CROSS JOIN LATERAL (
        SELECT CASE rule.field_name
            WHEN 'description' THEN material.description
            WHEN 'material_group' THEN material.material_group
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
                         evidence.material_evidence_id ASC
            ) AS evidence_rank
        FROM classification.material_evidence AS evidence
    ),
    selected AS (
        SELECT *
        FROM ranked
        WHERE evidence_rank = 1
    ),
    evidence_summary AS (
        SELECT
            material_id,
            COUNT(*)::INTEGER AS evidence_count,
            GREATEST(
                COUNT(DISTINCT family_code) FILTER (WHERE confidence >= 0.8000) - 1,
                0
            )::INTEGER AS conflict_count
        FROM classification.material_evidence
        GROUP BY material_id
    ),
    active_override AS (
        SELECT *
        FROM classification.material_override
        WHERE active
    )
    INSERT INTO classification.material_classification (
        material_id, material_family, polymer, confidence, method, classifier_version,
        reviewed, status, selected_rule_id, selected_dictionary_term_id, override_id,
        evidence_count, conflict_count
    )
    SELECT
        material.material_id,
        COALESCE(override.family_code, selected.family_code, 'unknown'),
        COALESCE(override.polymer_code, selected.polymer_code),
        CASE WHEN override.material_override_id IS NOT NULL THEN NULL
             ELSE selected.confidence END,
        CASE
            WHEN override.material_override_id IS NOT NULL THEN 'manual-override'
            WHEN selected.material_evidence_id IS NULL THEN 'no-evidence'
            ELSE selected.evidence_type
        END,
        CASE
            WHEN override.material_override_id IS NOT NULL THEN 'manual'
            WHEN selected.material_evidence_id IS NULL THEN 'rules-0.1.0'
            ELSE selected.classifier_version
        END,
        override.material_override_id IS NOT NULL,
        CASE
            WHEN override.material_override_id IS NOT NULL THEN 'overridden'
            WHEN COALESCE(summary.conflict_count, 0) > 0 THEN 'conflict'
            WHEN selected.material_evidence_id IS NULL THEN 'review'
            WHEN selected.confidence < 0.8000 THEN 'review'
            ELSE 'classified'
        END,
        CASE WHEN selected.evidence_type = 'rule' THEN selected.rule_id END,
        CASE WHEN selected.evidence_type = 'dictionary'
             THEN selected.dictionary_term_id END,
        override.material_override_id,
        COALESCE(summary.evidence_count, 0),
        COALESCE(summary.conflict_count, 0)
    FROM core.material AS material
    LEFT JOIN selected
      ON selected.material_id = material.material_id
    LEFT JOIN evidence_summary AS summary
      ON summary.material_id = material.material_id
    LEFT JOIN active_override AS override
      ON override.material_id = material.material_id;
END;
$$;

CREATE OR REPLACE VIEW classification.review_queue AS
SELECT
    classification.material_classification_id,
    material.material_id,
    material.sap_material_id,
    material.description,
    material.material_group,
    classification.material_family,
    classification.polymer,
    classification.confidence,
    classification.status,
    classification.evidence_count,
    classification.conflict_count,
    classification.created_at
FROM classification.material_classification AS classification
JOIN core.material AS material
  ON material.material_id = classification.material_id
WHERE classification.status IN ('review', 'conflict');

COMMIT;
