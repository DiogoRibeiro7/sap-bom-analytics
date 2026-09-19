DO $$
DECLARE
    missing_roles INTEGER;
BEGIN
    SELECT COUNT(*) INTO missing_roles
    FROM (
        VALUES
            ('sap_bom_reader'),
            ('sap_bom_ingest'),
            ('sap_bom_processor')
    ) AS expected(role_name)
    WHERE NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = expected.role_name
    );

    IF missing_roles <> 0 THEN
        RAISE EXCEPTION 'Expected all least-privilege group roles to exist';
    END IF;

    IF has_table_privilege('sap_bom_reader', 'raw.mara', 'INSERT') THEN
        RAISE EXCEPTION 'Reader role must not be able to insert raw SAP data';
    END IF;

    IF NOT has_table_privilege('sap_bom_reader', 'analytics.material_summary', 'SELECT') THEN
        RAISE EXCEPTION 'Reader role must be able to select analytics views';
    END IF;

    IF NOT has_table_privilege('sap_bom_ingest', 'raw.mara', 'INSERT') THEN
        RAISE EXCEPTION 'Ingest role must be able to insert raw SAP rows';
    END IF;

    IF has_table_privilege('sap_bom_ingest', 'core.material', 'DELETE') THEN
        RAISE EXCEPTION 'Ingest role must not be able to delete canonical data';
    END IF;
END
$$;
