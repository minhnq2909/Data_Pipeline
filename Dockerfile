FROM apache/airflow:3.3.0-python3.12

USER root

ENV PIP_INDEX_URL=https://pypi.org/simple \
    PIP_DEFAULT_TIMEOUT=300 \
    PIP_RETRIES=10 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

COPY dbt-requirements.txt /tmp/dbt-requirements.txt
COPY pipeline-requirements.txt /tmp/pipeline-requirements.txt

RUN python -m venv --system-site-packages /opt/pipeline-venv \
    && python -m venv /opt/dbt-venv \
    && /opt/pipeline-venv/bin/python -m pip install \
        --no-cache-dir \
        --retries 10 \
        --timeout 300 \
        --index-url https://pypi.org/simple \
        -r /tmp/pipeline-requirements.txt \
    && /opt/dbt-venv/bin/python -m pip install \
        --no-cache-dir \
        --retries 10 \
        --timeout 300 \
        --index-url https://pypi.org/simple \
        -r /tmp/dbt-requirements.txt \
    && chown -R airflow:0 /opt/pipeline-venv /opt/dbt-venv \
    && rm -f \
        /tmp/dbt-requirements.txt \
        /tmp/pipeline-requirements.txt

USER airflow
