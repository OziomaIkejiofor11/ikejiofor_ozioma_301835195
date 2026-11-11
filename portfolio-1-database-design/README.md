# Portfolio 1 — Database Design & Modelling (README)

CleanRoute Waste Services: 10 tables, ER diagram, 3NF, constraints, bulk data, constraint tests.

## Commands (Codespaces)

```bash
bash portfolio-1-database-design/run_p1.sh
# or step by step:
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE cleanroute;"
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d cleanroute -f portfolio-1-database-design/schema.sql
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d cleanroute -f portfolio-1-database-design/generate_bulk.sql
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d cleanroute -f portfolio-1-database-design/constraint_tests.sql
```

## What to screenshot

1. The row-count summary printed by `generate_bulk.sql` (pickups and collection_records both 50k+).
2. The 8 `TEST N PASS - ...` lines from `constraint_tests.sql`.
3. `psql -d cleanroute -c "\d shift"` and `"\d pickup"` showing the two EXCLUDE constraints and the
   three triggers.

## Suggested git commit

```bash
git add portfolio-1-database-design/
git commit -m "P1: CleanRoute schema (10 tables), 3NF design, 50k bulk generator, 8 constraint tests"
```

## What it demonstrates / study session

A 10-table 3NF schema with `btree_gist` exclusion constraints on a `tstzrange` (no truck or driver
overlap), a partial UNIQUE index (one active subscription per customer), and three triggers
(scheduled pickups only on the zone's collection day; shift weight ≤ truck capacity; pickup status
OPEN→ASSIGNED→COLLECTED or MISSED). Maps to **Session 1 — ER design, normalisation, integrity
constraints**. See `3nf_notes.md` for the ER diagram (Mermaid) and full normalisation notes.
