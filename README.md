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


## Canonical BOM model

The core layer materializes staged SAP data into stable relational entities:

- `core.material`;
- `core.bom`;
- `core.bom_version`;
- `core.bom_component`.

Each canonical record keeps lineage back to its staging record and ingestion run. BOM versions also retain the SAP base quantity and base unit, which are required for correct multi-level quantity propagation.

Where a component quantity uses an alternative unit and a valid `MARM` conversion is available, the core layer calculates `quantity_base_unit` alongside the original quantity and unit.

### Recursive BOM explosion

`core.explode_bom(...)` recursively expands a BOM from a root material for a selected date and optional plant:

```sql
SELECT *
FROM core.explode_bom(
    (SELECT material_id
     FROM core.material
     WHERE sap_material_id = 'FG-1000'),
    DATE '2026-01-01',
    'GB01'
)
ORDER BY depth, material_path;
```

The function returns both direct and cumulative quantities. Cumulative quantities account for each BOM version's base quantity.

The traversal records the material path as an array. If a component already exists in the current path, `cycle_detected` becomes true and recursion stops on that branch. This prevents malformed circular BOMs from producing infinite recursion.

The date argument provides an as-of view of the structure by selecting only BOM versions whose effective interval contains that date.

Run the complete raw-to-core example with:

```bash
make db-reset
make sap-demo
```

The workflow also runs a separate rollback-only cycle test to prove that circular BOMs are detected.


## Material classification

The classification layer keeps inference separate from SAP facts and from human review.

It has three distinct layers:

1. **Evidence** — dictionary matches and deterministic rules.
2. **Resolved classification** — the selected family/polymer with confidence, status and provenance.
3. **Reviewed override** — an explicit human decision that supersedes the resolved result without deleting the original evidence.

The initial taxonomy includes plastic, paper/board, glass, metal, wood, other and unknown material families, plus common polymer codes such as HDPE, LDPE, PET, PP, PS and PVC.

Dictionary terms carry:

- canonical term;
- synonym;
- matching strategy;
- material family;
- optional polymer;
- confidence;
- priority;
- classifier version.

Rules carry equivalent provenance plus the field they inspect and the rationale for the heuristic.

### Resolution states

A material classification has one of four states:

- `classified` — sufficiently strong and non-contradictory evidence;
- `review` — weak or absent evidence;
- `conflict` — strong evidence supports incompatible material families;
- `overridden` — an active reviewed override determines the final result.

For example, the synthetic descriptions `Bottle 500 ml clear` and `Closure black` produce plastic heuristics, but their confidence is deliberately below the automatic-classification threshold. They therefore remain in the review queue instead of being presented as facts.

A description such as `HDPE bottle` generates both polymer dictionary evidence and the weaker bottle heuristic. The dictionary evidence wins deterministically, while all evidence remains queryable.

### Review queue

```sql
SELECT *
FROM classification.review_queue
ORDER BY status, sap_material_id;
```

### Refresh

```bash
make classification-refresh
make classification-smoke
make classification-conflict-smoke
```

The contradiction smoke test creates a temporary synthetic conflict, verifies that the material becomes `conflict`, adds a reviewed override, verifies the `overridden` result, and rolls the entire test back.


## Plastic packaging assessment

The packaging layer connects the canonical BOM and material-classification layers to an auditable plastic-weight assessment.

It deliberately separates:

- packaging scope;
- material classification;
- material weight;
- recycled-content evidence;
- tax-policy configuration.

### Packaging scope

Packaging status is resolved independently from material family.

For example, a component can be:

- packaging + plastic;
- packaging + paper;
- non-packaging + plastic;
- unresolved and therefore sent to review.

Scope rules can inspect SAP material group, material type, description, or material ID. Reviewed overrides are stored separately from rule evidence.

### Plastic and recycled weight

For each exploded BOM component, the assessment stores:

- cumulative component quantity;
- component unit weight;
- normalized mass factor;
- total component weight in kilograms;
- plastic weight;
- recycled-content fraction;
- recycled plastic weight;
- the recycled-content evidence record used.

The synthetic example resolves the three packaging components as:

- bottle: 35 g, HDPE, 60% recycled;
- closure: 8 g, PP, 25% recycled;
- label: 2 g, paper.

This yields:

```text
plastic weight = 0.035 + 0.008 = 0.043 kg
recycled plastic weight = 0.035 × 0.60 + 0.008 × 0.25 = 0.023 kg
recycled fraction = 0.023 / 0.043 ≈ 0.5349
```

### Recycled-content evidence

Recycled content is evidence-dated and may come from:

- supplier declarations;
- certificates;
- SAP attributes;
- manual review;
- synthetic fixtures used only for testing.

The assessment selects the best effective evidence for the requested assessment date, prioritising reviewed and higher-confidence records.

### Configurable tax rules

Tax policy is stored separately in `tax.rule_set` and `tax.rule_parameter`.

The repository includes a **synthetic demo rule set only**. It is intentionally not a representation of current UK or any other legislation. Its purpose is to prove that the evaluator can consume versioned parameters without hard-coding policy into the BOM or classification layers.

A policy evaluator uses:

- an effective-dated rule set;
- named parameters;
- the packaging assessment output;
- an explainable JSON trace.

If any component still requires review, the tax decision becomes `review` instead of silently assuming missing facts.

### Explainability

Two views expose the reasoning chain:

```sql
SELECT *
FROM packaging.assessment_trace
ORDER BY assessment_run_id, depth, component_assessment_id;

SELECT *
FROM tax.assessment_trace
ORDER BY tax_assessment_id;
```

Each component trace retains references to the BOM component, material lineage, packaging rule, classification result, weight source, material path, and recycled-content evidence.

### End-to-end checks

```bash
make packaging-smoke
make packaging-review-smoke
```

The first test proves the complete calculation with reviewed synthetic evidence. The second removes those decisions and verifies that unresolved classifications correctly block an automatic tax result.

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
