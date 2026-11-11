# Portfolio 5 — Primary + streaming read replica setup (Codespaces)

This guide walks through creating a **physical streaming replica** of the PostgreSQL 16 primary on
a second port (5433), entirely inside one Codespace. The companion script `replica_setup.sh`
automates the same steps; this file explains what each step does and gives the manual fallback.

## Codespaces-specific rules followed

- The codespace user can `sudo` only as root, so every `postgres` command is run with
  `sudo runuser -u postgres -- …` (never `sudo -u postgres`).
- PostgreSQL 16 config lives in `/etc/postgresql/16/main/`; `pg_ctl` is at
  `/usr/lib/postgresql/16/bin/pg_ctl`.
- A `pg_basebackup`-made replica needs its own `postgresql.conf`, copies of `pg_hba.conf` and
  `pg_ident.conf`, and a data directory with `chmod 700`.
- `pg_hba.conf` **trust** lines must go at the **top** of the file.
- TCP logins need a password, so replication connects over the **Unix socket**
  (`host=/var/run/postgresql`).
- `postgres_fdw` is not used (this is physical replication, not FDW).

## Step 1 — configure the primary for replication

Append replication settings to the primary's `postgresql.conf` and prepend trust lines to
`pg_hba.conf`:

```bash
sudo bash -c "cat >> /etc/postgresql/16/main/postgresql.conf" <<'EOF'
# --- P5 replication settings ---
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
listen_addresses = 'localhost'
EOF

# trust lines MUST go at the top of pg_hba.conf
sudo bash -c "printf 'local   all         postgres                          trust\nlocal   replication postgres                          trust\n' | cat - /etc/postgresql/16/main/pg_hba.conf > /tmp/pghba && mv /tmp/pghba /etc/postgresql/16/main/pg_hba.conf"
sudo chown postgres:postgres /etc/postgresql/16/main/pg_hba.conf
sudo chmod 640 /etc/postgresql/16/main/pg_hba.conf

sudo pg_ctlcluster 16 main restart
```

Verify:

```bash
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "SHOW wal_level; SHOW max_wal_senders;"
```

## Step 2 — base backup into a new data directory

`pg_basebackup` with `-C -S replica_slot -R` creates a physical replication slot, takes the base
backup, and writes `standby.signal` + `primary_conninfo`/`primary_slot_name` into the replica's
`postgresql.auto.conf`:

```bash
REPLDATA=/var/lib/postgresql/16/replica

# drop a stale slot from a previous run if present
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c \
  "SELECT pg_drop_replication_slot('replica_slot') WHERE EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='replica_slot');"

sudo rm -rf "$REPLDATA"
sudo runuser -u postgres -- mkdir -p "$REPLDATA"
sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_basebackup \
   -D "$REPLDATA" -X stream -C -S replica_slot -R
```

`-R` connects to the primary over the Unix socket (no password needed because of the trust lines).

## Step 3 — give the replica its own config

The base backup does **not** copy Debian's external config files, so create the replica's own
`postgresql.conf` on port **5433** and copy `pg_hba.conf` + `pg_ident.conf` into the data dir:

```bash
sudo bash -c "cat >> $REPLDATA/postgresql.conf" <<'EOF'
# --- replica config ---
port = 5433
listen_addresses = 'localhost'
hot_standby = on
EOF

sudo cp /etc/postgresql/16/main/pg_hba.conf  "$REPLDATA/pg_hba.conf"
sudo cp /etc/postgresql/16/main/pg_ident.conf "$REPLDATA/pg_ident.conf"
sudo chown -R postgres:postgres "$REPLDATA"
sudo chmod 700 "$REPLDATA"
```

## Step 4 — start the replica

```bash
sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl \
   -D "$REPLDATA" -l /tmp/replica.log start

# verify it is in recovery (i.e. it is a hot standby)
sudo runuser -u postgres -- psql -p 5433 -d postgres -c "SELECT pg_is_in_recovery(), now();"
# expected: t (true)
```

## Step 5 — confirm streaming is live

```bash
sudo runuser -u postgres -- psql -d postgres -c "SELECT application_name, state, sync_state, sent_lsn, write_lsn FROM pg_stat_replication;"
sudo runuser -u postgres -- psql -p 5433 -d postgres -c "SELECT status, sender_host, sender_port, slot_name FROM pg_stat_wal_receiver;"
```

Then run the one-script demo that switches servers with `\connect`:

```bash
sudo runuser -u postgres -- psql -d cleanroute -f portfolio-5-distributed-cloud/replica_demo.sql
```

## Troubleshooting (manual fallback)

- If `pg_ctl` reports the port is in use, change `port = 5434` in `$REPLDATA/postgresql.conf` and
  reconnect with `-p 5434`.
- If the replica will not start, check `/tmp/replica.log`; the most common cause is a missing or
  mis-permissioned `pg_hba.conf` (chmod 640, owner postgres) or a data dir that is not `chmod 700`.
- To rebuild from scratch: `sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl -D "$REPLDATA" stop -m fast` then repeat Steps 2-4.

## Suggested git commit

```bash
git add portfolio-5-distributed-cloud/
git commit -m "P5: monthly partitioning + primary/streaming-replica setup + replica demo"
```
