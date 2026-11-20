-- predictions_unique.sql
-- Test: each tide appears once, checked on the deduplication key from
-- stg_predictions (station and tide time).
-- Returns rows only when something is wrong.
-- Confirms the row_number step in stg_predictions removed every duplicate.

select station_id, tide_at_utc, count(*) as copies
from stg_predictions
group by station_id, tide_at_utc
having count(*) > 1