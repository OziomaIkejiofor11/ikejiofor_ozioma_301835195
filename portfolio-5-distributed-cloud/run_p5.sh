#!/usr/bin/env bash
# run_p5.sh — Portfolio 5 runner.
# Runs the partitioning part automatically. The replica part is run via replica_setup.sh
# (privileged, multi-step) followed by replica_demo.sql.
set -euo pipefail

DB="cleanroute"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSQL="sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d ${DB}"

echo "==> P5a: monthly range partitioning of pickups + pruning demo  (evidence: ${DIR}/partition_output.log)"
${PSQL} -f "${DIR}/partition_setup.sql" 2>&1 | tee "${DIR}/partition_output.log"

echo "==> P5b: primary + streaming read replica (setup)  (evidence: ${DIR}/replication_output.log)"
{
  bash "${DIR}/replica_setup.sh"

  echo "==> P5c: replica demo (ONE script that switches servers: reject write, row arrives, lag, status)"
  sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d "${DB}" -f "${DIR}/replica_demo.sql"
} 2>&1 | tee "${DIR}/replication_output.log"

echo "==> P5 DONE"
echo "    Evidence files: ${DIR}/partition_output.log  ${DIR}/replication_output.log"
