#!/usr/bin/env bash
# run_p2.sh — Portfolio 2 runner.
# Assumes portfolio-1 has already created and loaded the cleanroute database.
set -euo pipefail

DB="cleanroute"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSQL="sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d ${DB}"

echo "==> Q1-Q8 results (current plan, baseline indexes only)"
${PSQL} -f "${DIR}/queries.sql"

echo "==> BEFORE optimisation indexes: EXPLAIN ANALYZE -> ${DIR}/p2_explain_BEFORE.txt"
${PSQL} -f "${DIR}/explain_queries.sql" > "${DIR}/p2_explain_BEFORE.txt" 2>&1 || { cat "${DIR}/p2_explain_BEFORE.txt"; exit 1; }
echo "    saved: ${DIR}/p2_explain_BEFORE.txt"

echo "==> creating optimisation indexes"
${PSQL} -f "${DIR}/create_indexes.sql"

echo "==> AFTER optimisation indexes: EXPLAIN ANALYZE -> ${DIR}/p2_explain_AFTER.txt"
${PSQL} -f "${DIR}/explain_queries.sql" > "${DIR}/p2_explain_AFTER.txt" 2>&1 || { cat "${DIR}/p2_explain_AFTER.txt"; exit 1; }
echo "    saved: ${DIR}/p2_explain_AFTER.txt"

echo "==> BEFORE vs AFTER summary (read straight from the two EXPLAIN ANALYZE files) -> ${DIR}/p2_summary.txt"
python3 -I "${DIR}/p2_summary.py" "${DIR}" | tee "${DIR}/p2_summary.txt"

echo "==> P2 DONE"
echo "    evidence: p2_explain_BEFORE.txt, p2_explain_AFTER.txt, p2_summary.txt (all real, from this run)"
