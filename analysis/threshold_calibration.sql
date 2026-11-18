with highs as (
    select
        p.station_id,
        cast((p.tide_at_utc at time zone 'UTC') at time zone 'America/New_York' as date) as tide_date_local,
        round(p.height_ft_mllw - d.mhhw_above_mllw_ft, 3) as above_mhhw_ft
    from stg_predictions p
    join stg_datums d using (station_id)
    where p.tide_type = 'high'
),

daily as (
    select
        station_id,
        tide_date_local,
        max(above_mhhw_ft) as peak_above_mhhw_ft
    from highs
    group by station_id, tide_date_local
),

crossing as (
    select m.margin_ft, d.station_id, d.tide_date_local
    from daily d
    cross join (values (0.5), (0.55), (0.6), (0.65), (0.7)) as m(margin_ft)
    where d.peak_above_mhhw_ft >= m.margin_ft
),

flagged as (
    select
        *,
        case
            when tide_date_local - lag(tide_date_local) over (
                partition by margin_ft, station_id order by tide_date_local
            ) <= 2 then 0
            else 1
        end as starts_event
    from crossing
)

select
    margin_ft,
    sum(starts_event) as events,
    count(*) as days_over_line
from flagged
group by margin_ft
order by margin_ft