# Module 5 — PostgreSQL Architecture ตามสไลด์ภาษาไทย

[กลับสารบัญ](README.md) · [สไลด์ 33 หน้า](../slides/module-05-architecture-th.md) · [Source SQL](module05-architecture/05-architecture.sql) · [Continuous lab เดิม](module-05-architecture-continuous.md)

ใช้สไลด์และ SQL จาก `setup-postgres-server/postgres-admin-labs` ตามลำดับ **5A–5G** รวม **5D.1–5D.5** เพื่อสังเกต Connection → Backend → Memory/Locks → Tuple versions → MVCC → WAL → Storage ดู [ที่มาและ hashes](module05-architecture/upstream.json)

## เตรียมฐานข้อมูลสำหรับเวอร์ชันนี้

ต้นฉบับใช้ `claimsure.claim`, `claimsure.audit_event` และสิทธิ์ Superuser จึงให้ **Instructor** เตรียม database เฉพาะ `architecture_m5_xx` (`01`–`20`) บน writable PostgreSQL 18 ไม่ใช้ฐาน continuous `claimsure_xx`, Supabase หรือ Primary ของ Lab 8 ซึ่งมี schema ต่างกัน

ต้องมี `psql`, `createdb`, Python 3.10+ และ Make หลัง SSH เข้าเครื่อง workshop ให้รันจาก **root ของ repo** ตั้ง host/port ตามอาจารย์และแทน `xx` ด้วยเลขที่ได้รับ:

```bash
export STUDENT_NO=xx
export PGHOST=127.0.0.1 PGPORT=5432
export PGUSER=postgres
export PGDATABASE="architecture_m5_$STUDENT_NO"
export PGCONNECT_TIMEOUT=5
unset PGPASSWORD

# Instructor ทำครั้งเดียว; ถ้าฐานมีอยู่แล้วให้ใช้ฐานเดิม ไม่ลบแล้วสร้างใหม่
createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -W "$PGDATABASE"
make lab5-setup
```

`make lab5-setup` รัน [00-setup.sql](module05-architecture/00-setup.sql): สร้าง policy/claim/audit fixtures ใน `insurance` มี **6 เคลม CLM-L1-001–006** และ **CLM-1001 อีกหนึ่งแถว** สำหรับ preflight/audit ของต้นฉบับ โดยเริ่ม `CLM-L1-005` เป็น `NEW` ตาราง claim มี `created_at` และไม่มี `updated_at` การ setup ซ้ำเก็บข้อมูลเดิมและผล Lab ที่ commit แล้ว ไม่ reset ให้โดยอัตโนมัติ

SQL ทั้งสามไฟล์และ setup ตรวจชื่อฐาน `architecture_m5_01..20`, writable server และ Superuser ก่อนเริ่ม ไม่สร้าง/เปลี่ยน Login หรือสิทธิ์ของบัญชีห้องเรียน

เปิดสไลด์บน laptop หรือเครื่องที่มี Node.js 22.12+:

```bash
make slides MODULE=5 PORT=3035
```

### เปิด Terminal และตรวจตัวตน

ตั้ง `STUDENT_NO`, `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE` ตามข้างบนใหม่ใน **แต่ละ Terminal** โดยไม่รัน `createdb` ซ้ำ แล้วเปิดอย่างน้อยสอง connections:

```bash
# Terminal A
PGAPPNAME=module5-a psql -X -W
```

```bash
# Terminal observer/B
PGAPPNAME=module5-observer psql -X -W
```

ใน psql ทุก connection:

```sql
\conninfo
\pset pager off
\set VERBOSITY verbose
SET TIME ZONE 'Asia/Bangkok';
SELECT pg_backend_pid(), current_database(), session_user, current_user;
```

ต้องเป็นฐาน `architecture_m5_xx` ของตนและ Instructor Login ที่ได้รับอนุญาต แต่ละ connection ต้องมี PID ต่างกัน ตัวอย่างใช้สอง connections ของ postgres เพื่อสังเกต backend ไม่ต้องสร้าง claim_app เพิ่ม บล็อก `bash` รันใน shell ส่วน `sql` รันใน psql และใช้ `\q` กลับ shell

