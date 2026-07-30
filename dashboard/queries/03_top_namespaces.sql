select
    namespace_name,
    sum(total_changes) as total_changes
from mart.agg_recentchanges_daily
group by namespace_name
order by total_changes desc
limit 10;
