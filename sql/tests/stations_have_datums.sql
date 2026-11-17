select s.station_id
from stg_stations s
left join stg_datums d on s.station_id = d.station_id
where d.station_id is null