# Portfolio 4 — NoSQL & Advanced Data Models (README)

MongoDB smart-bin telemetry (time-series, 15-min interval, 40k+ docs) + complaint reports
(polymorphic documents, `$jsonSchema` `oneOf` validation) + aggregations + COLLSCAN→IXSCAN indexes.

## Commands (Codespaces)

Assumes `bash setup.sh` has installed and started MongoDB 8.

```bash
bash portfolio-4-nosql/run_p4.sh

# or step by step:
mongosh portfolio-4-nosql/setup_validation.js
mongosh portfolio-4-nosql/generate_sensor_data.js
mongosh portfolio-4-nosql/generate_complaints.js
mongosh portfolio-4-nosql/create_indexes.js
mongosh portfolio-4-nosql/aggregations.js
```

## What to screenshot

1. `setup_validation.js` output confirming the three collections were created.
2. `db.runCommand({ collInfos: "complaints" })` showing the `$jsonSchema` validator with `oneOf`.
3. `generate_sensor_data.js` final `bin_readings count` (must be 40k+).
4. `aggregations.js` output for A1 (bins over 80% by zone), A2 (avg fill per day), A3 (complaints
   per zone + type).
5. `create_indexes.js` BEFORE / AFTER `explain()` outputs showing `COLLSCAN` → `IXSCAN` (or
   `COLLSCAN` → `IXSCAN` + `FETCH`), and the `getIndexes()` lists.
6. A deliberate insert that violates the validator, e.g.
   `db.complaints.insertOne({type:"spillage", customer_id:NumberInt(1), zone:"Lekki", location:{address:"x"}, status_history:[{status:"open",at:new Date()}], created_at:new Date()})`
   → must fail with `Document failed validation`.

## Suggested git commit

```bash
git add portfolio-4-nosql/
git commit -m "P4: MongoDB time-series bins + polymorphic complaints (jsonSchema oneOf), aggregations, indexes"
```

## What it demonstrates / study session

Time-series collections, `$jsonSchema` validation with `oneOf` for polymorphic documents, the
aggregation pipeline, and index-driven plan changes (COLLSCAN → IXSCAN). Maps to **Session 4 —
NoSQL & advanced data models**. See `sql_vs_nosql.md` for the full SQL-vs-NoSQL comparison on the
same case study.
