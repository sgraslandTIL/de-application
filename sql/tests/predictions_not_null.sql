select *
from stg_predictions
where station_id is null
   or tide_at_utc is null
   or height_ft_mllw is null
   or tide_type is null