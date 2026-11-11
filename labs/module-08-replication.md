# Module 8 — Replication และ High Availability

[กลับสารบัญ](README.md) · [สไลด์ต้นทาง English](../slides/module-08-replication.md) · [สไลด์ไทย](../slides/module-08-replication-th.md) · [Compose](module08-replication/compose.yaml)

ใช้ลำดับ **8A–8E** จาก `postgres-admin-labs/docs/slides/module-08-replication.md` เป้าหมายคือเห็นข้อมูลจาก Primary ไป Replica, เพิ่ม/หยุด Node แล้วอ่านสถานะได้ ก่อนเปรียบเทียบ Logical replication และ PgBouncer ช่วงท้ายใช้ทบทวน Failover runbook

## เตรียมครั้งแรก

ต้องมี Docker Engine/Desktop, Docker Compose v2, Python 3.10+ และ Make รันคำสั่งทั้งหมดจาก **root ของ repository** แต่ละกลุ่มใช้ Compose project และ host ports ของตน

```bash
make lab8-init
# ตรวจ labs/module08-replication/.env: เปลี่ยน project/ports ถ้ามีชุดอื่นใช้อยู่
make lab8-config
make lab8-pull
make up
```

`make up` สร้าง `.env` ให้เองถ้ายังไม่มี และเริ่มเพียง **primary + replica + pgbouncer** Replica ที่ volume ว่างจะ clone ด้วย `pg_basebackup -R -X stream` อัตโนมัติ แล้วเริ่ม read-only standby การเปิดซ้ำใช้ข้อมูลเดิม ไม่ clone ทับ

เปิดสไลด์อีก Terminal:

```bash
make slides MODULE=8 PORT=3048
# ภาษาไทย: make slides MODULE=8:th PORT=3048
```

### ชื่อ Node และพอร์ต

| Service | Host endpoint เริ่มต้น | หน้าที่ |
| --- | --- | --- |
| `primary` | `127.0.0.1:55811` | PostgreSQL เขียนข้อมูลได้ |
| `replica` | `127.0.0.1:55812` | Physical standby เริ่มพร้อม primary |
| `replica2` | `127.0.0.1:55813` | Physical standby เพิ่มเมื่อถึง 8B |
| `subscriber` | `127.0.0.1:55814` | PostgreSQL อีก cluster เริ่มเมื่อถึง 8D |
| `pgbouncer` | `127.0.0.1:55820` | Transaction pool ไป primary เริ่มพร้อม 8A |

ภายใน Docker network ทุก PostgreSQL ใช้ **5432** และ PgBouncer ใช้ **6432** การแยก host ports ไม่ได้เปลี่ยนพอร์ตภายใน ภาพสไลด์อธิบาย topology; ใช้ตารางนี้และ `.env` ของตนเป็นค่าเชื่อมต่อจริง

ทุก Node ใช้ database **`claimsure`** เป็นข้อมูลจำลองใน Compose ชุดนี้เอง แยกจาก `claimsure_xx` ของบทอื่น:

- `insurance.claim`: 3 เคลม — tenant 1 สองแถว, tenant 2 หนึ่งแถว
- `insurance.claim_payment`: 3 payments สำหรับทดลอง publication
- `insurance.audit_event`: เพิ่ม WAL ใน 8C; ไม่ได้ publish ไป logical subscriber
- `lab_m8`: แถวชั่วคราวสำหรับตัวตรวจ replication

### บัญชีเชื่อมต่อ

| Login | รหัสผ่านใน `.env` | ใช้กับ |
| --- | --- | --- |
| `postgres` | `M8_ADMIN_PASSWORD` | ตรวจ/จัดการ private lab |
| `replicator` | `M8_REPLICATION_PASSWORD` | Streaming และอ่านตารางที่ publish; ไม่ใช่ superuser |
| `claim_app` | `M8_APP_PASSWORD` | App ผ่าน PgBouncer; ไม่ใช่ owner/superuser และอยู่ภายใต้ RLS |

`make psql`, `make replica` และคำสั่ง Node อื่นเปิด psql ภายใน container จึงไม่ต้องติดตั้ง psql บน laptop ถ้ามี client อยู่แล้ว สามารถเชื่อมจาก laptop ได้ เช่น:

```bash
psql -X -W -h 127.0.0.1 -p 55811 -U postgres -d claimsure
psql -X -W -h 127.0.0.1 -p 55820 -U claim_app -d claimsure
```

ใช้พอร์ตจาก `.env` หากเปลี่ยนค่าไว้ และพิมพ์ SQL เฉพาะใน psql; ใช้ `\q` กลับ shell

## 8A — ตรวจ Replica ที่มีอยู่

