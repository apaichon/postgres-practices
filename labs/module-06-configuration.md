# Module 6: ตั้งค่าให้ workload เคลมชุดเดียวกัน

[กลับสารบัญ](README.md)

รับต่อ claimsure.claim 100,006 แถวจากบท 3 หลังบท 5 คืนข้อมูลแล้ว A/B/C/E ใช้ shared own database ส่วน D/F ใช้ private copy ของ customer/policy/claim ชุดนี้ ไม่ใช้ตาราง report/queue/wal_probe ชุดใหม่

## ภาพรวมก่อนเริ่ม Lab

โมดูลนี้มี **7 ช่วง (6A–6G)**: 6A–6F เป็นการอ่านค่าและทดลอง 6 ช่วง ส่วน 6G เป็นการสรุปผลและตรวจสภาพก่อนส่งต่อบท 7; หัวข้อย่อ 6D.1–6D.4 และ 6F.1–6F.2 เป็นขั้นตอนของ Lab เดียวกัน ไม่ได้นับแยกเป็น Lab ใหม่

| Lab | ค่าที่อ่าน/แก้ไข | เหตุผลที่ทดลอง | วัดผลอย่างไร |
| --- | --- | --- | --- |
| **6A — ขอบเขตการตั้งค่า** | อ่านค่าสำคัญจาก `pg_settings`; ทดลอง `SET LOCAL work_mem='32MB'` และ `ALTER ROLE ... SET work_mem='32MB'` ใน transaction | แยกให้ออกว่า session, transaction, role/database default มีขอบเขตและเวลาที่เกิดผลต่างกัน | `SHOW work_mem` ระหว่าง transaction และตรวจ `restored=true` หลัง `ROLLBACK` |
| **6B — Sort memory** | เปรียบเทียบ `work_mem` เดิม, `64kB`, `4MB`, `32MB` ด้วย `SET LOCAL` | หาค่าที่ลด sort spill โดยไม่ใช้ memory เกินงบเมื่อมีหลาย sort/hash และหลาย connection พร้อมกัน | รันคำสั่งเดิมค่าละ 3 รอบ; เทียบ median Execution Time, Sort Method/Space และ temp blocks |
| **6C — Timeout** | `statement_timeout='200ms'` และ `lock_timeout='200ms'` ด้วย `SET LOCAL` | หยุด statement ที่นานเกินไป และป้องกันการรอ row lock ไม่สิ้นสุด | ตรวจ SQLSTATE `57014` สำหรับ statement timeout และ `55P03` สำหรับ lock timeout; rollback แล้วยืนยันว่ายอดเคลมยังเป็น `15000` |
| **6D — WAL/checkpoint** | ใน private server เปรียบเทียบ `max_wal_size='64MB'` กับ `256MB` | ทดสอบว่า WAL budget ที่ใหญ่ขึ้นลด checkpoint pressure หรือไม่; ค่านี้ไม่ได้ทำให้ WAL ต่อ INSERT ลดลงโดยตรง | โหลด 120,000 แถวเหมือนกันต่อ pass; เทียบ WAL MiB, load time, checkpoint requested/completed และ write time |
| **6E — Autovacuum** | ปิด insert trigger ชั่วคราวด้วย `autovacuum_vacuum_insert_threshold=-1`; ทดลอง `autovacuum_vacuum_threshold=500` และ `autovacuum_vacuum_scale_factor=0.025` | ให้ autovacuum ตอบสนองต่อ dead tuples ของ claim workload ตาม threshold ที่คำนวณได้ | สร้าง dead tuples 5,000 แถว; ติดตาม `n_dead_tup`, `autovacuum_count`, `last_autovacuum` และขนาด relation ก่อน/หลัง |
| **6F — Logging** | ใน private server ทดลอง `log_min_duration_statement='500ms'`, `log_temp_files=0`, `log_lock_waits=on`, `deadlock_timeout='100ms'` | ทำให้ slow statement, temporary file และ lock wait ของ workload เดิมมองเห็นได้ใน log | เทียบ baseline/candidate ด้วย `application_name`; นับ duration, temporary-file และ still-waiting log lines |
| **6G — สรุป/ส่งต่อ** | ไม่แก้ค่าใหม่; รวบรวมผลและหลักฐานการคืนค่า | แปลผลทดลองเป็นข้อเสนอที่มี workload และหลักฐานรองรับ | ตรวจ shared claim ยังมี 100,006 แถว, ยอดเดิมและ table options ถูกคืนค่า; เก็บ private log/archive ไว้ review |

