---
theme: default
title: "Module 8: Replication และ High Availability"
layout: module08-cover
class: module-eight module-cover thai-deck
colorSchema: light
fonts:
  sans: 'Noto Sans Thai'
info: "PostgreSQL Developer and DBA Bootcamp v3 | Day 1"
transition: slide-left
mdc: true
lang: th
---




<div class="cover-art"><img src="./assets/module-08-replication-cover-enterprise-blue.png" alt="PostgreSQL primary, replicas, pooler, logical subscriber, monitoring, and controlled failover" /></div>

# Module 8: Replication และ High Availability

## สร้าง Platform ClaimSure แบบ Primary–Replica โดยคงความหมายของ Transaction ให้ถูกต้อง

<!--
Speaker notes: Mission: primary-replica claim platform, understand lag, introduce PgBouncer without breaking SET LOCAL tenant context. Replication is data movement, not a complete HA system. You still need health checks, fencing, promotion, client routing, old-primary isolation, and rejoin.
-->

---
layout: default
class: module-eight thai-deck
---


# Topology ของ Primary, Replica และ Pooler

<img src="./assets/module-08-topology-enterprise-blue.png" class="concept-visual" alt="Applications connect through a pooler to one writable primary that streams WAL to read-only replicas" />

<div class="concept-caption">
  <span>Applications</span><span>Pooler</span><span>Primary ที่เขียนได้</span><span>WAL Stream</span><span>Replicas แบบ Read-only</span>
</div>

<!--
Speaker notes: Applications connect to a routing layer instead of hard-coding a database node. One primary accepts writes. PostgreSQL container ports are all 5432; the walkthrough lists separate host ports. WAL moves in one direction to read-only replicas. Health and lag checks observe each node separately.
-->

---
layout: two-cols-header
class: module-eight
layoutClass: module-eight thai-deck
---


# Primary, Replica และ Pooler

::left::

- Application เชื่อมต่อผ่าน Pooler :55820
- Primary :55811 รับงานเขียน
- Replica :55812 ใช้อ่านข้อมูลหรือทำ DR
- Replica2 :55813 เป็นตัวเลือกสำหรับฝึกเพิ่มและหยุด Node

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
layoutClass: module-eight thai-deck
---


# Lab 8A — ตรวจ Replica ที่มีอยู่

::left::

- Role `replicator` ที่จำกัดสิทธิ์ร่วมกับ HBA Rule
- Compose เริ่ม `replica` จาก `pg_basebackup`
- ยืนยัน `wal_level`, Senders, Slots และ Recovery State

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
layoutClass: module-eight thai-deck
---


# Lab 8B — เพิ่ม Replica Node

::left::

- เริ่ม `replica2` ซึ่งเป็นตัวเลือกใน Profile `ha-lab`
- `replica2` Clone จาก Primary ด้วย `pg_basebackup`
- ใช้ Replication Slot ของตน คือ `replica2_slot`
- ตรวจจาก Primary ว่ามี Replicas สองตัวกำลัง Streaming

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
layoutClass: module-eight thai-deck
---


# Lab 8C — หยุด Replica Node

::left::

- หยุด `replica2` โดยไม่หยุด Primary
- สังเกตว่า Stream หายจาก `pg_stat_replication`
- ยืนยันว่า `replica2_slot` เปลี่ยนเป็น Inactive
- Start กลับแล้วดูการ Replay ให้ทัน

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
class: module-eight thai-deck compact-table compact-code
---

# Lab 8B/8C — ลำดับการจำลอง

| ขั้นตอน | การทำงาน | หลักฐานที่คาดว่าจะได้ |
| --- | --- | --- |
| 1 | เก็บ Baseline ของ Topology ปัจจุบัน | พบ Streaming หนึ่งหรือสองแถว |
| 2 | เพิ่ม `replica2` | มี Container ใหม่ Slot ใหม่ และ Stream ที่สอง |
| 3 | สร้าง WAL บน Primary | LSN เพิ่มขึ้น |
| 4 | หยุด `replica2` | Stream หายไปและ Slot เป็น Inactive |
| 5 | สร้าง WAL เพิ่ม | WAL ที่เก็บไว้ให้ Inactive Slot อาจเพิ่มขึ้น |
| 6 | Start `replica2` | Stream กลับมาและ Replay จนตามทัน |

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
layoutClass: module-eight thai-deck
---


# รายละเอียด Lab 8C — สร้าง WAL ขณะ Node หยุด

