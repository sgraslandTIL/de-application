-- alerts_unique.sql
-- Test: no two alerts share an ID.
-- Like every test here, this returns rows only when something is wrong.
-- transform.py runs it after the build and fails if any rows come back.
-- alert_id is the station plus the event's first day, so a repeat would
-- mean two events start on the same day at the same station.

-- Group by the ID and keep only the IDs that appear more than once.
-- having filters groups after counting, the way where filters rows before.
select alert_id, count(*) as copies
from mart_alerts
group by alert_id
having count(*) > 1