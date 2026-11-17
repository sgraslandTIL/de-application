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
    case s.type when 'R' then 'reference' when 'S' then 'subordinate' end as station_type,
    nullif(s.reference_id, '') as reference_station_id,
    round(s.lat, 4) as latitude,
    round(s.lng, 4) as longitude
from unnested
where s.id in (select distinct station_id from stg_predictions)