## วิธีเลือกทำ Lab

เลือกได้สองวิธี: วาง SQL ทีละหัวข้อใน psql ตามคู่มือนี้ หรือรันหัวข้อครบชุดด้วย Make จาก shell:

```bash
make lab5
make lab5 LAB_NO=5A
make lab5 LAB_NO=5C
make lab5 LAB_NO=5D.1
make lab5 LAB_NO=5F
```

Make อ่าน Section จาก Source SQL เดียวกับคู่มือ และตรวจ preflight ก่อนแต่ละหัวข้อ จึงใช้ transaction boundary และ cleanup ของต้นฉบับครบ ไม่ใช้ `psql --single-transaction` เพราะ 5D.1 และ 5F ต้อง commit จริง

`make lab5 LAB_NO=all` รัน Source SQL ครบ แต่ 5E ในไฟล์รวมเป็นคำแนะนำสำหรับเปิด Session A/B ต้องทำการทดลองสอง connections ตามหัวข้อ 5E แยกต่างหาก การรัน `all` อย่างเดียวไม่พิสูจน์ MVCC

| หัวข้อ | หน้าในสไลด์ | สิ่งที่ต้องเห็น |
| --- | --- | --- |
| 5A | 4–5 | สอง connection มี backend PID ต่างกัน |
| 5B | 6–7 | Background processes และ cumulative statistics |
| 5C | 8–9 | UPDATE ถือ locks แล้ว ROLLBACK คืน NEW |
| 5D / 5D.1 | 10–13 | Tuple header / commit แล้ว LSN เพิ่ม |
| 5D.2 | 14–16 | INSERT สร้าง tuple; rollback ไม่เก็บแถว |
| 5D.3 | 17–19 | UPDATE สร้าง replacement tuple |
| 5D.4 | 20–24 | DELETE visibility 0 → undo กลับ 1 |
| 5D.5 | 25 | แยก Page state, tuple visibility และ statistics |
| 5E | 26 | Repeatable Read คง snapshot จนจบ transaction |
| 5F | 27–28 | 1,000 committed events, WAL delta และ flush evidence |
| 5G | 29–31 | PGDATA, relation path, WAL directory; ทบทวน maintenance/recovery |
| Concept check / recap | 32–33 | อธิบายเส้นทางของ claim ด้วยหลักฐานที่ทดลอง |

## 5A — สังเกต Connections

เปิด observer connection ค้างไว้ก่อน แล้วใช้ A ตรวจ activity ต้องมี PID คนละตัว แม้ใช้ Login เดียวกัน Connection ตรงจะมี backend ของตัวเอง; ไม่ผ่าน transaction pooler ในการทดลอง MVCC นี้

```sql
\echo '\n-- Lab 5A: Observe Connections (PDF pp. 105-106)'
-- Open two terminals from the repository root:
--   PGAPPNAME=module5-a psql -X
--   PGAPPNAME=module5-observer psql -X
-- In each, run SELECT pg_backend_pid(); then inspect activity as postgres.
SELECT pg_backend_pid() AS backend_pid,
       current_database() AS database_name,
       current_user AS database_user,
       inet_client_addr() AS client_address,
       pg_postmaster_start_time() AS server_started_at;

SELECT pid, backend_type, usename, application_name, client_addr, state,
       query_start, wait_event_type, wait_event, left(query, 80) AS query
FROM pg_stat_activity
WHERE datname = current_database()
ORDER BY pid;
-- VERIFY: each direct session has a different PID; idle sessions keep a backend.
```

## 5B — Background Processes

ดู background writer, checkpointer, WAL writer และ autovacuum launcher ไม่จำเป็นต้องพบ worker ทุกชนิดในทุกครั้ง Counters เป็น cumulative ระดับ cluster และอาจเผยแพร่ช้า เปรียบเทียบสองช่วงพร้อม stats_reset แทนการอ่านยอดรวมครั้งเดียว

