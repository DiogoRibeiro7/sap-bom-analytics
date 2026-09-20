BEGIN;

TRUNCATE TABLE
    staging.bom_component,
    staging.bom_header,
    staging.unit_conversion,
    staging.plant,
    staging.material,
    staging.data_quality_issue
RESTART IDENTITY CASCADE;

WITH ranked_descriptions AS (
    SELECT
        raw_makt_id,
        ingestion_run_id,
        matnr,
        spras,
        maktx,
        ROW_NUMBER() OVER (
            PARTITION BY ingestion_run_id, matnr
            ORDER BY
                CASE WHEN spras IN ('E', 'EN') THEN 0 ELSE 1 END,
                raw_makt_id DESC
        ) AS rank_order
    FROM raw.makt
),
latest_mara AS (
    SELECT DISTINCT ON (matnr)
        *
    FROM raw.mara
    ORDER BY matnr, raw_mara_id DESC
),
latest_description AS (
    SELECT DISTINCT ON (matnr)
        raw_makt_id, ingestion_run_id, matnr, spras, maktx
    FROM ranked_descriptions
    WHERE rank_order = 1
    ORDER BY matnr, raw_makt_id DESC
)
INSERT INTO staging.material (
    source_system, sap_material_id, normalized_material_id, material_type,
    material_group, base_unit, gross_weight, net_weight, weight_unit,
    description, description_language, source_mara_id, source_makt_id, ingestion_run_id
)
SELECT
    'SAP',
    mara.matnr,
    upper(trim(mara.matnr)),
    nullif(trim(mara.mtart), ''),
    nullif(trim(mara.matkl), ''),
    upper(nullif(trim(mara.meins), '')),
    CASE WHEN trim(coalesce(mara.brgew, '')) ~ '^[+-]?[0-9]+([.][0-9]+)?$'
         THEN trim(mara.brgew)::NUMERIC END,
    CASE WHEN trim(coalesce(mara.ntgew, '')) ~ '^[+-]?[0-9]+([.][0-9]+)?$'
         THEN trim(mara.ntgew)::NUMERIC END,
    upper(nullif(trim(mara.gewei), '')),
    nullif(trim(descr.maktx), ''),
    nullif(trim(descr.spras), ''),
    mara.raw_mara_id,
    descr.raw_makt_id,
    mara.ingestion_run_id
FROM latest_mara AS mara
LEFT JOIN latest_description AS descr
  ON descr.matnr = mara.matnr;

WITH latest_marm AS (
    SELECT DISTINCT ON (matnr, meinh)
        *
    FROM raw.marm
    ORDER BY matnr, meinh, raw_marm_id DESC
)
INSERT INTO staging.unit_conversion (
    sap_material_id, normalized_material_id, alternative_unit,
    numerator, denominator, conversion_factor, source_marm_id, ingestion_run_id
)
SELECT
    matnr,
    upper(trim(matnr)),
    upper(trim(meinh)),
    CASE WHEN trim(coalesce(umrez, '')) ~ '^[0-9]+([.][0-9]+)?$'
         THEN trim(umrez)::NUMERIC END,
    CASE WHEN trim(coalesce(umren, '')) ~ '^[0-9]+([.][0-9]+)?$'
         THEN trim(umren)::NUMERIC END,
    CASE
        WHEN trim(coalesce(umrez, '')) ~ '^[0-9]+([.][0-9]+)?$'
         AND trim(coalesce(umren, '')) ~ '^[0-9]+([.][0-9]+)?$'
         AND trim(umren)::NUMERIC <> 0
        THEN trim(umrez)::NUMERIC / trim(umren)::NUMERIC
    END,
    raw_marm_id,
    ingestion_run_id
FROM latest_marm;

