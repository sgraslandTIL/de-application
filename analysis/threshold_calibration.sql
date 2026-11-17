with highs as (
    select
        p.station_id,
        p.tide_at_utc,
        p.height_ft_mllw - d.mhhw_above_mllw_ft as above_mhhw_ft
    from stg_predictions p
    join stg_datums d using (station_id)
    where p.tide_type = 'high'
)

select
    m.margin_ft,
    count(*) filter (where above_mhhw_ft > m.margin_ft) as high_tides_over,
    count(distinct cast(tide_at_utc as date)) filter (where above_mhhw_ft > m.margin_ft) as days_over
from highs
cross join (values (0.5), (0.55), (0.6), (0.65), (0.7)) as m(margin_ft)
group by m.margin_ft
order by m.margin_ft