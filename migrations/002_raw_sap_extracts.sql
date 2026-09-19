BEGIN;

CREATE TABLE raw.mara (
    raw_mara_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    source_file TEXT NOT NULL,
    source_row_number BIGINT NOT NULL CHECK (source_row_number > 1),
    matnr TEXT NOT NULL,
    mtart TEXT,
    matkl TEXT,
    meins TEXT,
    brgew TEXT,
    ntgew TEXT,
    gewei TEXT,
    raw_payload JSONB NOT NULL,
    UNIQUE (ingestion_run_id, source_file, source_row_number)
);

CREATE TABLE raw.makt (
    raw_makt_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    source_file TEXT NOT NULL,
    source_row_number BIGINT NOT NULL CHECK (source_row_number > 1),
    matnr TEXT NOT NULL,
    spras TEXT NOT NULL,
    maktx TEXT,
    maktg TEXT,
    raw_payload JSONB NOT NULL,
    UNIQUE (ingestion_run_id, source_file, source_row_number)
);

CREATE TABLE raw.mast (
    raw_mast_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    source_file TEXT NOT NULL,
    source_row_number BIGINT NOT NULL CHECK (source_row_number > 1),
    matnr TEXT NOT NULL,
    werks TEXT NOT NULL,
    stlan TEXT NOT NULL,
    stlnr TEXT NOT NULL,
    stlal TEXT,
    raw_payload JSONB NOT NULL,
    UNIQUE (ingestion_run_id, source_file, source_row_number)
);

CREATE TABLE raw.stko (
    raw_stko_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    source_file TEXT NOT NULL,
    source_row_number BIGINT NOT NULL CHECK (source_row_number > 1),
    stlty TEXT NOT NULL,
    stlnr TEXT NOT NULL,
    stlal TEXT,
    stkoz TEXT,
    datuv TEXT,
    aennr TEXT,
    bmeng TEXT,
    bmein TEXT,
    raw_payload JSONB NOT NULL,
    UNIQUE (ingestion_run_id, source_file, source_row_number)
);

CREATE TABLE raw.stpo (
    raw_stpo_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    source_file TEXT NOT NULL,
    source_row_number BIGINT NOT NULL CHECK (source_row_number > 1),
    stlty TEXT NOT NULL,
    stlnr TEXT NOT NULL,
    stlkn TEXT,
    stpoz TEXT,
    posnr TEXT,
    idnrk TEXT NOT NULL,
    menge TEXT,
    meins TEXT,
    datuv TEXT,
    aennr TEXT,
    raw_payload JSONB NOT NULL,
    UNIQUE (ingestion_run_id, source_file, source_row_number)
);

CREATE TABLE raw.marm (
    raw_marm_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    source_file TEXT NOT NULL,
    source_row_number BIGINT NOT NULL CHECK (source_row_number > 1),
    matnr TEXT NOT NULL,
    meinh TEXT NOT NULL,
    umrez TEXT,
    umren TEXT,
    ean11 TEXT,
    raw_payload JSONB NOT NULL,
    UNIQUE (ingestion_run_id, source_file, source_row_number)
);

CREATE TABLE raw.t001w (
    raw_t001w_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    source_file TEXT NOT NULL,
    source_row_number BIGINT NOT NULL CHECK (source_row_number > 1),
    werks TEXT NOT NULL,
    name1 TEXT,
    bwkey TEXT,
    land1 TEXT,
    raw_payload JSONB NOT NULL,
    UNIQUE (ingestion_run_id, source_file, source_row_number)
);

CREATE INDEX idx_raw_mara_matnr ON raw.mara (matnr);
CREATE INDEX idx_raw_makt_matnr_spras ON raw.makt (matnr, spras);
CREATE INDEX idx_raw_mast_material_plant ON raw.mast (matnr, werks);
CREATE INDEX idx_raw_mast_bom ON raw.mast (stlnr);
CREATE INDEX idx_raw_stko_bom ON raw.stko (stlnr, stlal);
CREATE INDEX idx_raw_stpo_bom ON raw.stpo (stlnr);
CREATE INDEX idx_raw_stpo_component ON raw.stpo (idnrk);
CREATE INDEX idx_raw_marm_material ON raw.marm (matnr);
CREATE INDEX idx_raw_t001w_plant ON raw.t001w (werks);

COMMIT;