```sql
\echo '\n-- Lab 5B: Background Process Evidence (PDF pp. 107-108)'
SELECT pid, backend_type, state, wait_event_type, wait_event
FROM pg_stat_activity
WHERE backend_type <> 'client backend'
ORDER BY backend_type, pid;

SELECT * FROM pg_stat_bgwriter;
SELECT to_regclass('pg_catalog.pg_stat_checkpointer') IS NOT NULL AS has_checkpointer \gset
\if :has_checkpointer
SELECT * FROM pg_stat_checkpointer;
\else
\echo 'Before PostgreSQL 17, checkpoint counters are included in pg_stat_bgwriter.'
\endif
SELECT * FROM pg_stat_wal;
-- VERIFY: find background writer, checkpointer, WAL writer and autovacuum launcher.
-- Workers appear only when needed; archiver depends on archive configuration.
-- Counters are cumulative and can lag; repeat after the writes in 5D/5F.
```

## 5C — Shared Memory และ Locks ระหว่าง UPDATE

เริ่มด้วย CLM-L1-005 เป็น NEW แล้ว UPDATE เป็น REVIEW ภายใน transaction ดู locks ก่อน ROLLBACK และกลับเป็น NEW ข้อมูล locks บน row อาจอยู่ใน tuple header ไม่ได้มีหนึ่งแถวใน pg_locks ต่อทุก row lock

```sql
\echo '\n-- Lab 5C: Shared Memory in a Claim Update (PDF pp. 109-110)'
SHOW shared_buffers;
SHOW wal_buffers;
SHOW max_connections;
SHOW work_mem;
-- shared_buffers and wal_buffers are shared; work_mem is per operation.
-- effective_cache_size is a planner estimate, not allocated memory.
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN ('effective_cache_size', 'maintenance_work_mem')
ORDER BY name;

-- Claim columns: claim_id, claim_no, policy_id, status, incident_at,
-- estimated_amount, approved_amount, created_at.
-- CLM-L1-005 starts as NEW. The update below is rolled back.
SELECT claim_id, claim_no, policy_id, status, incident_at,
       estimated_amount, approved_amount, created_at
FROM claimsure.claim
ORDER BY claim_id;

BEGIN;
UPDATE claimsure.claim
SET status = 'REVIEW'
WHERE claim_no = 'CLM-L1-005'
RETURNING claim_id, claim_no, policy_id, status, incident_at,
          estimated_amount, approved_amount, created_at;

SELECT locktype, relation::regclass AS relation, transactionid, mode, granted
FROM pg_locks
WHERE pid = pg_backend_pid()
ORDER BY locktype, mode;
ROLLBACK;

-- VERIFY: the read lists the claim columns above.
-- UPDATE returns CLM-L1-005 with status REVIEW.
-- ROLLBACK restores NEW. Relation/transaction locks exist before rollback.
-- Row locks are normally stored in tuple headers, not all listed in pg_locks.
```

## 5D — อ่าน Tuple Header และ Column Values

ctid เป็นตำแหน่ง tuple version ไม่ใช่ business key; xmin/xmax ต้องตีความร่วมกับ transaction status และ snapshot เลข xmax ไม่เป็นศูนย์ไม่ได้ยืนยันว่า tuple ตาย

```sql
\echo '\n-- Lab 5D: Data Page and Tuple States (PDF pp. 111-112)'
-- Dirty/clean describes a buffer page; live/old/deleted/dead describes tuples.
-- ctid is (block number, tuple slot), not a stable business key.
-- xmin identifies the inserting transaction. xmax can represent deletion,
-- update or locking; a nonzero xmax alone does not prove a tuple is dead.
-- Ask: show the example data stored in one tuple.
-- Header: ctid, xmin, xmax. Column values: the CLM-L1-005 claim row.
SELECT ctid, xmin, xmax,
       claim_id, claim_no, policy_id, status,
       incident_at, estimated_amount, approved_amount, created_at
FROM claimsure.claim
WHERE claim_no = 'CLM-L1-005';
```

## 5D.1 — Page Lifecycle และ Durable Commit

