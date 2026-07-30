with staging_counts as (
    select
        (changed_at_utc at time zone 'UTC')::date as activity_date,
        namespace_id,
        count(*)::bigint as expected_count
    from {{ ref('stg_wikimedia_recentchanges') }}
    group by
        (changed_at_utc at time zone 'UTC')::date,
        namespace_id
),

mart_counts as (
    select
        activity_date,
        namespace_id,
        total_changes as actual_count
    from {{ ref('agg_recentchanges_daily') }}
)

select
    coalesce(s.activity_date, m.activity_date) as activity_date,
    coalesce(s.namespace_id, m.namespace_id) as namespace_id,
    s.expected_count,
    m.actual_count
from staging_counts s
full outer join mart_counts m
    on s.activity_date = m.activity_date
   and s.namespace_id = m.namespace_id
where s.expected_count is distinct from m.actual_count
