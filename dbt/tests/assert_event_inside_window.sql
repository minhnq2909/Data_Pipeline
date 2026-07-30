select
    change_id,
    changed_at_utc,
    _window_start,
    _window_end
from {{ ref('stg_wikimedia_recentchanges') }}
where changed_at_utc < _window_start
   or changed_at_utc >= _window_end
