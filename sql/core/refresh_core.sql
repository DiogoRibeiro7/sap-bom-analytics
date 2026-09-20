BEGIN;

TRUNCATE TABLE
    tax.assessment,
    packaging.component_assessment,
    packaging.assessment_run,
    packaging.recycled_content_evidence,
    packaging.material_profile,
    packaging.scope_evidence,
    packaging.scope_override,
    classification.material_evidence,
    classification.material_classification,
    classification.material_override,
    core.bom_component,
    core.bom_version,
    core.bom,
    core.material
RESTART IDENTITY;

INSERT INTO core.material (
    source_system, sap_material_id, description, material_group, material_type, base_unit,
    gross_weight, net_weight, weight_unit, valid_from, valid_to, ingestion_run_id,
    source_staging_material_id
)
SELECT
    source_system,
    sap_material_id,
    description,
    material_group,
    material_type,
    base_unit,
    gross_weight,
    net_weight,
    weight_unit,
    DATE '1900-01-01',
    NULL,
    ingestion_run_id,
    staging_material_id
FROM staging.material;

INSERT INTO core.bom (
    source_system, sap_bom_id, parent_material_id, plant, usage_code,
    ingestion_run_id, source_staging_bom_header_id
)
SELECT DISTINCT ON (
    header.bom_number, parent.material_id, header.plant_code, header.bom_usage
)
    'SAP',
    header.bom_number,
    parent.material_id,
    header.plant_code,
    header.bom_usage,
    header.ingestion_run_id,
    header.staging_bom_header_id
FROM staging.bom_header AS header
JOIN core.material AS parent
  ON parent.sap_material_id = header.parent_material_id
ORDER BY
    header.bom_number, parent.material_id, header.plant_code, header.bom_usage,
    header.staging_bom_header_id DESC;

INSERT INTO core.bom_version (
    bom_id, alternative, revision, valid_from, valid_to, ingestion_run_id,
    base_quantity, base_unit, source_staging_bom_header_id
)
SELECT
    bom.bom_id,
    header.bom_alternative,
    COALESCE(header.header_counter, header.change_number, '0'),
    COALESCE(header.valid_from, DATE '1900-01-01'),
    NULL,
    header.ingestion_run_id,
    COALESCE(header.base_quantity, 1),
    header.base_unit,
    header.staging_bom_header_id
FROM staging.bom_header AS header
JOIN core.material AS parent
  ON parent.sap_material_id = header.parent_material_id
JOIN core.bom AS bom
  ON bom.sap_bom_id = header.bom_number
 AND bom.parent_material_id = parent.material_id
 AND bom.plant = header.plant_code
 AND bom.usage_code = header.bom_usage;

WITH version_ranges AS (
    SELECT
        bom_version_id,
        LEAD(valid_from) OVER (
            PARTITION BY bom_id, COALESCE(alternative, '')
            ORDER BY valid_from, bom_version_id
        ) AS next_valid_from
    FROM core.bom_version
)
UPDATE core.bom_version AS version
SET valid_to = ranges.next_valid_from - 1
FROM version_ranges AS ranges
WHERE ranges.bom_version_id = version.bom_version_id
  AND ranges.next_valid_from IS NOT NULL;

INSERT INTO core.bom_component (
    bom_version_id, component_material_id, item_number, quantity, unit,
    source_record_id, ingestion_run_id, quantity_base_unit, base_unit,
    source_staging_bom_component_id, item_category, is_deleted,
    is_fixed_quantity, component_scrap_percent, net_scrap_indicator
)
SELECT
    version.bom_version_id,
    component_material.material_id,
    staged.item_number,
    COALESCE(staged.quantity, 0),
    COALESCE(staged.unit, component_material.base_unit, 'EA'),
    'raw.stpo:' || staged.source_stpo_id::TEXT,
    staged.ingestion_run_id,
    CASE
        WHEN staged.unit IS NULL
          OR component_material.base_unit IS NULL
          OR upper(staged.unit) = upper(component_material.base_unit)
        THEN staged.quantity
        ELSE staged.quantity * conversion.conversion_factor
    END,
    component_material.base_unit,
    staged.staging_bom_component_id,
    staged.item_category,
    staged.is_deleted,
    staged.is_fixed_quantity,
    staged.component_scrap_percent,
    staged.net_scrap_indicator
FROM staging.bom_component AS staged
JOIN core.material AS parent_material
  ON parent_material.sap_material_id = staged.parent_material_id
JOIN core.material AS component_material
  ON component_material.sap_material_id = staged.component_material_id
JOIN core.bom AS bom
  ON bom.sap_bom_id = staged.bom_number
 AND bom.parent_material_id = parent_material.material_id
 AND bom.plant = staged.plant_code
 AND bom.usage_code = staged.bom_usage
JOIN core.bom_version AS version
  ON version.bom_id = bom.bom_id
 AND COALESCE(version.alternative, '') = COALESCE(staged.bom_alternative, '')
 AND COALESCE(staged.valid_from, version.valid_from)
     BETWEEN version.valid_from AND COALESCE(version.valid_to, DATE '9999-12-31')
LEFT JOIN staging.unit_conversion AS conversion
  ON conversion.sap_material_id = staged.component_material_id
 AND upper(conversion.alternative_unit) = upper(COALESCE(staged.unit, ''))
 AND conversion.conversion_factor IS NOT NULL;

COMMIT;