**หลักการวัดผล:** ทุกการเปรียบเทียบต้องใช้ workload และข้อมูลชุดเดิม เปลี่ยนทีละค่า บันทึก before/candidate และคืนค่าหลังวัดเสร็จ A/B/C/E ใช้ shared database จึงต้องระวังการคืนค่าเป็นพิเศษ; D/F ใช้ private server เพื่อไม่ให้การทดลองระดับ server กระทบผู้ใช้อื่น

## 6A — อ่านค่าเดิมและทดลองขอบเขต transaction

**Bash A** ตาม environment ใน README:

```bash
export PGAPPNAME=case-m6-shared
psql -X -v ON_ERROR_STOP=1
```

**psql shared:**

```sql
\pset pager off
\timing on
SELECT count(*) AS expected_100006 FROM claimsure.claim;
SELECT name,current_setting(name) AS effective,setting,unit,boot_val,reset_val,source,context,pending_restart
FROM pg_settings WHERE name IN ('work_mem','shared_buffers','max_connections','max_wal_size',
 'statement_timeout','autovacuum_vacuum_threshold','autovacuum_vacuum_scale_factor') ORDER BY name;
SELECT current_setting('work_mem') AS original_work_mem \gset

BEGIN;
SET LOCAL work_mem='32MB';
SHOW work_mem;
ROLLBACK;
SELECT current_setting('work_mem')=:'original_work_mem' AS restored;
SELECT current_user AS my_role,current_database() AS my_db \gset

BEGIN;
ALTER ROLE :"my_role" IN DATABASE :"my_db" SET work_mem='32MB';
SHOW work_mem;
ROLLBACK;
```

restored ต้อง true ส่วน ALTER ROLE จะมีผลกับการ login ใหม่ จึงยังไม่เปลี่ยน connection นี้ และ ROLLBACK คืน role default เดิม

## 6B — ปรับ work_mem ให้รายงานเคลมเดิม

รัน original สามครั้ง จด Execution Time, Sort Method, Sort Space และ temp written blocks:

```sql
BEGIN;
SET LOCAL max_parallel_workers_per_gather=0;
EXPLAIN (ANALYZE,BUFFERS,SETTINGS)
SELECT claim_no,description FROM claimsure.claim ORDER BY description,claim_no;
ROLLBACK;
```

รัน candidate สามครั้งต่อค่า เริ่ม 64kB แล้วเปลี่ยนเฉพาะค่าเป็น 4MB และ 32MB:

```sql
BEGIN;
SET LOCAL work_mem='64kB';
SET LOCAL max_parallel_workers_per_gather=0;
EXPLAIN (ANALYZE,BUFFERS,SETTINGS)
SELECT claim_no,description FROM claimsure.claim ORDER BY description,claim_no;
ROLLBACK;
SHOW work_mem;
```

| work_mem | เวลา 1/2/3 | Median | Sort method/space | Temp blocks |
| --- | --- | --- | --- | --- |
| original | วัดจริง | | | |
| 64kB | | | | |
| 4MB | | | | |
| 32MB | | | | |

ใช้คำสั่งและข้อมูลเดิมทุกครั้ง 32MB อาจยัง spill ได้ ขึ้นกับขนาดจริง งบ memory ต้องคิดจำนวน sort/hash และ concurrency พร้อมกัน

## 6C — Timeout ป้องกันการรอเคลมไม่สิ้นสุด

**A:**

```sql
BEGIN;
SET LOCAL statement_timeout='200ms';
SAVEPOINT slow_call;

\set ON_ERROR_STOP off

SELECT pg_sleep(0.4),claim_no FROM claimsure.claim WHERE claim_no='CLM-L1-001';

\echo Expected statement 57014; actual :SQLSTATE

ROLLBACK TO SAVEPOINT slow_call;

\set ON_ERROR_STOP on

ROLLBACK;
BEGIN;
UPDATE claimsure.claim SET estimated_amount=estimated_amount WHERE claim_no='CLM-L1-001';
```

ค้าง transaction A จากนั้น **Bash B** เปิด shared psql ตาม environment README:

```bash
export PGAPPNAME=case-m6-waiter
psql -X -v ON_ERROR_STOP=1
```

**B:**

