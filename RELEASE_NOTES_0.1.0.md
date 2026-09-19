# SAP BOM Analytics 0.1.0

This is the first public release of `sap-bom-analytics`.

It provides a complete analytical path from SAP exports to a canonical, auditable BOM model, with deterministic reconciliation, material classification, plastic-packaging analysis, and downstream policy evaluation.

## Highlights

- Ingest SAP BOM-related exports from CSV, semicolon-delimited text, TSV, pipe-delimited text, and XLSX.
- Preserve source lineage, source hashes, raw payloads, and quarantined malformed rows.
- Reconstruct versioned BOMs from `MAST → STKO → STPO`.
- Query historical BOM state and recursively explode multi-level BOMs with cycle detection.
- Separate SAP facts from inferred classifications and reviewed overrides.
- Calculate packaging, plastic, and recycled-plastic weights.
- Evaluate configurable downstream policy rules without hard-coding legislation into the canonical model.
- Inspect quality issues and operational metrics through SQL views and the `sap-bom` CLI.
- Run the full synthetic pipeline under CI with idempotency, performance, property-based, and security checks.

## Release command

After this release-prep PR is merged, the intended release tag is:

```text
v0.1.0
```

The existing release workflow will verify that the tag matches the package version, run quality checks, build the wheel and source distribution, generate SHA-256 checksums, and upload the artifacts.

## Important

The demo tax rule set in the repository is synthetic. It is not a representation of current UK Plastic Packaging Tax or any other current legislation.
