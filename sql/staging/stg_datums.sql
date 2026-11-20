-- stg_datums.sql
-- Staging table for tidal datums: one row per station.
-- A datum is a reference water level that NOAA averages over many years.
-- This table keeps two of them, MHHW (the average higher high tide) and
-- MLLW (the average lower low tide), and the gap between them.
-- The predictions measure heights from MLLW, so the marts subtract this gap
-- to get each tide's height above a normal high tide.
-- "create or replace" means each run rebuilds this table from scratch,
-- so running it twice never adds rows.

create or replace table stg_datums as

-- Step 1: read the raw files and flatten them.
with unnested as (
    select
        -- The station ID: the 7 digits before the underscore in the file name.
        -- 8725577_2026-11-17T194804Z.json -> 8725577
        regexp_extract(filename, '(\d{7})_', 1) as station_id,

        -- The pull time: the timestamp after the underscore, as a real timestamp.
        -- Used below to pick the newest file.
        -- 8725577_2026-11-17T194804Z.json -> 2026-11-17 19:48:04
        strptime(regexp_extract(filename, '_(\d{4}-\d{2}-\d{2}T\d{6}Z)', 1), '%Y-%m-%dT%H%M%SZ') as pulled_at_utc,

        -- These three fields appear once per file, so every datum row from
        -- the same file gets the same value.
        units,                              -- "feet", checked by the datums_in_feet test
        epoch,                              -- the years NOAA averaged over, like "1983-2001"
        ctrlStation as control_station,     -- the long-term station NOAA used to calculate
                                            -- these datums: "8725110 Naples, FL"

        -- Each file holds one list called "datums", with one entry per datum:
        -- name (like MHHW) and value (its height in feet).
        -- unnest turns the list into one row per datum, and recursive := true
        -- splits each entry into its own columns: name and value.
        unnest(datums, recursive := true)
    from read_json('data/raw/datums/*.json', filename = true)
),

-- Step 2: keep only the newest file for each station.
-- Datums only make sense as a set from the same file, so this keeps whole
-- files rather than deduplicating datum by datum.
latest as (
    select *
    from unnested
    -- One file produces many rows, all with the same pull time.
    -- dense_rank gives every row from the newest file rank 1, so the whole
    -- file survives. row_number would number them 1, 2, 3 and keep only one datum.
    qualify dense_rank() over (partition by station_id order by pulled_at_utc desc) = 1
)

-- Step 3: turn the long list (one row per datum) into one wide row per station.
-- This works like a Cross Tab in Alteryx.
select
    station_id,

    -- Identical on every row for the station, so any_value picks one.
    any_value(units) as units,
    any_value(epoch) as datum_epoch,
    any_value(control_station) as control_station,

    -- Only one row per station is named MHHW, so max() returns its value.
    -- The other rows give null, which max() ignores.
    -- _stnd means measured from station datum, the fixed zero point NOAA
    -- sets for each station.
    max(case when name = 'MHHW' then value end) as mhhw_ft_stnd,
    max(case when name = 'MLLW' then value end) as mllw_ft_stnd,

    -- The gap between a normal high tide and the zero of the predictions.
    -- At Port Boca Grande: 3.38 - 1.82 = 1.56 feet.
    -- Rounded to 2 decimals, NOAA's precision for datums. Without rounding,
    -- the subtraction gives 1.5599999... because of how computers store decimals.
    -- If either datum is missing, this is null and the datums_in_feet test fails.
    round(
        max(case when name = 'MHHW' then value end)
        - max(case when name = 'MLLW' then value end),
        2
    ) as mhhw_above_mllw_ft
from latest
group by station_id