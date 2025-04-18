{{
  config(
    materialized='table',
  )
}}

with exploded_genres as (
  select
    games.id as game_id,
    cast(genre_id as int64) as genre_id
  from
    {{ source('igdb_source', 'games') }} as games,
    unnest(cast(json_extract_array(genres) as array<string>)) as genre_id
),

genre_names as (
  select
    exploded_genres.game_id,
    string_agg(genres_mapping.name, ', ') as genre_names
  from
    exploded_genres
  join
    {{ source('igdb_source', 'genres') }} as genres_mapping
    on exploded_genres.genre_id = genres_mapping.id
  group by
    exploded_genres.game_id
),

exploded_platforms as (
  select
    games.id as game_id,
    cast(platform_id as int64) as platform_id
  from
    {{ source('igdb_source', 'games') }} as games,
    unnest(cast(json_extract_array(platforms) as array<string>)) as platform_id
),

platform_names as (
  select
    exploded_platforms.game_id,
    string_agg(platforms_mapping.name, ', ') as platform_names
  from
    exploded_platforms
  join
    {{ source('igdb_source', 'platforms') }} as platforms_mapping
    on exploded_platforms.platform_id = platforms_mapping.id
  group by
    exploded_platforms.game_id
)

select
  distinct games.id,
  games.name,
  date(timestamp_seconds(games.first_release_date)) as first_release_date,
  games.created_at,
  datetime(timestamp_seconds(safe_cast(split(games._dlt_load_id, ".")[0] as int))) as dlt_load_timestamp,
  ifnull(concat(
    'https://images.igdb.com/igdb/image/upload/t_cover_big/',
    games.cover.image_id,
    '.jpg'
  ), 'https://www.igdb.com/assets/no_cover_show-ef1e36c00e101c2fb23d15bb80edd9667bbf604a12fc0267a66033afea320c65.png') as cover_url,
  games.parent_game as parent_game_id,
  url as igdb_url,
  games.game_type as game_type_id,
  game_types.type as game_type_name,
  coalesce(games.game_status, 0) as game_status_id,
  game_statuses.status as game_status_name,
  genre_names.genre_names,
  platform_names.platform_names,
  games.hypes,
  games.rating,
  games.rating_count,
  games.total_rating,
  games.total_rating_count,
  games.aggregated_rating,
  games.aggregated_rating_count,
  steam_popularity_primitives.* except(game_id),
  igdb_popularity_primitives.* except(game_id)
from
  {{ source('igdb_source', 'games') }} as games
left join 
  {{ source('igdb_source', 'game_types') }} as game_types on games.game_type = game_types.id
left join 
  {{ source('igdb_source', 'game_statuses') }} as game_statuses on coalesce(games.game_status, 0) = game_statuses.id
left join 
  {{ ref('steam_popularity_primitives') }} as steam_popularity_primitives on games.id = steam_popularity_primitives.game_id
left join 
  {{ ref('igdb_popularity_primitives') }} as igdb_popularity_primitives on games.id = igdb_popularity_primitives.game_id
left join 
  genre_names on games.id = genre_names.game_id
left join 
  platform_names on games.id = platform_names.game_id
