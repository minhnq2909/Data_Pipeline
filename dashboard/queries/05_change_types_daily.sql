select
    activity_date,
    sum(edit_count) as edit_count,
    sum(new_page_count) as new_page_count,
    sum(log_count) as log_count
from mart.agg_recentchanges_daily
group by activity_date
order by activity_date;
