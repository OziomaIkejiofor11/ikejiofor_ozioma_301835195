#!/usr/bin/env bash
# start_services.sh — (re)start PostgreSQL 16 and MongoDB. Safe to run any time, e.g. after a
# Codespace has slept. Codespaces has no systemd, so services are started directly.
set -euo pipefail

echo "==> PostgreSQL 16"
if ! sudo pg_lsclusters | grep -q "16 *main .*online"; then
  sudo pg_ctlcluster 16 main start
fi
sudo pg_lsclusters

echo "==> MongoDB"
if ! pgrep -x mongod >/dev/null 2>&1; then
  sudo mkdir -p /var/lib/mongodb /var/log/mongodb
  sudo chown -R mongodb:mongodb /var/lib/mongodb /var/log/mongodb 2>/dev/null || true
  sudo runuser -u mongodb -- /usr/bin/mongod --config /etc/mongod.conf --fork \
       --logpath /var/log/mongodb/mongod.log >/dev/null
fi
for i in $(seq 1 30); do
  if mongosh --quiet --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q 1; then
    echo "    mongod: answering on 27017"; break
  fi
  sleep 1
done
mongosh --quiet --eval 'db.runCommand({ping:1}).ok' | grep -q 1 || { echo "mongod did not start - see /var/log/mongodb/mongod.log"; exit 1; }
