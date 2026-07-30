select
    _window_start,
    _window_end,
    count(*) as raw_rows,
    min(_ingested_at) as first_ingested_at,
    max(_ingested_at) as last_ingested_at
from raw.wikimedia_recentchanges
group by _window_start, _window_end
order by _window_start;

select
    activity_date,
    sum(total_changes) as mart_total_changes
from mart.agg_recentchanges_daily
group by activity_date
order by activity_date;
