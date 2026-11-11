-- portfolio-1-database-design/schema.sql
-- CleanRoute Waste Services - relational schema, keys, constraints, triggers.
-- Target: PostgreSQL 16. Run as superuser (postgres) so CREATE EXTENSION works.
\set ON_ERROR_STOP on

-- ---------- Extensions ----------
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- scalar opclasses for EXCLUDE USING gist
CREATE EXTENSION IF NOT EXISTS pgcrypto;     -- gen_random_uuid() if needed later

-- ---------- Enum-ish CHECK domains via CHECK (kept portable) ----------

DROP TABLE IF EXISTS collection_record CASCADE;
DROP TABLE IF EXISTS pickup CASCADE;
DROP TABLE IF EXISTS shift CASCADE;
DROP TABLE IF EXISTS payment CASCADE;
DROP TABLE IF EXISTS subscription CASCADE;
DROP TABLE IF EXISTS customer CASCADE;
DROP TABLE IF EXISTS crew_member CASCADE;
DROP TABLE IF EXISTS truck CASCADE;
DROP TABLE IF EXISTS disposal_site CASCADE;
DROP TABLE IF EXISTS zone CASCADE;

-- ---------- 1. zone ----------
CREATE TABLE zone (
    zone_id        BIGSERIAL PRIMARY KEY,
    name           TEXT NOT NULL UNIQUE,
    city           TEXT NOT NULL CHECK (city IN ('Lagos','Enugu')),
    collection_day TEXT NOT NULL
        CHECK (collection_day IN
            ('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- 2. customer ----------
CREATE TABLE customer (
    customer_id  BIGSERIAL PRIMARY KEY,
    name         TEXT NOT NULL,
    type         TEXT NOT NULL CHECK (type IN ('household','business')),
    address      TEXT NOT NULL,
    zone_id      BIGINT NOT NULL REFERENCES zone(zone_id),
    phone        TEXT NOT NULL,
    email        TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_customer_zone ON customer(zone_id);

-- ---------- 3. subscription ----------
CREATE TABLE subscription (
    subscription_id    BIGSERIAL PRIMARY KEY,
    customer_id        BIGINT NOT NULL REFERENCES customer(customer_id),
    plan               TEXT NOT NULL
        CHECK (plan IN ('weekly_basic','weekly_premium','business')),
    start_date         DATE NOT NULL,
    end_date           DATE,                         -- NULL = still active
    monthly_fee_naira  NUMERIC(10,2) NOT NULL CHECK (monthly_fee_naira > 0),
    status             TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','suspended','cancelled')),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- a customer can have only ONE active subscription (partial UNIQUE)
CREATE UNIQUE INDEX uq_one_active_subscription
    ON subscription(customer_id) WHERE status = 'active';
CREATE INDEX idx_subscription_customer ON subscription(customer_id);

-- ---------- 4. truck ----------
CREATE TABLE truck (
    truck_id        BIGSERIAL PRIMARY KEY,
    plate_number    TEXT NOT NULL UNIQUE,
    capacity_tonnes NUMERIC(6,2) NOT NULL CHECK (capacity_tonnes > 0),
    status          TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','maintenance','decommissioned')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- 5. crew_member ----------
CREATE TABLE crew_member (
    crew_member_id BIGSERIAL PRIMARY KEY,
    full_name      TEXT NOT NULL,
    role           TEXT NOT NULL CHECK (role IN ('driver','collector')),
    phone          TEXT NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- 6. shift ----------
CREATE TABLE shift (
    shift_id     BIGSERIAL PRIMARY KEY,
    truck_id     BIGINT NOT NULL REFERENCES truck(truck_id),
    driver_id    BIGINT NOT NULL REFERENCES crew_member(crew_member_id),
    zone_id      BIGINT NOT NULL REFERENCES zone(zone_id),
    shift_date   DATE NOT NULL,
    shift_start  TIMESTAMPTZ NOT NULL,
    shift_end    TIMESTAMPTZ NOT NULL,
    time_range   TSTZRANGE,                          -- populated by trigger
    status       TEXT NOT NULL DEFAULT 'planned'
        CHECK (status IN ('planned','active','closed')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (shift_end > shift_start)
);
CREATE INDEX idx_shift_zone_date ON shift(zone_id, shift_date);
CREATE INDEX idx_shift_truck     ON shift(truck_id);
CREATE INDEX idx_shift_driver    ON shift(driver_id);

-- ---------- 7. pickup ----------
CREATE TABLE pickup (
    pickup_id      BIGSERIAL PRIMARY KEY,
    customer_id    BIGINT NOT NULL REFERENCES customer(customer_id),
    zone_id        BIGINT NOT NULL REFERENCES zone(zone_id),
    scheduled_date DATE NOT NULL,
    requested_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    pickup_type    TEXT NOT NULL CHECK (pickup_type IN ('scheduled','on_demand')),
    status         TEXT NOT NULL DEFAULT 'OPEN'
        CHECK (status IN ('OPEN','ASSIGNED','COLLECTED','MISSED')),
    shift_id       BIGINT REFERENCES shift(shift_id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    collected_at   TIMESTAMPTZ
);
CREATE INDEX idx_pickup_zone_status  ON pickup(zone_id, status);
CREATE INDEX idx_pickup_status       ON pickup(status);
CREATE INDEX idx_pickup_scheduled    ON pickup(scheduled_date);
CREATE INDEX idx_pickup_shift        ON pickup(shift_id);
CREATE INDEX idx_pickup_customer     ON pickup(customer_id);

-- ---------- 8. disposal_site (defined before collection_record because of FK) ----------
CREATE TABLE disposal_site (
    disposal_site_id BIGSERIAL PRIMARY KEY,
    name             TEXT NOT NULL,
    type             TEXT NOT NULL CHECK (type IN ('dumpsite','recycling_centre')),
    city             TEXT NOT NULL CHECK (city IN ('Lagos','Enugu')),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- 9. collection_record ----------
CREATE TABLE collection_record (
    record_id        BIGSERIAL PRIMARY KEY,
    pickup_id        BIGINT NOT NULL UNIQUE REFERENCES pickup(pickup_id),
    shift_id         BIGINT NOT NULL REFERENCES shift(shift_id),
    weight_kg        NUMERIC(10,2) NOT NULL CHECK (weight_kg > 0),
    waste_type       TEXT NOT NULL
        CHECK (waste_type IN ('general','recyclable','organic')),
    disposal_site_id BIGINT NOT NULL REFERENCES disposal_site(disposal_site_id),
    recorded_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_collection_shift   ON collection_record(shift_id);
CREATE INDEX idx_collection_waste   ON collection_record(waste_type);
CREATE INDEX idx_collection_pickup  ON collection_record(pickup_id);

-- ---------- 10. payment ----------
CREATE TABLE payment (
    payment_id     BIGSERIAL PRIMARY KEY,
    customer_id    BIGINT NOT NULL REFERENCES customer(customer_id),
    amount_naira   NUMERIC(12,2) NOT NULL CHECK (amount_naira > 0),
    billing_month  DATE NOT NULL,
    status         TEXT NOT NULL DEFAULT 'unpaid'
        CHECK (status IN ('paid','unpaid','partial')),
    paid_at        TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_payment_customer  ON payment(customer_id);
CREATE INDEX idx_payment_status    ON payment(status);
CREATE INDEX idx_payment_month     ON payment(billing_month);

-- =====================================================================
-- Helper: day name -> integer day-of-week (Sunday=0 .. Saturday=6)
-- so we can compare with EXTRACT(DOW FROM <date>).
-- =====================================================================
CREATE OR REPLACE FUNCTION day_name_to_dow(d TEXT) RETURNS INTEGER
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE lower(d)
        WHEN 'sunday'    THEN 0
        WHEN 'monday'    THEN 1
        WHEN 'tuesday'   THEN 2
        WHEN 'wednesday' THEN 3
        WHEN 'thursday'  THEN 4
        WHEN 'friday'    THEN 5
        WHEN 'saturday'  THEN 6
        ELSE NULL END;
$$;

-- =====================================================================
-- Shift time_range auto-fill + exclusion constraints (btree_gist)
--   (a) a truck cannot be on two overlapping shifts
--   (b) a driver cannot drive two overlapping shifts
-- =====================================================================
CREATE OR REPLACE FUNCTION fill_shift_time_range()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.shift_start IS NOT NULL AND NEW.shift_end IS NOT NULL THEN
        NEW.time_range := tstzrange(NEW.shift_start, NEW.shift_end, '[)');
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_fill_shift_time_range
BEFORE INSERT OR UPDATE OF shift_start, shift_end ON shift
FOR EACH ROW EXECUTE FUNCTION fill_shift_time_range();

-- (a) no two overlapping shifts for the same truck
ALTER TABLE shift
    ADD CONSTRAINT exc_truck_no_overlap
    EXCLUDE USING gist (truck_id WITH =, time_range WITH &&);

-- (b) no two overlapping shifts for the same driver
ALTER TABLE shift
    ADD CONSTRAINT exc_driver_no_overlap
    EXCLUDE USING gist (driver_id WITH =, time_range WITH &&);

-- =====================================================================
-- Trigger: scheduled pickups only on the zone's weekly collection day.
-- =====================================================================
CREATE OR REPLACE FUNCTION check_pickup_collection_day()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    z_dow   INTEGER;
    sched_dow INTEGER;
BEGIN
    IF NEW.pickup_type = 'scheduled' AND NEW.scheduled_date IS NOT NULL THEN
        SELECT day_name_to_dow(z.collection_day) INTO z_dow
          FROM zone z WHERE z.zone_id = NEW.zone_id;
        sched_dow := EXTRACT(DOW FROM NEW.scheduled_date)::int;
        IF z_dow IS NULL THEN
            RAISE EXCEPTION 'zone % has no valid collection_day', NEW.zone_id;
        END IF;
        IF z_dow <> sched_dow THEN
            RAISE EXCEPTION
              'scheduled pickup for zone % must fall on its collection day (%) - got %',
              NEW.zone_id,
              (SELECT collection_day FROM zone WHERE zone_id = NEW.zone_id),
              NEW.scheduled_date;
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_pickup_collection_day
BEFORE INSERT OR UPDATE OF scheduled_date, zone_id, pickup_type ON pickup
FOR EACH ROW EXECUTE FUNCTION check_pickup_collection_day();

-- =====================================================================
-- Trigger: a shift's total collected weight cannot exceed truck capacity.
-- Fires on collection_record insert / update of weight or shift.
-- =====================================================================
CREATE OR REPLACE FUNCTION check_shift_capacity()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    t_id        BIGINT;
    cap_kg      NUMERIC;
    cur_total   NUMERIC;
BEGIN
    SELECT s.truck_id INTO t_id FROM shift s WHERE s.shift_id = NEW.shift_id;
    IF t_id IS NULL THEN
        RAISE EXCEPTION 'shift % not found', NEW.shift_id;
    END IF;
    SELECT t.capacity_tonnes * 1000 INTO cap_kg FROM truck t WHERE t.truck_id = t_id;
    SELECT COALESCE(SUM(weight_kg), 0) INTO cur_total
      FROM collection_record
     WHERE shift_id = NEW.shift_id
       AND record_id <> NEW.record_id;
    IF cur_total + NEW.weight_kg > cap_kg THEN
        RAISE EXCEPTION
          'shift % would exceed truck capacity: current % kg + new % kg > capacity % kg (truck %)',
          NEW.shift_id, cur_total, NEW.weight_kg, cap_kg, t_id;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_shift_capacity
BEFORE INSERT OR UPDATE OF weight_kg, shift_id ON collection_record
FOR EACH ROW EXECUTE FUNCTION check_shift_capacity();

-- =====================================================================
-- Trigger: pickup status transition: OPEN -> ASSIGNED -> COLLECTED,
--          or -> MISSED.  COLLECTED and MISSED are terminal.
-- =====================================================================
CREATE OR REPLACE FUNCTION check_pickup_status_transition()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- allowed: OPEN -> ASSIGNED, OPEN -> MISSED,
    --          ASSIGNED -> COLLECTED, ASSIGNED -> MISSED.
    -- COLLECTED and MISSED are terminal; OPEN cannot jump straight to COLLECTED.
    IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
        IF NOT (
               (OLD.status = 'OPEN'     AND NEW.status IN ('ASSIGNED','MISSED'))
            OR (OLD.status = 'ASSIGNED' AND NEW.status IN ('COLLECTED','MISSED'))
        ) THEN
            RAISE EXCEPTION 'invalid pickup status transition: % -> %',
                OLD.status, NEW.status;
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_pickup_status_transition
BEFORE UPDATE OF status ON pickup
FOR EACH ROW EXECUTE FUNCTION check_pickup_status_transition();

-- =====================================================================
-- Helpful views for the later portfolios
-- =====================================================================
CREATE OR REPLACE VIEW v_open_pickups_today AS
SELECT p.pickup_id, p.customer_id, p.zone_id, z.name AS zone_name,
       p.pickup_type, p.scheduled_date, p.requested_at
  FROM pickup p JOIN zone z USING (zone_id)
 WHERE p.status = 'OPEN' AND p.scheduled_date = CURRENT_DATE;

-- done