หัวข้อนี้ COMMIT ค่า created_at ใหม่ให้ CLM-L1-005 โดย status ยัง NEW ต้องเห็น WAL delta > 0 ภายใต้ fsync/synchronous_commit ตามชุด Lab แต่ไม่ได้ใช้ LSN เป็นเครื่องวัด page dirtiness โดยตรง

```sql
\echo '\n-- Lab 5D.1: Page Lifecycle (PDF p. 113)'
SHOW shared_buffers;
SELECT pg_current_wal_insert_lsn() AS page_before_lsn \gset
BEGIN;
SET LOCAL synchronous_commit = on;
-- claim has created_at, not updated_at.
-- This commit replaces created_at on CLM-L1-005. status stays NEW.
UPDATE claimsure.claim
SET created_at = clock_timestamp()
WHERE claim_no = 'CLM-L1-005'
RETURNING ctid, xmin, xmax, claim_no, status, created_at;
COMMIT;

SELECT :'page_before_lsn'::pg_lsn AS before_lsn,
       pg_current_wal_insert_lsn() AS after_lsn,
       pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'page_before_lsn'::pg_lsn) AS wal_bytes;
-- VERIFY: WAL advanced. With fsync enabled and synchronous_commit=on, commit
-- waits for local WAL flush; it need not wait for the changed heap page write.
-- Background writer/checkpointer (and sometimes backends) write dirty pages.
-- An LSN change is WAL evidence, not a direct measurement of buffer dirtiness.
```

## 5D.2 — INSERT สร้าง Tuple ใหม่

INSERT คืน ctid/xmin ของ audit event ที่ transaction นี้เห็นเอง แล้ว ROLLBACK จึงไม่เหลือ event นั้น แต่ sequence สามารถข้ามเลขและมี WAL เกิดขึ้นได้

```sql
\echo '\n-- Lab 5D.2: INSERT New Live Tuple (PDF p. 114)'
BEGIN;
INSERT INTO claimsure.audit_event (
    tenant_id, actor, action, entity_type, entity_id, details
)
VALUES (1, current_user, 'PAGE_STATE_LAB', 'claim', 'CLM-1001',
        '{"activity":"insert"}'::jsonb)
RETURNING ctid, xmin, xmax, event_id, action;
ROLLBACK;
-- VERIFY: INSERT returns a tuple with xmin. This transaction sees its own insert;
-- other sessions would see it only after commit. Here rollback removes it.
```

## 5D.3 — UPDATE สร้าง Replacement Tuple

จด ctid/xmin ก่อนและหลัง UPDATE โดย claim_no ยังเดิม แล้ว ROLLBACK คืน status การ SELECT ปกติไม่ได้เปิดให้เห็นทุก physical version ใน heap

```sql
\echo '\n-- Lab 5D.3: UPDATE Old Tuple Plus New Tuple (PDF p. 115)'
BEGIN;
SELECT ctid, xmin, xmax, claim_no, status
FROM claimsure.claim
WHERE claim_no = 'CLM-L1-005';

UPDATE claimsure.claim
SET status = 'REVIEW'
WHERE claim_no = 'CLM-L1-005'
RETURNING ctid, xmin, xmax, claim_no, status;
ROLLBACK;
-- VERIFY: compare ctid/xmin before and after. UPDATE creates a replacement
-- tuple; ordinary SELECT does not expose every physical version on the page.
```

## 5D.4 — DELETE และ Undo Delete

สร้าง audit event ของรอบนี้และเก็บ event_id จาก RETURNING ก่อน DELETE แถวนั้น เห็น count 0 แล้ว ROLLBACK TO SAVEPOINT กลับเป็น 1 ก่อน outer ROLLBACK ลบ fixture ทั้งชุด จึงไม่แตะ events ของผู้อื่น