```sql
BEGIN;
SET LOCAL lock_timeout='200ms';
SAVEPOINT waiting_claim;
\set ON_ERROR_STOP off
UPDATE claimsure.claim SET estimated_amount=estimated_amount+1 WHERE claim_no='CLM-L1-001';
\echo Expected lock 55P03; actual :SQLSTATE
ROLLBACK TO SAVEPOINT waiting_claim;
\set ON_ERROR_STOP on
ROLLBACK;
```

กลับ **A**:

```sql
ROLLBACK;
SELECT claim_no,estimated_amount FROM claimsure.claim WHERE claim_no='CLM-L1-001';
```

ต้องยังเป็น 15000 ทั้งสอง connection ปิด transaction แล้ว \q ก่อนทำ D

## 6D.1 — Bash A: สำเนาตารางหลักเข้า private server

ใช้ PostgreSQL 18 server binaries ไม่ใช้ sudo เก็บ Bash นี้ไว้ตลอด D/F; environment ของ shared ไม่ถูกแก้:

```bash
export PATH="/usr/lib/postgresql/18/bin:$PATH"
postgres --version
M6_LAB=$(mktemp -d "$HOME/case-m6.XXXXXXXX")
M6_PORT=$((5700 + 10#$STUDENT_NO))
mkdir "$M6_LAB/socket"
printf '%s\n' "$M6_LAB" > "$HOME/case-labs/m6-path"
printf '%s\n' "$M6_PORT" > "$M6_LAB/port"
CORE_TABLES=(--table=claimsure.customer --table=claimsure.policy --table=claimsure.claim
 --table=claimsure.customer_customer_id_seq --table=claimsure.policy_policy_id_seq
 --table=claimsure.claim_claim_id_seq)
pg_dump -Fc --no-owner --no-acl "${CORE_TABLES[@]}" -f "$M6_LAB/core.dump"
pg_restore --list "$M6_LAB/core.dump"
initdb -D "$M6_LAB/data" -U labadmin --auth-local=trust --auth-host=reject --encoding=UTF8 --locale=C
cat >> "$M6_LAB/data/postgresql.conf" <<CONF
listen_addresses = ''
unix_socket_directories = '$M6_LAB/socket'
unix_socket_permissions = 0700
port = $M6_PORT
shared_buffers = '32MB'
max_connections = 10
max_wal_size = '64MB'
min_wal_size = '32MB'
checkpoint_timeout = '30min'
logging_collector = off
log_line_prefix = '%m [%p] %a '
log_min_duration_statement = -1
log_temp_files = -1
log_lock_waits = off
deadlock_timeout = '1s'
CONF
cp "$M6_LAB/data/postgresql.auto.conf" "$M6_LAB/auto.before"
pg_ctl -D "$M6_LAB/data" -l "$M6_LAB/server.log" -w start
createdb -h "$M6_LAB/socket" -p "$M6_PORT" -U labadmin claimsure
PRIVATE=(-h "$M6_LAB/socket" -p "$M6_PORT" -U labadmin -d claimsure)
psql -X -v ON_ERROR_STOP=1 "${PRIVATE[@]}" -c 'CREATE SCHEMA claimsure;'
pg_restore "${PRIVATE[@]}" --exit-on-error --no-owner --no-acl "$M6_LAB/core.dump"
psql -X -v ON_ERROR_STOP=1 "${PRIVATE[@]}"
```

private ได้ core tables/indexes/sequence ของเดิม ไม่รวม view/routines/report ซึ่งไม่ได้ใช้ใน D/F labadmin เป็น superuser เฉพาะ private cluster นี้

## 6D.2 — psql private: INSERT เคลมอ้างกรมธรรม์เดิม

```sql
SELECT count(*) AS copied_claims FROM claimsure.claim;
ALTER TABLE claimsure.claim ALTER COLUMN description SET STORAGE PLAIN;
CREATE PROCEDURE claimsure.cs_load_claims(n integer) LANGUAGE plpgsql AS $$
DECLARE template claimsure.claim%ROWTYPE; batch integer;
BEGIN
 SELECT * INTO STRICT template FROM claimsure.claim WHERE claim_no='CLM-L1-001';
 FOR batch IN 0..((n-1)/5000) LOOP
  INSERT INTO claimsure.claim
   (claim_no,policy_id,status,incident_at,estimated_amount,description,metadata)
  SELECT 'CLM-WAL-'||lpad(g::text,6,'0'),template.policy_id,'NEW',template.incident_at,
         template.estimated_amount,repeat(md5(g::text),48),'{}'::jsonb
  FROM generate_series(batch*5000+1,least(n,(batch+1)*5000)) g;
  COMMIT;
 END LOOP;
END $$;
CREATE TABLE claimsure.cs_wal_results(
 phase text,wal_bytes numeric,load_ms numeric,requested bigint,completed bigint,write_ms double precision
);
```

