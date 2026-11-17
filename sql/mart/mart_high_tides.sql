create or replace table mart_high_tides as

with settings as (
    select 0.6 as margin_ft
),

highs as (
    select
        p.station_id,
        s.station_name,
        p.tide_at_utc,
        (p.tide_at_utc at time zone 'UTC') at time zone 'America/New_York' as tide_at_local,
        p.height_ft_mllw,
        round(p.height_ft_mllw - d.mhhw_above_mllw_ft, 3) as above_mhhw_ft
    from stg_predictions p
    join stg_datums d using (station_id)
    join stg_stations s using (station_id)
    where p.tide_type = 'high'
)

select
    h.*,
    cast(h.tide_at_local as date) as tide_date_local,
    cast(h.tide_at_local as date) - 3 as alert_date_local,
    h.above_mhhw_ft >= st.margin_ft as crosses_threshold
from highs h
cross join settings st