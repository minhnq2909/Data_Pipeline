select
    activity_date,
    sum(total_changes) as total_changes
from mart.agg_recentchanges_daily
group by activity_date
order by activity_date;
