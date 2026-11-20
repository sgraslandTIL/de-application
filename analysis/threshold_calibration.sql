-- threshold_calibration.sql
-- Analysis query, not part of the pipeline: transform.py doesn't run it.
-- Tests several threshold margins against a year of predictions and counts
-- the alerts and flooded days each would produce. I used the results to
-- choose 0.6 feet for mart_high_tides. The table is in the README.
-- Run it after transform.py, because it reads mart_high_tides.
-- It only reads tables, so running it never changes the database.

-- The gap rule, copied from mart_alerts. If you change max_gap_days there,
-- change it here too, or these counts won't match the alerts.
with settings as (
    select 1 as max_gap_days
),

-- Step 1: one row per day, with the day's highest tide above MHHW.
-- Reads above_mhhw_ft from mart_high_tides, so the calibration always uses
-- the same height calculation and rounding as the alerts.
daily as (
    select
        station_id,
        tide_date_local,
        max(above_mhhw_ft) as peak_above_mhhw_ft
    from mart_high_tides
    group by station_id, tide_date_local
),

-- Step 2: test every margin against every day.
-- The values list is a small table of five margins. The cross join pairs
-- each day with each margin, and the where clause keeps the pairs where the
-- day's highest tide reaches that margin.
crossing as (
    select m.margin_ft, d.station_id, d.tide_date_local
    from daily d
    cross join (values (0.5), (0.55), (0.6), (0.65), (0.7)) as m(margin_ft)
    where d.peak_above_mhhw_ft >= m.margin_ft
),

-- Step 3: mark the days that start a new event, using the same rule as
-- mart_alerts. Each margin is grouped separately, so every margin gets its
-- own set of events.
flagged as (
    select
        *,
        case
            -- The first crossing day for a margin always starts an event.
            when lag(tide_date_local) over w is null then 1
            -- A gap of more than max_gap_days + 1 days starts a new event.
            when tide_date_local - lag(tide_date_local) over w
                > (select max_gap_days from settings) + 1 then 1
            else 0
        end as starts_event
    from crossing
    window w as (partition by margin_ft, station_id order by tide_date_local)
)

-- Step 4: one row per margin. Each event start is one alert, so summing
-- starts_event counts the alerts. Counting rows counts the days over the line.
select
    margin_ft,
    sum(starts_event) as events,
    count(*) as days_over_line
from flagged
group by margin_ft
order by margin_ft