ตรงสไลด์หน้า 2–4 รันจาก shell:

```bash
make up
make node-status
make sql-m8
make lab8-verify
```

ผลที่ควรเห็น:

- `primary`, `replica`, `pgbouncer` running/healthy
- Primary `is_standby = f` และ sender ของ `replica` อยู่ในสถานะ `streaming`
- มี physical slot `replica_slot` ที่ `active = t`
- `wal_level = logical` ในชุดนี้รองรับทั้ง physical streaming และ 8D; `max_wal_senders` / `max_replication_slots` มากพอ
- `make lab8-verify` ขึ้น `PASS` หลังเขียนแถว probe, รอ replay, ตรวจ shared system identifier และลองเขียนบน standby แล้วถูกปฏิเสธ ก่อนลบแถว probe

เปิด Primary:

```bash
make psql
```

ใน psql:

```sql
SELECT current_database(), current_user, pg_is_in_recovery();
SELECT application_name, client_addr, state, sync_state,
       write_lsn, flush_lsn, replay_lsn
FROM pg_stat_replication;
SELECT claim_id, tenant_id, claim_no, status FROM insurance.claim ORDER BY claim_id;
\q
```

เปิด Replica แล้วตรวจข้อมูลเดียวกัน:

```bash
make replica
```

```sql
SELECT pg_is_in_recovery(), pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();
SELECT claim_id, tenant_id, claim_no, status FROM insurance.claim ORDER BY claim_id;
BEGIN;
CREATE TABLE lab_m8.should_be_readonly(id integer);
-- Expected: SQLSTATE 25006 / cannot execute CREATE TABLE in a read-only transaction
ROLLBACK;
\q
```

หลักฐาน: Replica อยู่ใน recovery และอ่านเคลมได้เหมือน Primary หลัง replay แต่เขียนไม่ได้ `receive` และ `replay` เป็นคนละตำแหน่ง

## 8B — เพิ่ม Replica Node

ตรงสไลด์หน้า 5:

```bash
make node-add
make node-status
make sql-m8
make lab8-verify
```

ผลที่ควรเห็น:

- มี `replica2` เพิ่มจาก profile `ha-lab`
- Primary มี **2 physical streaming senders**: `replica` และ `replica2`
- มี slot แยก `replica_slot` และ `replica2_slot`, ทั้งคู่ active
- ตัวตรวจขึ้น `2 physical standbys`; ทั้งสองมี cluster identifier เดียวกับ Primary

```bash
make replica2
```

```sql
SELECT pg_is_in_recovery();
SELECT count(*) FROM insurance.claim;
\q
```

ควรได้ `t` และ 3 แถวสำหรับชุดตั้งต้น การส่ง `make node-add` ซ้ำใช้ volume เดิม ไม่ clone ทับ

## 8C — หยุด Replica แล้วดู WAL และ Catch-up

ตรงสไลด์หน้า 6–10 ขั้นนี้หยุด **replica2** โดย Primary ยังรับงานตามปกติ

```bash
make node-down NODE=replica2
make node-status
make sql-m8
```

ควรเหลือ sender ของ `replica` เพียงตัวเดียว แต่ **slot `replica2_slot` ยังอยู่และ inactive**: sender เป็น connection ปัจจุบัน ส่วน slot เป็นจุดเก็บตำแหน่ง WAL ที่ Node ยังต้องใช้

สร้าง WAL ระหว่างหยุด:

```bash
make lab8-wal
```

คำสั่งนี้ commit audit events 1,000 แถว ตาม SQL ในสไลด์หน้า 8 แล้วแสดงสถานะเปรียบเทียบ `restart_lsn` และ `retained_wal` หรือทำเองใน `make psql`:

```sql
INSERT INTO insurance.audit_event
  (tenant_id, actor, action, entity_type, entity_id, details)
SELECT 1, 'ha_lab', 'NODE_DOWN_WAL', 'replica2', g::text,
       jsonb_build_object('lab', '8C')
FROM generate_series(1, 1000) g;

SELECT slot_name, active, restart_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots ORDER BY slot_name;
```

เลือกสร้าง WAL แบบใดแบบหนึ่งก็พอ; ถ้ารันทั้งสองแบบจะได้ events เพิ่มอีก 1,000 แถว ไม่จำเป็นต้องได้ retained bytes เท่ากันทุกเครื่อง เพราะขึ้นกับ checkpoint และจังหวะ replay

คืน Node:

```bash
make node-up NODE=replica2
make lab8-verify
make sql-m8
make replica2
```

```sql
SELECT count(*) FROM insurance.audit_event WHERE action = 'NODE_DOWN_WAL';
SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();
\q
```

