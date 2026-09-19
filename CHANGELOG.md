# Changelog

All notable changes to this project will be documented in this file.

The format follows Keep a Changelog principles and the project uses semantic versioning.

## [0.1.0] - 2026-09-19

### Added

- SAP extract contracts for MARA, MAKT, MAST, STKO, STPO, MARM, and T001W.
- CSV, semicolon-delimited, TSV, pipe-delimited, and XLSX SAP export adapters.
- Raw ingestion lineage with SHA-256 source hashes and content-addressed incremental ingestion.
- Row-level quarantine for malformed SAP records.
- Deterministic staging and reconciliation.
- Canonical material, BOM, BOM-version, and BOM-component models.
- Effective-dated recursive BOM explosion with cycle detection.
- Canonical unit conversion and quantity propagation.
- Material-family and polymer taxonomies.
- Rule-based and dictionary-based classification with confidence, evidence, conflicts, review queues, and overrides.
- Packaging-scope classification.
- Recycled-content evidence and plastic-weight calculations.
- Configurable tax rule sets and explainable assessment traces.
- Analytical views for materials, BOMs, ingestion, quality, packaging, and operations.
- CLI commands for ingestion, reconciliation, BOM explosion, quality inspection, summaries, and exports.
- CSV and Parquet export support.
- MkDocs Material documentation with Mermaid architecture and ER diagrams.
- Structured JSON logging and database-backed processing-run observability.
- Idempotency, property-based, performance, and integration tests.
- PostgreSQL backup/restore documentation and least-privilege deployment roles.
- Tag-driven release workflow with package-version validation and SHA-256 artifact checksums.

### Notes

- The included tax rule set is synthetic and exists only to exercise the configurable evaluator.
- No HTTP API is included in 0.1.0; this remains deferred until a real integration use case requires it.
