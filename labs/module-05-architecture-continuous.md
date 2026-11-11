# Module 5: ดู MVCC และ WAL ของเคลมที่เคยเขียนในบท 1

[กลับสารบัญ](README.md)

ทำบท 4 จนคืน RLS/ACL แล้ว เปิด Terminal A/B ด้วย environment ใน README ใช้ claim จริง ไม่สร้างตาราง MVCC ใหม่ อย่าวางทั้งบทพร้อมกัน

## 5A — A ดู backend และเก็บค่าเดิม

```bash
export PGAPPNAME=case-m5-a
psql -X -v ON_ERROR_STOP=1
```

```sql
\pset pager off
SELECT pg_backend_pid(),current_database(),current_user;
SELECT pid,backend_type,state,wait_event_type,wait_event
FROM pg_stat_activity WHERE usename=current_user OR backend_type<>'client backend';
SELECT * FROM pg_stat_bgwriter;
SELECT * FROM pg_stat_checkpointer;
SELECT wal_records,wal_fpi,wal_bytes FROM pg_stat_wal;
CREATE TABLE cs_m5_original AS
SELECT * FROM claimsure.claim WHERE claim_no IN ('CLM-L1-001','CLM-L1-006');
SELECT ctid,xmin,xmax,claim_no,estimated_amount FROM claimsure.claim WHERE claim_no='CLM-L1-001';
```

ปกติ estimated_amount เดิมเป็น 15000 จดค่าจริงไว้ สถิติ background/WAL เป็นระดับ cluster อาจรวมงานของคนอื่น ctid เป็นที่อยู่ tuple ไม่ใช่ business key

## 5B — A แก้ยอด แต่ยังไม่ commit

```sql
BEGIN;
UPDATE claimsure.claim SET estimated_amount=estimated_amount+100
WHERE claim_no='CLM-L1-001' RETURNING ctid,xmin,xmax,claim_no,estimated_amount;
```

A เห็น 15100 เมื่อค่าเดิม 15000 จากนั้นเปิด B และค้าง transaction A ไว้

## 5C — B ตรึง snapshot

```bash
export PGAPPNAME=case-m5-b
psql -X -v ON_ERROR_STOP=1
```

```sql
SELECT claim_no,estimated_amount FROM claimsure.claim WHERE claim_no='CLM-L1-001';
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT claim_no,estimated_amount FROM claimsure.claim WHERE claim_no='CLM-L1-001';
```

B ต้องยังเห็น 15000 ทั้งสองครั้ง ให้ค้าง B ไว้ แล้ว **A**:

```sql
COMMIT;
```

**B** อ่านจาก snapshot เดิมแล้วเริ่ม statement หลังจบ transaction:

```sql
SELECT claim_no,estimated_amount FROM claimsure.claim WHERE claim_no='CLM-L1-001';
COMMIT;
SELECT claim_no,estimated_amount FROM claimsure.claim WHERE claim_no='CLM-L1-001';
```

ได้ 15000 แล้ว 15100 บท 2 claim_detail_v อ่านยอดใหม่ด้วย แต่ materialized summary ของบท 3 ไม่ refresh เอง

## 5D — ลบ CLM-L1-006 แล้วดู visibility

**A:**

```sql
BEGIN;
DELETE FROM claimsure.claim WHERE claim_no='CLM-L1-006';
SELECT count(*) FROM claimsure.claim WHERE claim_no='CLM-L1-006';
```

A เห็น 0 ส่วน **B**:

```sql
SELECT count(*) FROM claimsure.claim WHERE claim_no='CLM-L1-006';
```

B ยังเห็น 1 จากนั้น **A**:

```sql
COMMIT;
```

แล้ว **B**:

```sql
SELECT count(*) FROM claimsure.claim WHERE claim_no='CLM-L1-006';
VACUUM (ANALYZE) claimsure.claim;
SELECT n_live_tup,n_dead_tup,last_vacuum,last_autovacuum
FROM pg_stat_user_tables WHERE relid='claimsure.claim'::regclass;
```

