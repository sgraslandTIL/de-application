create or replace table mart_alerts as

with crossing_days as (
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

islands as (
    select
        *,
        tide_date_local - cast(row_number() over (
            partition by station_id order by tide_date_local
        ) as integer) as event_key
    from crossing_days
),

events as (
    select
        station_id,
        any_value(station_name) as station_name,
        min(tide_date_local) as first_day,
        max(tide_date_local) as last_day,
        count(*) as days,
        max(peak_above_mhhw_ft) as peak_above_mhhw_ft,
        arg_max(peak_tide_at_local, peak_above_mhhw_ft) as peak_tide_at_local
    from islands
    group by station_id, event_key
)

select
    station_id || '_' || strftime(first_day, '%Y%m%d') as alert_id,
    station_id,
    station_name,
    first_day,
    last_day,
    days,
    peak_tide_at_local,
    peak_above_mhhw_ft,
    first_day - 3 as send_date
from events
order by send_date, station_id