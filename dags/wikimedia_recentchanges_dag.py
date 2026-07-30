from __future__ import annotations

import os
from datetime import timedelta

import pendulum
from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG


dag_start_date = pendulum.parse(
    os.getenv("DAG_START_DATE", "2026-07-23T00:00:00Z")
).in_timezone("UTC")


with DAG(
    dag_id="wikimedia_recentchanges_daily",
    description="Wikimedia RecentChanges -> raw -> dbt staging/mart -> dbt tests",
    schedule="@daily",
    start_date=dag_start_date,
    catchup=True,
    max_active_runs=1,
    default_args={
        "owner": "dataflow",
        "retries": 3,
        "retry_delay": timedelta(minutes=2),
    },
    tags=["dataflow", "wikimedia", "dbt"],
) as dag:
    extract = BashOperator(
        task_id="extract",
        bash_command=(
            "/opt/pipeline-venv/bin/python "
            "/opt/airflow/src/wikimedia_pipeline.py"
        ),
        env={
            "WINDOW_START": "{{ data_interval_start }}",
            "WINDOW_END": "{{ data_interval_end }}",
        },
        append_env=True,
        do_xcom_push=False,
        execution_timeout=timedelta(hours=2),
    )

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=(
            "/opt/dbt-venv/bin/dbt run "
            "--project-dir /opt/airflow/dbt "
            "--profiles-dir /opt/airflow/dbt"
        ),
        append_env=True,
        do_xcom_push=False,
        execution_timeout=timedelta(hours=1),
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            "/opt/dbt-venv/bin/dbt test "
            "--project-dir /opt/airflow/dbt "
            "--profiles-dir /opt/airflow/dbt"
        ),
        append_env=True,
        do_xcom_push=False,
        execution_timeout=timedelta(hours=1),
    )

    extract >> dbt_run >> dbt_test
