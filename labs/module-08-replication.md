# PostgreSQL Tutorial: Set Up Streaming Replication and HA

For the Docker Compose version (one primary and two standbys), use the
[Lab 8 Docker walkthrough](module08-replication/README.md) or
[quick start](DOCKER-LABS.md). The commands below target native instances.

This tutorial builds a writable ClaimSure primary, a streaming replica, and a failover runbook you can actually execute. Replication moves WAL. High availability also requires detection, fencing, promotion, client routing, verification, and rejoin.

```text
prepare primary -> clone replica -> stream WAL -> measure lag
                -> choose commit mode -> failover drill -> rejoin old primary
```

Use PostgreSQL 16 or newer. Commands below use PostgreSQL 18 paths; change the version directory if yours differs.

---

## What you will have

```text
Applications  --->  pooler or VIP  --->  Primary :5432   (writes)
                                          |
                                          | WAL stream
                                          v
                                       Replica :5433   (read-only / DR)
```

| Role | Purpose |
| --- | --- |
| Primary | Accepts writes. Generates WAL. Serves `walsender` processes. |
| Replica | Applies WAL. Stays in recovery. Candidate for promotion. |
| Routing | Points clients at the current writable node after failover. |

A connected replica is not HA by itself. If the old primary can still accept writes after you promote, you have split-brain.

---

## Lab hosts

Use two machines, or two instances on one host. Fill these in and keep them consistent.

| Variable | Example | Meaning |
| --- | --- | --- |
| `PRIMARY_HOST` | `10.0.0.11` | Address the replica uses to reach the primary |
| `REPLICA_HOST` | `10.0.0.12` | Address allowed in `pg_hba.conf` |
| `PGDATA_PRIMARY` | `/var/lib/postgresql/18/main` | Primary data directory |
| `PGDATA_REPLICA` | `/var/lib/postgresql/18/replica` | Replica data directory |
| `REPL_USER` | `replicator` | Replication-only login role |
| `SLOT_NAME` | `replica_slot` | Physical slot that retains WAL for this replica |

Single-host lab: run primary on port `5432` and replica on port `5433`, and use `127.0.0.1` for both hosts.

Run primary commands as a superuser (`postgres`). Run clone commands from the replica host.

---

## Step 1 — Confirm the primary is healthy

On the primary:

```sql
SELECT version();
SELECT pg_is_in_recovery();          -- must be false
SHOW data_directory;
SHOW port;
```

If `pg_is_in_recovery()` is `true`, you are already on a standby. Stop and use the writable node.

Create a tiny canary if ClaimSure is not loaded yet:

```sql
CREATE SCHEMA IF NOT EXISTS lab_repl;
CREATE TABLE IF NOT EXISTS lab_repl.canary (
    id bigint PRIMARY KEY,
    note text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO lab_repl.canary (id, note)
VALUES (1, 'before replica')
ON CONFLICT (id) DO UPDATE SET note = EXCLUDED.note, updated_at = clock_timestamp();
```

---

## Step 2 — Prepare the primary for streaming

Edit `postgresql.conf` on the primary (or use `ALTER SYSTEM`):

```sql
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET wal_keep_size = '1GB';
ALTER SYSTEM SET hot_standby = on;
ALTER SYSTEM SET listen_addresses = '*';
```

`wal_level = replica` is enough for physical streaming. Use `logical` later only if you need publications.

These settings need a restart:

```bash
sudo systemctl restart postgresql
# or: pg_ctl -D "$PGDATA_PRIMARY" restart
```

Verify:

```sql
SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;
SHOW listen_addresses;
```

Expected: `wal_level` is `replica` or `logical`. `listen_addresses` is not `localhost` if the replica is on another host.

---

## Step 3 — Create a restricted replication role

```sql
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') THEN
        CREATE ROLE replicator
            WITH REPLICATION LOGIN
            PASSWORD 'change-me-now';
    END IF;
END
$$;
```

This role should not be a superuser and should not own application data. It only streams WAL.

---

## Step 4 — Allow the replica to connect for replication

On the primary, add a replication line to `pg_hba.conf`. Prefer host + scram in the lab; use `hostssl` in production.

```text
# TYPE  DATABASE     USER        ADDRESS           METHOD
host    replication  replicator  10.0.0.12/32      scram-sha-256
```

