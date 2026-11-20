-- predictions_not_null.sql
-- Test: no prediction is missing a key column.
-- Returns rows only when something is wrong.
-- Each null points to a specific problem upstream:
--   station_id: a raw file name doesn't match the expected pattern
--   tide_at_utc: NOAA changed its time format
--   height_ft_mllw: NOAA sent a height that isn't a number
--   tide_type: NOAA sent a code other than H or L

select *
from stg_predictions
where station_id is null
   or tide_at_utc is null
   or height_ft_mllw is null
   or tide_type is null