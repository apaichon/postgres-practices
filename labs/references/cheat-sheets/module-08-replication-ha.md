# Module 8 Cheat Sheet — Replication and High Availability

## Mission

Move WAL predictably, measure apply state, preserve application transaction semantics, and execute failover without split brain.

## Replication lifecycle

```text
prepare primary -> seed replica -> start streaming -> measure receive/flush/replay
                -> monitor slots and retained WAL -> test node loss/recovery
```

## Failover lifecycle

```text
detect -> fence old primary -> choose/promote replica -> route clients
       -> verify writes, security context, and lag -> rebuild/rejoin old node
```

Replication is data movement. High availability also requires detection, fencing, leadership, routing, verification, and rejoin.

## Primary evidence

```sql
SELECT application_name, client_addr, state, sync_state,
       sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS replay_gap
FROM pg_stat_replication;

SELECT slot_name, slot_type, active, restart_lsn,
       wal_status, safe_wal_size
FROM pg_replication_slots;
```

## Replica evidence

```sql
SELECT pg_is_in_recovery(),
       pg_last_wal_receive_lsn(),
       pg_last_wal_replay_lsn(),
       now() - pg_last_xact_replay_timestamp() AS replay_delay;
```

No single lag number is sufficient. Distinguish send, receive, write, flush, and replay.

## Decision points

| Decision | Trade-off |
| --- | --- |
| Asynchronous commit | Lower primary latency; possible loss of unreplicated commits |
| Synchronous commit | Lower RPO; added latency and availability dependency |
| Physical replication | Whole-cluster binary stream; same major-version constraints |
| Logical replication | Selected data/change stream; not a complete DR system |
| Session pooling | Preserves session state; lower multiplexing |
| Transaction pooling | Better multiplexing; session assumptions may break |

With transaction pooling, use transaction-local context such as `SET LOCAL`; do not assume session state persists.

## Analysis questions

- Does the business care about receipt, durable flush, or replay visibility?
- Can an inactive slot retain WAL until disk fills?
- How are clients routed away from a failed primary?
- What mechanism proves the old primary cannot accept writes?
- Does the application tolerate the selected pool mode and read-after-write behavior?

## Avoid

- Calling one connected replica “HA.”
- Promoting before fencing the old primary.
- Measuring receive lag while ignoring replay.
- Treating a logical publication as the backup/DR plan.
- Depending on session GUCs or temp tables behind transaction pooling without validation.

## Definition of done

Streaming and replay are measured against RPO, slot retention is bounded, pool semantics are tested, and the failover drill proves fence, promote, route, verify, and rejoin.