::left::

**หลังหยุด `replica2`**

- เขียน Audit Batch ขนาดเล็กบน Primary
- ตรวจ `replica2_slot`
- เปรียบเทียบ Retained WAL ก่อนและหลัง
- Start Node กลับ แล้วตรวจว่า Replay ตามทัน

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
class: module-eight thai-deck
---


# ขั้นต่าง ๆ ของ Replication Lag

<img src="./assets/module-08-lag-enterprise-blue.png" class="concept-visual" alt="WAL generation, network transfer, replica write, flush, replay, and inactive slot retention" />

<div class="concept-caption">
  <span>สร้าง WAL</span><span>ส่ง WAL</span><span>เขียน WAL</span><span>Flush WAL</span><span>Replay WAL</span><span>การเก็บ WAL ของ Slot</span>
</div>

<!--
Speaker notes: Lag exists at several boundaries. A replica may receive WAL before it writes, flushes, or replays it. Only replay changes the visible standby data. An inactive slot retains WAL on the primary and creates a separate disk-capacity risk.
-->

---
layout: two-cols-header
class: module-eight
layoutClass: module-eight thai-deck
---


# Lag ไม่ได้มีเพียงค่าเดียว

::left::

- Write Lag, Flush Lag และ Replay Lag
- Byte Lag เทียบกับ Time Lag
- Slot Retention อาจทำให้ `pg_wal` เต็ม

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
class: module-eight thai-deck
---


# Commit Modes

| Mode                     | พฤติกรรมของ Commit              | ข้อแลกเปลี่ยน                              |
| ------------------------ | ---------------------------- | -------------------------------------- |
| Asynchronous             | Primary ไม่ต้องรอ Replica        | Failover อาจสูญเสีย Transactions ล่าสุด    |
| Synchronous remote write | รอให้ OS ฝั่ง Remote รับการเขียน     | ลดโอกาสสูญหาย แต่เพิ่ม Network Latency       |
| Synchronous remote apply | รอจน Replica Replay แล้ว          | Standby อ่านหลัง Replay ได้แน่นอนขึ้น แต่มี Latency สูงสุดในกลุ่มนี้  |

<!--
Speaker notes: ClaimSure payments may justify sync write; a reporting replica may not. Name the RPO implication. FAILOVER reminder: lag graphs do not promote a node. Promotion without fencing the old primary is split-brain.
-->

---
layout: default
class: module-eight thai-deck
---


# Physical และ Logical Replication

<img src="./assets/module-08-physical-logical-enterprise-blue.png" class="concept-visual" alt="Physical WAL replication mirrors a cluster while logical replication selects published tables" />

<div class="concept-caption">
  <span>Physical WAL Stream</span><span>Replica ของทั้ง Cluster</span><span>Logical decoding</span><span>Tables ที่เลือก</span><span>Subscriber แยกต่างหาก</span>
</div>

<!--
Speaker notes: Physical streaming reproduces the complete cluster at the storage level and supports standby recovery. Logical replication selects published tables and applies row changes to a separate subscriber. Roles, sequence state, and schema changes need separate handling.
-->

---
layout: two-cols-header
class: module-eight
layoutClass: module-eight thai-deck
---


# Lab 8D — Logical Replication

::left::

- ใช้กับ Tables ที่เลือก การ Upgrade และ Integration
- ไม่ได้แทน DR ของทั้ง Cluster
- ต้องมี `wal_level=logical` และ Slots

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
layoutClass: module-eight thai-deck
---


# Lab 8E — Pool Modes ของ PgBouncer

::left::

- session: คืน Server Connection เมื่อ Disconnect
- transaction: เหมาะกับ Applications จำนวนมาก
- statement: ใช้กับ Transaction หลาย Statements ไม่ได้

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
class: module-eight thai-deck
---


# ลำดับ Failover แบบควบคุม

<img src="./assets/module-08-failover-enterprise-blue.png" class="concept-visual" alt="Detect failure, fence the old primary, promote a replica, reroute clients, verify, and rejoin" />

<div class="concept-caption">
  <span>ตรวจพบปัญหา</span><span>Fence ระบบเดิม</span><span>Promote Replica</span><span>เปลี่ยนเส้นทาง Connection</span><span>ตรวจสอบผล</span><span>นำ Node กลับเข้าระบบ</span>
</div>

