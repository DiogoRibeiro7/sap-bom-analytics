BEGIN;

ALTER TABLE raw.stpo
    ADD COLUMN postp TEXT,
    ADD COLUMN lkenz TEXT,
    ADD COLUMN fmeng TEXT,
    ADD COLUMN ausch TEXT,
    ADD COLUMN netau TEXT;

ALTER TABLE staging.bom_component
    ADD COLUMN item_category TEXT,
    ADD COLUMN is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN is_fixed_quantity BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN component_scrap_percent NUMERIC(12, 6),
    ADD COLUMN net_scrap_indicator BOOLEAN NOT NULL DEFAULT FALSE,
    ADD CONSTRAINT chk_staging_component_scrap_nonnegative
        CHECK (component_scrap_percent IS NULL OR component_scrap_percent >= 0);

ALTER TABLE core.bom_component
    ADD COLUMN item_category TEXT,
    ADD COLUMN is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN is_fixed_quantity BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN component_scrap_percent NUMERIC(12, 6),
    ADD COLUMN net_scrap_indicator BOOLEAN NOT NULL DEFAULT FALSE,
    ADD CONSTRAINT chk_core_component_scrap_nonnegative
        CHECK (component_scrap_percent IS NULL OR component_scrap_percent >= 0);

DROP FUNCTION IF EXISTS core.explode_bom(BIGINT, DATE, TEXT);

CREATE FUNCTION core.explode_bom(
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
        (
            COALESCE(bc.quantity_base_unit, bc.quantity)
            * (1 + COALESCE(bc.component_scrap_percent, 0) / 100)
        )::NUMERIC AS direct_quantity,
        CASE
            WHEN bc.is_fixed_quantity THEN (
                COALESCE(bc.quantity_base_unit, bc.quantity)
                * (1 + COALESCE(bc.component_scrap_percent, 0) / 100)
            )::NUMERIC
            ELSE (
                COALESCE(bc.quantity_base_unit, bc.quantity)
                * (1 + COALESCE(bc.component_scrap_percent, 0) / 100)
                / NULLIF(COALESCE(bv.base_quantity, 1), 0)
            )::NUMERIC
        END AS cumulative_quantity,
        COALESCE(bc.base_unit, bc.unit) AS unit,
        ARRAY[b.parent_material_id, bc.component_material_id]::BIGINT[] AS material_path,
        bc.component_material_id = b.parent_material_id AS cycle_detected
    FROM core.bom AS b
    JOIN core.bom_version AS bv
      ON bv.bom_id = b.bom_id
    JOIN core.bom_component AS bc
      ON bc.bom_version_id = bv.bom_version_id
    WHERE b.parent_material_id = root_material_id
      AND NOT bc.is_deleted
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
        (
            COALESCE(bc.quantity_base_unit, bc.quantity)
            * (1 + COALESCE(bc.component_scrap_percent, 0) / 100)
        )::NUMERIC,
        CASE
            WHEN bc.is_fixed_quantity THEN (
                COALESCE(bc.quantity_base_unit, bc.quantity)
                * (1 + COALESCE(bc.component_scrap_percent, 0) / 100)
            )::NUMERIC
            ELSE (
                parent.cumulative_quantity
                * COALESCE(bc.quantity_base_unit, bc.quantity)
                * (1 + COALESCE(bc.component_scrap_percent, 0) / 100)
                / NULLIF(COALESCE(bv.base_quantity, 1), 0)
            )::NUMERIC
        END,
        COALESCE(bc.base_unit, bc.unit),
        parent.material_path || bc.component_material_id,
        bc.component_material_id = ANY(parent.material_path)
    FROM explosion AS parent
    JOIN core.bom AS b
      ON b.parent_material_id = parent.component_material_id
    JOIN core.bom_version AS bv
      ON bv.bom_id = b.bom_id
    JOIN core.bom_component AS bc
      ON bc.bom_version_id = bv.bom_version_id
    WHERE NOT parent.cycle_detected
      AND NOT bc.is_deleted
      AND (plant_filter IS NULL OR b.plant = plant_filter)
      AND bv.valid_from <= as_of_date
      AND (bv.valid_to IS NULL OR bv.valid_to >= as_of_date)
)
SELECT * FROM explosion;
$$;

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
    component.source_staging_bom_component_id,
    component.item_category,
    component.is_deleted,
    component.is_fixed_quantity,
    component.component_scrap_percent,
    component.net_scrap_indicator
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

COMMIT;