หลัง catch-up events ต้องมาถึง Replica2 และ slot กลับ active คำสั่ง `node-up/down` รับเฉพาะ `replica`/`replica2` เพื่อให้การทดลองตรงกับสไลด์

### อ่าน Lag และ Commit Mode

ใน `make psql`:

```sql
SELECT application_name,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS replay_byte_lag,
       write_lag, flush_lag, replay_lag
FROM pg_stat_replication;
SHOW synchronous_commit;
SHOW synchronous_standby_names;
```

ชุดเริ่มต้นเป็น **asynchronous replication**: แม้ `synchronous_commit = on` แต่ `synchronous_standby_names` ว่าง จึงไม่ได้รอ standby ไม่ใช้ค่า lag ที่เป็น NULL หลังว่างงานตัดสินว่า replication เสีย ให้เทียบ LSN และ probe ด้วย

| Mode | Primary รออะไรจาก standby ที่ตั้งเป็น synchronous |
| --- | --- |
| Async / ไม่มี synchronous standby | ไม่รอ standby; commit ล่าสุดอาจหายเมื่อ primary เสีย |
| `remote_write` | WAL เขียนถึง OS ของ standby; ยังไม่เท่ากับ durable flush |
| `on` พร้อม synchronous standby | WAL flush ลง durable storage ของ standby |
| `remote_apply` | WAL replay แล้วบน synchronous standby ที่กำหนด; latency เพิ่ม |

Slot ช่วยเก็บ WAL ไม่ใช่ backup ชุดนี้จำกัด `max_slot_wal_keep_size = 256MB` หากปล่อย Node หยุดนานและเขียนมากจน slot invalidated จะต้อง clone standby ใหม่ ไม่แก้ด้วยการ promote

## 8D — Logical Replication ไปอีก Cluster

ตรงสไลด์หน้า 12–13: publish เฉพาะ `insurance.claim` และ `insurance.claim_payment` ไป PostgreSQL `subscriber` ที่มี data directory และ system identifier ของตัวเอง

```bash
make logical-up
make logical-verify
```

`logical-up` ทำตามลำดับ:

1. สร้าง publication `claims_reporting` บน Primary สำหรับสองตาราง
2. เปิด profile `logical-lab` และสร้าง schema/tables ที่ Subscriber จาก [schema.sql](module08-replication/sql/schema.sql)
3. สร้าง subscription `claims_reporting_sub` ด้วยบัญชี `replicator` และ passfile ภายใน container
4. รอ initial copy ของตารางพร้อมใช้งาน การเปิดซ้ำใช้ subscription เดิม

`logical-verify` ทดลอง INSERT → UPDATE → DELETE ด้วยแถว UUID ใหม่ แล้วรอผลบน Subscriber ทุกขั้น ก่อนคืนแถวทดลอง ตรวจด้วยว่าตาราง audit ที่ไม่ได้ publish ไม่ได้ตามมาด้วย

ดู publication บน `make psql`:

```sql
SELECT pubname, schemaname, tablename
FROM pg_publication_tables ORDER BY pubname, tablename;
```

ดู Subscriber:

```bash
make subscriber
```

```sql
SELECT pg_is_in_recovery(); -- f: เป็นอีก cluster ไม่ใช่ physical standby
SELECT claim_no, status FROM insurance.claim ORDER BY claim_no;
SELECT count(*) FROM insurance.claim_payment;
SELECT to_regclass('insurance.audit_event'); -- NULL: ไม่ได้ publish ตารางนี้
SELECT subname, received_lsn, latest_end_lsn FROM pg_stat_subscription;
\q
```

แถวตั้งต้นควรเป็นเคลม 3 แถวและ payments 3 แถว Logical replication ไม่สร้าง schema/DDL/roles/RLS policies และไม่ส่ง sequence state ให้เอง ชุด Subscriber นี้ใช้ `postgres` ตรวจข้อมูลการจำลองเท่านั้น ถ้าใช้เป็น app database ต้องออกแบบสิทธิ์/Policies ของ Subscriber แยกต่างหาก

## 8E — PgBouncer Transaction Pooling

ตรงสไลด์หน้า 14; config อยู่ที่ [pgbouncer.ini](module08-replication/config/pgbouncer.ini) ใช้ `pool_mode = transaction` และไป `primary:5432`

```bash
make pool-verify
make pgbouncer
```

`make pgbouncer` เป็น Login จริงของ **`claim_app`** ผ่าน Pooler ไม่ใช่ superuser ใน psql ทดลอง:

