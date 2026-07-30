insert into mart.agg_recentchanges_daily (
    activity_date,
    namespace_id,
    namespace_name,
    total_changes,
    edit_count,
    new_page_count,
    log_count,
    bot_changes,
    anonymous_changes,
    minor_changes,
    missing_user_changes,
    unique_users,
    net_bytes_change,
    bot_rate,
    anonymous_rate
)
select
    activity_date,
    namespace_id,
    namespace_name,
    total_changes,
    edit_count,
    new_page_count,
    log_count,
    bot_changes,
    anonymous_changes,
    minor_changes,
    missing_user_changes,
    unique_users,
    net_bytes_change,
    bot_rate,
    anonymous_rate
from mart.agg_recentchanges_daily
limit 1;
