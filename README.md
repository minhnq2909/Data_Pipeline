# DataFlow Wikimedia Pipeline

Pipeline học tập end-to-end:

```text
Wikimedia RecentChanges
    -> Airflow extract theo đúng data interval
    -> PostgreSQL raw append-only
    -> dbt staging
    -> dbt mart
    -> dbt tests
    -> Metabase dashboard
```

## 1. Grain

| Model | Grain |
|---|---|
| `raw.wikimedia_recentchanges` | 1 payload nguồn duy nhất theo `rcid` |
| `staging.stg_wikimedia_recentchanges` | 1 Wikimedia recent-change event |
| `mart.agg_recentchanges_daily` | 1 ngày UTC + 1 namespace |

## 2. Lưu ý về nguồn

Wikimedia RecentChanges chỉ giữ khoảng 30 ngày gần nhất. Vì vậy:

- `DAG_START_DATE` phải nằm trong 30 ngày gần nhất.
- Backfill nên dùng khoảng 7 ngày để demo.
- Nếu cần backfill lịch sử dài hơn, đổi nguồn sang Wikipedia Pageviews hoặc Open-Meteo.

## 3. Chuẩn bị

Cần:

- Docker Engine / Docker Desktop
- Docker Compose V2
- Khoảng 4–8 GB RAM trống

Tạo cấu hình:

```bash
cp .env.example .env
```

Sửa ít nhất:

```env
WIKIMEDIA_USER_AGENT=DataFlowLearningPipeline/1.0 (your-email@example.com)
DAG_START_DATE=<một ngày UTC trong 7 ngày gần nhất>
```

Ví dụ nếu hôm nay là `2026-07-30`, có thể dùng:

```env
DAG_START_DATE=2026-07-23T00:00:00Z
```

Linux:

```bash
sed -i "s/^AIRFLOW_UID=.*/AIRFLOW_UID=$(id -u)/" .env
```

Tạo thư mục:

```bash
mkdir -p dags logs plugins config dbt/logs dbt/target
```

## 4. Khởi động toàn bộ hệ thống

```bash
docker compose build
docker compose up airflow-init
docker compose up -d
docker compose ps
```

Hoặc:

```bash
make init
make up
```

`make init` đã tạo thư mục cần thiết, build image và chạy `airflow-init`.

Truy cập:

- Airflow: `http://localhost:8080`
- Metabase: `http://localhost:3000`
- Warehouse từ máy host: `localhost:5433`

Tài khoản Airflow mặc định nằm trong `.env`.

## 5. Chạy pipeline

Trong Airflow:

1. Mở DAG `wikimedia_recentchanges_daily`.
2. Unpause DAG.
3. Vì `catchup=True`, Airflow tạo run cho từng interval hoàn chỉnh từ `DAG_START_DATE`.
4. Mỗi run chạy:

```text
extract -> dbt_run -> dbt_test
```

DAG dùng `max_active_runs=1` vì mart hiện được rebuild toàn bộ. Điều này tránh hai `dbt run` cùng thay một bảng.

## 6. Kiểm tra từng tầng

Mở psql:

```bash
docker compose exec warehouse \
  psql -U dataflow -d dataflow
```

Raw:

```sql
select
    _raw ->> 'rcid' as rcid,
    _raw,
    _window_start,
    _window_end,
    _ingested_at
from raw.wikimedia_recentchanges
limit 5;
```

Staging:

```sql
select *
from staging.stg_wikimedia_recentchanges
limit 5;
```

Mart:

```sql
select *
from mart.agg_recentchanges_daily
order by activity_date, namespace_id
limit 20;
```

## 7. Chạy dbt thủ công

```bash
make dbt-debug
make dbt-run
make dbt-test
```

Hoặc:

```bash
docker compose run --rm airflow-cli \
  /opt/dbt-venv/bin/dbt run \
  --project-dir /opt/airflow/dbt \
  --profiles-dir /opt/airflow/dbt
```

## 8. Chứng minh idempotency

Lấy số liệu trước khi rerun:

```bash
docker compose exec -T warehouse \
  psql -U dataflow -d dataflow \
  < scripts/check_idempotency.sql
```