```sql
SELECT session_user, current_user;
SELECT claim_no, tenant_id FROM insurance.claim; -- 0 แถว: ยังไม่มี tenant context

BEGIN;
SET LOCAL app.tenant_id = '1';
SELECT claim_no, tenant_id FROM insurance.claim ORDER BY claim_no; -- tenant 1: 2 แถว
COMMIT;

SELECT claim_no, tenant_id FROM insurance.claim; -- 0 แถว: SET LOCAL จบพร้อม transaction

BEGIN;
SET LOCAL app.tenant_id = '2';
SELECT claim_no, tenant_id FROM insurance.claim ORDER BY claim_no; -- tenant 2: 1 แถว
COMMIT;
\q
```

`pool-verify` ตรวจโหมดจริงผ่าน PgBouncer admin DB แล้ว Login เป็น claim_app เพื่อทดสอบทั้งสอง tenant และ context หลัง commit การใช้ `SET LOCAL` ต้องอยู่ใน transaction ของแต่ละ request; session state อาจติดอยู่ใน backend pool ถ้าใช้ `SET` แบบถาวร Custom GUC นี้เป็นการจำลอง context ใน SQL ไม่ใช่กลไกยืนยัน tenant ที่ผู้ใช้ปลอมเองไม่ได้

## Failover Runbook — ทบทวนท้ายสไลด์

8C เป็น **replica outage** ส่วน primary failover ต้องทำครบ:

| ขั้น | หลักฐานที่ต้องตอบได้ |
| --- | --- |
| Detect | Node ใดเสียและ replica ใด replay ถึงจุดไหน |
| Fence | ยืนยันว่า Primary เดิมรับงานเขียนไม่ได้แล้ว |
| Promote | เลือก standby และยอมรับความเสี่ยงข้อมูลตาม commit/lag |
| Route | เปลี่ยน pooler/client endpoint ให้ไป Primary ใหม่ |
| Verify | เขียนและอ่านสำเร็จ, role/RLS ถูกต้อง และตรวจ lag |
| Rejoin | Rebuild หรือ rewind Primary เดิมให้เป็น standby ของ Primary ใหม่ |

Compose นี้ใช้ Primary endpoint คงที่และสอน node-add/down ตามสไลด์ ไม่ได้ตั้ง automatic leader election หรือให้ `node-up` ทำ failover การเปิด Primary เดิมหลัง promote โดยไม่ fence/rejoin อาจทำให้มีสองฝั่งรับ writes จึงต้องใช้ runbook ที่ออกแบบแยกเมื่อฝึก primary failover จริง

## จบงานและเปิดต่อ

```bash
make stop
# เปิดชุดหลักต่อ: make up
# ถ้าทำ 8B/8D แล้ว ให้เปิดเพิ่มด้วย make node-add / make logical-up
make down
```

`stop` หยุดทุก service ของ Lab 8 รวม optional profiles ส่วน `down` ลบ containers/network แต่ **เก็บ named volumes** การหยุด subscriber ทิ้ง logical slot ไว้บน publisher เช่นกัน ให้จบ workshop ด้วยการหยุดทั้ง project ไม่ปล่อย publisher เขียนต่อไม่จำกัดโดยไม่มี subscriber

`.env` เก็บ secrets สิทธิ์ `0600` ไม่ต้อง `init` ใหม่เมื่อ resume และไม่ลบ volumes เพื่อแก้ error ของพอร์ต ใช้ Compose project และ host ports คนละชุดกับบริการอื่น

หากมี `.env` ของ Lab รุ่นเก่า `pg1/pg2/pg3` อยู่ ตัว helper จะปฏิเสธเพื่อเก็บ credentials/volumes เดิมไว้ สามารถสร้างไฟล์ใหม่ด้วย `M8_ENV_FILE=/absolute/path/new.env make lab8-init` แล้วตั้ง **project ใหม่** และพอร์ตว่าง ใช้ `M8_ENV_FILE` ไฟล์เดิมทุกคำสั่งของชุดใหม่

## ส่งหลักฐาน

- 8A: Primary sender / Replica recovery และผล `make lab8-verify`
- 8B: Two physical senders และสอง active slots
- 8C: Slot inactive ระหว่างหยุด, WAL ที่ค้าง และ events หลัง catch-up
- 8D: สอง published tables, ผล initial copy และ `make logical-verify`
- 8E: `make pool-verify` และผล claim_app เห็น 2 → 0 → 1 แถวตาม transaction context
- อธิบายว่า streaming, slot retention และ primary failover ต่างกันอย่างไร

อ้างอิง: [pg_basebackup](https://www.postgresql.org/docs/18/app-pgbasebackup.html), [Logical subscription](https://www.postgresql.org/docs/18/sql-createsubscription.html), [PgBouncer pool mode](https://www.pgbouncer.org/config.html#pool_mode)
