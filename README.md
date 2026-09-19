# sap-bom-analytics

A data-engineering and analytics framework for turning SAP-derived Bill of Materials data into a canonical, versioned, and auditable relational model.

SAP remains the source system. This repository focuses on ingestion, reconciliation, lineage, BOM reconstruction, and downstream analytical use cases.

## Why this exists

Operational SAP data is designed for transactions, not for analytical questions such as:

- What components belonged to a product BOM on a particular date?
- Which SAP records produced a calculated component weight?
- Which values came directly from SAP and which were inferred?
- How can material classifications be reviewed without overwriting source data?
- How can a regulatory calculation be reproduced months later?

The project addresses those questions by separating source facts from derived facts and preserving lineage throughout the pipeline.

## Intended architecture

```text
SAP
 |
 v
raw ingestion
 |
 v
staging / normalisation
 |
 v
canonical BOM model
 |
 +--> classification
 |       |
 |       +--> packaging / plastic analysis
 |
 +--> analytical views
 |
 +--> downstream regulatory calculations
```

## Database layers

| Schema | Purpose |
| --- | --- |
| `raw` | Near-verbatim SAP extracts |
| `staging` | Cleaning, unit normalisation, reconciliation |
| `core` | Canonical materials, BOMs, versions and components |
| `classification` | Derived material classifications and review state |
| `audit` | Ingestion runs, hashes and lineage |
| `tax` | Downstream regulatory calculations |

The initial system of record is PostgreSQL.

## Design principles

- SAP remains authoritative for source facts.
- Raw source values are immutable.
- Derived values never overwrite SAP-derived values.
- BOMs are versioned and effective-dated.
- Every important transformation must be traceable.
- Deterministic reconciliation comes before machine learning.
- Regulatory rules stay outside the canonical BOM model.

## Local development

Requirements:

- Docker with Docker Compose;
- Python 3.12+;
- Poetry for development tooling.

Start PostgreSQL and initialise the schema:

```bash
cp .env.example .env
make db-up
make db-migrate
make db-seed
make db-smoke
```

The synthetic fixture creates one finished product with a three-component packaging BOM and preserves SAP-like source record identifiers for lineage checks.

To rebuild from an empty database:

```bash
make db-reset
make db-migrate
make db-seed
make db-smoke
```

Migrations are applied in lexical order from `migrations/`. Applied migration checksums are recorded in `audit.schema_migration`; modifying an already-applied migration causes the migration runner to fail rather than silently changing history.


## SAP extract ingestion

The initial ingestion layer supports CSV exports corresponding to the SAP tables most relevant to BOM reconstruction:

| SAP table | Role in the analytical model |
| --- | --- |
| `MARA` | Material master attributes and base units |
| `MAKT` | Material descriptions by language |
| `MAST` | Material-to-BOM assignment by plant and BOM usage |
| `STKO` | BOM header and validity metadata |
| `STPO` | BOM component items and quantities |
| `MARM` | Alternative units of measure and conversion ratios |
| `T001W` | Plant metadata |

CSV headers are matched case-insensitively. Required SAP key columns are validated before loading, while additional columns are retained in the raw table's `raw_payload` JSONB field.

That is deliberate: SAP installations often contain customer-specific `Z*` or `ZZ*` fields. The ingestion layer should not discard them merely because the canonical model does not use them yet.

After migrating the database, load all synthetic SAP extracts with:

```bash
make sap-ingest-example
```

A single extract can be loaded directly:

```bash
poetry run python scripts/sap_ingest_csv.py stpo path/to/STPO.csv
```

Every file creates an `audit.ingestion_run` containing the source path, SHA-256 digest, status and timestamps. Each raw row carries the ingestion run, source filename and source row number.


## Staging and reconciliation

The staging layer converts the raw SAP extracts into a normalized analytical representation without altering the original source values.

The current transformation:

- keeps the original SAP material and BOM identifiers;
- creates separate normalized identifiers for joins;
- chooses a preferred material description, prioritising English where available;
- parses SAP `YYYYMMDD` validity dates into PostgreSQL dates;
- parses numeric weights, quantities, and unit-conversion ratios;
- normalizes unit codes to upper case;
- resolves `MAST → STKO → STPO` into staged BOM headers and components;
- records source-row lineage back to the raw SAP tables;
- emits deterministic data-quality issues for missing material masters, missing BOM headers, and invalid unit conversions.

Run the complete synthetic pipeline with:

```bash
make db-reset
make sap-demo
```

After that, useful inspection queries include:

```sql
SELECT *
FROM staging.bom_component
ORDER BY bom_number, item_number;

SELECT *
FROM staging.data_quality_issue
ORDER BY severity, issue_type;
```

The staging refresh is intentionally deterministic SQL. It can be reviewed, reproduced, and audited without hiding reconciliation decisions in application code.

## Current status

The repository is in its foundation phase.

The first schema defines:

- ingestion runs;
- canonical materials;
- BOM identities;
- BOM versions;
- BOM components;
- derived material classifications.

See [the architecture notes](docs/architecture.md) and [the roadmap](ROADMAP.md) for the planned implementation.
