-- portfolio-3-transactions-concurrency/rollback_demo.sql
-- Demonstrates COMMIT (a valid collection) and ROLLBACK (an overloaded collection
-- that the shift_capacity trigger rejects). The nested BEGIN..EXCEPTION creates a
-- subtransaction: the overload insert is rolled back while the valid insert survives.
\set ON_ERROR_STOP on

DO $$
DECLARE
    v_p1        bigint;
    v_p2        bigint;
    v_rec       bigint;
    v_shift     bigint;
    v_truck     bigint;
    v_cap_kg    numeric;
    v_over      numeric;
    v_driver    bigint;
    v_zone      bigint;
    v_dsite     bigint;
    v_accepted  boolean := false;
BEGIN
    SELECT crew_member_id INTO v_driver FROM crew_member WHERE phone = '+2348000999001';
    SELECT zone_id INTO v_zone FROM zone
      WHERE day_name_to_dow(collection_day) = EXTRACT(DOW FROM CURRENT_DATE)::int
      ORDER BY zone_id LIMIT 1;

    v_p1 := claim_pickup(v_driver, v_zone);
    v_p2 := claim_pickup(v_driver, v_zone);
    IF v_p1 IS NULL OR v_p2 IS NULL THEN
        RAISE EXCEPTION 'need at least 2 OPEN pickups today in zone % (got p1=%, p2=%)',
                        v_zone, v_p1, v_p2;
    END IF;

    SELECT disposal_site_id INTO v_dsite FROM disposal_site
     WHERE type = 'dumpsite'
       AND city = (SELECT city FROM zone WHERE zone_id = v_zone)
     ORDER BY disposal_site_id LIMIT 1;

    -- STEP 1 (COMMIT path): a valid 8 kg collection on pickup 1
    v_rec := record_collection(v_p1, 8, 'general', v_dsite);
    RAISE NOTICE 'STEP 1 (COMMIT path): pickup % -> COLLECTED, record % (8 kg)', v_p1, v_rec;

    -- STEP 2 (ROLLBACK path): an overload on pickup 2 -> trigger must reject
    SELECT shift_id INTO v_shift FROM pickup WHERE pickup_id = v_p2;
    SELECT s.truck_id INTO v_truck FROM shift s WHERE s.shift_id = v_shift;
    SELECT t.capacity_tonnes * 1000 INTO v_cap_kg FROM truck t WHERE t.truck_id = v_truck;
    v_over := v_cap_kg + 50;   -- definitely over capacity
    BEGIN
        PERFORM record_collection(v_p2, v_over, 'general', v_dsite);
        v_accepted := true;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'STEP 2 (ROLLBACK path): overload % kg rejected by trigger -> %', v_over, SQLERRM;
    END;
    IF v_accepted THEN
        RAISE EXCEPTION 'STEP 2 FAILED: overload % kg was accepted (should have rolled back)', v_over;
    END IF;
END $$;

\echo '==> verification:'
\echo '    - STEP 1 pickup is COLLECTED with a collection_record (survived).'
\echo '    - STEP 2 pickup is still ASSIGNED with NO collection_record (rolled back).'
SELECT pickup_id, status
  FROM pickup
 WHERE shift_id = (SELECT shift_id FROM shift
                    WHERE driver_id = (SELECT crew_member_id FROM crew_member WHERE phone='+2348000999001')
                      AND shift_date = CURRENT_DATE)
 ORDER BY pickup_id;

SELECT cr.record_id, cr.pickup_id, cr.weight_kg
  FROM collection_record cr
 WHERE cr.shift_id = (SELECT shift_id FROM shift
                       WHERE driver_id = (SELECT crew_member_id FROM crew_member WHERE phone='+2348000999001')
                         AND shift_date = CURRENT_DATE)
 ORDER BY cr.pickup_id;
