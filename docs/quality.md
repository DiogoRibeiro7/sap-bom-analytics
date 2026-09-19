# Data quality

The analytics layer exposes two main quality views.

## Detailed dashboard input

```sql
SELECT *
FROM analytics.data_quality_dashboard
ORDER BY observed_at DESC;
```

This combines:

- staging reconciliation issues;
- material-classification review/conflict records;
- packaging-scope review/conflict records.

## Scorecard

```sql
SELECT *
FROM analytics.quality_scorecard
ORDER BY quality_layer, severity, issue_type;
```

This view is designed to feed a dashboard without coupling the project to a specific BI tool.

The same information is available through:

```bash
poetry run sap-bom quality
poetry run sap-bom quality --details
```
