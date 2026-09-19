.PHONY: db-up db-down db-reset db-migrate db-seed db-smoke lint typecheck test

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
