DO $$
DECLARE
    component_count INTEGER;
    issue_count INTEGER;
    parsed_date_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO component_count FROM staging.bom_component;
    IF component_count <> 3 THEN
        RAISE EXCEPTION 'Expected 3 staged BOM components, found %', component_count;
    END IF;

    SELECT COUNT(*) INTO issue_count FROM staging.data_quality_issue;
    IF issue_count <> 0 THEN
        RAISE EXCEPTION 'Expected no staging data-quality issues, found %', issue_count;
    END IF;

    SELECT COUNT(*) INTO parsed_date_count
    FROM staging.bom_component
    WHERE valid_from = DATE '2026-01-01';
    IF parsed_date_count <> 3 THEN
        RAISE EXCEPTION 'Expected 3 parsed component dates, found %', parsed_date_count;
    END IF;
END
$$;
