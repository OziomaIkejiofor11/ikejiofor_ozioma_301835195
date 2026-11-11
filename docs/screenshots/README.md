# Screenshots / evidence to capture (from YOUR own Codespace run)

Screenshots must come from your own run. Take them from the terminal or from the `*_output.log` files
that the run-all step saved (they are committed to the repo). Never edit or invent output.

| # | Portfolio | What to capture | Where it comes from |
|---|---|---|---|
| 1 | P1 | `\dt` and the row counts (54k+ pickups) | `p1_output.log` |
| 2 | P1 | the 8 constraint tests, all PASS | `p1_output.log` |
| 3 | P2 | BEFORE/AFTER table | `portfolio-2-query-optimisation/p2_summary.txt` |
| 4 | P2 | Q1 plan before and after (Bitmap Heap Scan to Index Only Scan) | `p2_explain_BEFORE.txt` / `p2_explain_AFTER.txt` |
| 5 | P3 | claim and record transactions, COMMIT and ROLLBACK demo | `p3_output.log` |
| 6 | P3 | race bug, the two fixes, isolation levels, deadlock | `portfolio-3-transactions-concurrency/race_demos_output.log` |
| 7 | P4 | COLLSCAN to IXSCAN for complaints (documents examined) | `p4_output.log` |
| 8 | P4 | aggregation results | `p4_output.log` |
| 9 | P5 | partition list and pruning plan | `portfolio-5-distributed-cloud/partition_output.log` |
| 10 | P5 | replica rejects write, row arrives, `pg_stat_replication` | `portfolio-5-distributed-cloud/replication_output.log` |
