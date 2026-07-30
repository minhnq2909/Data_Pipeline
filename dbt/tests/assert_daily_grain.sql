select
    activity_date,
    namespace_id,
    count(*) as row_count
from {{ ref('agg_recentchanges_daily') }}
group by activity_date, namespace_id
having count(*) > 1
