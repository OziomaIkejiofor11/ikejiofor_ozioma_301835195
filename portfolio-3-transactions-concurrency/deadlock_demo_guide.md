# Portfolio 3 — Deadlock demo (two terminals)

A classic AB-BA deadlock: Terminal A locks row 1 then asks for row 2; Terminal B locks row 2 then
asks for row 1. PostgreSQL's deadlock detector aborts one of them with
`ERROR: deadlock detected`. One statement per step. No `pg_sleep`.

```bash
# Terminal A                       # Terminal B
sudo runuser -u postgres -- psql -d cleanroute
sudo runuser -u postgres -- psql -d cleanroute   # separate shell
```

Prerequisite: `bash portfolio-3-transactions-concurrency/run_p3.sh` has run.

Capture two distinct OPEN pickup ids to lock in opposite orders. Run in **both** terminals:

```sql
SELECT pickup_id AS p1
  FROM pickup
 WHERE status='OPEN' AND zone_id = (SELECT zone_id FROM zone
     WHERE day_name_to_dow(collection_day)=EXTRACT(DOW FROM CURRENT_DATE)::int ORDER BY zone_id LIMIT 1)
   AND scheduled_date <= CURRENT_DATE
 ORDER BY pickup_id LIMIT 1
\gset

SELECT pickup_id AS p2
  FROM pickup
 WHERE status='OPEN'
   AND zone_id = (SELECT zone_id FROM zone
     WHERE day_name_to_dow(collection_day)=EXTRACT(DOW FROM CURRENT_DATE)::int ORDER BY zone_id LIMIT 1)
   AND scheduled_date <= CURRENT_DATE
   AND pickup_id <> :p1
 ORDER BY pickup_id LIMIT 1
\gset

\echo 'p1=' :p1 ' p2=' :p2
```

Both terminals now hold the same `:p1` and `:p2`.

---

## The deadlock

```sql
-- A1: Terminal A   (lock p1)
BEGIN;
SELECT pickup_id FROM pickup WHERE pickup_id=:p1 FOR UPDATE;

-- B1: Terminal B   (lock p2)
BEGIN;
SELECT pickup_id FROM pickup WHERE pickup_id=:p2 FOR UPDATE;

-- A2: Terminal A   (try to lock p2 -> blocks, because B holds it)
SELECT pickup_id FROM pickup WHERE pickup_id=:p2 FOR UPDATE;

-- B2: Terminal B   (try to lock p1 -> blocks, because A holds it)
SELECT pickup_id FROM pickup WHERE pickup_id=:p1 FOR UPDATE;
-- within ~1 second PostgreSQL's deadlock detector fires and one terminal gets:
--   ERROR:  deadlock detected
--   DETAIL:  Process ... waits for ShareLock on transaction ... blocked by process ...
--   Process ... waits for ShareLock on transaction ... blocked by process ...
-- The deadlocked statement is rolled back; the rest of that transaction is still alive but aborted.

-- Survivor: commit cleanly
-- Victim:   ROLLBACK;   (its row lock is released; the survivor's blocked SELECT now proceeds)
COMMIT;   -- in the survivor terminal
ROLLBACK;  -- in the victim terminal
```

> Order matters: run A1, then B1, then A2 (blocks), then B2 (triggers the deadlock). The two
> `FOR UPDATE` statements are the lock acquisitions; there is no artificial delay.

## What to screenshot

1. The full `ERROR: deadlock detected` block from the victim terminal, including the `DETAIL`
   lines naming the two processes waiting on each other.
2. The survivor terminal's `SELECT` returning the row after the victim's rollback.

## Why it happens and how to avoid it

- **Cause:** two transactions acquire locks on the same set of rows in **opposite order**. Each ends
  up holding a lock the other needs, forever — the deadlock detector breaks the cycle by aborting
  one.
- **Prevention:** always lock shared resources in a **consistent global order** (e.g. always lock
  the lower `pickup_id` first), or use `FOR UPDATE NOWAIT` / `SKIP LOCKED` so a contended lock does
  not turn into a wait cycle.
- **App behaviour:** treat `deadlock_detected` (`SQLSTATE 40P01`) as a transient error and **retry
  the whole transaction**.

## Study session

Maps to **Session 3 — Locking, deadlocks, deadlock detection** (wait-for graphs, lock ordering,
`SQLSTATE 40P01` retry).
