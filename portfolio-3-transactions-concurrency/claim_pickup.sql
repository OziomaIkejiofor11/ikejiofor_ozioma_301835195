-- portfolio-3-transactions-concurrency/claim_pickup.sql
-- claim_pickup(p_driver_id, p_zone_id) : atomic transaction that lets a driver take the
-- next OPEN pickup in their zone and mark it ASSIGNED. Uses SELECT ... FOR UPDATE
-- SKIP LOCKED LIMIT 1 so two drivers never grab the same pickup.
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION claim_pickup(p_driver_id bigint, p_zone_id bigint)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
    v_pickup_id bigint;
    v_shift_id  bigint;
BEGIN
    -- the driver's shift in this zone today
    SELECT s.shift_id INTO v_shift_id
      FROM shift s
     WHERE s.driver_id = p_driver_id
       AND s.zone_id   = p_zone_id
       AND s.shift_date = CURRENT_DATE
     ORDER BY s.shift_id DESC
     LIMIT 1;
    IF v_shift_id IS NULL THEN
        RAISE EXCEPTION 'no shift for driver % in zone % today', p_driver_id, p_zone_id;
    END IF;

    -- work queue: skip rows already locked by another driver
    SELECT p.pickup_id INTO v_pickup_id
      FROM pickup p
     WHERE p.zone_id = p_zone_id
       AND p.status  = 'OPEN'
       AND p.scheduled_date <= CURRENT_DATE
     ORDER BY p.requested_at
     FOR UPDATE SKIP LOCKED
     LIMIT 1;

    IF v_pickup_id IS NULL THEN
        RETURN NULL;              -- nothing to claim right now
    END IF;

    -- conditional update guards against any race that slipped past the lock
    UPDATE pickup
       SET status = 'ASSIGNED', shift_id = v_shift_id
     WHERE pickup_id = v_pickup_id
       AND status = 'OPEN';

    RETURN v_pickup_id;
END $$;

-- ---------- demo ----------
\echo '==> claim_pickup() demo (explicit BEGIN / COMMIT)'
BEGIN;
SELECT claim_pickup(
        (SELECT crew_member_id FROM crew_member WHERE phone = '+2348000999001'),
        (SELECT zone_id FROM zone
          WHERE day_name_to_dow(collection_day) = EXTRACT(DOW FROM CURRENT_DATE)::int
          ORDER BY zone_id LIMIT 1)
       ) AS claimed_pickup_id \gset

\echo '==> claimed pickup_id = ' :claimed_pickup_id
SELECT pickup_id, status, shift_id, zone_id
  FROM pickup WHERE pickup_id = :claimed_pickup_id;
COMMIT;

\echo '==> after COMMIT, the row is ASSIGNED:'
SELECT pickup_id, status, shift_id FROM pickup WHERE pickup_id = :claimed_pickup_id;
