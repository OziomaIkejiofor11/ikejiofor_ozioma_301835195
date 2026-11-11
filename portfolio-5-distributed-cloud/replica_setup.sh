#!/usr/bin/env bash
# replica_setup.sh — automated primary + streaming replica (Codespaces, PostgreSQL 16).
# See replica_setup_guide.md for the explanation of each step.
set -euo pipefail

PGCONF=/etc/postgresql/16/main/postgresql.conf
PGHBA=/etc/postgresql/16/main/pg_hba.conf
REPLDATA=/var/lib/postgresql/16/replica
PGCTL=/usr/lib/postgresql/16/bin/pg_ctl
PGBASEBACKUP=/usr/lib/postgresql/16/bin/pg_basebackup

echo "==> (0) stop any replica left from an earlier run"
if [ -d "${REPLDATA}" ]; then
  sudo runuser -u postgres -- "${PGCTL}" -D "${REPLDATA}" stop -m fast 2>/dev/null || true
fi

echo "==> (1) configure primary for replication (only once)"
if ! sudo grep -q "P5 replication settings" "${PGCONF}"; then
sudo bash -c "cat >> ${PGCONF}" <<'EOF'
# --- P5 replication settings ---
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
listen_addresses = 'localhost'
EOF
fi

# trust lines MUST go at the top of pg_hba.conf
if ! sudo grep -q "^local   replication postgres" "${PGHBA}"; then
  sudo bash -c "printf 'local   all         postgres                          trust\nlocal   replication postgres                          trust\n' | cat - ${PGHBA} > /tmp/pghba && mv /tmp/pghba ${PGHBA}"
fi
sudo chown postgres:postgres "${PGHBA}"
sudo chmod 640 "${PGHBA}"

sudo pg_ctlcluster 16 main restart
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "SHOW wal_level; SHOW max_wal_senders;"

echo "==> (2) base backup + physical replication slot"
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c \
  "SELECT pg_drop_replication_slot('replica_slot') WHERE EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='replica_slot');" || true

sudo rm -rf "${REPLDATA}"
sudo runuser -u postgres -- mkdir -p "${REPLDATA}"
sudo runuser -u postgres -- "${PGBASEBACKUP}" -D "${REPLDATA}" -X stream -C -S replica_slot -R

echo "==> (3) replica config (own postgresql.conf + copies of pg_hba/pg_ident + chmod 700)"
sudo bash -c "cat >> ${REPLDATA}/postgresql.conf" <<'EOF'
# --- replica config ---
port = 5433
listen_addresses = 'localhost'
hot_standby = on
EOF
sudo cp /etc/postgresql/16/main/pg_hba.conf  "${REPLDATA}/pg_hba.conf"
sudo cp /etc/postgresql/16/main/pg_ident.conf "${REPLDATA}/pg_ident.conf"
sudo chown -R postgres:postgres "${REPLDATA}"
sudo chmod 700 "${REPLDATA}"

echo "==> (4) start replica on port 5433"
sudo runuser -u postgres -- "${PGCTL}" -D "${REPLDATA}" -l /tmp/replica.log start
sleep 2
sudo runuser -u postgres -- psql -p 5433 -d postgres -c "SELECT pg_is_in_recovery() AS is_replica, now();"

echo "==> (5) replication status (primary side)"
sudo runuser -u postgres -- psql -d postgres -c \
  "SELECT application_name, state, sync_state, sent_lsn, write_lsn FROM pg_stat_replication;"

echo "==> replica setup DONE."
