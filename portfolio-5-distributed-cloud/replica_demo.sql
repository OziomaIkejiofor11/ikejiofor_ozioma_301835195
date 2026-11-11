-- portfolio-5-distributed-cloud/replica_demo.sql
-- ONE psql script that switches between the PRIMARY (port 5432) and the REPLICA (port 5433)
-- over the Unix socket, and prints real evidence:
--   who is who -> a write is REJECTED on the replica -> a write on the primary ARRIVES on the replica
--   -> replication status/lag -> a delete also arrives.
-- Run AFTER replica_setup.sh:
--   sudo runuser -u postgres -- psql -d cleanroute -f replica_demo.sql
-- The script waits (a few milliseconds) until the replica has REPLAYED the primary's WAL position
-- before it reads, so the result does not depend on timing luck.
\set ON_ERROR_STOP on
\pset footer off

\echo
\echo '=== 1. PRIMARY: who am I? ==='
\connect -reuse-previous=off cleanroute - /var/run/postgresql 5432
SELECT current_setting('port') AS port, pg_is_in_recovery() AS is_replica, 'PRIMARY' AS expected_role;

\echo
\echo '=== 2. REPLICA: who am I? ==='
\connect -reuse-previous=off cleanroute - /var/run/postgresql 5433
SELECT current_setting('port') AS port, pg_is_in_recovery() AS is_replica, 'REPLICA' AS expected_role;

\echo
\echo '=== 3. REPLICA rejects a write (read-only standby) - the next line SHOULD be an ERROR ==='
\set ON_ERROR_STOP off
INSERT INTO disposal_site(name, type, city) VALUES ('Replica Reject Me','dumpsite','Lagos');
\set ON_ERROR_STOP on

\echo
\echo '=== 4. PRIMARY: insert a marker row ==='
\connect -reuse-previous=off cleanroute - /var/run/postgresql 5432
DELETE FROM disposal_site WHERE name = 'Replica Demo Site';
INSERT INTO disposal_site(name, type, city) VALUES ('Replica Demo Site','dumpsite','Lagos');
SELECT 'primary' AS node, count(*) AS marker_rows FROM disposal_site WHERE name = 'Replica Demo Site';
SELECT pg_current_wal_lsn() AS primary_lsn \gset
SELECT set_config('demo.lsn', :'primary_lsn', false) \gset
\echo 'primary WAL position after the insert: ' :primary_lsn

\echo
\echo '=== 5. REPLICA: wait until it has replayed that position, then read the row ==='
\connect -reuse-previous=off cleanroute - /var/run/postgresql 5433
SELECT set_config('demo.lsn', :'primary_lsn', false) \gset
DO $$
DECLARE i int := 0;
BEGIN
    WHILE pg_last_wal_replay_lsn() < current_setting('demo.lsn')::pg_lsn AND i < 200 LOOP
        PERFORM pg_sleep(0.05); i := i + 1;
    END LOOP;
    RAISE NOTICE 'replica replayed up to % (waited % x 50 ms)', pg_last_wal_replay_lsn(), i;
END $$;
SELECT 'replica' AS node, count(*) AS marker_rows FROM disposal_site WHERE name = 'Replica Demo Site';
SELECT pg_last_wal_replay_lsn() AS replica_replay_lsn,
       now() - pg_last_xact_replay_timestamp() AS time_since_last_replayed_commit;

\echo
\echo '=== 6. PRIMARY: replication status (pg_stat_replication) ==='
\connect -reuse-previous=off cleanroute - /var/run/postgresql 5432
SELECT application_name, state, sync_state, sent_lsn, replay_lsn,
       (sent_lsn - replay_lsn) AS replay_gap_bytes
  FROM pg_stat_replication;

\echo
\echo '=== 7. PRIMARY: delete the marker, then confirm it disappears on the REPLICA too ==='
DELETE FROM disposal_site WHERE name = 'Replica Demo Site';
SELECT pg_current_wal_lsn() AS primary_lsn2 \gset
SELECT 'primary' AS node, count(*) AS marker_rows FROM disposal_site WHERE name = 'Replica Demo Site';
\connect -reuse-previous=off cleanroute - /var/run/postgresql 5433
SELECT set_config('demo.lsn', :'primary_lsn2', false) \gset
DO $$
DECLARE i int := 0;
BEGIN
    WHILE pg_last_wal_replay_lsn() < current_setting('demo.lsn')::pg_lsn AND i < 200 LOOP
        PERFORM pg_sleep(0.05); i := i + 1;
    END LOOP;
END $$;
SELECT 'replica' AS node, count(*) AS marker_rows FROM disposal_site WHERE name = 'Replica Demo Site';

\echo
\echo '=== replica demo DONE: write rejected on the replica, insert and delete both replicated ==='
