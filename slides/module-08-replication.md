---
theme: default
title: "Module 8: Replication & High Availability"
layout: module08-cover
class: module-eight module-cover
colorSchema: light
fonts:
  sans: Inter
info: "PostgreSQL Developer and DBA Bootcamp v3 | Day 1"
transition: slide-left
mdc: true
---



<div class="cover-art"><img src="./assets/module-08-replication-cover-enterprise-blue.png" alt="PostgreSQL primary, replicas, pooler, logical subscriber, monitoring, and controlled failover" /></div>

# Module 8: Replication & High Availability

## Build a primary-replica ClaimSure platform without breaking transaction semantics

<!--
Speaker notes: Mission: primary-replica claim platform, understand lag, introduce PgBouncer without breaking SET LOCAL tenant context. Replication is data movement, not a complete HA system. You still need health checks, fencing, promotion, client routing, old-primary isolation, and rejoin.
-->

---
layout: default
class: module-eight
---

# Primary, Replica, and Pooler Topology

<img src="./assets/module-08-topology-enterprise-blue.png" class="concept-visual" alt="Applications connect through a pooler to one writable primary that streams WAL to read-only replicas" />

<div class="concept-caption">
  <span>Applications</span><span>Pooler</span><span>Writable primary</span><span>WAL stream</span><span>Read-only replicas</span>
</div>

<!--
Speaker notes: Applications connect to a routing layer instead of hard-coding a database node. One primary accepts writes. PostgreSQL container ports are all 5432; the walkthrough lists separate host ports. WAL moves in one direction to read-only replicas. Health and lag checks observe each node separately.
-->

---
layout: two-cols-header
class: module-eight
layoutClass: module-eight
---

# Primary, Replica, Pooler

::left::

- Application connects to pooler :55820
- Primary :55811 takes writes
- Replica :55812 is read-only / DR
- Optional replica2 :55813 supports node-add/down drills

::right::

```text
APP TRAFFIC
Application :55820
    -> PgBouncer
    -> Primary :55811

WAL STREAMS
Primary :55811
    -> Replica :55812   read-only / DR
    -> Replica2 :55813  optional lab
```

<!--
Speaker notes: Host ports: primary 55811, replica 55812, optional replica2 55813, PgBouncer 55820. PostgreSQL uses 5432 inside every DB container; PgBouncer listens on 6432 inside its container. The guide is ../labs/module-08-replication.md (8A–8E). Do not teach applications to hard-code the primary hostname if failover is a goal. Read-your-writes on a designated synchronous standby requires configured synchronous_standby_names and remote_apply; asynchronous replicas may lag.
-->

---
layout: two-cols-header
class: module-eight
layoutClass: module-eight
---

# Lab 8A — Existing Replica

::left::

- Restricted `replicator` role + HBA rule
- Compose starts `replica` from `pg_basebackup`
- Confirm `wal_level`, senders, slots, recovery state

::right::

```bash
make up
make sql-m8
make replica
```

```sql
-- primary
SELECT application_name, client_addr, state,
       sync_state, write_lsn, flush_lsn, replay_lsn
FROM pg_stat_replication;
-- replica
SELECT pg_is_in_recovery(),
       pg_last_wal_receive_lsn(),
       pg_last_wal_replay_lsn();
```

<!--
Speaker notes: VERIFY: primary shows a streaming walsender; replica reports pg_is_in_recovery() = true. SHOW wal_level, max_wal_senders, max_replication_slots on the primary first. hostssl replication replicator ... scram-sha-256 in production HBA. This reuses Module 4's replicator habit.
-->

---
layout: two-cols-header
class: module-eight
layoutClass: module-eight
---

# Lab 8B — Add a Replica Node

::left::

- Start optional `replica2` with the `ha-lab` profile
- `replica2` clones from primary using `pg_basebackup`
- It uses its own replication slot: `replica2_slot`
- Verify two streaming replicas from the primary

