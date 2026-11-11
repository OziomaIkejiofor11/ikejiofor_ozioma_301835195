#!/usr/bin/env bash
# run_p3.sh — Portfolio 3 runner.
# Assumes portfolio-1 has loaded the cleanroute database.
set -euo pipefail

DB="cleanroute"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSQL="sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d ${DB}"

echo "==> P3 demo setup (today's zone, two demo drivers+shifts, OPEN pickups today)"
${PSQL} -f "${DIR}/p3_setup.sql"

echo "==> claim_pickup() transaction"
${PSQL} -f "${DIR}/claim_pickup.sql"

echo "==> record_collection() transaction"
${PSQL} -f "${DIR}/record_collection.sql"

echo "==> COMMIT / ROLLBACK demo (overload rolls back)"
${PSQL} -f "${DIR}/rollback_demo.sql"

echo "==> two-session demos: race bug + 2 fixes, READ COMMITTED vs REPEATABLE READ, deadlock + fix"
echo "    (real sessions; evidence saved to ${DIR}/race_demos_output.log)"
sudo runuser -u postgres -- /usr/bin/python3 "${DIR}/run_race_demos.py" 2>&1 | tee "${DIR}/race_demos_output.log"

echo "==> P3 DONE."
echo "    Evidence file: ${DIR}/race_demos_output.log"
echo "    (The hand-typed two-terminal versions are in race_condition_guide.md, isolation_levels_guide.md,"
echo "     deadlock_demo_guide.md if your lecturer wants to see them done manually.)"
