-- portfolio-1-database-design/constraint_tests.sql
-- Each test builds its OWN data inside one transaction (rolled back at the end, so the
-- bulk data is untouched) and attempts an operation a constraint MUST reject.
-- A test only PASSES when the INTENDED constraint (named in the test) raised the error;
-- if the bad row is accepted, or a different error fires, the test FAILS loudly.
\set ON_ERROR_STOP on
BEGIN;

-- helper: run one statement, require a specific constraint / trigger message
CREATE TEMP TABLE test_result(test TEXT, outcome TEXT, detail TEXT);

CREATE OR REPLACE FUNCTION pg_temp.expect_reject(p_test TEXT, p_sql TEXT, p_needle TEXT)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_msg TEXT; v_con TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME;
        v_msg := SQLERRM;
        IF v_msg ILIKE '%' || p_needle || '%' OR COALESCE(v_con,'') ILIKE '%' || p_needle || '%' THEN
            INSERT INTO test_result VALUES (p_test, 'PASS', left(v_msg, 120));
            RAISE NOTICE '% PASS - rejected by [%]: %', p_test, p_needle, left(v_msg, 120);
        ELSE
            INSERT INTO test_result VALUES (p_test, 'FAIL', 'wrong error: ' || v_msg);
            RAISE EXCEPTION '% FAILED: rejected, but not by [%]: %', p_test, p_needle, v_msg;
        END IF;
        RETURN;
    END;
    INSERT INTO test_result VALUES (p_test, 'FAIL', 'bad row was ACCEPTED');
    RAISE EXCEPTION '% FAILED: the bad operation was ACCEPTED', p_test;
END $$;

\o /dev/null
-- ---------- shared fixtures (rolled back at the end) ----------
-- a Wednesday-collection zone, a 5-tonne truck, a driver, a customer, one disposal site
INSERT INTO zone(name, city, collection_day) VALUES ('CT-Zone','Lagos','Wednesday');
INSERT INTO truck(plate_number, capacity_tonnes, status) VALUES ('CT-001-AA', 5, 'active'), ('CT-002-AA', 5, 'active');
INSERT INTO crew_member(full_name, role, phone) VALUES ('CT Driver A','driver','+2348000000001'), ('CT Driver B','driver','+2348000000002');
INSERT INTO customer(name, type, address, zone_id, phone)
    SELECT 'CT Customer','household','1 Test Street, CT-Zone', zone_id, '+2348000000003' FROM zone WHERE name='CT-Zone';
INSERT INTO disposal_site(name, type, city) VALUES ('CT Dump','dumpsite','Lagos');

-- a far-future closed shift so nothing collides with bulk shifts
INSERT INTO shift(truck_id, driver_id, zone_id, shift_date, shift_start, shift_end, status)
SELECT t.truck_id, d.crew_member_id, z.zone_id, DATE '2031-01-01',
       TIMESTAMPTZ '2031-01-01 06:00+00', TIMESTAMPTZ '2031-01-01 16:00+00', 'planned'
  FROM truck t, crew_member d, zone z
 WHERE t.plate_number='CT-001-AA' AND d.full_name='CT Driver A' AND z.name='CT-Zone';

-- TEST 1: same truck, overlapping window, DIFFERENT (real) driver -> exc_truck_no_overlap
SELECT pg_temp.expect_reject('TEST 1 truck overlap', $q$
    INSERT INTO shift(truck_id, driver_id, zone_id, shift_date, shift_start, shift_end, status)
    SELECT t.truck_id, d.crew_member_id, z.zone_id, DATE '2031-01-01',
           TIMESTAMPTZ '2031-01-01 08:00+00', TIMESTAMPTZ '2031-01-01 12:00+00', 'planned'
      FROM truck t, crew_member d, zone z
     WHERE t.plate_number='CT-001-AA' AND d.full_name='CT Driver B' AND z.name='CT-Zone'
$q$, 'exc_truck_no_overlap');

-- TEST 2: same driver, different truck, overlapping window -> exc_driver_no_overlap
SELECT pg_temp.expect_reject('TEST 2 driver overlap', $q$
    INSERT INTO shift(truck_id, driver_id, zone_id, shift_date, shift_start, shift_end, status)
    SELECT t.truck_id, d.crew_member_id, z.zone_id, DATE '2031-01-01',
           TIMESTAMPTZ '2031-01-01 08:00+00', TIMESTAMPTZ '2031-01-01 12:00+00', 'planned'
      FROM truck t, crew_member d, zone z
     WHERE t.plate_number='CT-002-AA' AND d.full_name='CT Driver A' AND z.name='CT-Zone'
$q$, 'exc_driver_no_overlap');

-- TEST 3: second ACTIVE subscription for one customer -> uq_one_active_subscription
INSERT INTO subscription(customer_id, plan, start_date, monthly_fee_naira, status)
    SELECT customer_id, 'weekly_basic', CURRENT_DATE - 30, 8000, 'active' FROM customer WHERE name='CT Customer';