::right::

```bash
make node-add
make node-status
make replica2
```

```sql
SELECT application_name, client_addr,
       state, sync_state, replay_lsn
FROM pg_stat_replication;

SELECT slot_name, active, restart_lsn
FROM pg_replication_slots
ORDER BY slot_name;
```

<!--
Speaker notes: This lab is now supported by compose.yaml through the optional replica2 service. The default lab starts primary, replica and PgBouncer; observability is outside this exercise. Adding a node is deliberately explicit so learners can see the clone and replication slot appear.
-->

---
layout: two-cols-header
class: module-eight
layoutClass: module-eight
---

# Lab 8C — Take a Replica Node Down

::left::

- Stop `replica2`, not the primary
- Observe it disappear from `pg_stat_replication`
- Confirm `replica2_slot` becomes inactive
- Restart it and watch it catch up

::right::

```bash
make node-down NODE=replica2
make node-status
make sql-m8

make node-up NODE=replica2
make sql-m8
```

```sql
SELECT slot_name, active,
       pg_size_pretty(
         pg_wal_lsn_diff(
           pg_current_wal_lsn(), restart_lsn
         )
       ) AS retained_wal
FROM pg_replication_slots
ORDER BY slot_name;
```

<!--
Speaker notes: This is a replica outage drill, not a primary failover. An inactive physical slot can retain WAL on the primary, so a stopped replica is also a future disk-pressure problem. Do not promote nodes in this drill.
-->

---
layout: default
class: module-eight compact-table compact-code
---

# Lab 8B/8C — Simulation Steps

| Step | Action | Expected evidence |
| --- | --- | --- |
| 1 | baseline current topology | one or two streaming rows |
| 2 | add `replica2` | new container, new slot, second stream |
| 3 | generate WAL on primary | LSN advances |
| 4 | stop `replica2` | stream disappears, slot inactive |
| 5 | generate more WAL | retained WAL can grow for inactive slot |
| 6 | start `replica2` | stream returns and replay catches up |

```bash
make node-status
make node-add
make sql-m8
make node-down NODE=replica2
make sql-m8
make node-up NODE=replica2
make sql-m8
```

<!--
Speaker notes: Run this as a controlled outage simulation. The target is replica2 only. The point is to see the difference between a streaming replica row and a physical replication slot. A stopped replica can disappear from pg_stat_replication while its slot remains and retains WAL.
-->

---
layout: two-cols-header
class: module-eight
layoutClass: module-eight
---

# Lab 8C Detail — Generate WAL While Down

::left::

**After stopping `replica2`**

- write a small audit batch on the primary
- inspect `replica2_slot`
- compare retained WAL before and after
- restart the node and verify catch-up

::right::

```sql
INSERT INTO insurance.audit_event (
  tenant_id, actor, action,
  entity_type, entity_id, details
)
SELECT 1, 'ha_lab', 'NODE_DOWN_WAL',
       'replica2', g::text,
       jsonb_build_object('lab', '8C')
FROM generate_series(1, 1000) g;

SELECT slot_name, active,
       pg_size_pretty(
         pg_wal_lsn_diff(
           pg_current_wal_lsn(), restart_lsn
         )
       ) AS retained_wal
FROM pg_replication_slots
ORDER BY slot_name;
```

<!--
Speaker notes: This small write batch makes the retained-WAL behavior easier to see. If retained_wal stays small, that is also valid evidence: the workload was small or the replica caught up quickly after restart. The operational risk remains the same for a long outage with a high-write primary.
-->

---
layout: default
class: module-eight
---

# Replication Lag Stages

<img src="./assets/module-08-lag-enterprise-blue.png" class="concept-visual" alt="WAL generation, network transfer, replica write, flush, replay, and inactive slot retention" />

<div class="concept-caption">
  <span>Generate</span><span>Send</span><span>Write</span><span>Flush</span><span>Replay</span><span>Slot retention</span>
