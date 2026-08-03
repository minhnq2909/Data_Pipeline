.PHONY: init up down reset status logs web-logs dbt-debug dbt-run dbt-test airflow-info psql

DBT_CMD=/opt/dbt-venv/bin/dbt --project-dir /opt/airflow/dbt --profiles-dir /opt/airflow/dbt

init:
	mkdir -p dags logs plugins config dbt/logs dbt/target
	docker compose build
	docker compose up airflow-init

up:
	docker compose up -d

down:
	docker compose down

reset:
	docker compose down --volumes --remove-orphans

status:
	docker compose ps

logs:
	docker compose logs -f airflow-scheduler airflow-dag-processor airflow-api-server

web-logs:
	docker compose logs -f web

airflow-info:
	docker compose run --rm airflow-cli airflow info

dbt-debug:
	docker compose run --rm airflow-cli $(DBT_CMD) debug

dbt-run:
	docker compose run --rm airflow-cli $(DBT_CMD) run

dbt-test:
	docker compose run --rm airflow-cli $(DBT_CMD) test

psql:
	docker compose exec warehouse psql -U $${WAREHOUSE_USER:-dataflow} -d $${WAREHOUSE_DB:-dataflow}

# Example:
# make backfill FROM=2026-07-23 TO=2026-07-29
backfill:
	docker compose run --rm airflow-cli airflow backfill create \
		--dag-id wikimedia_recentchanges_daily \
		--from-date $(FROM) \
		--to-date $(TO) \
		--reprocess-behavior completed \
		--max-active-runs 1
