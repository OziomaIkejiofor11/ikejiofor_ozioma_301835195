# Portfolio 3 — Race Condition: two drivers grab the same pickup

This guide reproduces the classic lost-update race in `claim_pickup`, then shows two fixes. It is
written as a **step-by-step two-terminal demo**: open two `psql` sessions (Terminal A and Terminal B)
and run the statements in order. **One statement per step.** No `pg_sleep` — the row-locking and
`SKIP LOCKED` mechanics are deterministic.

Both terminals connect over the Unix socket (no password) in Codespaces:

```bash
# Terminal A
sudo runuser -u postgres -- psql -d cleanroute

# Terminal B (separate shell)
sudo runuser -u postgres -- psql -d cleanroute
```

Prerequisite: `bash portfolio-3-transactions-concurrency/run_p3.sh` has already created the two demo
drivers (`+2348000999001`, `+2348000999002`) with shifts today in whichever zone's collection day is
today, and 5 demo OPEN pickups for that zone.

## Shared setup (run once in Terminal A, before each scenario)

This resets the 5 demo pickups back to OPEN and captures the shared zone + the two shifts into psql
variables. Run it in **Terminal A only**, then mirror the `\set`/`\gset` values into Terminal B as
shown.

```sql
-- Terminal A: remove leftover demo pickups, then create two fresh OPEN ones that sort FIRST in the queue.
-- (A plain "UPDATE ... SET status='OPEN'" would be rejected by the status-transition trigger,
--  because ASSIGNED -> OPEN is not an allowed move - that trigger is doing its job.)
DELETE FROM pickup
 WHERE customer_id IN (SELECT customer_id FROM customer WHERE phone LIKE '+2348000999%')
   AND scheduled_date = CURRENT_DATE AND status='OPEN';
INSERT INTO pickup(customer_id, zone_id, scheduled_date, requested_at, pickup_type, status)
SELECT c.customer_id, c.zone_id, CURRENT_DATE, now() - interval '10 years' + (row_number() OVER ())*interval '1 second', 'on_demand', 'OPEN'
  FROM customer c WHERE c.phone IN ('+2348000999001','+2348000999002');

-- capture the zone and the two shifts into variables
SELECT zone_id AS z
  FROM zone
 WHERE day_name_to_dow(collection_day) = EXTRACT(DOW FROM CURRENT_DATE)::int
 ORDER BY zone_id LIMIT 1
\gset

SELECT (SELECT shift_id FROM shift WHERE driver_id=(SELECT crew_member_id FROM crew_member WHERE phone='+2348000999001') AND shift_date=CURRENT_DATE) AS sa,
       (SELECT shift_id FROM shift WHERE driver_id=(SELECT crew_member_id FROM crew_member WHERE phone='+2348000999002') AND shift_date=CURRENT_DATE) AS sb
\gset

\echo 'zone=' :z ' shiftA=' :sa ' shiftB=' :sb
```

In **Terminal B**, run the same `\gset` block so it also has `:z`, `:sa`, `:sb`:

```sql
-- Terminal B: capture the same variables
SELECT zone_id AS z
  FROM zone
 WHERE day_name_to_dow(collection_day) = EXTRACT(DOW FROM CURRENT_DATE)::int
 ORDER BY zone_id LIMIT 1
\gset

SELECT (SELECT shift_id FROM shift WHERE driver_id=(SELECT crew_member_id FROM crew_member WHERE phone='+2348000999001') AND shift_date=CURRENT_DATE) AS sa,
       (SELECT shift_id FROM shift WHERE driver_id=(SELECT crew_member_id FROM crew_member WHERE phone='+2348000999002') AND shift_date=CURRENT_DATE) AS sb
\gset
```

> The two terminals are independent `psql` processes, so variables are **not** shared. Each terminal
> must run its own `\gset`. After `\gset`, the value of `:z`, `:sa`, `:sb` is identical in both
> because they query the same rows — that is the point.

---

## Scenario 1 — THE BUG (both drivers grab the same pickup)

Both drivers SELECT the oldest OPEN pickup (no lock) and then UPDATE it without checking the
status. Under READ COMMITTED, B's UPDATE blocks until A commits, then blindly overwrites A's
`shift_id`. **Result: two trucks dispatched to the same house.**

```sql
-- A1: Terminal A
BEGIN;
SELECT pickup_id AS pid
  FROM pickup
 WHERE status='OPEN' AND zone_id=:z AND scheduled_date<=CURRENT_DATE
 ORDER BY requested_at LIMIT 1
\gset
-- A reads pickup_id = :pid

-- B1: Terminal B
BEGIN;
SELECT pickup_id AS pid
  FROM pickup
 WHERE status='OPEN' AND zone_id=:z AND scheduled_date<=CURRENT_DATE
 ORDER BY requested_at LIMIT 1
\gset
-- B reads the SAME pickup_id = :pid   <-- THE BUG: both saw OPEN

-- A2: Terminal A   (assigns to shift A)
UPDATE pickup SET status='ASSIGNED', shift_id=:sa WHERE pickup_id=:pid;
-- A: UPDATE 1

-- A3: Terminal A
COMMIT;

-- B2: Terminal B   (was blocked on the row lock; now proceeds after A's COMMIT)
UPDATE pickup SET status='ASSIGNED', shift_id=:sb WHERE pickup_id=:pid;
-- B: UPDATE 1      <-- B overwrote A's assignment; both trucks think they have it

-- B3: Terminal B
COMMIT;

-- Verify (either terminal):
SELECT pickup_id, status, shift_id FROM pickup WHERE pickup_id=:pid;
-- status=ASSIGNED, shift_id=sb  -> driver A's assignment was lost; truck A is on its way for nothing.
```

