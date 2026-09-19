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
