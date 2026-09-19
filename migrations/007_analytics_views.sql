BEGIN;

CREATE SCHEMA IF NOT EXISTS analytics;

CREATE OR REPLACE VIEW analytics.material_summary AS
SELECT
    material.material_id,
    material.sap_material_id,
    material.description,
    material.material_group,
    material.material_type,
    material.base_unit,
    material.net_weight,
    material.gross_weight,
    material.weight_unit,
    classification.material_family,
    classification.polymer,
    classification.status AS classification_status,
    classification.confidence AS classification_confidence,
    profile.is_packaging,
    profile.status AS packaging_status,
    profile.confidence AS packaging_confidence,
    material.source_system,
    material.ingestion_run_id,
    material.source_staging_material_id
FROM core.material AS material
LEFT JOIN classification.material_classification AS classification
  ON classification.material_id = material.material_id
LEFT JOIN packaging.material_profile AS profile
  ON profile.material_id = material.material_id;

CREATE OR REPLACE VIEW analytics.bom_summary AS
SELECT
    bom.bom_id,
    bom.sap_bom_id,
    parent.sap_material_id AS parent_sap_material_id,
    parent.description AS parent_description,
    bom.plant,
    bom.usage_code,
    COUNT(DISTINCT version.bom_version_id) AS version_count,
    COUNT(component.bom_component_id) AS component_row_count,
    MIN(version.valid_from) AS first_valid_from,
    MAX(version.valid_to) AS last_valid_to
FROM core.bom AS bom
JOIN core.material AS parent
  ON parent.material_id = bom.parent_material_id
LEFT JOIN core.bom_version AS version
  ON version.bom_id = bom.bom_id
LEFT JOIN core.bom_component AS component
  ON component.bom_version_id = version.bom_version_id
GROUP BY
    bom.bom_id, bom.sap_bom_id, parent.sap_material_id,
    parent.description, bom.plant, bom.usage_code;

CREATE OR REPLACE VIEW analytics.bom_component_detail AS
SELECT
    bom.bom_id,
    bom.sap_bom_id,
    version.bom_version_id,
    version.alternative,
    version.revision,
    version.valid_from,
    version.valid_to,
    parent.material_id AS parent_material_id,
    parent.sap_material_id AS parent_sap_material_id,
    parent.description AS parent_description,
    component.bom_component_id,
    component.item_number,
    child.material_id AS component_material_id,
    child.sap_material_id AS component_sap_material_id,
    child.description AS component_description,
    component.quantity,
    component.unit,
    component.quantity_base_unit,
    component.base_unit,
    classification.material_family,
    classification.polymer,
    classification.status AS classification_status,
    profile.is_packaging,
    profile.status AS packaging_status,
    bom.plant,
    bom.usage_code,
    component.source_record_id,
    component.source_staging_bom_component_id
FROM core.bom AS bom
JOIN core.material AS parent
  ON parent.material_id = bom.parent_material_id
JOIN core.bom_version AS version
  ON version.bom_id = bom.bom_id
JOIN core.bom_component AS component
  ON component.bom_version_id = version.bom_version_id
JOIN core.material AS child
  ON child.material_id = component.component_material_id
LEFT JOIN classification.material_classification AS classification
  ON classification.material_id = child.material_id
LEFT JOIN packaging.material_profile AS profile
  ON profile.material_id = child.material_id;

CREATE OR REPLACE VIEW analytics.ingestion_run_summary AS
SELECT
    run.ingestion_run_id,
    run.source_system,
    run.source_reference,
    run.source_sha256,
    run.status,
    run.started_at,
    run.completed_at,
    COALESCE(mara.row_count, 0)
      + COALESCE(makt.row_count, 0)
      + COALESCE(mast.row_count, 0)
      + COALESCE(stko.row_count, 0)
      + COALESCE(stpo.row_count, 0)
      + COALESCE(marm.row_count, 0)
      + COALESCE(t001w.row_count, 0) AS raw_row_count
FROM audit.ingestion_run AS run
LEFT JOIN (SELECT ingestion_run_id, COUNT(*) AS row_count FROM raw.mara GROUP BY ingestion_run_id) mara
  USING (ingestion_run_id)
LEFT JOIN (SELECT ingestion_run_id, COUNT(*) AS row_count FROM raw.makt GROUP BY ingestion_run_id) makt
  USING (ingestion_run_id)