CALL ต้องอยู่นอก BEGIN ของผู้เรียก ทุก pass โหลด 120,000 เคลมใหม่บน private claim เดิม Indexes/constraints ของบท 1/3 ยังอยู่ จึงไม่คัดตัวเลข WAL 192MiB ของ workload คนละแบบมาใช้

## 6D.3 — วัด 64MB

```sql
\set phase 64MB

SHOW max_wal_size;
DELETE FROM claimsure.claim WHERE claim_no LIKE 'CLM-WAL-%';
VACUUM (ANALYZE) claimsure.claim;
CHECKPOINT;
SELECT pg_stat_clear_snapshot();
CREATE TEMP TABLE checkpoint_before AS SELECT * FROM pg_stat_checkpointer;
SELECT clock_timestamp() AS started,pg_current_wal_insert_lsn() AS start_lsn \gset

CALL claimsure.cs_load_claims(120000);
SELECT clock_timestamp() AS finished,pg_current_wal_insert_lsn() AS end_lsn \gset

SELECT pg_sleep(1);
SELECT pg_stat_clear_snapshot();
INSERT INTO claimsure.cs_wal_results
SELECT :'phase',pg_wal_lsn_diff(:'end_lsn'::pg_lsn,:'start_lsn'::pg_lsn),
 extract(epoch FROM :'finished'::timestamptz-:'started'::timestamptz)*1000,
 c.num_requested-b.num_requested,c.num_done-b.num_done,c.write_time-b.write_time
FROM pg_stat_checkpointer c CROSS JOIN checkpoint_before b
WHERE c.stats_reset IS NOT DISTINCT FROM b.stats_reset;
SELECT count(*) AS expected_120000 FROM claimsure.claim WHERE claim_no LIKE 'CLM-WAL-%';
TABLE claimsure.cs_wal_results;
```

DELETE/VACUUM/CHECKPOINT เป็น preparation นอกช่วงวัด ถ้า stats_reset ต่างกัน ผลไม่ถูก INSERT ให้เริ่ม sample ใหม่ ตัวเลข INSERT ของ cs_wal_results คือ metric rows ไม่ใช่ data load

## 6D.4 — วัด 256MB ด้วย workload เดิม แล้วคืน private config

```sql
ALTER SYSTEM SET max_wal_size='256MB';
SELECT pg_reload_conf();
```

รัน SHOW max_wal_size เป็น statement ถัดไปจนได้ 256MB แล้ว:

```sql
DROP TABLE checkpoint_before;
\set phase 256MB
```

รัน **6D.3 ตั้งแต่ SHOW ถึง TABLE** ซ้ำ โดยไม่ใช้บรรทัดตั้ง phase 64MB ต้องเห็น CLM-WAL-* 120000 เท่ากันทั้งสอง pass:

```sql
SELECT phase,round(wal_bytes/1024/1024,1) AS wal_mib,round(load_ms,1) AS load_ms,
 requested,completed,write_ms FROM claimsure.cs_wal_results;
```

max_wal_size เปลี่ยนแรงกด checkpoint ไม่ได้ลด WAL ที่ INSERT ต้องสร้าง Index/page/FPI และการใช้พื้นที่รอบสองทำให้ bytes ไม่เท่ากันเป๊ะได้ รายงานตามจริง completed=0 อาจเพราะ sample จบก่อน checkpoint เสร็จ ไม่รับประกันเร็วขึ้น และไม่ได้วัด crash recovery

ออก \q แล้ว **Bash A**:

```bash
cp "$M6_LAB/auto.before" "$M6_LAB/data/postgresql.auto.conf"
pg_ctl -D "$M6_LAB/data" reload
cmp "$M6_LAB/auto.before" "$M6_LAB/data/postgresql.auto.conf"
psql -X "${PRIVATE[@]}" -c 'SHOW max_wal_size;'
```

## 6E — กลับ shared: autovacuum บน claim จริง

**Bash A:** เปิด psql โดยไม่ใส่ PRIVATE เพื่อใช้ environment shared:

```bash
psql -X -v ON_ERROR_STOP=1
```

**psql shared** ใช้ session นี้จนจบ E เพราะมี temporary tables:

```sql
CREATE TEMP TABLE cs_m6_options AS SELECT reloptions FROM pg_class WHERE oid='claimsure.claim'::regclass;
CREATE TEMP TABLE cs_m6_rows AS
SELECT claim_id,status FROM claimsure.claim WHERE claim_no LIKE 'CLM-L3-%' ORDER BY claim_no LIMIT 5000;
SELECT count(*) AS expected_5000 FROM cs_m6_rows;
ALTER TABLE claimsure.claim SET(autovacuum_vacuum_insert_threshold=-1);
VACUUM (ANALYZE) claimsure.claim;
SELECT current_setting('autovacuum_vacuum_threshold') AS base,
 current_setting('autovacuum_vacuum_scale_factor') AS scale,reltuples
FROM pg_class WHERE oid='claimsure.claim'::regclass;
UPDATE claimsure.claim c SET status=CASE WHEN b.status='NEW' THEN 'REVIEW' ELSE 'NEW' END
FROM cs_m6_rows b WHERE c.claim_id=b.claim_id;
SELECT pg_stat_force_next_flush();
SELECT pg_sleep(1);
SELECT pg_stat_clear_snapshot();
CREATE TEMP TABLE cs_m6_before AS
SELECT n_dead_tup,autovacuum_count,pg_total_relation_size(relid) AS bytes
FROM pg_stat_user_tables WHERE relid='claimsure.claim'::regclass;
TABLE cs_m6_before;
ALTER TABLE claimsure.claim SET(autovacuum_vacuum_threshold=500,autovacuum_vacuum_scale_factor=0.025);
SELECT clock_timestamp(),n_dead_tup,autovacuum_count,last_autovacuum,
 pg_total_relation_size(relid) AS bytes
FROM pg_stat_user_tables WHERE relid='claimsure.claim'::regclass;
\watch 5
```

Ctrl+C หลังเห็น dead tuples ลดและ count เพิ่ม หรือสังเกตครบอย่างน้อย 75 วินาที Candidate threshold คือ **500 + 0.025 × 100006 = 3000.15**; จำนวน rows/reltuples จริงอาจต่าง ค่า baseline ต้องใช้ค่าที่อ่าน ไม่เดาว่าเป็น 5050 หาก baseline vacuum ไปแล้วให้รายงานว่าเปรียบเทียบแบบเดิมไม่ได้

```sql
SELECT b.n_dead_tup AS dead_before,s.n_dead_tup AS dead_after,
 s.autovacuum_count-b.autovacuum_count AS completed_passes,
 b.bytes AS bytes_before,pg_total_relation_size(s.relid) AS bytes_after
FROM pg_stat_user_tables s CROSS JOIN cs_m6_before b WHERE s.relid='claimsure.claim'::regclass;
ALTER TABLE claimsure.claim RESET(autovacuum_vacuum_threshold,autovacuum_vacuum_scale_factor,autovacuum_vacuum_insert_threshold);
SELECT format('ALTER TABLE claimsure.claim SET (%I=%L)',option_name,option_value)
FROM cs_m6_options s CROSS JOIN LATERAL pg_options_to_table(s.reloptions)
WHERE option_name IN ('autovacuum_vacuum_threshold','autovacuum_vacuum_scale_factor','autovacuum_vacuum_insert_threshold')

\gexec

SELECT c.reloptions IS NOT DISTINCT FROM s.reloptions AS options_restored
FROM pg_class c CROSS JOIN cs_m6_options s WHERE c.oid='claimsure.claim'::regclass;
UPDATE claimsure.claim c SET status=b.status FROM cs_m6_rows b WHERE c.claim_id=b.claim_id;
VACUUM (ANALYZE) claimsure.claim;
SELECT count(*) AS expected_100006 FROM claimsure.claim;
```

options_restored ต้อง true UPDATE/VACUUM ท้ายบล็อกเป็น **การคืนค่า** หลังบันทึกผล autovacuum แล้ว ไม่ใช้ manual VACUUM นี้เป็นหลักฐานว่าตัว candidate ทำงาน

## 6F.1 — private: ทดสอบ logging กับเคลมเดียวกันสองรอบ

ออก shared psql แล้ว **Bash A**:

```bash
psql -X -v ON_ERROR_STOP=1 "${PRIVATE[@]}"
```

