with clean_events as (
    select *
    from {{ ref('stg_wikimedia_recentchanges') }}
),

aggregated as (
    select
        (changed_at_utc at time zone 'UTC')::date as activity_date,
        namespace_id,

        case namespace_id
            when 0 then 'Bài viết'
            when 1 then 'Thảo luận'
            when 2 then 'Thành viên'
            when 3 then 'Thảo luận thành viên'
            when 4 then 'Wikipedia'
            when 5 then 'Thảo luận Wikipedia'
            when 6 then 'Tập tin'
            when 7 then 'Thảo luận tập tin'
            when 10 then 'Bản mẫu'
            when 11 then 'Thảo luận bản mẫu'
            when 12 then 'Trợ giúp'
            when 13 then 'Thảo luận trợ giúp'
            when 14 then 'Thể loại'
            when 15 then 'Thảo luận thể loại'
            else 'Namespace ' || namespace_id::text
        end as namespace_name,

        count(*)::bigint as total_changes,
        count(*) filter (where change_type = 'edit')::bigint as edit_count,
        count(*) filter (where change_type = 'new')::bigint as new_page_count,
        count(*) filter (where change_type = 'log')::bigint as log_count,
        count(*) filter (where is_bot)::bigint as bot_changes,
        count(*) filter (where is_anonymous)::bigint as anonymous_changes,
        count(*) filter (where is_minor)::bigint as minor_changes,
        count(*) filter (where is_user_missing)::bigint as missing_user_changes,

        count(distinct user_name)
            filter (where not is_user_missing)::bigint as unique_users,

        coalesce(
            sum(
                case
                    when old_length is not null and new_length is not null
                        then new_length - old_length
                    else 0
                end
            ),
            0
        )::bigint as net_bytes_change

    from clean_events
    group by
        (changed_at_utc at time zone 'UTC')::date,
        namespace_id
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

    round(
        bot_changes::numeric / nullif(total_changes, 0),
        4
    ) as bot_rate,

    round(
        anonymous_changes::numeric / nullif(total_changes, 0),
        4
    ) as anonymous_rate

from aggregated
