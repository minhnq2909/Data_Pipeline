select
    min(activity_date) as min_date,
    max(activity_date) as max_date,
    count(distinct activity_date) as number_of_days,
    sum(total_changes) as total_changes,
    sum(bot_changes) as bot_changes,
    sum(anonymous_changes) as anonymous_changes
from mart.agg_recentchanges_daily;
