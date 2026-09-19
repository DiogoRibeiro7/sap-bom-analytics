BEGIN;

CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.schema_migration (
    version TEXT PRIMARY KEY,
    checksum TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS classification;
CREATE SCHEMA IF NOT EXISTS tax;

CREATE TABLE audit.ingestion_run (
    ingestion_run_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_system TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    source_reference TEXT,
    source_sha256 TEXT,
    status TEXT NOT NULL CHECK (status IN ('running', 'succeeded', 'failed'))
);

CREATE TABLE core.material (
    material_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_system TEXT NOT NULL,
    sap_material_id TEXT NOT NULL,
    description TEXT,
    material_group TEXT,
    base_unit TEXT,
    valid_from DATE,
    valid_to DATE,
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    UNIQUE (source_system, sap_material_id, valid_from)
);

CREATE TABLE core.bom (
    bom_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_system TEXT NOT NULL,
    sap_bom_id TEXT NOT NULL,
    parent_material_id BIGINT NOT NULL REFERENCES core.material(material_id),
    plant TEXT,
    usage_code TEXT,
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    UNIQUE (source_system, sap_bom_id, parent_material_id, plant)
);

CREATE TABLE core.bom_version (
    bom_version_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bom_id BIGINT NOT NULL REFERENCES core.bom(bom_id),
    alternative TEXT,
    revision TEXT,
    valid_from DATE NOT NULL,
    valid_to DATE,
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    CHECK (valid_to IS NULL OR valid_to >= valid_from),
    UNIQUE (bom_id, alternative, revision, valid_from)
);

CREATE TABLE core.bom_component (
    bom_component_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bom_version_id BIGINT NOT NULL REFERENCES core.bom_version(bom_version_id),
    component_material_id BIGINT NOT NULL REFERENCES core.material(material_id),
    item_number TEXT,
    quantity NUMERIC(20, 8) NOT NULL CHECK (quantity >= 0),
    unit TEXT NOT NULL,
    source_record_id TEXT,
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    UNIQUE (bom_version_id, item_number, component_material_id)
);

CREATE TABLE classification.material_classification (
    material_classification_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    material_id BIGINT NOT NULL REFERENCES core.material(material_id),
    material_family TEXT NOT NULL,
    polymer TEXT,
    confidence NUMERIC(5, 4) CHECK (
        confidence IS NULL OR (confidence >= 0 AND confidence <= 1)
    ),
    method TEXT NOT NULL,
    classifier_version TEXT NOT NULL,
    reviewed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_material_sap_id
    ON core.material (source_system, sap_material_id);

CREATE INDEX idx_bom_parent
    ON core.bom (parent_material_id);

CREATE INDEX idx_bom_component_version
    ON core.bom_component (bom_version_id);

CREATE INDEX idx_bom_component_material
    ON core.bom_component (component_material_id);

COMMIT;
