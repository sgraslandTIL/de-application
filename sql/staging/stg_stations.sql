create or replace table stg_stations as

with latest_file as (
    select stations
    from read_json('data/raw/stations/*.json', filename = true)
    order by filename desc
    limit 1
),

unnested as (
    select unnest(stations) as s
    from latest_file
)

select
    s.id as station_id,
    s.name as station_name,
    s.tideType as tide_type,
    round(s.lat, 4) as latitude,
    round(s.lng, 4) as longitude
from unnested