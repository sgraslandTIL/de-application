select station_id, units, mhhw_above_mllw_ft
from stg_datums
where units is distinct from 'feet'
   or mhhw_above_mllw_ft is null