**Why it happens:** the read (`SELECT`) and the write (`UPDATE`) are two separate statements with no
guard between them, and the `UPDATE` does not check that the row is still `OPEN`. It is a textbook
**lost update / non-atomic read-modify-write**.

---

## Scenario 2 — FIX 1: conditional UPDATE (atomic compare-and-swap)

Make the UPDATE itself the guard: `WHERE pickup_id=… AND status='OPEN'`. The first driver flips the
row to ASSIGNED; the second driver's UPDATE matches 0 rows and returns nothing. Use `RETURNING` so
each driver knows whether they won.

```sql
-- reset (Terminal A): repeat the DELETE + INSERT from the shared setup above
UPDATE pickup SET status='OPEN', shift_id=NULL
 WHERE customer_id IN (SELECT customer_id FROM customer WHERE phone LIKE '+2348000999%')
   AND scheduled_date = CURRENT_DATE;

-- A1: Terminal A
BEGIN;
UPDATE pickup
   SET status='ASSIGNED', shift_id=:sa
 WHERE pickup_id = (
        SELECT pickup_id FROM pickup
         WHERE status='OPEN' AND zone_id=:z AND scheduled_date<=CURRENT_DATE
         ORDER BY requested_at LIMIT 1)
   AND status='OPEN'
 RETURNING pickup_id AS pid
\gset
-- A: UPDATE 1, :pid set   -> A claimed it

-- B1: Terminal B
BEGIN;
UPDATE pickup
   SET status='ASSIGNED', shift_id=:sb
 WHERE pickup_id = (
        SELECT pickup_id FROM pickup
         WHERE status='OPEN' AND zone_id=:z AND scheduled_date<=CURRENT_DATE
         ORDER BY requested_at LIMIT 1)
   AND status='OPEN'
 RETURNING pickup_id AS pid
\gset
-- B: UPDATE 0, :pid unset -> B got nothing, must retry

-- A2 / B2: both
COMMIT;

-- Verify (either terminal):
SELECT pickup_id, status, shift_id FROM pickup WHERE pickup_id=:pid;
-- exactly one driver won.
```

> Note: the inner `SELECT ... LIMIT 1` may still point at the same row in both sessions (READ
> COMMITTED), but the outer `AND status='OPEN'` re-checks at UPDATE time, so only one UPDATE
> succeeds. The subquery is just to *name* the candidate row.

---

## Scenario 3 — FIX 2: work queue with SELECT … FOR UPDATE SKIP LOCKED

Each driver pulls the next available row from a queue, skipping anything already locked by the other
driver. Both drivers get a **different** pickup, immediately, with no waiting.

```sql
-- reset (Terminal A): repeat the DELETE + INSERT from the shared setup above
UPDATE pickup SET status='OPEN', shift_id=NULL
 WHERE customer_id IN (SELECT customer_id FROM customer WHERE phone LIKE '+2348000999%')
   AND scheduled_date = CURRENT_DATE;

-- A1: Terminal A
BEGIN;
SELECT pickup_id AS pid
  FROM pickup
 WHERE status='OPEN' AND zone_id=:z AND scheduled_date<=CURRENT_DATE
 ORDER BY requested_at
 FOR UPDATE SKIP LOCKED
 LIMIT 1
\gset
-- A locks pickup X, :pid = X

-- B1: Terminal B
BEGIN;
SELECT pickup_id AS pid
  FROM pickup
 WHERE status='OPEN' AND zone_id=:z AND scheduled_date<=CURRENT_DATE
 ORDER BY requested_at
 FOR UPDATE SKIP LOCKED
 LIMIT 1
\gset
-- B skips X (locked by A) and locks pickup Y, :pid = Y   <-- different row, no waiting

-- A2: Terminal A
UPDATE pickup SET status='ASSIGNED', shift_id=:sa WHERE pickup_id=:pid;

-- B2: Terminal B
UPDATE pickup SET status='ASSIGNED', shift_id=:sb WHERE pickup_id=:pid;

-- A3 / B3: both
COMMIT;

-- Verify (either terminal): two different pickups, each ASSIGNED to its own driver.
SELECT pickup_id, status, shift_id FROM pickup
 WHERE shift_id IN (:sa,:sb) AND status='ASSIGNED' ORDER BY pickup_id;
```

**Why SKIP LOCKED wins:** PostgreSQL acquires the row lock during the `SELECT`, atomically with
reading the row. `SKIP LOCKED` tells the planner to pass over any row whose lock is already held by
another transaction, instead of waiting. Each driver therefore dequeues a distinct row in O(log n).

This is exactly what `claim_pickup()` in `claim_pickup.sql` does, wrapped in a function for the
driver app to call.

---

## What to screenshot

1. Scenario 1: the two `UPDATE 1` lines (one in each terminal) and the final `SELECT` showing
   `shift_id = :sb` (B overwrote A).
2. Scenario 2: `UPDATE 1` in Terminal A and `UPDATE 0` in Terminal B.
3. Scenario 3: the two `\gset` outputs showing **different** `:pid` values, and the final `SELECT`
   showing two distinct ASSIGNED rows.

## Suggested git commit

```bash
git add portfolio-3-transactions-concurrency/
git commit -m "P3: claim/record transactions, COMMIT/ROLLBACK, race condition (bug + 2 fixes)"
```

## Study session

Maps to **Session 3 — Transactions, ACID, concurrency control** (lost update, atomic compare-and-
swap, row-level locking, `FOR UPDATE SKIP LOCKED` work queues).
