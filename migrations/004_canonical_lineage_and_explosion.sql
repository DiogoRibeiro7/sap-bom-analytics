BEGIN;

ALTER TABLE core.material
    ADD COLUMN source_staging_material_id BIGINT
        REFERENCES staging.material(staging_material_id);

ALTER TABLE core.bom
    ADD COLUMN source_staging_bom_header_id BIGINT
        REFERENCES staging.bom_header(staging_bom_header_id);

ALTER TABLE core.bom_version
    ADD COLUMN base_quantity NUMERIC(20, 8),
    ADD COLUMN base_unit TEXT,
    ADD COLUMN source_staging_bom_header_id BIGINT
        REFERENCES staging.bom_header(staging_bom_header_id);

ALTER TABLE core.bom_component
    ADD COLUMN quantity_base_unit NUMERIC(20, 8),
    ADD COLUMN base_unit TEXT,
    ADD COLUMN source_staging_bom_component_id BIGINT
        REFERENCES staging.bom_component(staging_bom_component_id);

CREATE INDEX idx_core_material_source_staging
    ON core.material (source_staging_material_id);
CREATE INDEX idx_core_bom_source_staging
    ON core.bom (source_staging_bom_header_id);
CREATE INDEX idx_core_bom_version_validity
    ON core.bom_version (valid_from, valid_to);

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
        bc.quantity AS direct_quantity,
        (bc.quantity / NULLIF(COALESCE(bv.base_quantity, 1), 0))::NUMERIC
            AS cumulative_quantity,
        bc.unit,
        ARRAY[b.parent_material_id, bc.component_material_id]::BIGINT[]
            AS material_path,
        bc.component_material_id = b.parent_material_id AS cycle_detected
    FROM core.bom AS b
    JOIN core.bom_version AS bv
      ON bv.bom_id = b.bom_id
    JOIN core.bom_component AS bc
      ON bc.bom_version_id = bv.bom_version_id
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
        bc.quantity,
        (
            parent.cumulative_quantity
            * bc.quantity
            / NULLIF(COALESCE(bv.base_quantity, 1), 0)
        )::NUMERIC,
        bc.unit,
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
      AND (plant_filter IS NULL OR b.plant = plant_filter)
      AND bv.valid_from <= as_of_date
      AND (bv.valid_to IS NULL OR bv.valid_to >= as_of_date)
)
SELECT *
FROM explosion;
$$;

COMMIT;