**Bash B** หา workspace เดิมและเปิด private psql:

```bash
M6_LAB=$(cat "$HOME/case-labs/m6-path")
M6_PORT=$(cat "$M6_LAB/port")
psql -X -h "$M6_LAB/socket" -p "$M6_PORT" -U labadmin -d claimsure -v ON_ERROR_STOP=1
```

**A baseline** เริ่ม transaction และรัน sleep/sort ก่อน:

```sql
SET application_name='case-m6-f-before';
BEGIN;
SET LOCAL work_mem='64kB';
SET LOCAL max_parallel_workers_per_gather=0;
SET LOCAL lock_timeout='30s';
SELECT pg_sleep(0.6);
EXPLAIN (ANALYZE,BUFFERS)
SELECT claim_no,description FROM claimsure.claim ORDER BY description,claim_no;
```

**B** ถือ lock แล้วค้างไว้:

```sql
BEGIN;
UPDATE claimsure.claim SET estimated_amount=estimated_amount WHERE claim_no='CLM-L1-001';
```

**A** ขอแถวเดียวกัน จะรอ:

```sql
UPDATE claimsure.claim SET estimated_amount=estimated_amount+1 WHERE claim_no='CLM-L1-001';
```

เมื่อ A รอแล้ว **B**:

```sql
SELECT pg_sleep(3);
ROLLBACK;
```

A UPDATE จบแล้ว **A**:

```sql
ROLLBACK;
```

## 6F.2 — Candidate logging แล้วทำ lock เดิมซ้ำ

**A:**

```sql
SET application_name='case-m6-f-after';
BEGIN;
SET LOCAL work_mem='64kB';
SET LOCAL max_parallel_workers_per_gather=0;
SET LOCAL lock_timeout='30s';
SET LOCAL log_min_duration_statement='500ms';
SET LOCAL log_temp_files=0;
SET LOCAL log_lock_waits=on;
SET LOCAL deadlock_timeout='100ms';
SELECT pg_sleep(0.6);
EXPLAIN (ANALYZE,BUFFERS)
SELECT claim_no,description FROM claimsure.claim ORDER BY description,claim_no;
```

ทำ **B BEGIN/UPDATE → A UPDATE รอ → B sleep(3)/ROLLBACK** ตาม 6F.1 อีกครั้ง แล้ว **A**:

```sql
ROLLBACK;
SHOW log_min_duration_statement;
SHOW log_temp_files;
SHOW log_lock_waits;
SHOW deadlock_timeout;
```

ออก A/B ด้วย \q แล้ว **Bash A**:

```bash
grep 'case-m6-f-before' "$M6_LAB/server.log"
grep 'case-m6-f-after' "$M6_LAB/server.log"
grep -c 'case-m6-f-after.*duration:' "$M6_LAB/server.log"
grep -c 'case-m6-f-after.*temporary file:' "$M6_LAB/server.log"
grep -c 'case-m6-f-after.*still waiting for' "$M6_LAB/server.log"
pg_ctl -D "$M6_LAB/data" -m fast -w stop
psql -X -c 'SHOW work_mem;' -c 'SHOW max_wal_size;'
```

grep ไม่พบคืน exit 1 ได้ตามปกติ Baseline ไม่มี event lines ถ้าค่า private เดิมปิดไว้ Candidate ทำเหตุการณ์เดิมให้มองเห็น Sort อาจเกิน 500ms จึงอาจมี slow line เพิ่ม ไม่บังคับตัวเลข 2/2/1 และ lock wait ไม่ใช่ deadlock

## 6G — สรุปและส่งต่อบท 7

บันทึก workload, before/candidate, median/counter delta, หลักฐาน reset และสิ่งที่ยังไม่วัด เลือก work_mem ตาม spill และ memory budget; เลือก max_wal_size ตาม checkpoint pressure; ระวัง log_temp_files=0 บนงานจริง ต้องประเมินปริมาณ log ก่อน

Shared ต้องยังมีเคลม 100006 แถว CLM-L1-* หกแถว ยอดเดิม และ options คืนค่าแล้ว ไม่ลบ claim หรือ objects ของบท 2–3 เก็บ private log/archive ไว้ review

อ้างอิง: [Configuration](https://www.postgresql.org/docs/18/config-setting.html), [Autovacuum](https://www.postgresql.org/docs/18/runtime-config-vacuum.html)
