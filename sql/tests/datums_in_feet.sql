-- datums_in_feet.sql
-- Test: every station's datums are in feet, and the MHHW-MLLW gap exists.
-- Returns rows only when something is wrong.
-- The predictions are in feet, so datums in any other unit would put every
-- height in mart_high_tides on the wrong scale without causing an error.

select station_id, units, mhhw_above_mllw_ft
from stg_datums
-- "is distinct from" also catches a missing unit. With "<>", a null unit
-- gives null instead of true, so the row would slip through.
where units is distinct from 'feet'
   -- Null when NOAA's response is missing MHHW or MLLW.
   or mhhw_above_mllw_ft is null