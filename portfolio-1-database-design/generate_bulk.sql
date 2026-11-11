-- portfolio-1-database-design/generate_bulk.sql
-- Bulk data generator for CleanRoute Waste Services.
-- Produces 50k+ pickups + collection_records over ~2 years (relative to today),
-- payments in Naira, realistic Nigerian names/addresses, NO truck/driver overlap,
-- NO shift over capacity, with festive bumps after Christmas, Easter and Sallah.
--
-- Run AFTER schema.sql. Safe to re-run (truncates first).
\set ON_ERROR_STOP on

BEGIN;

TRUNCATE TABLE collection_record, pickup, shift, payment, subscription,
            customer, crew_member, truck, disposal_site, zone
RESTART IDENTITY CASCADE;

-- =========================================================== zones
INSERT INTO zone (name, city, collection_day) VALUES
 ('Lekki',                 'Lagos', 'Wednesday'),
 ('Yaba',                  'Lagos', 'Monday'),
 ('Ikeja',                 'Lagos', 'Thursday'),
 ('Surulere',              'Lagos', 'Tuesday'),
 ('Independence Layout',   'Enugu', 'Friday'),
 ('New Haven',             'Enugu', 'Saturday');

-- =========================================================== disposal sites
INSERT INTO disposal_site (name, type, city) VALUES
 ('Epe Dumpsite',              'dumpsite',         'Lagos'),
 ('Olososun Dumpsite',         'dumpsite',         'Lagos'),
 ('Lagos Recycling Centre',    'recycling_centre', 'Lagos'),
 ('Enugu Transfer Station',    'dumpsite',         'Enugu'),
 ('Enugu Eco Recycling Hub',   'recycling_centre', 'Enugu');

-- =========================================================== trucks (12, mixed fleet)
INSERT INTO truck (plate_number, capacity_tonnes, status) VALUES
 ('LAG-471-XA',  5.0, 'active'),
 ('LAG-529-XP',  7.0, 'active'),
 ('LAG-614-XK', 10.0, 'active'),
 ('LAG-708-XZ',  5.0, 'active'),
 ('LAG-812-XR',  7.0, 'active'),
 ('LAG-903-XM', 10.0, 'active'),
 ('LAG-044-XL',  7.0, 'active'),
 ('ENU-118-XB',  5.0, 'active'),
 ('ENU-237-XY',  7.0, 'active'),
 ('ENU-356-XW', 10.0, 'active'),
 ('LAG-330-XF', 10.0, 'maintenance'),
 ('ENU-461-XN',  7.0, 'active');

-- =========================================================== crew (12 drivers + 12 collectors = 24)
INSERT INTO crew_member (full_name, role, phone) VALUES
 ('Chinedu Okafor',      'driver',    '+2348031000001'),
 ('Oluwaseun Adeyemi',   'driver',    '+2348031000002'),
 ('Ibrahim Bello',       'driver',    '+2348031000003'),
 ('Emeka Eze',           'driver',    '+2348031000004'),
 ('Fatima Suleiman',     'driver',    '+2348031000005'),
 ('Tunde Olawale',       'driver',    '+2348031000006'),
 ('Ngozi Nwosu',         'driver',    '+2348031000007'),
 ('Bola Adebayo',        'driver',    '+2348031000008'),
 ('Yakubu Mohammed',     'driver',    '+2348031000009'),
 ('Adaeze Okonkwo',      'driver',    '+2348031000010'),
 ('Sani Abubakar',       'driver',    '+2348031000011'),
 ('Funke Adesanya',      'driver',    '+2348031000012'),
 ('David Ojo',           'collector', '+2348031000013'),
 ('Ebere Onyeka',        'collector', '+2348031000014'),
 ('Tobi Ogunleye',       'collector', '+2348031000015'),
 ('Amina Salami',        'collector', '+2348031000016'),
 ('Femi Olatunji',       'collector', '+2348031000017'),
 ('Joy Haruna',          'collector', '+2348031000018'),
 ('Ifeanyi Igbokwe',     'collector', '+2348031000019'),
 ('Helen Dauda',         'collector', '+2348031000020'),
 ('Bayo Nnamdi',         'collector', '+2348031000021'),
 ('Mary Lawal',          'collector', '+2348031000022'),
 ('Danjuma Adeleke',     'collector', '+2348031000023'),
 ('Grace Oyebola',       'collector', '+2348031000024');

