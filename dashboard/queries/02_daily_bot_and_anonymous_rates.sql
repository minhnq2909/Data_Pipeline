select
    activity_date,
    round(
        sum(bot_changes)::numeric / nullif(sum(total_changes), 0),
        4
    ) as bot_rate,
    round(
        sum(anonymous_changes)::numeric / nullif(sum(total_changes), 0),
        4
    ) as anonymous_rate
from mart.agg_recentchanges_daily
group by activity_date
order by activity_date;