Single-host lab:

```text
host    replication  replicator  127.0.0.1/32      scram-sha-256
```

Reload HBA (no restart):

```sql
SELECT pg_reload_conf();
```

From the replica host, prove the role can authenticate:

```bash
psql "host=$PRIMARY_HOST port=5432 user=replicator dbname=postgres replication=database"
```

If this fails, fix HBA, `listen_addresses`, firewall, or the password before cloning. Do not start `pg_basebackup` yet.

---

## Step 5 — Create a physical replication slot

Slots keep the primary from recycling WAL the replica still needs. An unused slot can fill `pg_wal`. Create one slot per replica, then keep that replica running or drop the slot.

On the primary:

```sql
SELECT * FROM pg_create_physical_replication_slot('replica_slot', true);
SELECT slot_name, slot_type, active, restart_lsn
FROM pg_replication_slots;
```

Expected: `replica_slot` exists, `slot_type = physical`, `active = false` until the replica connects.

---

## Step 6 — Stop the replica instance and empty its data directory

The replica data directory must be empty or absent. You cannot stream into an initialized cluster that already has its own system identifier.

On the replica host:

```bash
sudo systemctl stop postgresql
# or stop only the replica instance if you run two clusters on one host

sudo rm -rf "$PGDATA_REPLICA"
sudo mkdir -p "$PGDATA_REPLICA"
sudo chown postgres:postgres "$PGDATA_REPLICA"
```

---

## Step 7 — Clone the primary with `pg_basebackup`

On the replica host, as `postgres`:

```bash
pg_basebackup \
  -h "$PRIMARY_HOST" \
  -p 5432 \
  -U replicator \
  -D "$PGDATA_REPLICA" \
  -Fp -Xs -P -R \
  -S replica_slot
```

| Flag | Meaning |
| --- | --- |
| `-Fp` | Plain-format data directory |
| `-Xs` | Stream WAL during the backup so the clone is consistent |
| `-P` | Progress |
| `-R` | Write `standby.signal` and `primary_conninfo` |
| `-S replica_slot` | Use the physical slot created on the primary |

When the command finishes, confirm the standby files exist:

```bash
ls -l "$PGDATA_REPLICA/standby.signal"
grep primary_conninfo "$PGDATA_REPLICA/postgresql.auto.conf"
```

If you run two instances on one host, set a unique port and cluster name in the replica `postgresql.conf`:

```text
port = 5433
```

---

## Step 8 — Start the replica and prove streaming

Start the replica:

```bash
sudo systemctl start postgresql
# or: pg_ctl -D "$PGDATA_REPLICA" start
```

**On the primary:**

```sql
SELECT application_name, client_addr, state, sync_state,
       sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS replay_gap
FROM pg_stat_replication;

SELECT slot_name, active, restart_lsn
FROM pg_replication_slots;
```

Expected:

- one row in `pg_stat_replication` with `state = streaming`
- `replica_slot.active = true`

**On the replica:**

```sql
SELECT pg_is_in_recovery();                 -- must be true
SELECT pg_last_wal_receive_lsn();
SELECT pg_last_wal_replay_lsn();
SELECT now() - pg_last_xact_replay_timestamp() AS replay_delay;

SELECT status, sender_host, slot_name,
       written_lsn, flushed_lsn, last_msg_receipt_time
FROM pg_stat_wal_receiver;
```

Expected: `pg_is_in_recovery() = true` and `pg_stat_wal_receiver` shows a connected sender.

---

## Step 9 — Write on the primary and read on the replica

**Primary:**

```sql
UPDATE lab_repl.canary
SET note = 'streamed to replica', updated_at = clock_timestamp()
WHERE id = 1
RETURNING *;
```

**Replica:**

```sql
SELECT * FROM lab_repl.canary WHERE id = 1;
```

Expected: the replica shows `streamed to replica` after replay. If the row is missing or old, you are looking at receive lag or replay lag, not a finished apply.

Writes on the replica must fail:

```sql
INSERT INTO lab_repl.canary (id, note) VALUES (2, 'should fail');
```

Expected: `cannot execute INSERT in a read-only transaction`.

---

## Step 10 — Measure lag correctly

Lag is not one number. A replica can receive WAL and still not show new rows until replay finishes.

