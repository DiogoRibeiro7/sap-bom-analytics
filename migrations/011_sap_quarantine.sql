BEGIN;

CREATE TABLE raw.quarantine (
    quarantine_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ingestion_run_id BIGINT NOT NULL REFERENCES audit.ingestion_run(ingestion_run_id),
    source_entity TEXT NOT NULL,
    source_file TEXT NOT NULL,
    source_row_number BIGINT NOT NULL CHECK (source_row_number > 1),
    reason_code TEXT NOT NULL,
    reason_detail TEXT NOT NULL,
    raw_payload JSONB NOT NULL,
    quarantined_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (ingestion_run_id, source_entity, source_file, source_row_number)
);

CREATE INDEX idx_raw_quarantine_run
    ON raw.quarantine (ingestion_run_id, reason_code);

CREATE OR REPLACE VIEW analytics.quarantine_summary AS
SELECT
    ingestion_run_id,
    source_entity,
    reason_code,
    COUNT(*) AS row_count,
    MIN(quarantined_at) AS first_quarantined_at,
    MAX(quarantined_at) AS last_quarantined_at
FROM raw.quarantine
GROUP BY ingestion_run_id, source_entity, reason_code;

COMMIT;
