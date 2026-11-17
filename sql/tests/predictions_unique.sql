select station_id, tide_at_utc, count(*) as copies
from stg_predictions
group by station_id, tide_at_utc
having count(*) > 1