</div>

<!--
Speaker notes: Lag exists at several boundaries. A replica may receive WAL before it writes, flushes, or replays it. Only replay changes the visible standby data. An inactive slot retains WAL on the primary and creates a separate disk-capacity risk.
-->

---
layout: two-cols-header
class: module-eight
layoutClass: module-eight
---

# Lag Is Not One Number

::left::

- Write lag, flush lag, replay lag
- Byte lag vs time lag
- Slot retention can fill `pg_wal`

::right::

```sql
SELECT application_name,
  pg_size_pretty(pg_wal_lsn_diff(
    pg_current_wal_lsn(), replay_lsn))
    AS replay_byte_lag,
  write_lag, flush_lag, replay_lag
FROM pg_stat_replication;
```

<!--
Speaker notes: A replica that received WAL but has not replayed it is a DR lie. Byte lag compared to RPO becomes an alert in Module 9. Long-idle replication slots are a disk-full incident waiting to happen.
-->

---
layout: default
class: module-eight
---

# Commit Modes

| Mode                     | Commit behavior              | Trade-off                              |
| ------------------------ | ---------------------------- | -------------------------------------- |
| Asynchronous             | Primary need not wait        | Possible recent TX loss on failover    |
| Synchronous remote write | Wait for remote OS write     | Lower loss, adds network latency       |
| Synchronous remote apply | Wait until replayed          | Strong standby reads, highest latency  |

<!--
Speaker notes: ClaimSure payments may justify sync write; a reporting replica may not. Name the RPO implication. FAILOVER reminder: lag graphs do not promote a node. Promotion without fencing the old primary is split-brain.
-->

---
layout: default
class: module-eight
---

# Physical and Logical Replication

<img src="./assets/module-08-physical-logical-enterprise-blue.png" class="concept-visual" alt="Physical WAL replication mirrors a cluster while logical replication selects published tables" />

<div class="concept-caption">
  <span>Physical WAL stream</span><span>Whole-cluster replica</span><span>Logical decoding</span><span>Selected tables</span><span>Separate subscriber</span>
</div>

<!--
Speaker notes: Physical streaming reproduces the complete cluster at the storage level and supports standby recovery. Logical replication selects published tables and applies row changes to a separate subscriber. Roles, sequence state, and schema changes need separate handling.
-->

---
layout: two-cols-header
class: module-eight
layoutClass: module-eight
---

# Lab 8D — Logical Replication

::left::

- Use: selective tables, upgrades, integration
- Not: complete cluster DR
- Needs `wal_level=logical` and slots

::right::

```text
Publisher tables
      → WAL logical decoding
      → publication
      → subscription
      → subscriber tables
```

```sql
CREATE PUBLICATION claims_reporting
  FOR TABLE insurance.claim,
            insurance.claim_payment;
```

<!--
Speaker notes: Run make logical-up, then make logical-verify for a separate subscriber. Subscriber tables must be pre-created. Sequences, roles, and DDL are not magically replicated. Apply wal_level=logical through the restart workflow from Module 6. Physical replica remains the DR path.
-->

---
layout: two-cols-header
class: module-eight
layoutClass: module-eight
---

# Lab 8E — PgBouncer Pool Modes

::left::

- session: released at disconnect
- transaction: preferred for many apps
- statement: breaks multi-statement TX

::right::

```ini
[databases]
claimsure = host=primary port=5432 dbname=claimsure

[pgbouncer]
listen_port = 6432
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 40
reserve_pool_size = 10
```

<!--
Speaker notes: Run make pool-verify to verify a real claim_app login and tenant RLS. APPLICATION RULE: with transaction pooling, use SET LOCAL inside a transaction for tenant context. Do not depend on session-scoped temp tables or prepared statements without checking PgBouncer and driver behavior. This is why Lab 3B used SET LOCAL, not SET.
-->

---
layout: default
class: module-eight
---

# Controlled Failover Sequence

