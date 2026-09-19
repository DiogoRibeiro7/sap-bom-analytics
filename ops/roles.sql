-- Group roles only. A deployment DBA should grant these roles to login roles.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sap_bom_reader') THEN
        CREATE ROLE sap_bom_reader NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sap_bom_ingest') THEN
        CREATE ROLE sap_bom_ingest NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sap_bom_processor') THEN
        CREATE ROLE sap_bom_processor NOLOGIN;
    END IF;
END
$$;

REVOKE ALL ON SCHEMA
    raw, staging, core, classification, packaging, tax, analytics, audit
FROM PUBLIC;

GRANT USAGE ON SCHEMA analytics TO sap_bom_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO sap_bom_reader;

GRANT USAGE ON SCHEMA raw, audit TO sap_bom_ingest;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA raw TO sap_bom_ingest;
GRANT SELECT, INSERT, UPDATE ON audit.ingestion_run TO sap_bom_ingest;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA raw, audit TO sap_bom_ingest;

GRANT USAGE ON SCHEMA
    raw, staging, core, classification, packaging, tax, analytics, audit
TO sap_bom_processor;
GRANT SELECT ON ALL TABLES IN SCHEMA raw TO sap_bom_processor;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
    ON ALL TABLES IN SCHEMA staging, core, classification, packaging, tax, audit
TO sap_bom_processor;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO sap_bom_processor;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA
    staging, core, classification, packaging, tax, audit
TO sap_bom_processor;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA
    core, classification, packaging, tax
TO sap_bom_processor;

ALTER DEFAULT PRIVILEGES IN SCHEMA analytics
    GRANT SELECT ON TABLES TO sap_bom_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw
    GRANT SELECT, INSERT ON TABLES TO sap_bom_ingest;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw
    GRANT USAGE, SELECT ON SEQUENCES TO sap_bom_ingest;
