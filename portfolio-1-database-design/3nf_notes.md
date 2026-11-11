# Portfolio 1 — Database Design & Modelling

**Case study:** CleanRoute Waste Services (Lagos + Enugu waste collection).

## ER diagram (Mermaid — renders on GitHub)

```mermaid
erDiagram
    ZONE ||--o{ CUSTOMER : serves
    ZONE ||--o{ SHIFT : covers
    CUSTOMER ||--o{ SUBSCRIPTION : holds
    CUSTOMER ||--o{ PICKUP : requests
    CUSTOMER ||--o{ PAYMENT : billed
    SUBSCRIPTION }o--|| CUSTOMER : belongs_to
    TRUCK ||--o{ SHIFT : used_in
    CREW_MEMBER ||--o{ SHIFT : drives_or_collects
    SHIFT ||--o{ PICKUP : fulfils
    SHIFT ||--o{ COLLECTION_RECORD : produces
    PICKUP ||--o| COLLECTION_RECORD : weighed_as
    DISPOSAL_SITE ||--o{ COLLECTION_RECORD : receives

    ZONE {
        bigint zone_id PK
        text name UK
        text city
        text collection_day
    }
    CUSTOMER {
        bigint customer_id PK
        text name
        text type
        text address
        bigint zone_id FK
        text phone
        text email
    }
    SUBSCRIPTION {
        bigint subscription_id PK
        bigint customer_id FK
        text plan
        date start_date
        date end_date
        numeric monthly_fee_naira
        text status
    }
    TRUCK {
        bigint truck_id PK
        text plate_number UK
        numeric capacity_tonnes
        text status
    }
    CREW_MEMBER {
        bigint crew_member_id PK
        text full_name
        text role
        text phone
    }
    SHIFT {
        bigint shift_id PK
        bigint truck_id FK
        bigint driver_id FK
        bigint zone_id FK
        date shift_date
        timestamptz shift_start
        timestamptz shift_end
        tstzrange time_range
        text status
    }
    PICKUP {
        bigint pickup_id PK
        bigint customer_id FK
        bigint zone_id FK
        date scheduled_date
        timestamptz requested_at
        text pickup_type
        text status
        bigint shift_id FK
        timestamptz collected_at
    }
    COLLECTION_RECORD {
        bigint record_id PK
        bigint pickup_id FK_UK
        bigint shift_id FK
        numeric weight_kg
        text waste_type
        bigint disposal_site_id FK
        timestamptz recorded_at
    }
    DISPOSAL_SITE {
        bigint disposal_site_id PK
        text name
        text type
        text city
    }
    PAYMENT {
        bigint payment_id PK
        bigint customer_id FK
        numeric amount_naira
        date billing_month
        text status
        timestamptz paid_at
    }
```

## Relational schema (keys)

| Table | PK | FKs | Notable constraints |
|---|---|---|---|
| zone | zone_id | — | name UNIQUE; collection_day CHECK |
| customer | customer_id | zone_id | type CHECK |
| subscription | subscription_id | customer_id | **partial UNIQUE (customer_id) WHERE status='active'** |
| truck | truck_id | — | plate_number UNIQUE; capacity_tonnes > 0 |
| crew_member | crew_member_id | — | role CHECK |
| shift | shift_id | truck_id, driver_id, zone_id | **EXCLUDE (truck_id, time_range &&)**; **EXCLUDE (driver_id, time_range &&)**; shift_end > shift_start |
| pickup | pickup_id | customer_id, zone_id, shift_id | status CHECK; **trigger: scheduled pickup on zone collection day**; **trigger: status OPEN→ASSIGNED→COLLECTED or MISSED** |
| disposal_site | disposal_site_id | — | type/city CHECK |
| collection_record | record_id | pickup_id (UNIQUE), shift_id, disposal_site_id | weight_kg > 0; **trigger: shift total ≤ truck capacity** |
| payment | payment_id | customer_id | amount_naira > 0; status CHECK |

## Normalisation (1NF → 2NF → 3NF)

- **1NF** — every column is atomic (e.g. `customer.address` is one text value; waste type is a
  single enum, not a comma list). No repeating groups: crew are stored in their own `crew_member`
  table and linked to shifts, not embedded as `crew1, crew2, crew3` columns.
- **2NF** — every non-key column depends on the whole primary key. All bridge/junction tables
  (`collection_record`, `pickup`, `shift`, `payment`, `subscription`) use a single surrogate key,
  and attributes such as `weight_kg` depend on the whole collection-record identity (pickup +
  shift), not on a sub-part. `customer.name` depends on `customer_id` alone; `zone.name` on
  `zone_id` alone.
- **3NF** — no transitive dependencies. `zone.city` and `zone.collection_day` depend only on
  `zone_id`, and the weekly collection day lives on `zone` (not on `customer` or `pickup`), so the
  scheduled-day trigger can validate against one source of truth. Truck capacity lives on `truck`,
  not on `shift` or `collection_record`; the capacity trigger joins `shift → truck` rather than
  copying `capacity_tonnes` into every shift row. `customer.type` is kept on `customer`; plan choice
  is stored once in `subscription`, not duplicated on `pickup` or `payment`.
- **BCNF** — every determinant is a candidate key: `subscription(customer_id)` is a candidate key
  for the active subset (enforced as a partial UNIQUE index), `pickup.pickup_id` is the only
  determinant of `collection_record` rows (UNIQUE FK), and `truck.plate_number` is a candidate key
  (UNIQUE). The schema satisfies BCNF.

## Files

| File | Purpose |
|---|---|
| `schema.sql` | 10 tables, all constraints + 4 triggers + btree_gist exclusion |
| `seed.sql` | small readable seed (alternative to bulk) |
| `generate_bulk.sql` | 50k+ pickups & collection records over ~2 years, festive bumps, ₦ payments |
| `constraint_tests.sql` | 8 self-contained tests that must be rejected by a constraint |
| `3nf_notes.md` | this file (ERD + normalisation notes) |
| `run_p1.sh` | one-shot runner |
| `README.md` | commands / screenshots / commit |

See `README.md` for run commands, what to screenshot, and the suggested git commit.

## Study session

Portfolio 1 → **Session 1 — Conceptual modelling, ER design, relational mapping, normalisation
(1NF→BCNF), integrity constraints**. Demonstrates 10 entities, exclusion constraints with
`btree_gist` on a `tstzrange`, partial UNIQUE, and three behavioural triggers.