Trong Airflow, clear toàn bộ ba task của một DAG run đã thành công để chạy lại cùng interval.

Chạy lại query trên. Kỳ vọng:

- `raw_rows` của window không tăng.
- `mart_total_changes` không đổi.
- Log extract lần hai có `duplicates > 0`, `inserted = 0` hoặc chỉ insert các event đến muộn.

Raw dùng unique index trên `rcid` và loader dùng `ON CONFLICT DO NOTHING`.

## 9. Backfill 7 ngày

Ví dụ:

```bash
make backfill FROM=2026-07-23 TO=2026-07-29
```

Hoặc:

```bash
docker compose run --rm airflow-cli \
  airflow backfill create \
  --dag-id wikimedia_recentchanges_daily \
  --from-date 2026-07-23 \
  --to-date 2026-07-29 \
  --reprocess-behavior completed \
  --max-active-runs 1
```

Kiểm tra:

```bash
docker compose exec -T warehouse \
  psql -U dataflow -d dataflow \
  < scripts/check_backfill.sql
```

Chạy cùng lệnh backfill lần hai. Các tổng trong mart phải không đổi, trừ trường hợp API vừa xuất hiện event đến muộn.

## 10. Chứng minh custom test bắt lỗi

Sau khi mart có dữ liệu:

```bash
docker compose exec -T warehouse \
  psql -U dataflow -d dataflow \
  < scripts/inject_test_failure.sql
```

Chạy:

```bash
make dbt-test
```

`assert_daily_grain` phải fail vì đã có hai dòng cùng
`(activity_date, namespace_id)`.

Khôi phục:

```bash
make dbt-run
make dbt-test
```

## 11. Cấu hình Metabase

Mở `http://localhost:3000` và hoàn thành tài khoản quản trị.

Thêm database PostgreSQL:

| Field | Value |
|---|---|
| Host | `warehouse` |
| Port | `5432` |
| Database | giá trị `WAREHOUSE_DB` |
| Username | giá trị `WAREHOUSE_USER` |
| Password | giá trị `WAREHOUSE_PASSWORD` |

Lưu ý: từ container Metabase phải dùng host `warehouse`, không dùng `localhost`.

Chỉ tạo question từ:

```text
mart.agg_recentchanges_daily
```

Các query sẵn có trong:

```text
dashboard/queries/
```

Chart đề xuất:

1. `01_daily_total_changes.sql` -> Line chart.
2. `02_daily_bot_and_anonymous_rates.sql` -> 2-line chart.
3. `03_top_namespaces.sql` -> Horizontal bar.
4. `04_latest_day_kpis.sql` -> KPI cards.
5. `05_change_types_daily.sql` -> Stacked bar.

## 12. Các test hiện có

Built-in:

- Raw `_raw` not null.
- Raw window start/end not null.
- Staging `change_id` not null.
- Staging `change_id` unique.
- `changed_at_utc` not null.
- `namespace_id` not null.
- `change_type` accepted values.
- Mart grain columns not null.

Custom singular tests:

- `assert_daily_grain`.
- `assert_non_negative_metrics`.
- `assert_staging_mart_reconciliation`.
- `assert_event_inside_window`.

dbt singular test pass khi query trả về 0 dòng.

## 13. Tại sao project chạy lại không sai?

- Airflow truyền `data_interval_start` và `data_interval_end`.
- Extract chỉ giữ event trong `[start, end)`.
- Raw giữ payload gốc, unique theo `rcid`, và có trigger chặn `UPDATE`, `DELETE`, `TRUNCATE`.
- Staging dedupe lần nữa bằng `row_number()`.
- Mart được rebuild từ staging.
- `max_active_runs=1` tránh concurrent full refresh.
- Dashboard chỉ đọc mart.
- Backfill tạo một DAG run cho mỗi interval ngày.

## 14. Reset hoàn toàn

```bash
docker compose down --volumes --remove-orphans
```

Sau đó chạy lại:

```bash
docker compose build
docker compose up airflow-init
docker compose up -d
```

Cảnh báo: `--volumes` xóa toàn bộ dữ liệu warehouse và metadata.
