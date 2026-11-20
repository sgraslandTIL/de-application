-- mart_alerts.sql
-- Mart table: one row per king tide event at each station.
-- An event is a run of days with at least one high tide over the threshold.
-- Each event gets one alert, sent a set number of days before it starts.
-- Reads mart_high_tides, which flags each tide that crosses the threshold.
-- "create or replace" means each run rebuilds this table from scratch,
-- so running it twice never adds rows.

create or replace table mart_alerts as

-- The alert rules, kept in one place so they're easy to change.
with settings as (
    select
        -- How many quiet days can sit inside one event. With 1, crossing days
        -- on November 24, 25, and 27 are one event, not two, so boat owners
        -- get one alert instead of a second one a day later.
        -- analysis/threshold_calibration.sql uses the same rule.
        1 as max_gap_days,
        -- How many days before an event's first day the alert goes out,
        -- so boat owners have time to secure their boats and docks.
        3 as lead_days
),

-- Step 1: one row per day with a crossing tide.
-- A day can have two high tides over the threshold, but it's one day of
-- flooding, so collapse them and keep the day's highest tide.
crossing_days as (
    select
        station_id,
        station_name,
        tide_date_local,
        max(above_mhhw_ft) as peak_above_mhhw_ft,
        -- arg_max returns the first value from the row where the second is
        -- largest: here, the time of the day's highest tide.
        arg_max(tide_at_local, above_mhhw_ft) as peak_tide_at_local
    from mart_high_tides
    where crosses_threshold
    group by station_id, station_name, tide_date_local
),

-- Steps 2 to 4 group crossing days into events. The pattern is: measure
-- the gap to the previous crossing day, mark the days that start a new
-- event, then number the events with a running total.

-- Step 2: days since the previous crossing day at the same station.
-- lag reads the previous row's value. Subtracting two dates gives a number
-- of days. The first crossing day has no previous day, so it gets null.
gaps as (
    select
        *,
        tide_date_local - lag(tide_date_local) over (
            partition by station_id order by tide_date_local
        ) as days_since_previous
    from crossing_days
),

-- Step 3: mark each day that starts a new event with 1, and the rest with 0.
flagged as (
    select
        *,
        case
            -- The first crossing day always starts an event.
            when days_since_previous is null then 1
            -- Back-to-back days are 1 apart. One quiet day between them
            -- makes 2. So with max_gap_days = 1, a new event starts only
            -- when the gap is more than 2.
            when days_since_previous > (select max_gap_days from settings) + 1 then 1
            else 0
        end as starts_event
    from gaps
),

-- Step 4: number the events. A running total of starts_event goes up by 1
-- at the start of each event and stays the same for the rest of it, so
-- every day in an event gets the same number.
-- November 24, 25, and 27 have starts_event 1, 0, 0, so all three get the
-- same event number.
numbered as (
    select
        *,
        sum(starts_event) over (
            partition by station_id order by tide_date_local
        ) as event_number
    from flagged
),

-- Step 5: collapse each event into one row.
events as (
    select
        station_id,
        any_value(station_name) as station_name,
        min(tide_date_local) as first_day,
        max(tide_date_local) as last_day,
        -- crossing_days counts only days over the threshold. span_days counts
        -- every day from first to last, including quiet days inside the event.
        -- November 24 to 27: 3 crossing days, 4 days in the span.
        count(*) as crossing_days,
        max(tide_date_local) - min(tide_date_local) + 1 as span_days,
        -- The event's highest tide and when it happens, for the alert message.
        max(peak_above_mhhw_ft) as peak_above_mhhw_ft,
        arg_max(peak_tide_at_local, peak_above_mhhw_ft) as peak_tide_at_local
    from numbered
    group by station_id, event_number
)

-- Step 6: add an ID and the send date.
select
    -- The station and the event's first day, like 8725577_20261124.
    -- The same data always produces the same ID, and the alerts_unique test
    -- checks that no two events share one.
    station_id || '_' || strftime(first_day, '%Y%m%d') as alert_id,
    station_id,
    station_name,
    first_day,
    last_day,
    crossing_days,
    span_days,
    peak_tide_at_local,
    peak_above_mhhw_ft,
    first_day - (select lead_days from settings) as send_date
from events
-- Sorted so the table reads in the order alerts go out.
order by send_date, station_id