<!--
Speaker notes: Fencing must prevent the old primary from accepting writes before another node becomes writable. Promotion changes the replica role. Client routing then moves to the new primary, followed by verification and a controlled rebuild of the former primary as a replica.
-->

---
layout: default
class: module-eight thai-deck
---


# Failover ต้องมีขั้นตอนชัดเจน

- Health Checks และ Leader Election / Fencing
- Promote Replica พร้อมแยก Primary เดิมออก
- เปลี่ยนปลายทาง Pooler / Clients
- นำ Primary เดิมกลับมาเป็น Replica
- พิสูจน์งานเขียน RLS Context และ Lag หลัง Cutover

```text
detect → fence → promote → route → verify → rejoin
```

<!--
Speaker notes: Replication is data movement, not HA. Patroni/HAProxy may appear in production designs; the lab must still name these steps. Capstone scoring includes promotion, fencing, routing, and rejoin — not just pg_is_in_recovery().
-->

---
layout: default
class: module-eight thai-deck
---


# จุดตรวจ Module 8

- เห็น Streaming Walsender และ Replica อยู่ใน Recovery
- เพิ่ม หยุด และ Start Replica2 ซึ่งเป็นตัวเลือกได้
- อธิบายความต่าง Write / Flush / Replay Lag ได้
- อธิบายการเก็บ WAL ของ Inactive Slot ได้
- Logical Publication ไม่ใช่แผน DR
- Transaction Pooling ร่วมกับ SET LOCAL Tenant Context
- Failover Runbook มี Fence, Route, Verify และ Rejoin

<!--
Speaker notes: Verify SET LOCAL inside each transaction; RLS also applies with session pooling, but transaction pooling cannot rely on session state. If they only cloned with pg_basebackup and never measured lag, they are not done. Next: operate by symptoms — slow SQL, locks, deadlocks, disk, lag.
-->

---
layout: default
class: module-eight thai-deck
---


# ปัญหาที่พบบ่อย

- เรียก Replica ที่เชื่อมต่อได้ว่า HA ทั้งที่ไม่มี Fencing
- วัด Receive Lag แต่ไม่ดู Replay
- Slot ของ Replica ที่หยุดอยู่เก็บ WAL โดยไม่จำกัด
- ใช้ Logical Publication เป็นแผน DR
- ใช้ Session GUCs และ Temp Tables หลัง Transaction Pooling โดยไม่คำนึงถึงขอบเขต

```text
streaming ≠ failover    receive ≠ replay
```

<!--
Speaker notes: Idle replication slots fill pg_wal. Promoting without isolating the old primary is split-brain. SET versus SET LOCAL is the Module 4 tenant-context lesson again.
-->

---
layout: two-cols-header
class: module-eight
layoutClass: module-eight thai-deck
---


# รายการตรวจสำหรับ Production

::left::

- `pg_stat_replication` แสดง Streaming และ Replica อยู่ใน Recovery
- การฝึกเพิ่ม/หยุด Node บันทึกพฤติกรรม Slot ไว้
- เปรียบเทียบ Replay Byte/Time Lag กับ RPO
- Failover Runbook: Detect, Fence, Promote, Route, Verify และ Rejoin
- PgBouncer Transaction Mode ร่วมกับ SET LOCAL Tenant Context
- ใช้ Logical Replication เฉพาะขอบเขตที่กำหนดไว้

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
class: module-eight thai-deck
---


# สถานการณ์ให้ตัดสินใจ

> งานเขียน Payment ต้องไม่สูญหายเมื่อ Primary หาย แต่รายงานยอม Lag ได้ 30 วินาที ควรเลือก Commit Mode ใด และยังต้องสร้างอะไรนอกจาก Replication?

```text
sync write for payments? → latency cost
still need: fence, promote, route, rejoin
```

<!--
Speaker notes: Asynchronous replica is not "near zero RPO." Synchronous remote write waits for OS write, not apply. They must still name the control plane. No vendor name required — the steps are.
-->

---
layout: default
class: module-eight thai-deck
---


# สรุป Module 8

- Replica คือการส่งต่อ WAL ไม่ได้ทำให้เป็น HA โดยอัตโนมัติ
- วัด Replay ด้วย ไม่ใช่ดูเพียงว่า Connected
- Logical ไม่เท่ากับ DR
- เลือก Pool Mode โดยคำนึงถึงความหมายของ Transaction

<!--
Speaker notes: Close by repeating the mission. Module 9 incident drill will include a replica 4 GB behind during a settlement batch — they will need today's lag query.
-->
