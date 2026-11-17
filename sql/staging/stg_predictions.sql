create or replace table stg_predictions as

with unnested as (
    select
        filename,
        unnest(predictions, recursive := true)
    from read_json('data/raw/predictions/*.json', filename = true)
),

typed as (
    select
        regexp_extract(filename, '(\d{7})_', 1) as station_id,
        strptime(regexp_extract(filename, '_(\d{4}-\d{2}-\d{2}T\d{6}Z)', 1), '%Y-%m-%dT%H%M%SZ') as pulled_at_utc,
        strptime(t, '%Y-%m-%d %H:%M') as tide_at_utc,
        cast(v as double) as height_ft_mllw,
        case type when 'H' then 'high' when 'L' then 'low' end as tide_type
    from unnested
)

select *
from typed
qualify row_number() over (
    partition by station_id, tide_at_utc
    order by pulled_at_utc desc
) = 1