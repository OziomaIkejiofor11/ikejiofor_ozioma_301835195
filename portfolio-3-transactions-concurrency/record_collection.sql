-- portfolio-3-transactions-concurrency/record_collection.sql
-- record_collection(p_pickup_id, p_weight_kg, p_waste_type, p_disposal_site_id)
--   - inserts the collection_record (the shift_capacity trigger checks truck capacity)
--   - marks the pickup COLLECTED (the status-transition trigger checks ASSIGNED -> COLLECTED)
--   - returns the new record_id
-- If the weight would overload the truck, the trigger raises -> the calling transaction
-- rolls back (see rollback_demo.sql).
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION record_collection(
    p_pickup_id        bigint,
    p_weight_kg        numeric,
    p_waste_type       text,
    p_disposal_site_id bigint)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
    v_shift_id  bigint;
    v_record_id bigint;
BEGIN
    IF p_weight_kg <= 0 THEN
        RAISE EXCEPTION 'weight must be > 0 (got %)', p_weight_kg;
    END IF;

    SELECT shift_id INTO v_shift_id FROM pickup WHERE pickup_id = p_pickup_id;
    IF v_shift_id IS NULL THEN
        RAISE EXCEPTION 'pickup % has no shift assigned; claim it first', p_pickup_id;
    END IF;
    IF (SELECT status FROM pickup WHERE pickup_id = p_pickup_id) <> 'ASSIGNED' THEN
        RAISE EXCEPTION 'pickup % is not ASSIGNED (must be ASSIGNED before COLLECTED)', p_pickup_id;
    END IF;

    -- shift_capacity trigger fires here; raises if cur_total + weight > truck capacity
    INSERT INTO collection_record(pickup_id, shift_id, weight_kg, waste_type, disposal_site_id)
    VALUES (p_pickup_id, v_shift_id, p_weight_kg, p_waste_type, p_disposal_site_id)
    RETURNING record_id INTO v_record_id;

    -- status transition trigger checks ASSIGNED -> COLLECTED
    UPDATE pickup
       SET status = 'COLLECTED', collected_at = now()
     WHERE pickup_id = p_pickup_id AND status = 'ASSIGNED';

    RETURN v_record_id;
END $$;

-- ---------- demo ----------
\echo '==> record_collection() demo (explicit BEGIN / COMMIT)'
BEGIN;
-- claim a fresh pickup for the demo driver
SELECT claim_pickup(
        (SELECT crew_member_id FROM crew_member WHERE phone = '+2348000999001'),
        (SELECT zone_id FROM zone
          WHERE day_name_to_dow(collection_day) = EXTRACT(DOW FROM CURRENT_DATE)::int
          ORDER BY zone_id LIMIT 1)
       ) AS claimed_pickup_id \gset

SELECT record_collection(:claimed_pickup_id, 12.50, 'general',
        (SELECT disposal_site_id FROM disposal_site WHERE type='dumpsite'
           AND city = (SELECT city FROM zone WHERE zone_id =
              (SELECT zone_id FROM pickup WHERE pickup_id = :claimed_pickup_id))
          ORDER BY disposal_site_id LIMIT 1)
       ) AS new_record_id \gset

COMMIT;

\echo '==> after COMMIT:'
SELECT pickup_id, status, collected_at FROM pickup WHERE pickup_id = :claimed_pickup_id;
SELECT record_id, pickup_id, weight_kg, waste_type FROM collection_record WHERE record_id = :new_record_id;
