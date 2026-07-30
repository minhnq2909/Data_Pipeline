select *
from {{ ref('agg_recentchanges_daily') }}
where total_changes < 0
   or edit_count < 0
   or new_page_count < 0
   or log_count < 0
   or bot_changes < 0
   or anonymous_changes < 0
   or minor_changes < 0
   or missing_user_changes < 0
   or unique_users < 0
   or bot_rate < 0
   or bot_rate > 1
   or anonymous_rate < 0
   or anonymous_rate > 1
