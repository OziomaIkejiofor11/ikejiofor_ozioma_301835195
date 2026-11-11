# Portfolio 5 — Distributed & Cloud Database (README)

Monthly range partitioning of pickups, a primary + streaming read replica, and a Nigeria-anchored
cloud architecture (NDPA 2023, CAP, sync vs async, offline-first driver app).

## Commands (Codespaces)

```bash
# partitioning (automated, runs against the cleanroute database)
bash portfolio-5-distributed-cloud/run_p5.sh

# or step by step:
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d cleanroute \
    -f portfolio-5-distributed-cloud/partition_setup.sql

# replica setup (automated) + demo (one \connect script)
bash portfolio-5-distributed-cloud/replica_setup.sh
sudo runuser -u postgres -- psql -d cleanroute \
    -f portfolio-5-distributed-cloud/replica_demo.sql
```

`replica_setup_guide.md` explains every replica step and the Codespaces-specific rules.

## What to screenshot

1. `partition_setup.sql`: the per-month row distribution, the partition count, and the two
   `EXPLAIN (COSTS OFF)` outputs (all-partitions scan vs single-partition scan after pruning).
2. `replica_setup.sh`: `SELECT pg_is_in_recovery()` returning `t` on port 5433, and the
   `pg_stat_replication` row showing `state=streaming`.
3. `replica_demo.sql`: the `ERROR: cannot execute INSERT in a read-only transaction` on the
   replica, and the `replica_count` `SELECT` showing the row that arrived from the primary.

## Suggested git commit

```bash
git add portfolio-5-distributed-cloud/
git commit -m "P5: monthly partitioning + primary/streaming replica + Nigeria cloud architecture (NDPA 2023)"
```

## What it demonstrates / study session

Declarative range partitioning with partition pruning, physical streaming replication with
replication slots, read replicas for read scale-out, CAP trade-offs, synchronous vs asynchronous
replication, data sovereignty (NDPA 2023), and offline-first edge apps. Maps to **Session 5 —
Distributed & cloud databases**.