**Primary:**

```sql
SELECT application_name,
       write_lag,
       flush_lag,
       replay_lag,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn))
         AS replay_byte_lag
FROM pg_stat_replication;
```

| Signal | What it means |
| --- | --- |
| `write_lag` | Replica OS has not written the WAL yet |
| `flush_lag` | Replica has not flushed WAL to durable storage |
| `replay_lag` | Replica has not applied WAL to visible data |
| replay byte lag | How much WAL is still unpublished on the standby |

Compare replay byte/time lag to the service RPO. Receive-only “connected” is not a recovery promise.

Also watch slots. A stopped replica disappears from `pg_stat_replication`, but its slot can keep retaining WAL:

```sql
SELECT slot_name, active,
       pg_size_pretty(
         pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)
       ) AS retained_wal
FROM pg_replication_slots
ORDER BY slot_name;
```

If a replica is retired, drop its slot:

```sql
SELECT pg_drop_replication_slot('replica_slot');
```

---

## Step 11 — Optional: add a second replica

Repeat steps 5–8 with a new slot and data directory, for example `replica2_slot` and port `5434`.

Then on the primary you should see two streaming rows and two physical slots.

Node-down drill (replica only — do not promote):

1. Record baseline `pg_stat_replication` and slot `retained_wal`.
2. Stop replica2.
3. Generate WAL on the primary (`INSERT` a batch into an audit or canary table).
4. Confirm replica2 vanished from `pg_stat_replication` and its slot is inactive.
5. Start replica2 and wait until replay catches up.

This is an outage drill, not failover.

---

## Step 12 — Choose a commit mode

| Mode | Primary commit waits for | Trade-off |
| --- | --- | --- |
| Asynchronous (`synchronous_commit = on` with empty `synchronous_standby_names`) | Local durable WAL only | Lowest latency. Recent commits can be lost if you fail over. |
| Synchronous remote write | Standby has written/flushed WAL | May still lose visibility until replay. Adds network wait. |
| Synchronous remote apply | Standby has replayed WAL | Stronger standby reads. Highest latency. |

Example: wait for one standby named `replica` to flush WAL:

```sql
ALTER SYSTEM SET synchronous_standby_names = 'FIRST 1 (replica)';
ALTER SYSTEM SET synchronous_commit = 'on';
SELECT pg_reload_conf();
```

The replica `application_name` in `primary_conninfo` must match the name in `synchronous_standby_names`.

```text
primary_conninfo = 'host=10.0.0.11 port=5432 user=replicator application_name=replica'
```

For payment writes that must survive primary loss, synchronous write is the usual teaching choice. You still need fencing and routing. Replication does not elect a leader for you.

Reload and confirm:

```sql
SHOW synchronous_commit;
SHOW synchronous_standby_names;

SELECT application_name, sync_state
FROM pg_stat_replication;
```

Expected for a sync standby: `sync_state = sync`.

---

## Step 13 — Failover is a procedure

Do this as a planned drill on lab nodes, not on an unexplained production outage.

```text
detect -> fence old primary -> promote replica -> route clients
       -> verify writes and security context -> rebuild/rejoin old node
```

### 13a. Detect

Primary does not accept connections, or health checks fail. Confirm the replica is the intended survivor and measure replay lag. Do not promote a replica that is minutes behind if that violates RPO.

### 13b. Fence the old primary

Stop writes on the old primary **before** the replica becomes writable. Examples:

```bash
# Stop PostgreSQL on the old primary
sudo systemctl stop postgresql

# Or block 5432 at the firewall / security group
```

Fencing is whatever guarantees the old process cannot commit. Promotion without fencing is split-brain.

### 13c. Promote the replica

On the replica:

```sql
SELECT pg_promote();
```

or:

```bash
pg_ctl -D "$PGDATA_REPLICA" promote
```

Verify:

```sql
SELECT pg_is_in_recovery();   -- must now be false
SHOW transaction_read_only;   -- off
```

### 13d. Route clients

Point the pooler, VIP, or HAProxy backend at the new primary. Applications should not hard-code the old hostname if failover is in scope.

```text
write endpoint  ->  new primary :5432
read endpoint   ->  remaining standbys only
```

### 13e. Verify