-- =========================================================== customers (~80 per zone = 480) + subscriptions
DO $$
DECLARE
    fn TEXT[] := ARRAY[
        'Chinedu','Oluwaseun','Aisha','Emeka','Fatima','Tunde','Ngozi','Bola',
        'Yakubu','Adaeze','Sani','Funke','Ibrahim','Chioma','Kunle','Hauwa',
        'Obinna','Yetunde','Musa','Tobi','Amina','David','Ebere','Seyi',
        'Zainab','Femi','Joy','Ifeanyi','Helen','Bayo','Mary','Danjuma',
        'Grace','Tope','Halima','Uche','Bisi','Yusuf','Amara','Chuka'];
    ln TEXT[] := ARRAY[
        'Okafor','Adeyemi','Ibrahim','Eze','Bello','Olawale','Mohammed','Nwosu',
        'Adebayo','Suleiman','Okonkwo','Adesanya','Abubakar','Okeke','Lawal',
        'Adeleke','Ojo','Onyeka','Ogunleye','Salami','Olatunji','Haruna',
        'Igbokwe','Oyebola','Dauda','Nnamdi','Bali','Eze','Uche','Musa'];
    streets_lag TEXT[] := ARRAY[
        'Admiralty Way','Lekki Phase 1 Road','Adeola Odeku Street','Ahmadu Bello Way',
        'Bode Thomas Street','Ikorodu Road','Allen Avenue','Akin Ogunlewe Road'];
    streets_enu TEXT[] := ARRAY[
        'Independence Avenue','Udosi Street','Ogui Road','New Haven Layout',
        'Chime Avenue','Abakpa Road','Agu Eze Street'];
    z RECORD;
    n INT := 0;
    street TEXT;
    is_lag BOOLEAN;
BEGIN
    FOR z IN SELECT zone_id, name, city FROM zone ORDER BY zone_id LOOP
        is_lag := (z.city = 'Lagos');
        FOR i IN 1..80 LOOP
            n := n + 1;
            street := CASE WHEN is_lag
                THEN streets_lag[(n % array_length(streets_lag,1)) + 1]
                ELSE streets_enu[(n % array_length(streets_enu,1)) + 1] END;
            INSERT INTO customer (name, type, address, zone_id, phone, email)
            VALUES (
                fn[(n % array_length(fn,1)) + 1] || ' ' || ln[(n % array_length(ln,1)) + 1],
                CASE WHEN (n % 5) = 0 THEN 'business' ELSE 'household' END,
                (i || ' ' || street || ', ' || z.name),
                z.zone_id,
                '+23480' || lpad((10000000 + n)::text, 8, '0'),
                'cust' || n || '@cleanroute.ng'
            );
        END LOOP;
    END LOOP;
END $$;

-- one active subscription per customer (partial UNIQUE guarantees uniqueness)
INSERT INTO subscription (customer_id, plan, start_date, end_date, monthly_fee_naira, status)
SELECT
    c.customer_id,
    CASE WHEN c.type = 'business' THEN 'business'
         WHEN c.customer_id % 3 = 0 THEN 'weekly_premium'
         ELSE 'weekly_basic' END,
    (CURRENT_DATE - INTERVAL '2 years')::date,
    NULL,
    CASE WHEN c.type = 'business' THEN 25000.00
         WHEN c.customer_id % 3 = 0 THEN 12000.00
         ELSE 8000.00 END,
    'active'
FROM customer c;

-- =========================================================== festive multiplier table
-- Christmas (Dec 25), Easter, Sallah (Eid al-Adha) approximate Gregorian dates.
CREATE TEMP TABLE festive(d DATE, mult NUMERIC) ON COMMIT DROP;
INSERT INTO festive VALUES
 ('2023-12-25', 2.0), ('2024-12-25', 2.0), ('2025-12-25', 2.0),
 ('2026-12-25', 2.0), ('2027-12-25', 2.0),
 ('2023-04-09', 1.6), ('2024-03-31', 1.6), ('2025-04-20', 1.6),
 ('2026-04-05', 1.6), ('2027-03-28', 1.6), ('2028-04-16', 1.6),
 ('2023-06-28', 1.7), ('2024-06-16', 1.7), ('2025-06-06', 1.7),
 ('2026-05-27', 1.7), ('2027-05-16', 1.7), ('2028-05-05', 1.7);

