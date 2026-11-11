#!/usr/bin/env bash
# run_p1.sh — Portfolio 1 runner (Codespaces / Ubuntu + PostgreSQL 16)
set -euo pipefail

DB="cleanroute"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSQL="sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1"

echo "==> (re)create database ${DB}"
${PSQL} -c "DROP DATABASE IF EXISTS ${DB};"
${PSQL} -c "CREATE DATABASE ${DB};"

echo "==> schema (tables, constraints, triggers)"
${PSQL} -d "${DB}" -f "${DIR}/schema.sql"

echo "==> bulk data generator (50k+ pickups + collection records)"
${PSQL} -d "${DB}" -f "${DIR}/generate_bulk.sql"

echo "==> constraint tests (each violation must be rejected)"
${PSQL} -d "${DB}" -f "${DIR}/constraint_tests.sql"

echo "==> P1 DONE"
echo "    quick check:  sudo runuser -u postgres -- psql -d ${DB} -c 'SELECT status, count(*) FROM pickup GROUP BY status;'"
