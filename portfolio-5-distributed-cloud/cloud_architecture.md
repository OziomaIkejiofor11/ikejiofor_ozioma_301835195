# Portfolio 5 — Distributed & Cloud Database Architecture (CleanRoute)

This portfolio covers (a) monthly range partitioning of pickups, (b) a primary + streaming read
replica for the operations dashboard, and (c) a cloud architecture that keeps CleanRoute's data
**in Nigeria** under the **Nigeria Data Protection Act, 2023 (NDPA)**, with CAP and sync-vs-async
trade-offs and an offline-first design for driver apps on routes with poor network coverage.

## 1. Partitioning (PostgreSQL declarative range partitioning)

- The `pickup_part` table is `PARTITION BY RANGE (scheduled_date)` with one partition per month
  (`pickup_part_YYYY_MM`) across the 2-year window.
- The partition key is part of the primary key (`pickup_id, scheduled_date`) — a PostgreSQL
  requirement.
- **Benefit:** queries that filter on `scheduled_date` (the operations dashboard's "today" /
  "this week" views) prune to a single partition. `EXPLAIN (COSTS OFF)` in `partition_setup.sql`
  shows a 1-partition scan for a single-day filter versus a scan over all partitions for an
  unfiltered aggregate.
- **Maintenance:** old monthly partitions can be detached (`ALTER TABLE pickup_part DETACH
  PARTITION pickup_part_2024_01`) and archived/dropped without touching live data; future months
  can be pre-created by a cron job so inserts never fail.

## 2. Replication — primary + streaming read replica

- A physical streaming replica on port 5433, fed from the primary via a replication slot
  (`replica_slot`), built with `pg_basebackup -R`.
- The operations dashboard (heavy `SELECT`s for live maps and KPIs) reads from the **replica** so
  analytical load does not slow down transactional writes on the primary.
- `replica_demo.sql` proves: (i) the replica rejects writes
  (`ERROR: cannot execute INSERT in a read-only transaction`), and (ii) a row written on the
  primary appears on the replica via streaming.
- See `replica_setup_guide.md` / `replica_setup.sh` for the Codespaces-specific setup (own
  `postgresql.conf`, copied `pg_hba.conf` / `pg_ident.conf`, `chmod 700` data dir, trust at top of
  `pg_hba.conf`, Unix-socket connections).

## 3. Cloud architecture (data sovereignty under NDPA 2023)

```
                      ┌──────────────────────────────────────────────────────┐
                      │            Nigeria region (lagos1 / abuja1)           │
                      │   All CleanRoute data stays in-country (NDPA 2023)    │
                      │                                                      │
   Driver app  ─────► │  API gateway  ──►  app tier  ──►  PG primary (RW)     │
   (offline-first)    │                                   │ streaming          │
                      │                                   ▼                    │
                      │                          PG read replica (RO)         │
                      │                                   │                    │
                      │                                   ▼                    │
                      │                          Analytics / dashboard        │
                      │                                                      │
                      │  MongoDB replica set (smart-bin telemetry,           │
                      │  complaints) — same Nigeria region                   │
                      └──────────────────────────────────────────────────────┘
                                 ▲ WAL / oplog ship to a DR site in a
                                 │ second Nigerian availability zone (async)
                                 └────────────────────────────────────────────
```

### Data sovereignty — NDPA 2023

- The **Nigeria Data Protection Act, 2023** (administered by the Nigeria Data Protection
  Commission, NDPC) requires that personal data be processed lawfully, stored securely, and not
  transferred outside Nigeria without an adequate safeguard / authorisation.
- CleanRoute holds personal data (customer names, phone numbers, addresses, complaint photos that
  may show people). To stay compliant, **all primary data lives in a cloud region physically
  located in Nigeria** (e.g. a Lagos or Abuja availability zone from a provider offering in-country
  regions, or a self-hosted cluster in a Nigerian data centre).
- Cross-border transfer is limited to **aggregated, anonymised analytics** only, and only where the
  destination provides an adequate level of protection (NDPA §41). Raw personal data does not leave
  the country.
- Retention: sensor readings are downsampled after 90 days; complaint photos are deleted after the
  complaint is closed plus the NDPA retention window; customers can request erasure (NDPA right to
  erasure).

### CAP theorem trade-off

CleanRoute's operations workload is **CP-biased**:

- **Consistency** matters most for billing, payments, and pickup status (`OPEN → ASSIGNED →
  COLLECTED`). A missed or double-assigned pickup directly costs money and trust.
- **Availability** is important but the system can tolerate a replica being briefly unavailable —
  the dashboard falls back to the primary if the replica is down.
- **Partition tolerance** is non-negotiable (the driver app operates on routes with poor network),
  so the design must behave correctly under network partitions.

Concretely:

- The **PostgreSQL primary is the single source of truth** for writes. During a partition, writes
  are accepted only on the primary; a partitioned replica stops receiving WAL and serves stale-but-
  consistent reads (it does not become a divergent writable primary). This is CP.
- MongoDB (smart-bin telemetry) runs as a **replica set** with `writeConcern: majority` and
  `readConcern: majority` for complaint status transitions (also CP), but telemetry ingestion uses
  `writeConcern: 1` for throughput (effectively AP for raw readings — losing one reading is
  acceptable).

### Sync vs async replication trade-off

| Aspect | Synchronous (sync) | Asynchronous (async) |
|---|---|---|
| Data loss on primary failure | None (replica has every committed WAL byte) | Possible (last few transactions lost) |
| Write latency | Higher (primary waits for ≥1 replica ACK) | Lower (primary commits immediately) |
| Availability | Lower (if sync replica is down, writes stall) | Higher (primary keeps writing) |
| CleanRoute use | Used only for **payments** and **pickup status** (small volume, must not be lost) | Used for everything else — telemetry, complaints, analytics replica |

- PostgreSQL: `synchronous_standby_names = 'FIRST 1 (cleanroute_sync)'` for the payment-critical
  path; the dashboard replica stays **asynchronous** so heavy reads never stall a write.
- MongoDB: `w:majority` for complaint status changes, `w:1` for sensor readings.

### Offline-first driver app (routes with poor network)

Drivers collect in Lekki, Yaba, Ikeja, Surulere, Independence Layout and New Haven, where mobile
coverage is patchy. The driver app is **offline-first**:

1. **Local queue on the device:** every `claim_pickup` and `record_collection` is written to a
   local SQLite/IndexedDB outbox first, with a generated client-side idempotency key.
2. **Optimistic UI:** the driver sees the pickup as ASSIGNED / COLLECTED immediately, without
   waiting for the server.
3. **Background sync:** when connectivity returns, the app replays the outbox to the API, which
   calls `claim_pickup()` / `record_collection()` server-side. The idempotency key means a replayed
   request is never applied twice.
4. **Conflict resolution:** the server is authoritative. If two drivers claimed the same pickup
   while offline, the server's `UPDATE … WHERE status='OPEN'` / `FOR UPDATE SKIP LOCKED` logic
   (Portfolio 3) decides the winner; the loser is notified to release the pickup.
5. **Read replica for the dashboard:** even when the primary is busy with the sync replay, the
   operations dashboard keeps reading from the replica.

### Why not sharding (yet)

CleanRoute's write volume (a few hundred pickups/day across 6 zones) is far below the point where
horizontal sharding pays off. Partitioning by month (above) gives the maintenance benefit (drop old
months) without the cross-shard query complexity. Sharding by `zone_id` would be the natural next
step only if Lagos and Enugu became separate operational regions with their own write load.

## 4. CAP / sync-async summary table

| Workload | Consistency need | Choice | Reason |
|---|---|---|---|
| Payments | strong, no loss | PG sync replica (`FIRST 1`) | money |
| Pickup status | strong | PG primary + `SKIP LOCKED` | no double-assignment |
| Smart-bin readings | eventual OK | MongoDB async, `w:1` | volume, single reading is cheap |
| Complaint status | strong | MongoDB `w:majority` | audit / legal |
| Dashboard reads | eventual OK | PG async read replica | read scale-out |
| Driver app offline | eventual | local outbox + idempotent replay | coverage |

## References

- Nigeria Data Protection Commission, *Nigeria Data Protection Act, 2023* — https://ndpc.gov.ng/ng/data-protection-act-2023/
- PostgreSQL, *High Availability, Load Balancing, and Replication* — https://www.postgresql.org/docs/16/high-availability.html
- PostgreSQL, *Partitioning* — https://www.postgresql.org/docs/16/ddl-partitioning.html
- MongoDB, *Replica Sets* — https://www.mongodb.com/docs/manual/replication/
- Brewer's CAP theorem; Gilbert & Lynch, 2002.