-- =========================================================== shifts
-- One shift per zone per weekly collection day, 06:00-16:00 local,
-- rotating trucks/drivers by week. Each calendar day only one zone collects
-- (collection_day differs per zone) so truck/driver exclusion is naturally safe.
INSERT INTO shift (truck_id, driver_id, zone_id, shift_date, shift_start, shift_end, status)
WITH zd AS (
    SELECT z.zone_id, g.d::date AS d,
           (row_number() OVER (PARTITION BY z.zone_id ORDER BY g.d) - 1) AS wk
      FROM zone z
      CROSS JOIN generate_series(
            (CURRENT_DATE - INTERVAL '2 years')::date,
            (CURRENT_DATE + INTERVAL '14 days')::date,
            INTERVAL '1 day') AS g(d)
     WHERE EXTRACT(DOW FROM g.d)::int = day_name_to_dow(z.collection_day)
)
SELECT
    (SELECT ta[(wk % cardinality(ta)) + 1]
       FROM (SELECT ARRAY(SELECT truck_id FROM truck WHERE status='active' ORDER BY truck_id) AS ta) x),
    (SELECT da[(wk % cardinality(da)) + 1]
       FROM (SELECT ARRAY(SELECT crew_member_id FROM crew_member WHERE role='driver' ORDER BY crew_member_id) AS da) y),
    zone_id,
    d,
    (d::timestamptz) + INTERVAL '6 hours',
    (d::timestamptz) + INTERVAL '16 hours',
    CASE WHEN d < CURRENT_DATE THEN 'closed'
         WHEN d = CURRENT_DATE THEN 'active'
         ELSE 'planned' END
FROM zd;

-- =========================================================== scheduled pickups (~480 customers x ~105 weeks ~ 50k)
INSERT INTO pickup (customer_id, zone_id, scheduled_date, requested_at, pickup_type, status)
SELECT c.customer_id, c.zone_id, zd.d, (zd.d::timestamptz) - INTERVAL '1 day', 'scheduled', 'OPEN'
FROM customer c
JOIN LATERAL (
    SELECT g.d::date AS d
      FROM generate_series(
            (CURRENT_DATE - INTERVAL '2 years')::date,
            (CURRENT_DATE + INTERVAL '14 days')::date,
            INTERVAL '1 day') AS g(d)
     WHERE EXTRACT(DOW FROM g.d)::int = day_name_to_dow(
        (SELECT collection_day FROM zone WHERE zone_id = c.zone_id))
) zd ON true;

