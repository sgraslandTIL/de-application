-- stations_not_empty.sql
-- Test: stg_stations has at least one row.
-- Returns a row only when something is wrong.
-- The other tests look for bad rows, so an empty table passes all of them:
-- with no rows, there are no duplicates and no nulls. If stg_stations were
-- empty, the inner join in mart_high_tides would leave the marts empty too,
-- and every other test would still pass.

-- A select with no from returns one row. The where clause removes it unless
-- the table is empty, so the message appears only when there's a problem.
select 'stg_stations is empty' as problem
where (select count(*) from stg_stations) = 0