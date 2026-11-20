-- stg_stations.sql
-- Staging table for station details: one row per station.
-- Reads every raw stations file, keeps the newest pull for each station, and
-- gives each field a clear name. The marts use it for the station's name.
-- "create or replace" means each run rebuilds this table from scratch,
-- so running it twice never adds rows.

create or replace table stg_stations as

-- Step 1: read the raw files and flatten them.
with unnested as (
    select
        -- The pull time: the timestamp after the underscore in the file name,
        -- as a real timestamp. Used below to pick the newest file.
        -- 8725577_2026-11-18T164914Z.json -> 2026-11-18 16:49:14
        strptime(regexp_extract(filename, '_(\d{4}-\d{2}-\d{2}T\d{6}Z)', 1), '%Y-%m-%dT%H%M%SZ') as pulled_at_utc,

        -- Each file holds one list called "stations". It has one entry,
        -- because extract.py asks for one station, but NOAA always sends a list.
        -- unnest turns the list into one row per station. Each row is a struct:
        -- one column holding all the station's fields, read below as s.id, s.name.
        unnest(stations) as s
    from read_json('data/raw/stations/*.json', filename = true)
),

-- Step 2: keep the newest pull for each station.
-- One file gives one row here, so row_number works, the same as in
-- stg_predictions. The station ID comes from NOAA's response, not the
-- file name, because this response includes it.
latest as (
    select *
    from unnested
    qualify row_number() over (partition by s.id order by pulled_at_utc desc) = 1
)

-- Step 3: pick the fields the pipeline needs and give them clear names.
select
    s.id as station_id,
    s.name as station_name,

    -- NOAA calls this tideType, like "Mixed Diurnal": how many highs and lows
    -- the station gets each day. Named tide_pattern so it isn't confused with
    -- tide_type in stg_predictions, which means high or low.
    s.tideType as tide_pattern,

    -- Rounded to 4 decimals, about 11 meters, which is precise enough to
    -- place the station on a map.
    round(s.lat, 4) as latitude,
    round(s.lng, 4) as longitude
from latest