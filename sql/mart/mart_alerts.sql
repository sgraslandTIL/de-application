create or replace table mart_alerts as

with settings as (
    select 1 as max_gap_days
),

crossing_days as (
    select
        station_id,
        station_name,
        tide_date_local,
        max(above_mhhw_ft) as peak_above_mhhw_ft,
        arg_max(tide_at_local, above_mhhw_ft) as peak_tide_at_local
    from mart_high_tides
    where crosses_threshold
    group by station_id, station_name, tide_date_local
),

gaps as (
    select
        *,
        tide_date_local - lag(tide_date_local) over (
            partition by station_id order by tide_date_local
        ) as days_since_previous
    from crossing_days
),

flagged as (
    select
        *,
        case
            when days_since_previous is null then 1
            when days_since_previous > (select max_gap_days from settings) + 1 then 1
            else 0
        end as starts_event
    from gaps
),

numbered as (
    select
        *,
        sum(starts_event) over (
            partition by station_id order by tide_date_local
        ) as event_number
    from flagged
),

events as (
    select
        station_id,
        any_value(station_name) as station_name,
        min(tide_date_local) as first_day,
        max(tide_date_local) as last_day,
        count(*) as crossing_days,
        max(tide_date_local) - min(tide_date_local) + 1 as span_days,
        max(peak_above_mhhw_ft) as peak_above_mhhw_ft,
        arg_max(peak_tide_at_local, peak_above_mhhw_ft) as peak_tide_at_local
    from numbered
    group by station_id, event_number
)

select
    station_id || '_' || strftime(first_day, '%Y%m%d') as alert_id,
    station_id,
    station_name,
    first_day,
    last_day,
    crossing_days,
    span_days,
    peak_tide_at_local,
    peak_above_mhhw_ft,
    first_day - 3 as send_date
from events
order by send_date, station_id