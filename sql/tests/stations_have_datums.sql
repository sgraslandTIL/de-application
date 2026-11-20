-- stations_have_datums.sql
-- Test: every station has datums.
-- Returns rows only when something is wrong.
-- mart_high_tides inner-joins the datums, so a station without them would
-- silently drop out of the alerts instead of causing an error.

-- Left join keeps every station, matched or not. Stations with no datums
-- get nulls on the datums side, and the where clause keeps only those.
-- This works like the L output of a Join tool in Alteryx.
select s.station_id
from stg_stations s
left join stg_datums d on s.station_id = d.station_id
where d.station_id is null