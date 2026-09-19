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
