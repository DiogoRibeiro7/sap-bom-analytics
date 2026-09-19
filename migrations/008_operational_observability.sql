BEGIN;

CREATE TABLE audit.processing_run (
    processing_run_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pipeline_name TEXT NOT NULL,
    stage_name TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('running', 'succeeded', 'failed')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    rows_processed BIGINT CHECK (rows_processed IS NULL OR rows_processed >= 0),
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    error_message TEXT,
    CHECK (
        (status = 'running' AND completed_at IS NULL)
        OR
        (status IN ('succeeded', 'failed') AND completed_at IS NOT NULL)
    )
);

CREATE INDEX idx_processing_run_pipeline_started
    ON audit.processing_run (pipeline_name, started_at DESC);
CREATE INDEX idx_processing_run_status
    ON audit.processing_run (status, started_at DESC);

CREATE OR REPLACE VIEW analytics.processing_run_metrics AS
SELECT
    processing_run_id,
    pipeline_name,
    stage_name,
    status,
    started_at,
    completed_at,
    CASE
        WHEN completed_at IS NOT NULL
        THEN ROUND(EXTRACT(EPOCH FROM (completed_at - started_at)) * 1000, 3)
    END AS duration_ms,
    rows_processed,
    metadata,
    error_message
FROM audit.processing_run;

CREATE OR REPLACE VIEW analytics.processing_stage_summary AS
SELECT
    pipeline_name,
    stage_name,
    COUNT(*) AS run_count,
    COUNT(*) FILTER (WHERE status = 'succeeded') AS succeeded_count,
    COUNT(*) FILTER (WHERE status = 'failed') AS failed_count,
    ROUND(
        AVG(EXTRACT(EPOCH FROM (completed_at - started_at)) * 1000)
            FILTER (WHERE completed_at IS NOT NULL),
        3
    ) AS mean_duration_ms,
    ROUND(
        MAX(EXTRACT(EPOCH FROM (completed_at - started_at)) * 1000)
            FILTER (WHERE completed_at IS NOT NULL),
        3
    ) AS max_duration_ms,
    MAX(started_at) AS latest_started_at
FROM audit.processing_run
GROUP BY pipeline_name, stage_name;

COMMIT;
