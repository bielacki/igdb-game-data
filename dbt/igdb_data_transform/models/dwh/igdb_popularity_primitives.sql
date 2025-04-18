{{
  config(
    materialized='table',
  )
}}

select
  game_id,
  max(`if`(popularity_type = 1, value, null)) as igdb_visits_score,
  max(`if`(popularity_type = 2, value, null)) as igdb_playing_score,
  max(`if`(popularity_type = 3, value, null)) as igdb_want_to_play_score,
  max(`if`(popularity_type = 4, value, null)) as igdb_played_score
from `course-data-engineering.igdb_source.popularity_primitives` as primitives
where external_popularity_source = 121
group by all
