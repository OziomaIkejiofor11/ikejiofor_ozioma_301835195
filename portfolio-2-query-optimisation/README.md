# Portfolio 2 — Query Processing & Optimisation (README)

8 analytical queries on CleanRoute data, with EXPLAIN ANALYZE before and after adding optimisation
indexes.

## Commands (Codespaces)

Assumes `cleanroute` is already loaded by `portfolio-1-database-design/run_p1.sh`.

```bash
# 1. run the queries and see the results
sudo runuser -u postgres -- psql -d cleanroute -f portfolio-2-query-optimisation/queries.sql

# 2. BEFORE indexes: capture EXPLAIN ANALYZE
sudo runuser -u postgres -- psql -d cleanroute -f portfolio-2-query-optimisation/explain_queries.sql > p2_explain_BEFORE.txt

# 3. add optimisation indexes
sudo runuser -u postgres -- psql -d cleanroute -f portfolio-2-query-optimisation/create_indexes.sql

# 4. AFTER indexes: capture EXPLAIN ANALYZE again
sudo runuser -u postgres -- psql -d cleanroute -f portfolio-2-query-optimisation/explain_queries.sql > p2_explain_AFTER.txt

# one-shot helper:
bash portfolio-2-query-optimisation/run_p2.sh
```

## What to screenshot

1. Output of `queries.sql` (8 result sets).
2. `p2_explain_BEFORE.txt` and `p2_explain_AFTER.txt` for at least Q1, Q4 and Q6 side by side.
3. The BEFORE/AFTER table in `p2_summary.txt` and the index list printed by `create_indexes.sql`.

## Suggested git commit

```bash
git add portfolio-2-query-optimisation/
git commit -m "P2: 8 analytical queries, EXPLAIN ANALYZE before/after optimisation indexes"
```

## What it demonstrates / study session

Query processing, EXPLAIN/ANALYZE, access-path selection (Seq Scan vs Index Scan / Bitmap Scan /
Index Only Scan), join strategies, and the effect of partial and composite indexes on the planner's
cost estimates. Maps to **Session 2 — Query processing & optimisation**. The real plans and a
BEFORE/AFTER table are written automatically by `run_p2.sh`; nothing is fabricated.
