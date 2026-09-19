# CLI

The `sap-bom` command provides a thin interface over the deterministic pipeline.

## Ingest

```bash
poetry run sap-bom ingest mara examples/sap/mara.csv
poetry run sap-bom ingest stpo examples/sap/stpo.csv
```

## Reconcile

Refresh staging, core, and classification layers:

```bash
poetry run sap-bom reconcile
```

Stop after rebuilding the canonical core:

```bash
poetry run sap-bom reconcile --skip-classification
```

## Explode a BOM

```bash
poetry run sap-bom explode FG-1000 --date 2026-01-01 --plant GB01
```

The result is emitted as CSV and includes direct quantity, cumulative quantity, path, and cycle flag.

## Quality

Summary:

```bash
poetry run sap-bom quality
```

Detailed issues:

```bash
poetry run sap-bom quality --details
```

## Analytics datasets

```bash
poetry run sap-bom summary materials
poetry run sap-bom summary boms
poetry run sap-bom summary assessments
```

## Export

CSV:

```bash
poetry run sap-bom export materials output/materials.csv --format csv
```

Parquet:

```bash
poetry run sap-bom export bom-components output/bom-components.parquet --format parquet
```

Exports are restricted to named analytical datasets. The CLI does not accept arbitrary SQL.
