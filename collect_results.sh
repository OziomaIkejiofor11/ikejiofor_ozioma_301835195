#!/usr/bin/env bash
# collect_results.sh — gathers the REAL output the student's own runs produced into ONE text file,
# my_results.txt, to paste back for the documentation. It only copies files that exist; a missing
# log is reported as "(no ... log)" so we know that portfolio did not run.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
OUT=my_results.txt
section() { printf '\n\n########## %s ##########\n' "$1" >> "$OUT"; }
cat_if() { if [ -s "$1" ]; then cat "$1" >> "$OUT"; else echo "(no $2)" >> "$OUT"; fi; }

: > "$OUT"
{
  echo "MIT 8103 results for Ikejiofor Ozioma Gospel (2026/A/MIT/0976)"
  echo "collected: $(date '+%Y-%m-%d %H:%M:%S %Z')   host: $(hostname)"
  echo "postgres: $(sudo runuser -u postgres -- psql -Atc 'select version()' 2>/dev/null | cut -c1-60)"
  echo "mongod  : $(mongod --version 2>/dev/null | head -1)"
  echo "git log (progress commits):"; git log --pretty='  %h %ad %s' --date=short 2>/dev/null | head -20
} >> "$OUT"

section "P1 output (p1_output.log)";            cat_if p1_output.log "p1_output.log"
section "P2 BEFORE/AFTER summary";              cat_if portfolio-2-query-optimisation/p2_summary.txt "p2_summary.txt"
section "P2 EXPLAIN ANALYZE BEFORE (first 120 lines)"
if [ -s portfolio-2-query-optimisation/p2_explain_BEFORE.txt ]; then head -120 portfolio-2-query-optimisation/p2_explain_BEFORE.txt >> "$OUT"; else echo "(no p2_explain_BEFORE.txt)" >> "$OUT"; fi
section "P2 EXPLAIN ANALYZE AFTER (first 120 lines)"
if [ -s portfolio-2-query-optimisation/p2_explain_AFTER.txt ]; then head -120 portfolio-2-query-optimisation/p2_explain_AFTER.txt >> "$OUT"; else echo "(no p2_explain_AFTER.txt)" >> "$OUT"; fi
section "P3 automated transactions (p3_output.log)"; cat_if p3_output.log "p3_output.log"
section "P3 two-session demos (race_demos_output.log)"; cat_if portfolio-3-transactions-concurrency/race_demos_output.log "race_demos_output.log"
section "P4 output (p4_output.log)";            cat_if p4_output.log "p4_output.log"
section "P5 partitioning (partition_output.log)"; cat_if portfolio-5-distributed-cloud/partition_output.log "partition_output.log"
section "P5 replication (replication_output.log)"; cat_if portfolio-5-distributed-cloud/replication_output.log "replication_output.log"
section "Row counts (live from the databases)"
{
  sudo runuser -u postgres -- psql -d cleanroute -Atc "select 'pickups='||count(*) from pickup union all select 'collection_records='||count(*) from collection_record union all select 'customers='||count(*) from customer union all select 'payments='||count(*) from payment" 2>&1
  mongosh --quiet cleanroute --eval 'print("bin_readings="+db.bin_readings.countDocuments()); print("complaints="+db.complaints.countDocuments()); print("smart_bins="+db.smart_bins.countDocuments())' 2>&1
} >> "$OUT"
echo
echo "Wrote $(pwd)/$OUT ($(wc -l < "$OUT") lines). Open it, press Ctrl+A, Ctrl+C and paste the text back."
