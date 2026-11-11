-- portfolio-3-transactions-concurrency/p3_setup.sql
-- Ensures a demo shift exists TODAY (in whichever zone's collection day is today)
-- plus a few OPEN pickups today, so the transaction demos work on any calendar day.
\set ON_ERROR_STOP on

DO $$
DECLARE
    v_zone   bigint;
    v_truck  bigint;
    v_driver bigint;
    v_shift  bigint;
BEGIN
    SELECT zone_id INTO v_zone FROM zone
      WHERE day_name_to_dow(collection_day) = EXTRACT(DOW FROM CURRENT_DATE)::int
      ORDER BY zone_id LIMIT 1;
    IF v_zone IS NULL THEN
        RAISE EXCEPTION 'no zone has its collection day today - run portfolio-1/generate_bulk.sql first';
    END IF;

    INSERT INTO truck(plate_number, capacity_tonnes, status)
    VALUES ('DEMO-TXN-001', 5, 'active')
    ON CONFLICT (plate_number) DO UPDATE SET capacity_tonnes = EXCLUDED.capacity_tonnes
    RETURNING truck_id INTO v_truck;

    SELECT crew_member_id INTO v_driver FROM crew_member WHERE phone = '+2348000999001';
    IF v_driver IS NULL THEN
        INSERT INTO crew_member(full_name, role, phone)
        VALUES ('Demo Driver Txn','driver','+2348000999001')
        RETURNING crew_member_id INTO v_driver;
    END IF;

    SELECT shift_id INTO v_shift FROM shift
      WHERE driver_id = v_driver AND shift_date = CURRENT_DATE;
    IF v_shift IS NULL THEN
        INSERT INTO shift(truck_id, driver_id, zone_id, shift_date, shift_start, shift_end, status)
        VALUES (v_truck, v_driver, v_zone, CURRENT_DATE,
                CURRENT_DATE::timestamptz + INTERVAL '6 hours',
                CURRENT_DATE::timestamptz + INTERVAL '16 hours','active')
        RETURNING shift_id INTO v_shift;
    END IF;

    -- second demo driver + truck + shift today (for the two-driver race demo)
    DECLARE
        v_truck2  bigint;
        v_driver2 bigint;
    BEGIN
        INSERT INTO truck(plate_number, capacity_tonnes, status)
        VALUES ('DEMO-TXN-002', 5, 'active')
        ON CONFLICT (plate_number) DO UPDATE SET capacity_tonnes = EXCLUDED.capacity_tonnes
        RETURNING truck_id INTO v_truck2;

        SELECT crew_member_id INTO v_driver2 FROM crew_member WHERE phone = '+2348000999002';
        IF v_driver2 IS NULL THEN
            INSERT INTO crew_member(full_name, role, phone)
            VALUES ('Demo Driver Txn 2','driver','+2348000999002')
            RETURNING crew_member_id INTO v_driver2;
        END IF;

        PERFORM 1 FROM shift WHERE driver_id = v_driver2 AND shift_date = CURRENT_DATE;
        IF NOT FOUND THEN
            INSERT INTO shift(truck_id, driver_id, zone_id, shift_date, shift_start, shift_end, status)
            VALUES (v_truck2, v_driver2, v_zone, CURRENT_DATE,
                    CURRENT_DATE::timestamptz + INTERVAL '6 hours',
                    CURRENT_DATE::timestamptz + INTERVAL '16 hours','active');
        END IF;
    END;

    -- a few demo customers + OPEN pickups today (today IS this zone's collection day)
    INSERT INTO customer(name, type, address, zone_id, phone)
    SELECT 'Demo Cust ' || g, 'household', 'Demo Street ' || g, v_zone, '+2348000999' || lpad(g::text,3,'0')
    FROM generate_series(1,5) g
    WHERE NOT EXISTS (SELECT 1 FROM customer c2 WHERE c2.phone = '+2348000999' || lpad(g::text,3,'0'));

    INSERT INTO pickup(customer_id, zone_id, scheduled_date, pickup_type, status)
    SELECT c.customer_id, v_zone, CURRENT_DATE, 'scheduled', 'OPEN'
      FROM customer c
     WHERE c.zone_id = v_zone
       AND c.phone LIKE '+2348000999%'
       AND NOT EXISTS (
            SELECT 1 FROM pickup p
             WHERE p.customer_id = c.customer_id AND p.scheduled_date = CURRENT_DATE);

    RAISE NOTICE 'P3 setup OK: zone=% truck=% driver=% shift=%', v_zone, v_truck, v_driver, v_shift;
END $$;
