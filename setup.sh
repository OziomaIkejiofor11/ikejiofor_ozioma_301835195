#!/usr/bin/env bash
# setup.sh — install and start PostgreSQL 16 + MongoDB 8 + the Python driver in a GitHub Codespace.
# Run once at the top of the repo:  bash setup.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> (0) Remove conflicting yarn source list (Codespaces quirk: expired key breaks apt-get update)"
sudo rm -f /etc/apt/sources.list.d/yarn.list

echo "==> (1) Detect Ubuntu codename for the MongoDB repo"
. /etc/os-release
DISTRO="${VERSION_CODENAME:-jammy}"
echo "    codename = ${DISTRO}"

echo "==> (2) apt-get update + base tools"
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates gnupg lsb-release python3-psycopg2 postgresql postgresql-contrib postgresql-client

echo "==> (3) Make sure PostgreSQL 16 is installed (the scripts use /usr/lib/postgresql/16)"
if [ ! -d /usr/lib/postgresql/16 ]; then
  echo "    PostgreSQL 16 not found (this Ubuntu ships a different default) - adding the official PGDG repo"
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor --yes -o /usr/share/keyrings/pgdg.gpg
  echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt ${DISTRO}-pgdg main" \
    | sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y postgresql-16 postgresql-client-16
fi
sudo pg_ctlcluster 16 main start 2>/dev/null || true
sudo runuser -u postgres -- psql --version

echo "==> (4) Add MongoDB 8 repo (signed key + list)"
curl -fsSL "https://www.mongodb.org/static/pgp/server-8.0.asc" | sudo gpg --dearmor --yes -o /usr/share/keyrings/mongodb-server-8.0.gpg
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${DISTRO}/mongodb-org/8.0 multiverse" \
  | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list >/dev/null

echo "==> (5) Install MongoDB 8 (includes mongosh)"
sudo apt-get update -y
sudo apt-get install -y mongodb-org

echo "==> (6) Start both servers (Codespaces has no systemd, so start them directly)"
SVC="${HERE}/start_services.sh"; [ -f "$SVC" ] || SVC="$HOME/kit/advanced-database-portfolio/start_services.sh"
bash "$SVC"

echo "==> (7) Versions"
sudo runuser -u postgres -- psql --version
mongod --version | head -n 1
mongosh --version
/usr/bin/python3 -c "import psycopg2; print('psycopg2', psycopg2.__version__)"

echo "==> DONE. PostgreSQL 16 + MongoDB 8 are installed and running."
echo "    PostgreSQL (Unix socket, no password):  sudo runuser -u postgres -- psql"
echo "    MongoDB:                                mongosh"
echo "    If the Codespace has slept:             bash start_services.sh"