WITH latest_plant AS (
    SELECT DISTINCT ON (werks)
        *
    FROM raw.t001w
    ORDER BY werks, raw_t001w_id DESC
)
INSERT INTO staging.plant (
    plant_code, normalized_plant_code, plant_name, valuation_area, country_code,
    source_t001w_id, ingestion_run_id
)
SELECT
    werks, upper(trim(werks)), nullif(trim(name1), ''),
    nullif(trim(bwkey), ''), upper(nullif(trim(land1), '')),
    raw_t001w_id, ingestion_run_id
FROM latest_plant;

WITH latest_mast AS (
    SELECT DISTINCT ON (matnr, werks, stlan, stlnr, coalesce(stlal, ''))
        *
    FROM raw.mast
    ORDER BY matnr, werks, stlan, stlnr, coalesce(stlal, ''), raw_mast_id DESC
),
latest_stko AS (
    SELECT DISTINCT ON (stlnr, coalesce(stlal, ''))
        *
    FROM raw.stko
    ORDER BY stlnr, coalesce(stlal, ''), raw_stko_id DESC
)
INSERT INTO staging.bom_header (
    parent_material_id, normalized_parent_material_id, plant_code, bom_usage,
    bom_number, bom_alternative, bom_category, header_counter, valid_from,
    change_number, base_quantity, base_unit, source_mast_id, source_stko_id,
    ingestion_run_id
)
SELECT
    mast.matnr,
    upper(trim(mast.matnr)),
    upper(trim(mast.werks)),
    trim(mast.stlan),
    mast.stlnr,
    nullif(trim(mast.stlal), ''),
    nullif(trim(stko.stlty), ''),
    nullif(trim(stko.stkoz), ''),
    CASE
        WHEN trim(coalesce(stko.datuv, '')) ~ '^[0-9]{8}$'
        THEN to_date(trim(stko.datuv), 'YYYYMMDD')
    END,
    nullif(trim(stko.aennr), ''),
    CASE WHEN trim(coalesce(stko.bmeng, '')) ~ '^[+-]?[0-9]+([.][0-9]+)?$'
         THEN trim(stko.bmeng)::NUMERIC END,
    upper(nullif(trim(stko.bmein), '')),
    mast.raw_mast_id,
    stko.raw_stko_id,
    mast.ingestion_run_id
FROM latest_mast AS mast
LEFT JOIN latest_stko AS stko
  ON stko.stlnr = mast.stlnr
 AND coalesce(stko.stlal, '') = coalesce(mast.stlal, '');

WITH latest_stpo AS (
    SELECT DISTINCT ON (stlnr, coalesce(stlkn, ''), coalesce(stpoz, ''), idnrk)
        *
    FROM raw.stpo
    ORDER BY stlnr, coalesce(stlkn, ''), coalesce(stpoz, ''), idnrk, raw_stpo_id DESC
)
INSERT INTO staging.bom_component (
    bom_number, bom_alternative, parent_material_id, normalized_parent_material_id,
    component_material_id, normalized_component_material_id, item_number,
    item_node, item_counter, quantity, unit, valid_from, change_number,
    item_category, is_deleted, is_fixed_quantity, component_scrap_percent,
    net_scrap_indicator, plant_code, bom_usage, source_mast_id, source_stpo_id,
    ingestion_run_id
)
SELECT
    header.bom_number,
    header.bom_alternative,
    header.parent_material_id,
    header.normalized_parent_material_id,
    stpo.idnrk,
    upper(trim(stpo.idnrk)),
    nullif(trim(stpo.posnr), ''),
    nullif(trim(stpo.stlkn), ''),
    nullif(trim(stpo.stpoz), ''),
    CASE WHEN trim(coalesce(stpo.menge, '')) ~ '^[+-]?[0-9]+([.][0-9]+)?$'
         THEN trim(stpo.menge)::NUMERIC END,
    upper(nullif(trim(stpo.meins), '')),
    CASE
        WHEN trim(coalesce(stpo.datuv, '')) ~ '^[0-9]{8}$'
        THEN to_date(trim(stpo.datuv), 'YYYYMMDD')
    END,
    nullif(trim(stpo.aennr), ''),
    nullif(trim(stpo.postp), ''),
    upper(trim(coalesce(stpo.lkenz, ''))) = 'X',
    upper(trim(coalesce(stpo.fmeng, ''))) = 'X',
    CASE
        WHEN trim(coalesce(stpo.ausch, '')) ~ '^[+-]?[0-9]+([.][0-9]+)?
    header.bom_usage,
    header.source_mast_id,
    stpo.raw_stpo_id,
    header.ingestion_run_id