SELECT pg_temp.expect_reject('TEST 3 one active subscription', $q$
    INSERT INTO subscription(customer_id, plan, start_date, monthly_fee_naira, status)
    SELECT customer_id, 'weekly_premium', CURRENT_DATE, 12000, 'active' FROM customer WHERE name='CT Customer'
$q$, 'uq_one_active_subscription');

-- TEST 4: scheduled pickup on a NON-collection day (zone collects Wednesday; use a Thursday)
SELECT pg_temp.expect_reject('TEST 4 collection-day trigger', $q$
    INSERT INTO pickup(customer_id, zone_id, scheduled_date, pickup_type, status)
    SELECT c.customer_id, c.zone_id,
           (SELECT g::date FROM generate_series(CURRENT_DATE, CURRENT_DATE + 6, INTERVAL '1 day') g
             WHERE EXTRACT(DOW FROM g) = 4),            -- always a Thursday
           'scheduled', 'OPEN'
      FROM customer c WHERE c.name='CT Customer'
$q$, 'collection day');

-- fixtures for the collection_record tests: a pickup on the 2031 shift
INSERT INTO pickup(customer_id, zone_id, scheduled_date, pickup_type, status, shift_id)
SELECT c.customer_id, c.zone_id, DATE '2031-01-01', 'on_demand', 'ASSIGNED',
       (SELECT shift_id FROM shift WHERE shift_date = DATE '2031-01-01' LIMIT 1)
  FROM customer c WHERE c.name='CT Customer';

-- TEST 5: shift over truck capacity. Truck is 5 t = 5000 kg; first load 4900 kg, then 200 kg more.
INSERT INTO collection_record(pickup_id, shift_id, weight_kg, waste_type, disposal_site_id)
SELECT p.pickup_id, p.shift_id, 4900, 'general', (SELECT disposal_site_id FROM disposal_site WHERE name='CT Dump')
  FROM pickup p WHERE p.scheduled_date = DATE '2031-01-01';
INSERT INTO pickup(customer_id, zone_id, scheduled_date, pickup_type, status, shift_id)
SELECT c.customer_id, c.zone_id, DATE '2031-01-01', 'on_demand', 'ASSIGNED',
       (SELECT shift_id FROM shift WHERE shift_date = DATE '2031-01-01' LIMIT 1)
  FROM customer c WHERE c.name='CT Customer';
SELECT pg_temp.expect_reject('TEST 5 shift capacity trigger', $q$
    INSERT INTO collection_record(pickup_id, shift_id, weight_kg, waste_type, disposal_site_id)
    SELECT p.pickup_id, p.shift_id, 200, 'general', (SELECT disposal_site_id FROM disposal_site WHERE name='CT Dump')
      FROM pickup p WHERE p.scheduled_date = DATE '2031-01-01'
       AND NOT EXISTS (SELECT 1 FROM collection_record r WHERE r.pickup_id = p.pickup_id)
$q$, 'exceed truck capacity');

-- TEST 6: weight must be > 0 -> collection_record_weight_kg_check
SELECT pg_temp.expect_reject('TEST 6 weight > 0 CHECK', $q$
    INSERT INTO collection_record(pickup_id, shift_id, weight_kg, waste_type, disposal_site_id)
    SELECT p.pickup_id, p.shift_id, 0, 'general', (SELECT disposal_site_id FROM disposal_site WHERE name='CT Dump')
      FROM pickup p WHERE p.scheduled_date = DATE '2031-01-01'
       AND NOT EXISTS (SELECT 1 FROM collection_record r WHERE r.pickup_id = p.pickup_id)
$q$, 'collection_record_weight_kg_check');

-- TEST 7: payment amount must be > 0 -> payment_amount_naira_check
SELECT pg_temp.expect_reject('TEST 7 payment > 0 CHECK', $q$
    INSERT INTO payment(customer_id, amount_naira, billing_month, status)
    SELECT customer_id, 0, date_trunc('month', CURRENT_DATE)::date, 'unpaid' FROM customer WHERE name='CT Customer'
$q$, 'payment_amount_naira_check');

-- TEST 8: invalid status jump OPEN -> COLLECTED
INSERT INTO pickup(customer_id, zone_id, scheduled_date, pickup_type, status)
SELECT c.customer_id, c.zone_id, CURRENT_DATE + 30, 'on_demand', 'OPEN' FROM customer c WHERE c.name='CT Customer';
SELECT pg_temp.expect_reject('TEST 8 status transition trigger', $q$
    UPDATE pickup SET status='COLLECTED'
     WHERE scheduled_date = CURRENT_DATE + 30 AND status='OPEN'
$q$, 'invalid pickup status transition');

\o
SELECT test, outcome FROM test_result ORDER BY test;
SELECT CASE WHEN count(*) FILTER (WHERE outcome='PASS') = 8
            THEN '==> All 8 constraint tests PASSED (each by its intended constraint).'
            ELSE '==> SOME TESTS FAILED' END AS summary FROM test_result;

ROLLBACK;   -- remove all CT-* test rows; bulk data untouched
