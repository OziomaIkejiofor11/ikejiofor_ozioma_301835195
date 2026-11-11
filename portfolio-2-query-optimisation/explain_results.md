# Portfolio 2 — EXPLAIN ANALYZE before / after indexes

Nothing in this file is typed by hand. `run_p2.sh` runs `explain_queries.sql` twice — before and after
`create_indexes.sql` — and builds the comparison table from the real EXPLAIN ANALYZE output:

| File (created by `run_p2.sh`) | What it holds |
|---|---|
| `p2_explain_BEFORE.txt` | full EXPLAIN ANALYZE for Q1–Q8 with only the baseline indexes |
| `p2_explain_AFTER.txt`  | the same eight plans after the optimisation indexes |
| `p2_summary.txt`        | BEFORE/AFTER table: scan used on the biggest table + real Execution Time + % change |

The same run is saved in `p2_output.log` at the repo root.

## How to read the result (honestly)

* **Q1 (open pickups today)** is the query the new partial index was built for. The plan moves from a
  Bitmap Heap Scan to an Index Only Scan on `idx_pickup_open_zone_date`, and the time drops sharply.
* **Q2, Q3, Q7, Q8** aggregate every row of a large table, so PostgreSQL correctly keeps a **Seq Scan**:
  an index cannot help when almost all rows are needed. Times stay roughly the same.
* **Q4 (missed-pickup rate)** reads the whole `pickup` table to count; the partial index on MISSED rows
  is not used, so there is no gain (small run-to-run differences of a few milliseconds are noise).
* An index is a trade-off: every extra index slows INSERT/UPDATE and uses disk, so an index that the
  planner does not use is not kept "to look good" — it is reported as not helping.

## My own analysis (student — written after reading p2_summary.txt)

> To be written by the student in their own words from their own `p2_summary.txt`: which queries
> improved, which did not, and why (cite the real milliseconds).
