BEGIN;

ALTER TABLE audit.ingestion_run
    ADD COLUMN source_entity TEXT;

CREATE INDEX idx_ingestion_run_source_entity_hash
    ON audit.ingestion_run (source_system, source_entity, source_sha256, status);

CREATE UNIQUE INDEX idx_ingestion_run_successful_source_hash
    ON audit.ingestion_run (source_system, source_entity, source_sha256)
    WHERE status = 'succeeded'
      AND source_entity IS NOT NULL
      AND source_sha256 IS NOT NULL;

CREATE OR REPLACE VIEW analytics.ingestion_run_summary AS
SELECT
    run.ingestion_run_id,
    run.source_system,
    run.source_entity,
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
LEFT JOIN (
    SELECT ingestion_run_id, COUNT(*) AS row_count
    FROM raw.mara
    GROUP BY ingestion_run_id
) mara USING (ingestion_run_id)
LEFT JOIN (
    SELECT ingestion_run_id, COUNT(*) AS row_count
    FROM raw.makt
    GROUP BY ingestion_run_id
) makt USING (ingestion_run_id)
LEFT JOIN (
    SELECT ingestion_run_id, COUNT(*) AS row_count
    FROM raw.mast
    GROUP BY ingestion_run_id
) mast USING (ingestion_run_id)
LEFT JOIN (
    SELECT ingestion_run_id, COUNT(*) AS row_count
    FROM raw.stko
    GROUP BY ingestion_run_id
) stko USING (ingestion_run_id)
LEFT JOIN (
    SELECT ingestion_run_id, COUNT(*) AS row_count
    FROM raw.stpo
    GROUP BY ingestion_run_id
) stpo USING (ingestion_run_id)
LEFT JOIN (
    SELECT ingestion_run_id, COUNT(*) AS row_count
    FROM raw.marm
    GROUP BY ingestion_run_id
) marm USING (ingestion_run_id)
LEFT JOIN (
    SELECT ingestion_run_id, COUNT(*) AS row_count
    FROM raw.t001w
    GROUP BY ingestion_run_id
) t001w USING (ingestion_run_id);

COMMIT;
