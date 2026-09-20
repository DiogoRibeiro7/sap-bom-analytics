# Operations

## Structured logging

The CLI emits one JSON object per log line to stderr. Command output such as CSV remains on stdout.

```bash
poetry run sap-bom --log-level INFO reconcile
```

A reconciliation stage records:

- pipeline and stage name;
- processing-run identifier;
- start and completion timestamps;
- status;
- optional row count;
- metadata;
- failure text.

Operational history is persisted in `audit.processing_run`.

```sql
SELECT *
FROM analytics.processing_run_metrics
ORDER BY processing_run_id DESC;
```

Aggregated stage metrics are available through:

```bash
poetry run sap-bom summary processing-summary
```

## Idempotency

Deterministic staging, core, and classification rebuilds must produce the same logical output when executed repeatedly against unchanged raw data.

```bash
make idempotency-check
```

The check fingerprints ordered logical datasets rather than surrogate IDs, since identity sequences may legitimately change during rebuilds.

## Database backup

Create a compressed PostgreSQL backup:

```bash
mkdir -p backups
docker compose exec -T db pg_dump \
  -U "${POSTGRES_USER:-sap_bom}" \
  -d "${POSTGRES_DB:-sap_bom}" \
  --format=custom \
  --no-owner \
  --no-privileges \
  > backups/sap-bom.dump
```

Verify that the archive is readable:

```bash
docker compose exec -T db pg_restore --list < backups/sap-bom.dump
```

## Database restore

Restore into an empty development database:

```bash
make db-reset
docker compose exec -T db pg_restore \
  -U "${POSTGRES_USER:-sap_bom}" \
  -d "${POSTGRES_DB:-sap_bom}" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  < backups/sap-bom.dump
```

Production backup policy, retention, encryption, off-site storage, and recovery objectives belong to the deployment environment rather than this repository.

## Releases

The project uses semantic versions in `pyproject.toml`.

A tag such as `v0.1.0` triggers the release workflow. The workflow verifies that the tag matches the package version, runs quality checks, builds wheel and source artifacts, creates SHA-256 checksums, and uploads the artifacts to the workflow run.

Publishing to PyPI or another registry is deliberately separate from the build step and should require an explicit trusted-publisher configuration.


## Incremental ingestion

Successful SAP extracts are deduplicated by source table and SHA-256 content hash.

An unchanged extract is reported as skipped and reuses the previous successful ingestion-run identifier. No raw rows are inserted again.

```bash
make incremental-smoke
```

## BOM performance regression check

```bash
make performance-smoke
```

The check generates a 250-level linear BOM, measures the real recursive explosion query, validates the row count, and cleans up all synthetic records.

The five-second threshold is intentionally generous. It detects pathological regressions without treating shared CI hardware as a precise benchmark.

## Database roles

Apply the group-role model as a database owner or deployment DBA:

```bash
make security-apply
make security-smoke
```

The roles are:

| Role | Intended access |
| --- | --- |
| `sap_bom_reader` | Read-only analytics |
| `sap_bom_ingest` | Raw SAP inserts and ingestion audit updates |
| `sap_bom_processor` | Reconciliation and derived-layer processing |

Login creation, passwords, certificates, workload identity, and secret rotation are deployment concerns and are intentionally not stored in the repository.


## PyPI trusted publishing

PyPI publication is intentionally separate from GitHub Release creation.

The workflow `.github/workflows/pypi.yml` publishes an **existing GitHub Release** to PyPI through OpenID Connect. It does not rebuild distributions and it does not use an API token.

The PyPI Trusted Publisher should be configured with:

| Setting | Value |
| --- | --- |
| PyPI project | `sap-bom-analytics` |
| Owner | `DiogoRibeiro7` |
| Repository | `sap-bom-analytics` |
| Workflow | `pypi.yml` |
| Environment | `pypi` |

For the first publication, PyPI supports a pending Trusted Publisher so the project can be created by the first successful OIDC publication.

After the publisher is configured, run the **Publish to PyPI** workflow manually with an existing GitHub release tag such as:

```text
v0.1.1
```

The workflow verifies the tag against both package version declarations, downloads the exact wheel and source archive attached to that GitHub Release, validates their filenames, and publishes those files to PyPI.
