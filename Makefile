.PHONY: db-up db-down db-reset db-migrate db-seed db-smoke sap-ingest-example lint typecheck test

db-up:
	docker compose up -d db

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
