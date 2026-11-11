-- portfolio-5-distributed-cloud/partition_setup.sql
-- Range-partitions the pickups by MONTH (scheduled_date) and demonstrates partition pruning.
-- Uses a partitioned copy `pickup_part` (same columns as pickup) so the original FK-bound
-- pickup table from Portfolio 1 is left intact for P2/P3.
\set ON_ERROR_STOP on

DROP TABLE IF EXISTS pickup_part CASCADE;

CREATE TABLE pickup_part (
    pickup_id      bigint NOT NULL,
    customer_id    bigint NOT NULL,
    zone_id        bigint NOT NULL,
    scheduled_date date NOT NULL,
    requested_at   timestamptz NOT NULL DEFAULT now(),
    pickup_type    text NOT NULL CHECK (pickup_type IN ('scheduled','on_demand')),
    status         text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','ASSIGNED','COLLECTED','MISSED')),
    shift_id       bigint,
    created_at     timestamptz NOT NULL DEFAULT now(),
    collected_at   timestamptz,
    PRIMARY KEY (pickup_id, scheduled_date)        -- partition key must be part of PK
) PARTITION BY RANGE (scheduled_date);

-- monthly partitions across the 2-year window + next 14 days (relative to today)
DO $$
DECLARE
    d date := date_trunc('month', (current_date - interval '2 years'))::date;
    e date := (current_date + interval '14 days')::date;
    part_name text;
    next_d date;
BEGIN
    WHILE d <= e LOOP
        next_d := (d + interval '1 month')::date;
        part_name := 'pickup_part_' || to_char(d, 'YYYY_MM');
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF pickup_part FOR VALUES FROM (%L) TO (%L)',
            part_name, d, next_d);
        d := next_d;
    END LOOP;
END $$;

-- copy data from the real pickup table
INSERT INTO pickup_part (pickup_id, customer_id, zone_id, scheduled_date, requested_at,
                          pickup_type, status, shift_id, created_at, collected_at)
SELECT pickup_id, customer_id, zone_id, scheduled_date, requested_at,
       pickup_type, status, shift_id, created_at, collected_at
  FROM pickup;

\echo '==> row distribution per partition (one row per month):'
SELECT tableoid::regclass AS partition, count(*) AS rows
  FROM pickup_part
 GROUP BY 1
 ORDER BY 1;

\echo '==> partition count:'
SELECT count(*) AS monthly_partitions
  FROM pg_inherits
 WHERE inhparent = 'pickup_part'::regclass;

\echo '==> EXPLAIN (no pruning): full table scan across ALL partitions'
EXPLAIN (COSTS OFF) SELECT count(*) FROM pickup_part;

\echo '==> EXPLAIN (partition pruning): a single-month filter scans ONE partition'
EXPLAIN (COSTS OFF) SELECT * FROM pickup_part WHERE scheduled_date = CURRENT_DATE;

\echo '==> EXPLAIN (range pruning): a 1-week window scans at most 2 partitions'
EXPLAIN (COSTS OFF)
SELECT * FROM pickup_part
 WHERE scheduled_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days';