LEFT JOIN (SELECT ingestion_run_id, COUNT(*) AS row_count FROM raw.mast GROUP BY ingestion_run_id) mast
  USING (ingestion_run_id)
LEFT JOIN (SELECT ingestion_run_id, COUNT(*) AS row_count FROM raw.stko GROUP BY ingestion_run_id) stko
  USING (ingestion_run_id)
LEFT JOIN (SELECT ingestion_run_id, COUNT(*) AS row_count FROM raw.stpo GROUP BY ingestion_run_id) stpo
  USING (ingestion_run_id)
LEFT JOIN (SELECT ingestion_run_id, COUNT(*) AS row_count FROM raw.marm GROUP BY ingestion_run_id) marm
  USING (ingestion_run_id)
LEFT JOIN (SELECT ingestion_run_id, COUNT(*) AS row_count FROM raw.t001w GROUP BY ingestion_run_id) t001w
  USING (ingestion_run_id);

CREATE OR REPLACE VIEW analytics.product_assessment_summary AS
SELECT
    run.assessment_run_id,
    root.sap_material_id AS root_sap_material_id,
    root.description AS root_description,
    run.as_of_date,
    run.plant,
    run.status AS assessment_status,
    COUNT(component.component_assessment_id) AS component_count,
    COUNT(*) FILTER (WHERE component.assessment_status = 'review') AS review_count,
    COALESCE(SUM(component.component_weight_kg), 0) AS packaging_weight_kg,
    COALESCE(SUM(component.plastic_weight_kg), 0) AS plastic_weight_kg,
    COALESCE(SUM(component.recycled_plastic_weight_kg), 0)
        AS recycled_plastic_weight_kg,
    CASE
        WHEN COALESCE(SUM(component.plastic_weight_kg), 0) > 0
        THEN COALESCE(SUM(component.recycled_plastic_weight_kg), 0)
             / SUM(component.plastic_weight_kg)
    END AS recycled_fraction,
    run.created_at,
    run.completed_at
FROM packaging.assessment_run AS run
JOIN core.material AS root
  ON root.material_id = run.root_material_id
LEFT JOIN packaging.component_assessment AS component
  ON component.assessment_run_id = run.assessment_run_id
GROUP BY
    run.assessment_run_id, root.sap_material_id, root.description,
    run.as_of_date, run.plant, run.status, run.created_at, run.completed_at;

CREATE OR REPLACE VIEW analytics.data_quality_dashboard AS
SELECT
    'staging'::TEXT AS quality_layer,
    issue.severity,
    issue.issue_type,
    issue.entity_type,
    issue.entity_key,
    issue.details,
    issue.ingestion_run_id,
    issue.detected_at AS observed_at
FROM staging.data_quality_issue AS issue

UNION ALL

SELECT
    'classification',
    CASE WHEN queue.status = 'conflict' THEN 'error' ELSE 'warning' END,
    'material_' || queue.status,
    'material',
    queue.sap_material_id,
    jsonb_build_object(
        'description', queue.description,
        'material_family', queue.material_family,
        'polymer', queue.polymer,
        'confidence', queue.confidence,
        'evidence_count', queue.evidence_count,
        'conflict_count', queue.conflict_count
    ),
    material.ingestion_run_id,
    queue.created_at
FROM classification.review_queue AS queue
JOIN core.material AS material
  ON material.material_id = queue.material_id

UNION ALL

SELECT
    'packaging',
    CASE WHEN profile.status = 'conflict' THEN 'error' ELSE 'warning' END,
    'packaging_' || profile.status,
    'material',
    material.sap_material_id,
    jsonb_build_object(
        'description', material.description,
        'is_packaging', profile.is_packaging,
        'confidence', profile.confidence,
        'evidence_count', profile.evidence_count,
        'conflict_count', profile.conflict_count
    ),
    material.ingestion_run_id,
    profile.refreshed_at
FROM packaging.material_profile AS profile
JOIN core.material AS material
  ON material.material_id = profile.material_id
WHERE profile.status IN ('review', 'conflict');

CREATE OR REPLACE VIEW analytics.quality_scorecard AS
SELECT
    quality_layer,
    severity,
    issue_type,
    COUNT(*) AS issue_count,
    MAX(observed_at) AS latest_observed_at
FROM analytics.data_quality_dashboard
GROUP BY quality_layer, severity, issue_type;

COMMIT;
