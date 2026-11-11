# Portfolio 3 — Isolation levels: READ COMMITTED vs REPEATABLE READ

A two-terminal demo of how the two isolation levels differ when one session inserts a new OPEN
pickup between another session's two reads. One statement per step. No `pg_sleep`.

```bash
# Terminal A                       # Terminal B
sudo runuser -u postgres -- psql -d cleanroute
sudo runuser -u postgres -- psql -d cleanroute   # separate shell
```

Prerequisite: `bash portfolio-3-transactions-concurrency/run_p3.sh` has run (so demo customers and
today's zone exist).

Capture the zone into a variable, in **both** terminals:

```sql
SELECT zone_id AS z
  FROM zone
 WHERE day_name_to_dow(collection_day) = EXTRACT(DOW FROM CURRENT_DATE)::int
 ORDER BY zone_id LIMIT 1
\gset
```

---

## Demo 1 — READ COMMITTED (PostgreSQL default)

In READ COMMITTED, each statement sees a fresh snapshot of committed data, so a new row committed by
another session becomes visible **between** two statements of the same transaction.

```sql
-- A1: Terminal A
BEGIN ISOLATION LEVEL READ COMMITTED;          -- default, shown for clarity
SELECT count(*) AS open_in_a FROM pickup
 WHERE status='OPEN' AND zone_id=:z AND scheduled_date<=CURRENT_DATE;
-- A sees N rows

-- B1: Terminal B   (insert + commit a brand-new OPEN pickup in the same zone)
BEGIN;
INSERT INTO pickup(customer_id, zone_id, scheduled_date, pickup_type, status)
SELECT c.customer_id, :z, CURRENT_DATE, 'on_demand', 'OPEN'
  FROM customer c
 WHERE c.zone_id=:z
 ORDER BY c.customer_id LIMIT 1;
COMMIT;

-- A2: Terminal A   (same transaction, repeat the same statement)
SELECT count(*) AS open_in_a FROM pickup
 WHERE status='OPEN' AND zone_id=:z AND scheduled_date<=CURRENT_DATE;
-- A now sees N+1 rows  <-- READ COMMITTED: new committed row is visible inside the txn

-- A3: Terminal A
COMMIT;
```

> Cleanup (either terminal):
> ```sql
> DELETE FROM pickup WHERE pickup_type='on_demand' AND status='OPEN' AND scheduled_date=CURRENT_DATE
>  AND customer_id IN (SELECT customer_id FROM customer WHERE phone LIKE '+2348000999%')
>  AND created_at > now() - INTERVAL '5 minutes';
> ```

---

## Demo 2 — REPEATABLE READ

In REPEATABLE READ, the transaction uses a **single snapshot** taken at its first read. Rows
committed by other sessions after that snapshot are **not** visible, even on repeated reads.

```sql
-- A1: Terminal A
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) AS open_in_a FROM pickup
 WHERE status='OPEN' AND zone_id=:z AND scheduled_date<=CURRENT_DATE;
-- A sees N rows

-- B1: Terminal B   (insert + commit a new OPEN pickup)
BEGIN;
INSERT INTO pickup(customer_id, zone_id, scheduled_date, pickup_type, status)
SELECT c.customer_id, :z, CURRENT_DATE, 'on_demand', 'OPEN'
  FROM customer c
 WHERE c.zone_id=:z
 ORDER BY c.customer_id LIMIT 1;
COMMIT;

-- A2: Terminal A   (same transaction, same statement)
SELECT count(*) AS open_in_a FROM pickup
 WHERE status='OPEN' AND zone_id=:z AND scheduled_date<=CURRENT_DATE;
-- A still sees N rows  <-- REPEATABLE READ: snapshot is frozen

-- A3: Terminal A
COMMIT;

-- A4: Terminal A   (new transaction -> fresh snapshot)
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) AS open_in_a FROM pickup
 WHERE status='OPEN' AND zone_id=:z AND scheduled_date<=CURRENT_DATE;
-- A now sees N+1 (the row committed by B earlier)
COMMIT;
```

> Cleanup (either terminal):
> ```sql
> DELETE FROM pickup WHERE pickup_type='on_demand' AND status='OPEN' AND scheduled_date=CURRENT_DATE
>  AND customer_id IN (SELECT customer_id FROM customer WHERE phone LIKE '+2348000999%')
>  AND created_at > now() - INTERVAL '5 minutes';
> ```

---

## What you should observe

| Isolation level     | A's 2nd read sees B's insert? | Snapshot |
|---|---|---|
| READ COMMITTED      | **Yes** (N → N+1)             | per-statement |
| REPEATABLE READ     | **No**  (N → N, then N+1 in next txn) | per-transaction |

REPEATABLE READ in PostgreSQL is actually **snapshot isolation** — it prevents non-repeatable reads
and phantoms. The trade-off: a transaction can fail with `ERROR: could not serialize access due to
concurrent update` if it tries to UPDATE a row another session modified; the app must retry.

## What to screenshot

1. Demo 1: A's two `SELECT count(*)` outputs showing `N` then `N+1`.
2. Demo 2: A's three `SELECT count(*)` outputs showing `N`, `N`, then `N+1`.

## Study session

Maps to **Session 3 — Transaction isolation, MVCC snapshots** (PostgreSQL isolation levels, snapshot
isolation, per-statement vs per-transaction snapshots).