FROM staging.bom_header AS header
JOIN latest_stpo AS stpo
  ON stpo.stlnr = header.bom_number;

INSERT INTO staging.data_quality_issue (
    issue_type, severity, entity_type, entity_key, details, ingestion_run_id
)
SELECT
    'missing_material_master',
    'error',
    'bom_component',
    component_material_id,
    jsonb_build_object(
        'bom_number', bom_number,
        'parent_material_id', parent_material_id,
        'component_material_id', component_material_id
    ),
    ingestion_run_id
FROM staging.bom_component AS component
WHERE NOT EXISTS (
    SELECT 1
    FROM staging.material AS material
    WHERE material.normalized_material_id = component.normalized_component_material_id
);

INSERT INTO staging.data_quality_issue (
    issue_type, severity, entity_type, entity_key, details, ingestion_run_id
)
SELECT
    'missing_bom_header',
    'error',
    'bom_header',
    bom_number,
    jsonb_build_object(
        'parent_material_id', parent_material_id,
        'bom_number', bom_number,
        'bom_alternative', bom_alternative
    ),
    ingestion_run_id
FROM staging.bom_header
WHERE source_stko_id IS NULL;

INSERT INTO staging.data_quality_issue (
    issue_type, severity, entity_type, entity_key, details, ingestion_run_id
)
SELECT
    'invalid_unit_conversion',
    'warning',
    'material',
    sap_material_id,
    jsonb_build_object(
        'alternative_unit', alternative_unit,
        'numerator', numerator,
        'denominator', denominator
    ),
    ingestion_run_id
FROM staging.unit_conversion
WHERE conversion_factor IS NULL;

COMMIT;

        THEN trim(stpo.ausch)::NUMERIC
    END,
    upper(trim(coalesce(stpo.netau, ''))) = 'X',
    header.plant_code,
    header.bom_usage,
    header.source_mast_id,
    stpo.raw_stpo_id,
    header.ingestion_run_id
FROM staging.bom_header AS header
JOIN latest_stpo AS stpo
  ON stpo.stlnr = header.bom_number;

INSERT INTO staging.data_quality_issue (
    issue_type, severity, entity_type, entity_key, details, ingestion_run_id
)
SELECT
    'missing_material_master',
    'error',
    'bom_component',
    component_material_id,
    jsonb_build_object(
        'bom_number', bom_number,
        'parent_material_id', parent_material_id,
        'component_material_id', component_material_id
    ),
    ingestion_run_id
FROM staging.bom_component AS component
WHERE NOT EXISTS (
    SELECT 1
    FROM staging.material AS material
    WHERE material.normalized_material_id = component.normalized_component_material_id
);

INSERT INTO staging.data_quality_issue (
    issue_type, severity, entity_type, entity_key, details, ingestion_run_id
)
SELECT
    'missing_bom_header',
    'error',
    'bom_header',
    bom_number,
    jsonb_build_object(
        'parent_material_id', parent_material_id,
        'bom_number', bom_number,
        'bom_alternative', bom_alternative
    ),
    ingestion_run_id
FROM staging.bom_header
WHERE source_stko_id IS NULL;

INSERT INTO staging.data_quality_issue (
    issue_type, severity, entity_type, entity_key, details, ingestion_run_id
)
SELECT
    'invalid_unit_conversion',
    'warning',
    'material',
    sap_material_id,
    jsonb_build_object(
        'alternative_unit', alternative_unit,
        'numerator', numerator,
        'denominator', denominator
    ),
    ingestion_run_id
FROM staging.unit_conversion
WHERE conversion_factor IS NULL;

COMMIT;
