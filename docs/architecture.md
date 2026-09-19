# Architecture

## System boundary

`sap-bom-analytics` does not replace SAP. It creates an analytical and reconciliation layer around SAP-derived BOM data.

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
 |       +--> packaging / plastic classification
 |
 +--> analytical views
 |
 +--> downstream regulatory calculations
```

## Database layers

### `raw`

Near-verbatim source extracts. Records in this layer should remain immutable.

### `staging`

Normalised identifiers, units, dates, descriptions, and source relationships. Invalid or irreconcilable records are retained explicitly rather than silently discarded.

### `core`

Canonical materials, BOMs, BOM versions, and BOM components.

### `classification`

Derived material classifications, confidence, rule provenance, and human-reviewed overrides.

### `audit`

Ingestion runs, source-file metadata, transformation runs, and lineage.

### `tax`

Reserved for downstream regulatory calculations. Tax logic is intentionally outside the canonical BOM model.

## Core invariant

A source value and a derived value are different facts.

For example:

```text
source description: "PKG COMP 13 BLK"
derived family:     "plastic"
derived polymer:    "PP"
confidence:         0.93
method:             "rule+dictionary"
```

The derived classification must never replace the source description.

## Versioned BOMs

A BOM is not a static list. The model therefore separates:

- the BOM identity;
- a BOM version or alternative;
- the effective date interval;
- the component rows belonging to that version.

This allows historical questions such as:

> Which components were effective for material X at plant Y on a given date?

## Lineage

Every canonical record should be traceable to:

1. an ingestion run;
2. the original SAP identifier;
3. the source record or extract;
4. the transformation that produced it.

This is required for reconciliation, debugging, and auditability.

## Technology

PostgreSQL is the intended system of record because the problem is relational and requires constraints, transactions, recursive queries, effective dating, and reliable audit history.

DuckDB may be used for local analytical exploration, but it is not the authoritative store.
