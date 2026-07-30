with latest_day as (
    select max(activity_date) as activity_date
    from mart.agg_recentchanges_daily
)
select
    m.activity_date,
    sum(m.total_changes) as total_changes,
    sum(m.unique_users) as namespace_user_occurrences,
    round(
        sum(m.bot_changes)::numeric / nullif(sum(m.total_changes), 0),
        4
    ) as bot_rate,
    round(
        sum(m.anonymous_changes)::numeric / nullif(sum(m.total_changes), 0),
        4
    ) as anonymous_rate
from mart.agg_recentchanges_daily m
join latest_day d
    on m.activity_date = d.activity_date
group by m.activity_date;
