# Portfolio 3 — Transactions & Concurrency (README)

`claim_pickup()` and `record_collection()` transactions, COMMIT/ROLLBACK of an overloaded
collection, and step-by-step two-terminal guides for the race condition (bug + 2 fixes), isolation
levels, and a deadlock.

## Commands (Codespaces)

Assumes `cleanroute` is loaded by portfolio 1.

```bash
# one-shot: setup + functions + rollback demo + ALL two-session demos (real sessions, saved to
# portfolio-3-transactions-concurrency/race_demos_output.log)
bash portfolio-3-transactions-concurrency/run_p3.sh

# optional - the same demos typed by hand in two terminals (open two shells, follow the guides in order):
#   race_condition_guide.md    (bug, FIX 1 conditional UPDATE, FIX 2 SKIP LOCKED)
#   isolation_levels_guide.md  (READ COMMITTED vs REPEATABLE READ)
#   deadlock_demo_guide.md     (AB-BA deadlock)
sudo runuser -u postgres -- psql -d cleanroute
```

## What to screenshot

1. `claim_pickup.sql` output: a pickup going from OPEN to ASSIGNED inside a BEGIN/COMMIT.
2. `record_collection.sql` output: a pickup going ASSIGNED -> COLLECTED with a new
   `collection_record` row.
3. `rollback_demo.sql` STEP 1 (COMMIT path, 8 kg accepted) and STEP 2 (ROLLBACK path, overload
   rejected by the capacity trigger) — and the verification `SELECT` showing pickup 2 still ASSIGNED
   with no collection_record.
4. From `race_condition_guide.md`: Scenario 1 (two `UPDATE 1`), Scenario 2 (`UPDATE 1` vs `UPDATE 0`),
   Scenario 3 (two different `:pid` values).
5. From `isolation_levels_guide.md`: the N → N+1 vs N → N → N+1 counts.
6. From `deadlock_demo_guide.md`: the `ERROR: deadlock detected` block.

## Suggested git commit

```bash
git add portfolio-3-transactions-concurrency/
git commit -m "P3: claim/record transactions, COMMIT/ROLLBACK, race condition, isolation, deadlock"
```

## What it demonstrates / study session

ACID transactions in PL/pgSQL, MVCC isolation levels, row-level locking, `FOR UPDATE SKIP LOCKED`
work queues, conditional (compare-and-swap) UPDATEs, and deadlock detection. Maps to **Session 3 —
Transactions, concurrency control, locking, MVCC**.
