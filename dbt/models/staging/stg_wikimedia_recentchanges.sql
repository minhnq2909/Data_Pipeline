with source_data as (
    select
        _raw_id,
        _raw,
        _window_start,
        _window_end,
        _ingested_at
    from {{ source('raw', 'wikimedia_recentchanges') }}
),

typed as (
    select
        _raw_id,

        case
            when (_raw ->> 'rcid') ~ '^[0-9]+$'
                then (_raw ->> 'rcid')::bigint
        end as change_id,

        nullif(_raw ->> 'type', '') as change_type,

        case
            when (_raw ->> 'ns') ~ '^-?[0-9]+$'
                then (_raw ->> 'ns')::integer
        end as namespace_id,

        nullif(_raw ->> 'title', '') as page_title,

        case
            when (_raw ->> 'pageid') ~ '^[0-9]+$'
                then (_raw ->> 'pageid')::bigint
        end as page_id,

        case
            when (_raw ->> 'revid') ~ '^[0-9]+$'
                then (_raw ->> 'revid')::bigint
        end as revision_id,

        case
            when (_raw ->> 'old_revid') ~ '^[0-9]+$'
                then (_raw ->> 'old_revid')::bigint
        end as old_revision_id,

        nullif(_raw ->> 'user', '') as source_user_name,

        case
            when (_raw ->> 'userid') ~ '^[0-9]+$'
                then (_raw ->> 'userid')::bigint
        end as user_id,

        nullif(_raw ->> 'comment', '') as change_comment,

        case
            when (_raw ->> 'timestamp') is not null
                then (_raw ->> 'timestamp')::timestamptz
        end as changed_at_utc,

        case
            when (_raw ->> 'oldlen') ~ '^-?[0-9]+$'
                then (_raw ->> 'oldlen')::bigint
        end as old_length,

        case
            when (_raw ->> 'newlen') ~ '^-?[0-9]+$'
                then (_raw ->> 'newlen')::bigint
        end as new_length,

        (_raw ? 'bot') as is_bot,
        (_raw ? 'minor') as is_minor,
        (_raw ? 'anon') as is_anonymous,
        (_raw ? 'redirect') as is_redirect,
        (_raw ? 'userhidden') as is_user_hidden,

        case
            when jsonb_typeof(_raw -> 'tags') = 'array'
                then jsonb_array_length(_raw -> 'tags')
            else 0
        end as tag_count,

        _window_start,
        _window_end,
        _ingested_at
    from source_data
),

deduplicated as (
    select
        *,
        row_number() over (
            partition by change_id
            order by _ingested_at desc, _raw_id desc
        ) as row_number
    from typed
)

select
    change_id,
    change_type,
    namespace_id,
    page_title,
    page_id,
    revision_id,
    old_revision_id,
    coalesce(source_user_name, 'unknown') as user_name,
    user_id,
    change_comment,
    changed_at_utc,
    old_length,
    new_length,
    is_bot,
    is_minor,
    is_anonymous,
    is_redirect,
    is_user_hidden,
    (source_user_name is null) as is_user_missing,
    tag_count,
    _window_start,
    _window_end,
    _ingested_at
from deduplicated
where row_number = 1
