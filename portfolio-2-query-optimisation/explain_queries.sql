-- portfolio-2-query-optimisation/explain_queries.sql
-- EXPLAIN ANALYZE for each of the 8 queries.
-- Run this file TWICE: once BEFORE create_indexes.sql and once AFTER.
-- Paste the real output into explain_results.md.
\set ON_ERROR_STOP on

\echo '==== Q1 EXPLAIN ANALYZE: open pickups per zone today ===='
EXPLAIN ANALYZE
SELECT z.name AS zone, count(*) AS open_pickups
  FROM pickup p JOIN zone z USING (zone_id)
 WHERE p.status = 'OPEN' AND p.scheduled_date = CURRENT_DATE
 GROUP BY z.name
 ORDER BY open_pickups DESC;

\echo '==== Q2 EXPLAIN ANALYZE: tonnes collected per zone per month ===='
EXPLAIN ANALYZE
SELECT z.name AS zone,
       to_char(date_trunc('month', s.shift_date), 'YYYY-MM') AS month,
       round(sum(cr.weight_kg) / 1000.0, 2) AS tonnes_collected
  FROM collection_record cr
  JOIN shift s ON s.shift_id = cr.shift_id
  JOIN zone  z ON z.zone_id = s.zone_id
 GROUP BY z.name, date_trunc('month', s.shift_date)
 ORDER BY month DESC, zone;

\echo '==== Q3 EXPLAIN ANALYZE: recycling rate % per zone ===='
EXPLAIN ANALYZE
SELECT z.name AS zone,
       round(100.0 * sum(CASE WHEN cr.waste_type='recyclable' THEN cr.weight_kg ELSE 0 END)
              / NULLIF(sum(cr.weight_kg),0), 2) AS recycling_rate_pct
  FROM collection_record cr
  JOIN shift s ON s.shift_id = cr.shift_id
  JOIN zone  z ON z.zone_id = s.zone_id
 GROUP BY z.name
 ORDER BY recycling_rate_pct DESC;

\echo '==== Q4 EXPLAIN ANALYZE: missed-pickup rate per zone ===='
EXPLAIN ANALYZE
SELECT z.name AS zone,
       round(100.0 * sum(CASE WHEN p.status='MISSED' THEN 1 ELSE 0 END)::numeric
              / NULLIF(count(*),0), 2) AS missed_rate_pct
  FROM pickup p JOIN zone z USING (zone_id)
 GROUP BY z.name
 ORDER BY missed_rate_pct DESC;

\echo '==== Q5 EXPLAIN ANALYZE: truck utilisation % per shift ===='
EXPLAIN ANALYZE
SELECT s.shift_id, t.plate_number, z.name AS zone, s.shift_date,
       t.capacity_tonnes,
       round(sum(cr.weight_kg)/1000.0, 2) AS load_tonnes,
       round(100.0 * sum(cr.weight_kg) / (t.capacity_tonnes * 1000), 2) AS utilisation_pct
  FROM shift s
  JOIN truck t              ON t.truck_id = s.truck_id
  JOIN zone  z              ON z.zone_id  = s.zone_id
  JOIN collection_record cr ON cr.shift_id = s.shift_id
 GROUP BY s.shift_id, t.plate_number, t.capacity_tonnes, z.name, s.shift_date
 ORDER BY utilisation_pct DESC
 LIMIT 50;

\echo '==== Q6 EXPLAIN ANALYZE: customers with unpaid bills ===='
EXPLAIN ANALYZE
SELECT c.name, c.phone, z.name AS zone,
       sum(p.amount_naira) AS unpaid_total_naira
  FROM payment p
  JOIN customer c ON c.customer_id = p.customer_id
  JOIN zone     z ON z.zone_id     = c.zone_id
 WHERE p.status IN ('unpaid','partial')
 GROUP BY c.customer_id, c.name, c.phone, z.name
 ORDER BY unpaid_total_naira DESC;

\echo '==== Q7 EXPLAIN ANALYZE: average weight per waste type ===='
EXPLAIN ANALYZE
SELECT waste_type,
       round(avg(weight_kg), 2) AS avg_weight_kg,
       count(*) AS records
  FROM collection_record
 GROUP BY waste_type
 ORDER BY avg_weight_kg DESC;

\echo '==== Q8 EXPLAIN ANALYZE: monthly revenue collected vs billed ===='
EXPLAIN ANALYZE
SELECT to_char(billing_month, 'YYYY-MM') AS month,
       round(sum(CASE WHEN status='paid' THEN amount_naira ELSE 0 END), 2) AS collected_naira,
       round(sum(amount_naira), 2) AS billed_naira
  FROM payment
 GROUP BY billing_month
 ORDER BY month DESC;
