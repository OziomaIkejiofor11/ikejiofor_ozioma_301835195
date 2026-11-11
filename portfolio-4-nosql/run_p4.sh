#!/usr/bin/env bash
# run_p4.sh — Portfolio 4 runner (MongoDB 8, Codespaces).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> create collections + jsonSchema validator"
mongosh "${DIR}/setup_validation.js"

echo "==> generate smart-bin sensor data (40k+ readings)"
mongosh "${DIR}/generate_sensor_data.js"

echo "==> generate complaint reports (polymorphic, oneOf)"
mongosh "${DIR}/generate_complaints.js"

echo "==> create indexes and print BEFORE/AFTER explain() (COLLSCAN -> IXSCAN)"
mongosh "${DIR}/create_indexes.js"

echo "==> run aggregations"
mongosh "${DIR}/aggregations.js"

echo "==> P4 DONE"
echo "    quick check:  mongosh --eval 'db = db.getSiblingDB(\"cleanroute\"); printjson(db.bin_readings.countDocuments()); printjson(db.complaints.countDocuments());'"
