-- Task 2: DELETE, VACUUM FULL and TRUNCATE in PostgreSQL.
-- Run statements individually in pgAdmin with Auto commit enabled.
-- Run VACUUM FULL outside any explicit transaction.
-- Use the training database. Start with public.table_to_delete absent.
-- The DROP below is only for the experiment table created by this script.

CREATE TABLE public.table_to_delete AS
SELECT 'veeeeeeery_long_string' || gs.x AS col
FROM generate_series(1, 10000000) AS gs(x);

SELECT 'Before DELETE' AS stage, size_bytes,
       pg_size_pretty(size_bytes) AS total_size
FROM (SELECT pg_total_relation_size('public.table_to_delete'::regclass)
             AS size_bytes) AS ms;

DELETE FROM public.table_to_delete
WHERE REPLACE(col, 'veeeeeeery_long_string', '')::int % 3 = 0;

SELECT 'After DELETE' AS stage, size_bytes,
       pg_size_pretty(size_bytes) AS total_size
FROM (SELECT pg_total_relation_size('public.table_to_delete'::regclass)
             AS size_bytes) AS ms;

VACUUM FULL VERBOSE public.table_to_delete;

SELECT 'After VACUUM FULL' AS stage, size_bytes,
       pg_size_pretty(size_bytes) AS total_size
FROM (SELECT pg_total_relation_size('public.table_to_delete'::regclass)
             AS size_bytes) AS ms;

DROP TABLE public.table_to_delete;

CREATE TABLE public.table_to_delete AS
SELECT 'veeeeeeery_long_string' || gs.x AS col
FROM generate_series(1, 10000000) AS gs(x);

SELECT 'Before TRUNCATE' AS stage, size_bytes,
       pg_size_pretty(size_bytes) AS total_size
FROM (SELECT pg_total_relation_size('public.table_to_delete'::regclass)
             AS size_bytes) AS ms;

TRUNCATE TABLE public.table_to_delete;

SELECT 'After TRUNCATE' AS stage, size_bytes,
       pg_size_pretty(size_bytes) AS total_size,
       (SELECT COUNT(*) FROM public.table_to_delete) AS remaining_rows
FROM (SELECT pg_total_relation_size('public.table_to_delete'::regclass)
             AS size_bytes) AS ms;

-- Observed in pgAdmin (sizes from pg_total_relation_size):
-- Stage                 Total bytes   Display       Elapsed time
-- Before DELETE          602611712    575 MB
-- After DELETE           602611712    575 MB        12.553 s
-- After VACUUM FULL      401580032    383 MB        10.628 s
-- Before TRUNCATE        602415104    575 MB
-- After TRUNCATE              8192    8192 bytes     1.664 s
--
-- DELETE evaluated the filter and removed every third row, leaving
-- 6,666,667 row versions reported by VACUUM FULL. PostgreSQL's MVCC
-- keeps obsolete row versions until they are no longer needed. Ordinary
-- vacuum usually makes that space reusable inside the table; DELETE did
-- not shrink the allocated file in this experiment.
--
-- VACUUM FULL rewrote the table into a smaller file, reclaiming
-- 201,031,680 bytes. It needs extra disk space during the rewrite and an
-- exclusive lock, so it can block access to the table while it runs.
--
-- TRUNCATE removed all rows without scanning and deleting them one at a
-- time. It reclaimed 602,406,912 bytes and left a small storage footprint.
-- It took about 13% as long as DELETE in this run.
-- The timings describe different operations: DELETE removed a subset,
-- whereas TRUNCATE emptied the whole table and required an exclusive lock.
--
-- In PostgreSQL, both DELETE and TRUNCATE can be rolled back before COMMIT
-- when used in an explicit transaction. In this autocommit experiment,
-- each successful statement was committed immediately. VACUUM FULL must
-- be run outside an explicit transaction block.
--
-- DELETE vs TRUNCATE (same starting row count in this experiment):
-- | Aspect              | DELETE                | TRUNCATE              |
-- |---------------------|-----------------------|-----------------------|
-- | Scope               | Every third row       | All rows              |
-- | Time                | 12.553 s              | 1.664 s               |
-- | Allocated size      | 575 MB -> 575 MB      | 575 MB -> 8192 bytes  |
-- | Rollback in a block | Yes, before COMMIT    | Yes, before COMMIT    |
--
-- A DELETE marks row versions as deleted. An older snapshot can still
-- need those versions, so their physical storage is not freed at once.
-- VACUUM FULL copies the surviving rows into a new compact file and
-- replaces the old file. TRUNCATE resets the table storage as a whole,
-- avoiding the scan and per-row work needed for a filtered DELETE.
