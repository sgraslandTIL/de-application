select alert_id, count(*) as copies
from mart_alerts
group by alert_id
having count(*) > 1