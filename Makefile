.PHONY: audit db-up db-down db-reset db-migrate db-seed db-smoke sap-ingest-example staging-refresh staging-smoke core-refresh core-smoke cycle-smoke classification-refresh classification-smoke classification-conflict-smoke packaging-smoke packaging-review-smoke analytics-smoke idempotency-check incremental-smoke performance-smoke security-apply security-smoke docs-build docs-serve sap-demo lint typecheck test

db-up:
	docker compose up -d --wait db

db-down:
	docker compose down

db-reset:
	docker compose down -v
	docker compose up -d db

db-migrate:
	python scripts/db_migrate.py

db-seed:
	python scripts/db_sql.py examples/synthetic_bom.sql

db-smoke:
	python scripts/db_smoke.py

lint:
	poetry run ruff check .

typecheck:
	poetry run mypy src scripts

test:
	poetry run pytest

sap-ingest-example:
	poetry run python scripts/sap_ingest_csv.py mara examples/sap/mara.csv
	poetry run python scripts/sap_ingest_csv.py makt examples/sap/makt.csv
	poetry run python scripts/sap_ingest_csv.py mast examples/sap/mast.csv
	poetry run python scripts/sap_ingest_csv.py stko examples/sap/stko.csv
	poetry run python scripts/sap_ingest_csv.py stpo examples/sap/stpo.csv
	poetry run python scripts/sap_ingest_csv.py marm examples/sap/marm.csv
	poetry run python scripts/sap_ingest_csv.py t001w examples/sap/t001w.csv

staging-refresh:
	poetry run python scripts/db_sql.py sql/staging/refresh_staging.sql

staging-smoke:
	poetry run python scripts/db_sql.py sql/staging/staging_smoke.sql

core-refresh:
	poetry run python scripts/db_sql.py sql/core/refresh_core.sql

core-smoke:
	poetry run python scripts/db_sql.py sql/core/core_smoke.sql

cycle-smoke:
	poetry run python scripts/db_sql.py sql/core/cycle_detection_smoke.sql

classification-refresh:
	poetry run python scripts/db_sql.py sql/classification/refresh_classification.sql

classification-smoke:
	poetry run python scripts/db_sql.py sql/classification/classification_smoke.sql

classification-conflict-smoke:
	poetry run python scripts/db_sql.py sql/classification/conflict_override_smoke.sql

packaging-smoke:
	poetry run python scripts/db_sql.py sql/packaging/plastic_packaging_smoke.sql

packaging-review-smoke:
	poetry run python scripts/db_sql.py sql/packaging/review_gate_smoke.sql

sap-demo: db-migrate sap-ingest-example staging-refresh staging-smoke core-refresh core-smoke cycle-smoke classification-refresh classification-smoke classification-conflict-smoke packaging-smoke packaging-review-smoke analytics-smoke

analytics-smoke:
	poetry run python scripts/db_sql.py sql/analytics/analytics_smoke.sql

docs-build:
	poetry run mkdocs build --strict

docs-serve:
	poetry run mkdocs serve

idempotency-check:
	poetry run python scripts/idempotency_check.py

incremental-smoke:
	poetry run python scripts/incremental_ingestion_check.py

performance-smoke:
	poetry run python scripts/bom_performance_check.py

security-apply:
	poetry run python scripts/db_sql.py ops/roles.sql

security-smoke:
	poetry run python scripts/db_sql.py sql/security/security_smoke.sql

audit:
	poetry run python -m pip freeze --exclude-editable > /tmp/requirements-audit.txt
	poetry run pip-audit --strict --progress-spinner off --no-deps --requirement /tmp/requirements-audit.txt