```sql
\echo '\n-- Lab 5D.4: DELETE and SELECT Visibility (PDF p. 116)'
-- D.2 rolled back its insert, so create a dedicated row for this DELETE.
-- Track its identity: never delete other learners' PAGE_STATE_LAB events.
BEGIN;
INSERT INTO claimsure.audit_event (
    tenant_id, actor, action, entity_type, entity_id, details
)
VALUES (1, current_user, 'PAGE_STATE_LAB', 'claim', 'CLM-1001',
        '{"activity":"delete"}'::jsonb)
RETURNING event_id AS delete_event_id \gset

SAVEPOINT before_delete;
DELETE FROM claimsure.audit_event
WHERE event_id = :delete_event_id
RETURNING ctid, xmin, xmax, event_id, action;

SELECT count(*) AS visible_after_delete
FROM claimsure.audit_event WHERE event_id = :delete_event_id;
ROLLBACK TO SAVEPOINT before_delete;
SELECT count(*) AS visible_after_undo_delete
FROM claimsure.audit_event WHERE event_id = :delete_event_id;

ROLLBACK;
-- VERIFY: DELETE returns one row; visibility counts are 0 then 1.
-- The outer rollback removes the fixture. DELETE does not immediately compact
-- the heap; versions become reclaimable when no active snapshot needs them.
```

## 5D.5 — เชื่อม Activity กับ Tuple State

n_live_tup/n_dead_tup เป็นค่าประมาณและอาจยังไม่อัปเดตทันที CHECKPOINT เขียน dirty pages แต่ไม่ได้เปลี่ยน snapshot visibility ส่วน VACUUM คืนพื้นที่เมื่อไม่มี snapshot/retention rule ต้องใช้ versions เก่า หัวข้อนี้สังเกตอย่างเดียว ไม่บังคับ CHECKPOINT/VACUUM

```sql
\echo '\n-- Lab 5D.5: Activity to Tuple-State Map (PDF p. 117)'
SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum,
       vacuum_count, autovacuum_count
FROM pg_stat_user_tables
WHERE schemaname = 'insurance' AND relname IN ('claim', 'audit_event')
ORDER BY relname;
-- These are estimates, not an immediate tuple-by-tuple visibility inventory.
-- SELECT: snapshot visibility; no new version (hint bits may dirty a page).
-- INSERT: new version. UPDATE: old + new versions. DELETE: removed version.
-- VACUUM: reclaims versions no snapshot needs; space can be reused.
-- CHECKPOINT: writes dirty pages; does not change transaction visibility.
-- Discussion only: no forced CHECKPOINT or VACUUM is needed for this lab.
```

## 5E — MVCC ด้วยสอง Connections

ใช้หลังทำ 5D.1–5D.5 แล้ว ตรงสไลด์หน้า 26 และไฟล์ [Session A](module05-architecture/05-mvcc-session-a.sql) / [Session B](module05-architecture/05-mvcc-session-b.sql)

ออกจาก psql ด้วย `\q` แล้วตั้ง environment ของ database เดียวกันไว้ในทั้งสอง Terminal ใช้ **A ก่อน**:

```bash
# Terminal A: จะรอที่ข้อความ Run ... Session B
PGAPPNAME=module5-mvcc-a make lab5 LAB_NO=5E-A
```

เมื่อ A อ่าน snapshot แรกและแสดง prompt รอแล้ว จึงใช้ **B**:

```bash
# Terminal B
PGAPPNAME=module5-mvcc-b make lab5 LAB_NO=5E-B
```

B เปลี่ยน CLM-L1-005 เป็น REVIEW และ created_at ใหม่ แล้ว COMMIT กลับ A และกด Enter:

1. A เปิด `REPEATABLE READ` และ SELECT ครั้งแรก จึงมี snapshot ก่อน B commit
2. หลัง B commit A SELECT ใน transaction เดิมยังเห็น status/created_at/ctid เดิม
3. หลัง A COMMIT แล้ว SELECT ใหม่ จึงเห็น version ใหม่ของ B

`xmax` ของ tuple เก่าอาจเปลี่ยนได้ สิ่งที่พิสูจน์ snapshot คือค่าข้อมูลที่เห็น ไม่ใช่การอ้างว่า physical tuple headers ทุกช่องคงเดิม รันซ้ำแม้ status เป็น REVIEW อยู่แล้ว ยังใช้ created_at/ctid ที่เปลี่ยนดู version ได้

ถ้าต้องการทำเองใน psql ให้เปิดสอง connections แล้วใช้ลำดับนี้แทน Make:

