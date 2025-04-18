{{
  config(
    materialized='table',
  )
}}

select
  game_id,
  max(`if`(popularity_type = 10, value, null)) as steam_most_wishlisted_upcoming_score,
  max(`if`(popularity_type = 9, value, null)) as steam_global_top_sellers_score,
  max(`if`(popularity_type = 8, value, null)) as steam_total_reviews_score,
  max(`if`(popularity_type = 7, value, null)) as steam_negative_reviews_score,
  max(`if`(popularity_type = 6, value, null)) as steam_positive_reviews_score,
  max(`if`(popularity_type = 5, value, null)) as steam_24h_peak_players_score
from `course-data-engineering.igdb_source.popularity_primitives` as primitives
where external_popularity_source = 1
group by all
