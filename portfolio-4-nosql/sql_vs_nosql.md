# Portfolio 4 — SQL vs NoSQL comparison (CleanRoute)

Both models use the **same case study** (CleanRoute Waste Services). The relational side
(Portfolio 1) handles the transactional core; the MongoDB side (this portfolio) handles sensor
telemetry and heterogeneous complaint reports.

## What lives where and why

| Concern | PostgreSQL (Portfolio 1) | MongoDB (Portfolio 4) |
|---|---|---|
| Customers, subscriptions, trucks, shifts, pickups, payments | ✅ relational, normalised to 3NF | ❌ not duplicated |
| Smart-bin sensor readings (fill %, temperature, battery every 15 min) | possible but heavy | ✅ time-series collection, ~65k docs/2 weeks |
| Complaint reports (missed pickup / spillage / illegal dumping) with different fields per type | needs many nullable columns or child tables | ✅ one collection, `$jsonSchema` `oneOf` per type |

## Dimension-by-dimension comparison

| Dimension | PostgreSQL | MongoDB |
|---|---|---|
| Data model | relational, schema-on-write, normalised to 3NF/BCNF | document / time-series, schema-on-read with optional `$jsonSchema` validation |
| Schema evolution | `ALTER TABLE` migrations, expensive on large tables | add a field by writing it; validation relaxed by changing the validator |
| Heterogeneous records | needs `NULL`-heavy columns or `TABLE` inheritance / child tables | natural fit — each complaint type simply carries its own sub-document |
| Time-series | `tstzrange`, partitioning (Portfolio 5), B-tree indexes | dedicated time-series collection with bucketed storage, automatic indexing on `meta` + `timeField` |
| Transactions | full ACID, MVCC, isolation levels, `FOR UPDATE SKIP LOCKED` | multi-document ACID since 4.0 (replica sets), single-document atomicity always |
| Joins | first-class (`JOIN`), planner-optimised | `$lookup` (limited), or denormalise / embed |
| Ad-hoc aggregation | SQL `GROUP BY`, window functions | aggregation pipeline (`$match`, `$group`, `$bucket`, `$densify`) |
| Consistency | strong (single primary) | tunable: read preference + read concern + write concern |
| Scaling | vertical first; read replicas, partitioning (P5) | horizontal sharding built-in; time-series buckets compress old data |
| Schema validation | `CHECK`, FKs, triggers, exclusion constraints | `$jsonSchema` (`oneOf`/`anyOf`), `validationLevel`, `validationAction` |
| Best workload | OLTP, complex joins, strict integrity | telemetry, event logs, polymorphic documents, rapid schema iteration |

## Why each was chosen for CleanRoute

- **PostgreSQL for the billing / dispatch core.** Payments, subscriptions, pickups, and shift
  assignments have strict integrity rules (one active subscription per customer, no overlapping
  shifts, status transitions, capacity limits). These are enforced declaratively with FKs, partial
  UNIQUE, `btree_gist` exclusion, and triggers — exactly where a relational database earns its
  keep. The data is highly structured and join-heavy (truck → shift → pickup → collection_record →
  disposal_site).

- **MongoDB for smart-bin telemetry.** 48 bins emit a reading every 15 minutes — ~65k documents in
  two weeks, append-only, time-ordered. MongoDB's time-series collection buckets the data, indexes
  the `timeField` automatically, and lets the operations dashboard ask "which bins are over 80%
  right now?" with a single `$group` over the latest slice. A relational table would work but is
  heavier to manage at this write rate.

- **MongoDB for complaint reports.** Missed-pickup, spillage, and illegal-dumping complaints share
  a common envelope (`complaint_id`, `type`, `location`, `photos`, `status_history`) but differ in
  their detail fields (`missed_pickup_details`, `spillage_details`, `illegal_dumping_details`). In
  SQL this means three detail tables + `LEFT JOIN`s or a wide `NULL`-heavy table. In MongoDB one
  collection holds all three shapes, and a `$jsonSchema` validator with `oneOf` enforces that each
  `type` carries its required detail sub-document — no migration when a new complaint type is added.

## Trade-offs

- **Joins:** the operations dashboard needs "open pickups per zone + the responsible driver's
  phone", which is a 3-table join in SQL and trivial. In MongoDB we would either denormalise the
  driver phone into the pickup document or do `$lookup` — both are weaker than SQL `JOIN`.
- **Consistency:** PostgreSQL gives strong consistency for free; MongoDB requires choosing a read
  concern / write concern and accepting that reads from a secondary may lag.
- **Schema discipline:** MongoDB's flexibility is a double-edged sword — without the validator,
  typos in field names silently create new fields. The `$jsonSchema` validator mitigates this but
  is less expressive than SQL `CHECK` + triggers (no cross-document constraints).

## When you would flip the choice

- If CleanRoute added a payments-fintech layer with strict double-entry accounting, keep that in
  PostgreSQL even if everything else moved.
- If bin telemetry grew to millions of readings per minute with mostly-append access, MongoDB
  time-series (or a dedicated TSDB) stays the right call; PostgreSQL partitioning (Portfolio 5)
  would be the fallback for a single-vendor stack.

## References

- MongoDB, *Timeseries Collections* — https://www.mongodb.com/docs/manual/core/timeseries-collections/
- MongoDB, *`$jsonSchema` schema validation* — https://www.mongodb.com/docs/manual/core/schema-validation/
- PostgreSQL, *Constraints / Exclusion* — https://www.postgresql.org/docs/16/ddl-constraints.html