B เห็น 0; VACUUM นี้เป็น manual และไม่จำเป็นต้องทำให้ไฟล์เล็กลง

## 5E — A คืนสองเคลมก่อนทดลอง WAL

ใช้ temporary table ใน A เดิม หาก A หลุด อย่าเดาข้อมูล; กลับไป seed 1B และทำ 1D ใหม่ก่อนเรียนต่อ:

```sql
INSERT INTO claimsure.claim OVERRIDING SYSTEM VALUE
SELECT * FROM cs_m5_original WHERE true
ON CONFLICT(claim_no) DO UPDATE
SET estimated_amount=EXCLUDED.estimated_amount,status=EXCLUDED.status,
    approved_amount=EXCLUDED.approved_amount;
SELECT claim_no,status,estimated_amount FROM claimsure.claim WHERE claim_no IN ('CLM-L1-001','CLM-L1-006');
```

CLM-L1-001 กลับ REVIEW/15000 และ CLM-L1-006 กลับ REJECTED/18000 claim_id ของแถวที่ลบต้องกลับค่าเดิมด้วย

## 5F — A วัด WAL จากเคลมใหม่ 1,000 แถวที่อ้างกรมธรรม์เดิม

```sql
DELETE FROM claimsure.claim WHERE claim_no LIKE 'CLM-L5-%';

DROP TABLE IF EXISTS cs_m5_lsn;
CREATE TEMP TABLE cs_m5_lsn AS
SELECT pg_current_wal_insert_lsn() AS before_lsn;

INSERT INTO claimsure.claim
 (claim_no,policy_id,status,incident_at,estimated_amount,description,metadata)
SELECT 'CLM-L5-'||lpad(g::text,6,'0'),c.policy_id,'NEW',c.incident_at,c.estimated_amount,
       c.description,jsonb_build_object('source','module5')
FROM generate_series(1,1000) g CROSS JOIN claimsure.claim c
WHERE c.claim_no='CLM-L1-001';

SELECT pg_wal_lsn_diff(pg_current_wal_insert_lsn(), before_lsn) AS interval_wal_bytes,
       (SELECT count(*) FROM claimsure.claim WHERE claim_no LIKE 'CLM-L5-%') AS expected_1000
FROM cs_m5_lsn;

SELECT pg_relation_filenode('claimsure.claim'),
       pg_relation_filepath('claimsure.claim'),
       pg_size_pretty(pg_relation_size('claimsure.claim'));
```

ค่า WAL diff รวมงานในช่วงเวลานี้บน shared cluster จึงไม่ใช่ WAL ของ INSERT อย่างเดียว path เป็นของ server ไม่ใช่ไฟล์ใน SSH home และไม่สั่ง CHECKPOINT บน shared

## 5G — ส่งต่อข้อมูลเดิมให้บท 6

ให้ B COMMIT/ROLLBACK ก่อน แล้ว **A**:

```sql
DELETE FROM claimsure.claim WHERE claim_no LIKE 'CLM-L5-%';
VACUUM (ANALYZE) claimsure.claim;
REFRESH MATERIALIZED VIEW claimsure.cs_monthly_claim_summary;
SELECT count(*) AS expected_100006 FROM claimsure.claim;
SELECT count(*) AS expected_6 FROM claimsure.claim_detail_v WHERE claim_no LIKE 'CLM-L1-%';
```

ลบเฉพาะแถวที่เพิ่มใน 5F เก็บตารางและข้อมูล CLM-L1-/CLM-L3- ไว้ B และ A ออกด้วย \q เมื่อจบ

อ้างอิง: [MVCC](https://www.postgresql.org/docs/18/mvcc.html), [Statistics](https://www.postgresql.org/docs/18/monitoring-stats.html)
