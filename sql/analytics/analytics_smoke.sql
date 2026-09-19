DO $$
DECLARE
    material_count INTEGER;
    bom_count INTEGER;
    quality_columns INTEGER;
BEGIN
    SELECT COUNT(*) INTO material_count
    FROM analytics.material_summary;

    IF material_count <> (SELECT COUNT(*) FROM core.material) THEN
        RAISE EXCEPTION
            'Material summary mismatch: analytics=%, core=%',
            material_count,
            (SELECT COUNT(*) FROM core.material);
    END IF;

    SELECT COUNT(*) INTO bom_count
    FROM analytics.bom_summary;

    IF bom_count <> (SELECT COUNT(*) FROM core.bom) THEN
        RAISE EXCEPTION
            'BOM summary mismatch: analytics=%, core=%',
            bom_count,
            (SELECT COUNT(*) FROM core.bom);
    END IF;

    SELECT COUNT(*) INTO quality_columns
    FROM information_schema.columns
    WHERE table_schema = 'analytics'
      AND table_name = 'data_quality_dashboard';

    IF quality_columns < 8 THEN
        RAISE EXCEPTION 'Quality dashboard view is incomplete';
    END IF;
END
$$;
