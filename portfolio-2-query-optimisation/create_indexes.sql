-- portfolio-2-query-optimisation/create_indexes.sql
-- Optimisation indexes added on top of the baseline indexes from schema.sql.
-- These are the indexes whose plan/time difference is recorded in explain_results.md.
\set ON_ERROR_STOP on

\echo '==> creating optimisation indexes (run this AFTER the BEFORE EXPLAIN ANALYZE pass)'

-- Q1: open pickups per zone today -> partial composite index on the OPEN subset
CREATE INDEX IF NOT EXISTS idx_pickup_open_zone_date
    ON pickup (zone_id, scheduled_date) WHERE status = 'OPEN';

-- Q2 & Q5: shift lookup by (zone, date) including truck, plus weight aggregation per shift
CREATE INDEX IF NOT EXISTS idx_shift_zone_date_truck
    ON shift (zone_id, shift_date, truck_id);

-- Q2/Q3/Q5: collection_record aggregation filtered/joined by shift + waste_type
CREATE INDEX IF NOT EXISTS idx_collection_shift_waste
    ON collection_record (shift_id, waste_type);

-- Q4: missed rate per zone -> partial index on MISSED rows for the count
CREATE INDEX IF NOT EXISTS idx_pickup_missed_zone
    ON pickup (zone_id) WHERE status = 'MISSED';

-- Q6: unpaid bills -> partial index on the unpaid/partial subset, ordered by amount
CREATE INDEX IF NOT EXISTS idx_payment_unpaid_customer
    ON payment (customer_id) WHERE status IN ('unpaid','partial');

-- Q8: monthly revenue -> index by billing_month
CREATE INDEX IF NOT EXISTS idx_payment_month_status
    ON payment (billing_month, status);

\echo '==> index list:'
\di idx_*_open_zone_date idx_shift_zone_date_truck idx_collection_shift_waste idx_pickup_missed_zone idx_payment_unpaid_customer idx_payment_month_status
