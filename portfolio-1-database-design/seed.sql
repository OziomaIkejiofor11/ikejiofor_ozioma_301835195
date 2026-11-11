-- portfolio-1-database-design/seed.sql
-- Small readable seed (alternative to generate_bulk.sql) for quick manual testing.
-- Creates the 6 zones, a few disposal sites, 3 trucks, 6 crew, 5 customers,
-- 5 subscriptions, 1 shift, 2 pickups, 1 collection_record, 1 payment.
-- Run AFTER schema.sql:  psql -d cleanroute -f seed.sql
\set ON_ERROR_STOP on

BEGIN;
TRUNCATE collection_record, pickup, shift, payment, subscription, customer, crew_member, truck, disposal_site, zone RESTART IDENTITY CASCADE;

INSERT INTO zone (name, city, collection_day) VALUES
 ('Lekki','Lagos','Wednesday'),
 ('Yaba','Lagos','Monday'),
 ('Ikeja','Lagos','Thursday'),
 ('Surulere','Lagos','Tuesday'),
 ('Independence Layout','Enugu','Friday'),
 ('New Haven','Enugu','Saturday');

INSERT INTO disposal_site (name, type, city) VALUES
 ('Epe Dumpsite','dumpsite','Lagos'),
 ('Lagos Recycling Centre','recycling_centre','Lagos'),
 ('Enugu Transfer Station','dumpsite','Enugu');

INSERT INTO truck (plate_number, capacity_tonnes, status) VALUES
 ('LAG-471-XA', 5, 'active'),
 ('LAG-529-XP', 7, 'active'),
 ('ENU-118-XB', 5, 'active');

INSERT INTO crew_member (full_name, role, phone) VALUES
 ('Chinedu Okafor','driver','+2348031000001'),
 ('Fatima Suleiman','driver','+2348031000005'),
 ('David Ojo','collector','+2348031000013'),
 ('Ebere Onyeka','collector','+2348031000014'),
 ('Tobi Ogunleye','collector','+2348031000015'),
 ('Amina Salami','collector','+2348031000016');

INSERT INTO customer (name, type, address, zone_id, phone, email) VALUES
 ('Chinedu Okafor','household','12 Admiralty Way, Lekki', 1, '+2348031000091','chinedu@cleanroute.ng'),
 ('Aisha Bello','business','3 Adeola Odeku Street, Yaba', 2, '+2348031000092','aisha@biz.ng'),
 ('Emeka Eze','household','5 Chime Avenue, Independence Layout', 5, '+2348031000093','emeka@cleanroute.ng'),
 ('Bola Adebayo','business','2 Allen Avenue, Ikeja', 3, '+2348031000094','bola@biz.ng'),
 ('Ngozi Nwosu','household','7 New Haven Layout, New Haven', 6, '+2348031000095','ngozi@cleanroute.ng');

INSERT INTO subscription (customer_id, plan, start_date, monthly_fee_naira, status) VALUES
 (1, 'weekly_basic',    CURRENT_DATE - INTERVAL '1 year', 8000,  'active'),
 (2, 'business',        CURRENT_DATE - INTERVAL '1 year', 25000, 'active'),
 (3, 'weekly_premium',  CURRENT_DATE - INTERVAL '1 year', 12000, 'active'),
 (4, 'business',        CURRENT_DATE - INTERVAL '1 year', 25000, 'active'),
 (5, 'weekly_basic',    CURRENT_DATE - INTERVAL '1 year', 8000,  'active');

INSERT INTO shift (truck_id, driver_id, zone_id, shift_date, shift_start, shift_end, status)
SELECT 1, 1, 1, g.d, g.d::timestamptz + INTERVAL '6 hours', g.d::timestamptz + INTERVAL '16 hours', 'closed'
  FROM generate_series(CURRENT_DATE, CURRENT_DATE + INTERVAL '6 days', INTERVAL '1 day') g(d)
 WHERE EXTRACT(DOW FROM g.d)::int = day_name_to_dow('Wednesday')
 LIMIT 1;

INSERT INTO pickup (customer_id, zone_id, scheduled_date, pickup_type, status, shift_id)
SELECT 1, 1, g.d, 'scheduled', 'ASSIGNED',
       (SELECT shift_id FROM shift WHERE zone_id = 1 AND shift_date = g.d)
  FROM generate_series(CURRENT_DATE, CURRENT_DATE + INTERVAL '6 days', INTERVAL '1 day') g(d)
 WHERE EXTRACT(DOW FROM g.d)::int = day_name_to_dow('Wednesday')
 LIMIT 1;

INSERT INTO collection_record (pickup_id, shift_id, weight_kg, waste_type, disposal_site_id)
SELECT pickup_id, shift_id, 18.5, 'general',
       (SELECT disposal_site_id FROM disposal_site WHERE name='Epe Dumpsite')
  FROM pickup WHERE customer_id = 1 LIMIT 1;

INSERT INTO payment (customer_id, amount_naira, billing_month, status, paid_at)
VALUES (1, 8000, date_trunc('month', CURRENT_DATE)::date, 'paid',
        date_trunc('month', CURRENT_DATE)::date + INTERVAL '5 days');
COMMIT;
