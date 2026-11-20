-- stg_predictions.sql
-- Staging table for tide predictions: one clean row per tide.
-- Reads every raw predictions file, fixes the types, and removes duplicate
-- tides, keeping the copy from the most recent pull.
-- "create or replace" means each run rebuilds this table from scratch,
-- so running it twice never adds rows.

create or replace table stg_predictions as

-- Step 1: read the raw files and flatten them.
with unnested as (
    select
        -- filename = true (below) adds this column: the path of the file each
        -- row came from. The station ID and pull time are only in the file
        -- name, not in NOAA's response, so this column is needed later.
        filename,
        -- Each file holds one list called "predictions", with one entry per
        -- tide: t (time), v (height), and type (H or L).
        -- unnest turns the list into one row per tide, and recursive := true
        -- splits each entry into its own columns: t, v, and type.
        unnest(predictions, recursive := true)
    -- The * reads every .json file in the folder at once, so a second pull
    -- is picked up automatically, which is why duplicates are possible.
    from read_json('data/raw/predictions/*.json', filename = true)
),

-- Step 2: pull values out of the file name and give every column a proper type.
typed as (
    select
        -- The station ID: the 7 digits before the underscore in the file name.
        -- 8725577_2026-11-17T194803Z.json -> 8725577
        regexp_extract(filename, '(\d{7})_', 1) as station_id,

        -- The pull time: the timestamp after the underscore, turned from text
        -- into a real timestamp so it can be sorted. Used for the tie-break below.
        -- 8725577_2026-11-17T194803Z.json -> 2026-11-17 19:48:03
        strptime(regexp_extract(filename, '_(\d{4}-\d{2}-\d{2}T\d{6}Z)', 1), '%Y-%m-%dT%H%M%SZ') as pulled_at_utc,

        -- When the tide happens. NOAA sends it as text, like "2026-08-01 01:14".
        -- It's in UTC because extract.py asked for GMT.
        strptime(t, '%Y-%m-%d %H:%M') as tide_at_utc,

        -- The tide height. NOAA sends it as text, like "0.116", so cast it to
        -- a number. Measured in feet above Mean Lower Low Water.
        -- Feet because extract.py asked for English units.
        cast(v as double) as height_ft_mllw,

        -- NOAA's one-letter code, spelled out so the marts read clearly.
        -- Any other code becomes null, which the predictions_not_null test catches.
        case type when 'H' then 'high' when 'L' then 'low' end as tide_type
    from unnested
)

-- Step 3: remove duplicate tides.
-- If two pulls cover the same tide, both copies are in "typed" at this point.
select *
from typed
qualify row_number() over (
    -- Deduplication key: one tide = one station at one moment.
    -- All copies of the same tide go in one group.
    partition by station_id, tide_at_utc
    -- Tie-break rule: newest pull first, so it gets row number 1.
    order by pulled_at_utc desc
) = 1  -- Keep only row 1 in each group: the newest copy of each tide.