# Roadmap

## Vision

`sap-bom-analytics` turns SAP-derived Bill of Materials data into a canonical, versioned, auditable analytical model.

SAP remains the source of record. This repository provides the reconciliation and analytical layer required for downstream use cases such as packaging analysis, material classification, sustainability reporting, and Plastic Packaging Tax assessment.

## Phase 0 — Foundation

- [x] Define repository scope and architectural principles.
- [x] Establish a canonical relational BOM model.
- [x] Preserve SAP source identifiers and source lineage.
- [x] Separate source facts from derived classifications.
- [x] Add PostgreSQL development environment with Docker Compose.
- [x] Add schema migrations.
- [ ] Add automated SQL validation in CI.
- [x] Add Python package skeleton for ingestion and reconciliation.

## Phase 1 — SAP ingestion

- [x] Define extract contracts for material master data.
- [x] Define extract contracts for BOM headers and BOM items.
- [x] Define extract contracts for units of measure and conversions.
- [x] Define extract contracts for plants and organisational context.
- [x] Support CSV extracts for local development.
- [ ] Add adapters for common SAP export formats.
- [x] Record extraction run metadata and source hashes.
- [ ] Reject malformed records into an explicit quarantine table.

## Phase 2 — Staging and normalisation

- [x] Normalise SAP identifiers without losing original values.
- [x] Standardise units of measure.
- [x] Resolve material descriptions and material groups.
- [x] Detect duplicate source records.
- [x] Validate BOM parent/component relationships.
- [x] Track effective dates and BOM alternatives.
- [x] Add deterministic reconciliation rules.
- [x] Produce data-quality metrics per ingestion run.

## Phase 3 — Canonical BOM model

- [x] Materialise product and material entities.
- [x] Build versioned BOM headers.
- [x] Build BOM component relationships.
- [x] Support multi-level BOM explosion.
- [x] Detect cycles in recursive BOMs.
- [x] Calculate component quantities in canonical units.
- [x] Preserve every canonical record's source lineage.
- [x] Add historical/as-of queries.

## Phase 4 — Classification framework

- [x] Add material-family taxonomy.
- [x] Add rule-based classification engine.
- [x] Add dictionary and synonym matching.
- [x] Add confidence and provenance to derived classifications.
- [x] Add contradiction detection.
- [x] Add manual-review queue.
- [x] Add reviewed overrides without changing SAP-derived facts.
- [x] Version classification rules.

## Phase 5 — Plastic packaging module

- [x] Identify packaging components.
- [x] Classify plastic versus non-plastic materials.
- [x] Add polymer taxonomy.
- [x] Store recycled-content evidence.
- [x] Calculate plastic weight per component and finished product.
- [x] Add configurable tax rules rather than hard-coded legislation.
- [x] Produce explainable assessment traces.
- [x] Add synthetic end-to-end examples.

## Phase 6 — Analytics and interfaces

- [ ] Add analytical views for product, BOM and material summaries.
- [ ] Add data-quality dashboard inputs.
- [ ] Add CLI for ingestion, reconciliation and BOM explosion.
- [ ] Add export to Parquet and CSV.
- [ ] Add API layer only if a real integration use case requires it.
- [ ] Add MkDocs documentation and ER diagrams.

## Phase 7 — Production hardening

- [ ] Property-based tests for BOM transformations.
- [ ] Performance tests for large BOM hierarchies.
- [ ] Incremental ingestion.
- [ ] Idempotent processing.
- [ ] Structured logging.
- [ ] Metrics and run observability.
- [ ] Database backup/restore documentation.
- [ ] Security and least-privilege database roles.
- [ ] Reproducible releases and semantic versioning.

## Design principles

1. SAP is the source system, not the analytical model.
2. Raw source facts are immutable.
3. Derived facts never overwrite SAP-derived values.
4. Every transformation must be traceable to its source and processing run.
5. Effective dating is part of the model from the beginning.
6. Regulatory logic belongs in configurable downstream modules.
7. Deterministic methods come before statistical or machine-learning methods.
