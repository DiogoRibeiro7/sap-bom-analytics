BEGIN;

CREATE TABLE staging.material (
    staging_material_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_system TEXT NOT NULL,
    sap_material_id TEXT NOT NULL,
    normalized_material_id TEXT NOT NULL,
    material_type TEXT,
    material_group TEXT,
    base_unit TEXT,
    gross_weight NUMERIC(20, 8),
    net_weight NUMERIC(20, 8),
    weight_unit TEXT,
    description TEXT,
    description_language TEXT,
    source_mara_id BIGINT NOT NULL REFERENCES raw.mara(raw_mara_id),
    source_makt_id BIGINT REFERENCES raw.makt(raw_makt_id),
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    UNIQUE (source_system, sap_material_id, ingestion_run_id)
);

CREATE TABLE staging.unit_conversion (
    staging_unit_conversion_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sap_material_id TEXT NOT NULL,
    normalized_material_id TEXT NOT NULL,
    alternative_unit TEXT NOT NULL,
    numerator NUMERIC(20, 8),
    denominator NUMERIC(20, 8),
    conversion_factor NUMERIC(20, 12),
    source_marm_id BIGINT NOT NULL REFERENCES raw.marm(raw_marm_id),
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    UNIQUE (sap_material_id, alternative_unit, ingestion_run_id)
);

CREATE TABLE staging.plant (
    staging_plant_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plant_code TEXT NOT NULL,
    normalized_plant_code TEXT NOT NULL,
    plant_name TEXT,
    valuation_area TEXT,
    country_code TEXT,
    source_t001w_id BIGINT NOT NULL REFERENCES raw.t001w(raw_t001w_id),
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    UNIQUE (plant_code, ingestion_run_id)
);

CREATE TABLE staging.bom_header (
    staging_bom_header_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_material_id TEXT NOT NULL,
    normalized_parent_material_id TEXT NOT NULL,
    plant_code TEXT NOT NULL,
    bom_usage TEXT NOT NULL,
    bom_number TEXT NOT NULL,
    bom_alternative TEXT,
    bom_category TEXT,
    header_counter TEXT,
    valid_from DATE,
    change_number TEXT,
    base_quantity NUMERIC(20, 8),
    base_unit TEXT,
    source_mast_id BIGINT NOT NULL REFERENCES raw.mast(raw_mast_id),
    source_stko_id BIGINT REFERENCES raw.stko(raw_stko_id),
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id)
);

CREATE TABLE staging.bom_component (
    staging_bom_component_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bom_number TEXT NOT NULL,
    bom_alternative TEXT,
    parent_material_id TEXT NOT NULL,
    normalized_parent_material_id TEXT NOT NULL,
    component_material_id TEXT NOT NULL,
    normalized_component_material_id TEXT NOT NULL,
    item_number TEXT,
    item_node TEXT,
    item_counter TEXT,
    quantity NUMERIC(20, 8),
    unit TEXT,
    valid_from DATE,
    change_number TEXT,
    plant_code TEXT NOT NULL,
    bom_usage TEXT NOT NULL,
    source_mast_id BIGINT NOT NULL REFERENCES raw.mast(raw_mast_id),
    source_stpo_id BIGINT NOT NULL REFERENCES raw.stpo(raw_stpo_id),
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id)
);

CREATE TABLE staging.data_quality_issue (
    data_quality_issue_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    issue_type TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'error')),
    entity_type TEXT NOT NULL,
    entity_key TEXT NOT NULL,
    details JSONB NOT NULL,
    ingestion_run_id BIGINT,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_staging_material_normalized
    ON staging.material (normalized_material_id);
CREATE INDEX idx_staging_bom_header_parent
    ON staging.bom_header (normalized_parent_material_id);
CREATE INDEX idx_staging_bom_header_number
    ON staging.bom_header (bom_number, bom_alternative);
CREATE INDEX idx_staging_bom_component_parent
    ON staging.bom_component (normalized_parent_material_id);
CREATE INDEX idx_staging_bom_component_component
    ON staging.bom_component (normalized_component_material_id);
CREATE INDEX idx_staging_bom_component_number
    ON staging.bom_component (bom_number, bom_alternative);

COMMIT;