```sql
INSERT INTO lab_repl.canary (id, note)
VALUES (3, 'after promote')
ON CONFLICT (id) DO UPDATE
SET note = EXCLUDED.note, updated_at = clock_timestamp()
RETURNING *;

SELECT inet_server_addr(), inet_server_port(),
       pg_is_in_recovery(),
       current_setting('transaction_read_only');
```

Also prove tenant or RLS session context still works through the pooler (`SET LOCAL` inside a transaction if you use transaction pooling).

### 13f. Rejoin the old primary as a replica

The former primary is now a divergent node. Do not start it as a second primary.

Preferred lab rebuild: take a fresh `pg_basebackup` from the new primary into the old data directory, create a new slot, and start it in recovery.

If the old data directory is still close to the new timeline, `pg_rewind` can be faster. It requires `full_page_writes = on` (default) and a shutdown or crash-consistent old data directory. After rewind, add `standby.signal` and `primary_conninfo` pointing at the new primary, then start in recovery.

When the old node is streaming again:

```sql
-- on the current primary
SELECT application_name, state, replay_lsn
FROM pg_stat_replication;
```

---

## Step 14 — Logical replication is not the DR plan

Physical streaming copies the whole cluster and is the standby/DR path.

Logical replication publishes selected tables to a separate subscriber. Use it for upgrades, reporting subsets, or integration. It does not copy roles, sequences, or DDL automatically.

On a primary with `wal_level = logical`:

```sql
CREATE PUBLICATION claims_reporting
  FOR TABLE insurance.claim, insurance.claim_payment;
```

The subscriber must already have matching tables. Keep the physical replica as the failover target.

---

## Step 15 — Routing and pool mode

If clients use PgBouncer in transaction pool mode:

- Use `SET LOCAL` for tenant context inside a transaction.
- Do not rely on session GUCs, temp tables, or session-level prepared statements unless you tested them.

```ini
[databases]
claimsure = host=primary port=5432 dbname=claimsure

[pgbouncer]
listen_port = 6432
pool_mode = transaction
```

After failover, change the pooler `host=` (or the VIP behind it) to the promoted node, then retest writes.

Course verification SQL for an existing lab stack is in `scripts/sql/08-replication.sql`. From this repo you can run:

```bash
./scripts/shells/run-lab.sh lab08_A
./scripts/shells/run-lab.sh lab08_C
./scripts/shells/run-lab.sh lab08_E
```

---

## Decision scenario

Payment writes must survive primary loss. Reporting can lag 30 seconds.

- Payments: consider synchronous remote write, and accept the extra commit latency.
- Reporting replica: asynchronous apply is usually enough.
- Both still need fence, promote, route, verify, and rejoin.

Asynchronous streaming is not “near-zero RPO.”

---

## Failure modes

| Mistake | What goes wrong |
| --- | --- |
| Calling a connected replica “HA” | No fencing, no routing, no promotion plan |
| Promoting before fencing | Two writable primaries (split-brain) |
| Watching receive lag only | Replica has WAL but users still see old data |
| Leaving a stopped replica’s slot | Primary `pg_wal` grows until disk fills |
| Using a logical publication as DR | Incomplete cluster, no clean standby promote |
| Session GUCs behind transaction pooling | Tenant context leaks or disappears |

```text
streaming ≠ failover
receive ≠ replay
```

---

## Definition of done

- Primary shows a streaming `walsender`; replica `pg_is_in_recovery()` is true.
- A primary write appears on the replica after replay.
- You can explain write vs flush vs replay lag and slot-retained WAL.
- Commit mode matches the RPO conversation.
- A drill recorded fence → promote → route → verify → rejoin.
- Clients no longer write to the fenced old primary.

---

## Quick command index

```bash
# Primary health
psql -c "SELECT pg_is_in_recovery(), pg_current_wal_lsn();"

# Clone
pg_basebackup -h "$PRIMARY_HOST" -U replicator -D "$PGDATA_REPLICA" -Fp -Xs -P -R -S replica_slot

# Promote
psql -c "SELECT pg_promote();"

# Drop a retired slot on the current primary
psql -c "SELECT pg_drop_replication_slot('replica_slot');"
```

Related course notes: [Module 8 cheat sheet](references/cheat-sheets/module-08-replication-ha.md) and [Module 8 slides](../slides/module-08-replication.md).
