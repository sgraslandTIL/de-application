create or replace table stg_datums as

with unnested as (
    select
        regexp_extract(filename, '(\d{7})_', 1) as station_id,
        strptime(regexp_extract(filename, '_(\d{4}-\d{2}-\d{2}T\d{6}Z)', 1), '%Y-%m-%dT%H%M%SZ') as pulled_at_utc,
        units,
        epoch,
        ctrlStation as control_station,
        unnest(datums, recursive := true)
    from read_json('data/raw/datums/*.json', filename = true)
),

latest as (
    select *
    from unnested
    qualify dense_rank() over (partition by station_id order by pulled_at_utc desc) = 1
)

select
    station_id,
    any_value(units) as units,
    any_value(epoch) as datum_epoch,
    any_value(control_station) as control_station,
    max(case when name = 'MHHW' then value end) as mhhw_ft_stnd,
    max(case when name = 'MLLW' then value end) as mllw_ft_stnd,
    round(
        max(case when name = 'MHHW' then value end)
        - max(case when name = 'MLLW' then value end),
        2
    ) as mhhw_above_mllw_ft
from latest
group by station_id