-- on-demand pickups (~5% extra, on the zone's collection day so a shift exists)
INSERT INTO pickup (customer_id, zone_id, scheduled_date, requested_at, pickup_type, status)
SELECT c.customer_id, c.zone_id, zd.d, (zd.d::timestamptz) - INTERVAL '2 hours', 'on_demand', 'OPEN'
FROM customer c
JOIN LATERAL (
    SELECT g.d::date AS d
      FROM generate_series(
            (CURRENT_DATE - INTERVAL '2 years')::date,
            (CURRENT_DATE - INTERVAL '1 day')::date,
            INTERVAL '1 day') AS g(d)
     WHERE EXTRACT(DOW FROM g.d)::int = day_name_to_dow(
        (SELECT collection_day FROM zone WHERE zone_id = c.zone_id))
) zd ON true
WHERE random() < 0.06;

-- =========================================================== link past pickups to their zone-day shift
UPDATE pickup p
SET shift_id = s.shift_id
FROM shift s
WHERE p.zone_id = s.zone_id
  AND p.scheduled_date = s.shift_date
  AND p.scheduled_date <= (CURRENT_DATE - 1)
  AND p.pickup_type IN ('scheduled','on_demand');

-- OPEN -> ASSIGNED for past pickups that got a shift
UPDATE pickup SET status = 'ASSIGNED'
 WHERE status = 'OPEN' AND shift_id IS NOT NULL
   AND scheduled_date <= (CURRENT_DATE - 1);

-- ASSIGNED -> COLLECTED (~96%) for past pickups; rest become MISSED
UPDATE pickup
   SET status = 'COLLECTED',
       collected_at = (scheduled_date::timestamptz) + INTERVAL '9 hours' + (random() * INTERVAL '4 hours')
 WHERE status = 'ASSIGNED'
   AND scheduled_date <= (CURRENT_DATE - 1)
   AND random() < 0.96;

UPDATE pickup SET status = 'MISSED'
 WHERE status = 'ASSIGNED'
   AND scheduled_date <= (CURRENT_DATE - 1);

-- =========================================================== collection records for COLLECTED pickups
-- Weight: household 5-25kg, business 20-80kg, festive multiplier, +/-20% jitter.
-- Waste type distribution: general 60%, recyclable 25%, organic 15%.
-- Disposal site: recyclable -> recycling_centre, else dumpsite, by city.
INSERT INTO collection_record (pickup_id, shift_id, weight_kg, waste_type, disposal_site_id, recorded_at)
SELECT
    p.pickup_id,
    p.shift_id,
    round((
        CASE WHEN c.type = 'business' THEN 20 + random()*60 ELSE 5 + random()*20 END
        * COALESCE((SELECT max(f.mult) FROM festive f
                    WHERE p.scheduled_date BETWEEN f.d - 5 AND f.d + 5), 1.0)
        * (0.8 + random()*0.4)
    )::numeric, 2),
    wt.waste_type,
    ds.disposal_site_id,
    (p.scheduled_date::timestamptz) + INTERVAL '10 hours' + (random() * INTERVAL '4 hours')
FROM pickup p
JOIN customer c ON c.customer_id = p.customer_id
JOIN zone zc ON zc.zone_id = p.zone_id
JOIN LATERAL (
    SELECT CASE
        WHEN random() < 0.60 THEN 'general'
        WHEN random() < 0.625 THEN 'recyclable'
        ELSE 'organic' END AS waste_type
) wt ON true
JOIN LATERAL (
    SELECT ds2.disposal_site_id
      FROM disposal_site ds2
     WHERE ds2.city = zc.city
       AND ds2.type = CASE WHEN wt.waste_type = 'recyclable'
                           THEN 'recycling_centre' ELSE 'dumpsite' END
     ORDER BY random() LIMIT 1
) ds ON true
WHERE p.status = 'COLLECTED' AND p.shift_id IS NOT NULL;

-- =========================================================== payments (monthly per active subscription, ~24 months)
-- status and paid_at are derived from ONE random draw per row so they always agree:
--   paid    -> paid_at is set (5-15 days after the month starts, never in the future)
--   unpaid / partial -> paid_at stays NULL
--   the current month's bill is still open, so it is unpaid until its due window has passed
INSERT INTO payment (customer_id, amount_naira, billing_month, status, paid_at)
SELECT x.customer_id, x.monthly_fee_naira, x.m, x.status,
       CASE WHEN x.status = 'paid'
            THEN LEAST(x.m + INTERVAL '5 days' + x.jitter, now())::timestamptz
            ELSE NULL END
FROM (
    SELECT s.customer_id, s.monthly_fee_naira, g.m,
           random() * INTERVAL '10 days' AS jitter,
           CASE WHEN g.m + INTERVAL '15 days' > now() THEN 'unpaid'
                WHEN r.p < 0.90 THEN 'paid'
                WHEN r.p < 0.97 THEN 'unpaid'
                ELSE 'partial' END AS status
    FROM subscription s
    CROSS JOIN LATERAL generate_series(
        date_trunc('month', (CURRENT_DATE - INTERVAL '2 years'))::date,
        date_trunc('month', CURRENT_DATE)::date,
        INTERVAL '1 month') AS g(m)
    CROSS JOIN LATERAL (SELECT random() + 0 * s.customer_id + 0 * extract(epoch FROM g.m) AS p) r  -- correlated => one draw PER ROW
    WHERE s.status = 'active'
) x;

COMMIT;

-- =========================================================== summary
SELECT 'zones' AS what, count(*)::text AS n FROM zone
UNION ALL SELECT 'customers', count(*)::text FROM customer
UNION ALL SELECT 'subscriptions', count(*)::text FROM subscription
UNION ALL SELECT 'trucks', count(*)::text FROM truck
UNION ALL SELECT 'crew_members', count(*)::text FROM crew_member
UNION ALL SELECT 'shifts', count(*)::text FROM shift
UNION ALL SELECT 'pickups', count(*)::text FROM pickup
UNION ALL SELECT 'collection_records', count(*)::text FROM collection_record
UNION ALL SELECT 'payments', count(*)::text FROM payment;