**A:**

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT ctid, xmin, xmax, claim_no, status, created_at
FROM claimsure.claim WHERE claim_no = 'CLM-L1-005';
```

**B หลัง A SELECT แล้ว:**

```sql
BEGIN;
UPDATE claimsure.claim SET status = 'REVIEW', created_at = clock_timestamp()
WHERE claim_no = 'CLM-L1-005'
RETURNING ctid, xmin, xmax, claim_no, status, created_at;
COMMIT;
```

**A หลัง B COMMIT:**

```sql
SELECT ctid, xmin, xmax, claim_no, status, created_at
FROM claimsure.claim WHERE claim_no = 'CLM-L1-005';
COMMIT;
SELECT ctid, xmin, xmax, claim_no, status, created_at
FROM claimsure.claim WHERE claim_no = 'CLM-L1-005';
```

หัวข้อนี้ตั้งใจเก็บ REVIEW และ created_at ใหม่ ไม่ rollback เพื่อให้ A เห็น committed version จริง

## 5F — วัด WAL ของ Batch ที่ COMMIT

ใช้ Source SQL ซึ่งอ่าน before LSN แยก statement, เก็บ IDs ของ 1,000 events, COMMIT แล้วตรวจ rows_inserted=1000, wal_bytes>0 และ batch_wal_flushed=true ก่อนลบเฉพาะ IDs ที่รอบนี้เพิ่ม การ cleanup สร้าง WAL เพิ่มและไม่ย้อน sequence; สไลด์ชี้มาที่คำสั่ง Make นี้เพื่อให้ใช้วิธีวัดเดียวกัน

```sql
\echo '\n-- Lab 5F: WAL Lab Example (PDF pp. 119-120)'
-- Capture LSNs in separate statements so the start is sampled before INSERT.
-- Retain only this batch's IDs for cleanup after the durable commit observation.
CREATE TEMP TABLE lab_m5_wal_event_ids (event_id bigint PRIMARY KEY);
SELECT pg_current_wal_insert_lsn() AS wal_before_lsn \gset
BEGIN;
SET LOCAL synchronous_commit = on;
WITH ins AS (
    INSERT INTO claimsure.audit_event (
        tenant_id, actor, action, entity_type, entity_id, details
    )
    SELECT 1, 'load_lab', 'CLAIM_VIEWED', 'claim', g::text,
           jsonb_build_object('source', 'lab_m5_wal')
    FROM generate_series(1, 1000) AS g
    RETURNING event_id
)
INSERT INTO lab_m5_wal_event_ids SELECT event_id FROM ins;
SELECT pg_current_wal_insert_lsn() AS wal_batch_end_lsn \gset
COMMIT;

SELECT count(*) AS rows_inserted,
       :'wal_before_lsn'::pg_lsn AS start_lsn,
       :'wal_batch_end_lsn'::pg_lsn AS batch_end_lsn,
       pg_wal_lsn_diff(:'wal_batch_end_lsn'::pg_lsn, :'wal_before_lsn'::pg_lsn) AS wal_bytes,
       pg_size_pretty(pg_wal_lsn_diff(
           :'wal_batch_end_lsn'::pg_lsn, :'wal_before_lsn'::pg_lsn)) AS wal_generated,
       pg_current_wal_flush_lsn() >= :'wal_batch_end_lsn'::pg_lsn AS batch_wal_flushed
FROM lab_m5_wal_event_ids;
-- VERIFY: 1,000 rows, positive WAL bytes, batch_wal_flushed = true.
-- LSNs are cluster-wide; concurrent writes can contribute to the measured delta.
-- The batch end is before COMMIT; the commit record adds further WAL.

-- Remove exactly this run's events after measuring; cleanup generates more WAL.
DELETE FROM claimsure.audit_event AS e
USING lab_m5_wal_event_ids AS batch
WHERE e.event_id = batch.event_id;
DROP TABLE lab_m5_wal_event_ids;

SELECT pg_current_wal_insert_lsn() AS insert_lsn,
       pg_current_wal_lsn() AS write_lsn,
       pg_current_wal_flush_lsn() AS flush_lsn,
       pg_walfile_name(pg_current_wal_lsn()) AS current_wal_file;

SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN ('wal_level', 'max_wal_size', 'min_wal_size', 'checkpoint_timeout',
               'archive_mode', 'archive_command', 'fsync', 'full_page_writes',
               'synchronous_commit')
ORDER BY name;
```

## 5G — Storage และ PGDATA

relation path เป็น path ฝั่ง server ที่อ้างอิงจาก PGDATA ไม่ใช่ path บน laptop ดูผ่าน SQL เท่านั้น ไม่แก้ data files หรือ pg_wal ใน workshop

```sql
\echo '\n-- Lab 5G: Storage and PGDATA Lab Example (PDF p. 121)'
SHOW data_directory;
SHOW config_file;
SHOW hba_file;
SHOW block_size;
SHOW data_checksums;

SELECT oid, datname FROM pg_database ORDER BY oid;
SELECT pg_relation_filepath('claimsure.claim') AS claim_file,
       pg_size_pretty(pg_relation_size('claimsure.claim')) AS claim_heap_size,
       pg_size_pretty(pg_total_relation_size('claimsure.claim')) AS claim_total_size;

SELECT c.oid::regclass AS relation, c.relkind,
       pg_relation_filepath(c.oid) AS relation_file,
       pg_size_pretty(pg_relation_size(c.oid)) AS heap_or_index,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_with_aux
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'insurance' AND c.relkind IN ('r', 'i', 'p')
ORDER BY pg_total_relation_size(c.oid) DESC
LIMIT 20;

SELECT spcname, pg_tablespace_location(oid) AS location
FROM pg_tablespace ORDER BY spcname;
SELECT name, pg_size_pretty(size) AS size, modification
FROM pg_ls_waldir()
ORDER BY modification DESC, name
LIMIT 10;
-- VERIFY: the relation path is relative to PGDATA; its database OID matches
-- pg_database for default-tablespace storage. Never edit PGDATA/delete pg_wal.

\echo '\n-- Concept Check and Architecture Recap (PDF pp. 122-123)'
-- Narrate CLM-1001: connection -> backend -> snapshot -> shared buffers/locks
-- -> new tuple version -> WAL flush for durable commit -> later page writeback
-- -> vacuum cleanup when old versions are no longer needed.
-- Point to one observation from 5A-5G for each step.
```

## จบงานและทำซ้ำ

ใช้ `\q` ปิด connections ที่จบแล้ว เก็บฐาน `architecture_m5_xx` ไว้ตรวจผลได้ 5D.1 และ 5E ตั้งใจ commit created_at/status ส่วน 5C/5D.2–5D.4 rollback และ 5F cleanup เฉพาะ events ของรอบตน

หากต้องการเริ่ม 5C ใหม่จาก NEW ในฐาน Lab ของตน ให้ปิด snapshot/transaction ค้างทั้งสองฝั่ง แล้วใช้ Instructor Login คืนเฉพาะ fixture นี้:

```sql
UPDATE claimsure.claim
SET status = 'NEW', created_at = '2026-01-05 09:00:00+07'
WHERE claim_no = 'CLM-L1-005';
```

ไม่ต้อง DROP schema/database หรือแก้ shared configuration เพื่อทดลองซ้ำ บทนี้ไม่มี forced CHECKPOINT หรือ physical file operations

สำหรับเรียนชุดข้อมูลต่อเนื่องไปบท 6 ใช้ [คู่มือ Module 5 เดิม](module-05-architecture-continuous.md) และ `make slides MODULE=5:continuous PORT=3035` ตัว `labs/run-labs.sh` ยังใช้ฉบับ continuous โดยเฉพาะ จึงไม่ได้อ่านชุด Source SQL นี้

อ้างอิง: [MVCC](https://www.postgresql.org/docs/18/mvcc.html), [Statistics](https://www.postgresql.org/docs/18/monitoring-stats.html), [WAL](https://www.postgresql.org/docs/18/wal-configuration.html) และ [หมายเหตุประกอบ Source SQL](module05-architecture/05-architecture-labnotes.md)