<img src="./assets/module-08-failover-enterprise-blue.png" class="concept-visual" alt="Detect failure, fence the old primary, promote a replica, reroute clients, verify, and rejoin" />

<div class="concept-caption">
  <span>Detect</span><span>Fence</span><span>Promote</span><span>Route</span><span>Verify</span><span>Rejoin</span>
</div>

<!--
Speaker notes: Fencing must prevent the old primary from accepting writes before another node becomes writable. Promotion changes the replica role. Client routing then moves to the new primary, followed by verification and a controlled rebuild of the former primary as a replica.
-->

---
layout: default
class: module-eight
---

# Failover Is a Procedure

- Health checks and leader election / fencing
- Promote replica, isolate old primary
- Repoint pooler / clients
- Rejoin former primary as replica
- Prove writes, RLS context, and lag after cutover

```text
detect → fence → promote → route → verify → rejoin
```

<!--
Speaker notes: Replication is data movement, not HA. Patroni/HAProxy may appear in production designs; the lab must still name these steps. Capstone scoring includes promotion, fencing, routing, and rejoin — not just pg_is_in_recovery().
-->

---
layout: default
class: module-eight
---

# Module 8 Checkpoint

- Streaming walsender visible; replica in recovery
- Optional replica2 can be added, stopped, and restarted
- Team can interpret write vs flush vs replay lag
- Team can explain inactive slot WAL retention
- Logical publication is not the DR plan
- Transaction pooling + SET LOCAL tenant context
- Failover runbook has fence, route, verify, rejoin

<!--
Speaker notes: Verify SET LOCAL inside each transaction; RLS also applies with session pooling, but transaction pooling cannot rely on session state. If they only cloned with pg_basebackup and never measured lag, they are not done. Next: operate by symptoms — slow SQL, locks, deadlocks, disk, lag.
-->

---
layout: default
class: module-eight
---

# Failure Modes

- Calling a connected replica "HA" with no fencing
- Measuring receive lag but ignoring replay
- Stopped replica slot retaining unbounded WAL
- Logical publication as the DR plan
- Session GUCs and temp tables behind transaction pooling

```text
streaming ≠ failover    receive ≠ replay
```

<!--
Speaker notes: Idle replication slots fill pg_wal. Promoting without isolating the old primary is split-brain. SET versus SET LOCAL is the Module 4 tenant-context lesson again.
-->

---
layout: two-cols-header
class: module-eight
layoutClass: module-eight
---

# Production Checklist

::left::

- `pg_stat_replication` shows streaming; replica in recovery
- Node-add/down drill records slot behavior
- Replay byte/time lag compared to RPO
- Failover runbook: detect, fence, promote, route, verify, rejoin
- PgBouncer transaction mode + SET LOCAL tenant context
- Logical replication used only for its stated scope

::right::

```text
clone ✓  stream ✓  lag ✓
pool semantics ✓  runbook ✓
```

<!--
Speaker notes: Clients use pooler host port 55820 (container 6432), not a node hostname, if failover is in scope. wal_level=logical is a restart change if they need publications later.
-->

---
layout: default
class: module-eight
---

# Decision Scenario

> Payment writes must survive primary loss; reporting can lag 30 seconds. Which commit mode, and what do you still have to build besides replication?

```text
sync write for payments? → latency cost
still need: fence, promote, route, rejoin
```

<!--
Speaker notes: Asynchronous replica is not "near zero RPO." Synchronous remote write waits for OS write, not apply. They must still name the control plane. No vendor name required — the steps are.
-->

---
layout: default
class: module-eight
---

# Module 8 Recap

- Replica is WAL movement, not automatic HA
- Measure replay, not just "connected"
- Logical ≠ DR
- Pool mode is a transaction-semantics choice

<!--
Speaker notes: Close by repeating the mission. Module 9 incident drill will include a replica 4 GB behind during a settlement batch — they will need today's lag query.
-->
