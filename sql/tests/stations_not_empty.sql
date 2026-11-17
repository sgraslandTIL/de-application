select 'stg_stations is empty' as problem
where (select count(*) from stg_stations) = 0