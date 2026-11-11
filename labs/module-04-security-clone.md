# Module 4 — Clone schema เพื่อทดลองสิทธิ์แบบเก็บผลจริง

[กลับสารบัญ](README.md) · [เวอร์ชันเดิมบน schema ต่อเนื่อง](module-04-security.md)

[สไลด์ประกอบเวอร์ชัน Clone](../slides/module-04-security-clone.md) เปิดจาก project root ด้วย `make slides MODULE=4:clone PORT=3044` ส่วน `MODULE=4` ยังคงเปิดสไลด์เวอร์ชันเดิม

เวอร์ชันนี้เริ่มจากสำเนา `claimsure` ไปยัง **`lab_m4_clone_xx`** แล้วทดลอง GRANT, role inheritance, sequence, RLS, column privileges, audit และ default privileges ในสำเนา การเพิ่มเคลม การอนุมัติ และ audit เก็บอยู่จริงหลังปิด connection ไม่ต้องใช้ `ROLLBACK` เพื่อคืนการทดลองแต่ละขั้น

ใช้ PostgreSQL 18, ข้อมูลบท 1–2 และทำบท 3 ก่อนหากต้องการ clone เคลมทั้ง 100,006 แถว แทน `xx` ด้วยหมายเลขที่ได้รับ (`01`–`20`) เช่นเดียวกับ [คู่มือการเชื่อมต่อ](README.md#เตรียมการเชื่อมต่อ)

## ขอบเขตของการ Clone

นี่คือการ clone **ชุดข้อมูลธุรกิจที่ใช้ใน Lab Security** ไม่ใช่เครื่องมือ copy ทุก object ใน schema โดยอัตโนมัติ:

| Object ต้นทาง | Object ใน `lab_m4_clone_xx` |
| --- | --- |
| `claimsure.customer`, `policy`, `claim` | คัดลอกโครงสร้างและข้อมูลทุกแถวจาก snapshot เดียวกัน |
| PK, UNIQUE, CHECK, indexes, defaults, generated columns | ใช้ `LIKE ... INCLUDING ALL`; generated columns คำนวณใหม่ตอน copy |
| Identity ของสามตาราง | เป็น sequences ใหม่ใน schema Lab แล้วตั้งเลขต่อจาก `max(id)` |
| FK: policy → customer, claim → policy | สร้างใหม่โดยอ้างถึงตารางใน schema Lab เท่านั้น |
| `claim_detail_v` | สร้าง view รูปแบบเดียวกับบท 2 โดย JOIN ตารางใน Lab และใช้ `security_invoker=true` |
| ACL, RLS, triggers และ functions ของต้นทาง | เริ่มสิทธิ์และ policy ของ Lab ใหม่ ไม่คัดลอกจากต้นทาง |
| Reports, partitions, materialized views และ routines บทอื่น | ไม่อยู่ใน clone นี้ |

ก่อนเริ่มให้พักงานที่เขียน `claimsure` เพื่อให้เทียบ checksum ตอนจบได้ ต้นทางต้องเป็น course schema ที่ใช้ identity ตามบท 1; script ปฏิเสธ serial-style defaults เพื่อไม่ให้เผลอใช้ sequence ต้นทางร่วมกัน

## 4C.0 — เตรียมบทบาทและ Login จริง

**Instructor Terminal:** จาก root ของ repository เชื่อมด้วยบัญชี `postgres` หรือ superuser ของห้องเรียน ไม่มอบ SUPERUSER/CREATEROLE ให้นักเรียน:

```bash
psql -X -W -h 127.0.0.1 -p 5432 -U postgres -d claimsure_xx \
  -v student_no=xx -v ON_ERROR_STOP=1
```

ใน psql:

```sql
\i labs/module04-security-clone/01-roles.sql
```

script ตรวจ Database/หมายเลข, PostgreSQL version และชื่อ roles ก่อนสร้าง หากมีชื่อเหล่านี้อยู่แล้วจะหยุด ให้ตรวจงานเดิมหรือใช้ cleanup แบบเจาะจงท้ายบท ไม่ใช้ script นี้เพื่อเขียนทับงานที่กำลังทำ

| Group role (NOLOGIN) | Login ที่ใช้ทดสอบ | สิทธิ์สุดท้าย |
| --- | --- | --- |
| `m4c_owner_xx` | Instructor ใช้ `SET ROLE` เฉพาะเตรียม objects | เจ้าของ schema/objects ไม่ให้ app เป็นสมาชิก |
| `m4c_reader_xx` | `m4c_read_a_xx`, `m4c_read_b_xx` | อ่านเคลม CUS-001 / CUS-002 ตามบัญชี |
| `m4c_writer_xx` สืบทอด reader | `m4c_create_a_xx` | อ่านและเพิ่มเคลม NEW ของ CUS-001 |
| `m4c_approver_xx` สืบทอด reader | `m4c_approve_a_xx` | อ่านและแก้เฉพาะ status ของเคลม CUS-001 |
| `m4c_auditor_xx` | `m4c_audit_xx` | อ่าน audit; ไม่มีสิทธิ์อ่าน/แก้ตาราง claim |

Role membership ใช้ `INHERIT TRUE, SET FALSE` ให้รับสิทธิ์ผ่าน group โดยไม่สลับเป็น owner บัญชี Login ยังไม่มี Password จึงต้องตั้งด้วย prompt ของ psql ทีละบัญชี ไม่มี Password จริงในไฟล์ SQL หรือประวัติคำสั่ง:

```sql
\password :read_a
\password :read_b
\password :create_a
\password :approve_a
\password :audit_login
```

ใช้รหัสต่างกันตามที่ Instructor จัดให้ HBA ของห้องเรียนต้องอนุญาต TCP/SCRAM ให้บัญชีเหล่านี้ด้วย ไม่เปลี่ยนเป็น `trust` เพื่อให้ผ่านการ Login

## 4C.A — Clone ก่อนเปลี่ยนสิทธิ์

**Instructor psql เดิม:**

```sql
\i labs/module04-security-clone/02-clone.sql

SELECT table_name, source_rows, source_sequence, source_last_value
FROM :"lab_schema".source_manifest ORDER BY table_name;
SELECT count(*) AS copied_claims FROM :"lab_schema".claim;
SELECT count(*) AS starter_claims FROM :"lab_schema".claim WHERE claim_no LIKE 'CLM-L1-%';

SELECT pg_get_serial_sequence('claimsure.claim', 'claim_id') AS source_sequence,
       pg_get_serial_sequence(format('%I.claim', :'lab_schema'), 'claim_id') AS lab_sequence;
SELECT conname, confrelid::regclass AS referenced_table
FROM pg_constraint
WHERE conrelid IN (format('%I.policy', :'lab_schema')::regclass,
                   format('%I.claim', :'lab_schema')::regclass) AND contype = 'f';
```

`starter_claims` ต้องเป็น 6 ส่วน `copied_claims` เท่าจำนวนจริงต้นทาง (หลังบท 3 คือ 100,006) ชื่อ sequence ต้องต่างกัน และ FK ทั้งสองต้องชี้ `lab_m4_clone_xx` ไม่มี FK กลับไป `claimsure`

การ clone ใช้ `REPEATABLE READ` และ `COMMIT` เพื่อเก็บสำเนาที่สอดคล้องกัน หลังจากนี้ขั้นทดสอบใช้ **autocommit** คำสั่งที่ตั้งใจให้ error จึงไม่ทำให้ transaction ยาวค้างอยู่ในสถานะ failed

## 4C.B — ทดสอบ schema gate และ table gate แยกกัน

**Terminal สำหรับผู้เรียน:** ตั้งค่าตามเครื่องห้องเรียนและเปิด connection ด้วย Login ของ Lab จริง ทุกครั้งที่สลับ Login ให้ใช้ `\q` ออกจาก psql แล้วเชื่อมใหม่:

```bash
STUDENT_NO=xx
export PGHOST=127.0.0.1 PGPORT=5432
psql -X -W -h "$PGHOST" -p "$PGPORT" -U "m4c_read_a_$STUDENT_NO" \
  -d "claimsure_$STUDENT_NO" -v student_no="$STUDENT_NO" -v ON_ERROR_STOP=1
```

**เริ่มทุก app connection ด้วยบล็อกนี้** ไม่เรียก `context.sql` ของ Instructor เพราะไฟล์นั้นตรวจ superuser:

```sql
\set AUTOCOMMIT on
\pset pager off
\set VERBOSITY verbose
SELECT 'lab_m4_clone_' || :'student_no' AS lab_schema \gset
SELECT current_database(), session_user, current_user;
```

ตรวจว่า Database/หมายเลข/Login ตรงหน้าที่ก่อนรัน ห้ามใช้ `postgres` หรือ `student_xx` เป็นหลักฐานสิทธิ์ของ app

**Reader A:**

```sql
\set ON_ERROR_STOP off
SELECT claim_no FROM :"lab_schema".claim LIMIT 1;
\echo Expected schema gate 42501; actual :SQLSTATE
\set ON_ERROR_STOP on
```

ต้องเป็น `permission denied for schema lab_m4_clone_xx` เพราะยังไม่มี schema USAGE

**Instructor:** เปิดเฉพาะ schema gate:

```sql
GRANT USAGE ON SCHEMA :"lab_schema" TO :"reader_role";
```

**Reader A connection เดิม:** รัน SELECT/error block เดิมอีกครั้ง ต้องเป็น `permission denied for table claim` แทน schema ไม่ต้อง reconnect เพื่อรับ GRANT ที่เพิ่ง commit

**Instructor:** เปิด table gate:

```sql
GRANT SELECT ON :"lab_schema".claim TO :"reader_role";
```

**Reader A:**

```sql
SELECT claim_no, status FROM :"lab_schema".claim
WHERE claim_no LIKE 'CLM-L1-%' ORDER BY claim_no;
```

ตอนนี้อ่านได้ทั้ง 6 เคลมตั้งต้น เพราะยังไม่เปิด RLS ในขั้น D นี่เป็น checkpoint เพื่อเทียบก่อน/หลัง

## 4C.C — กำหนดแต่ละ operation และทดสอบ sequence

**Instructor:** ให้ข้อมูลที่ view ใช้ และกำหนดสิทธิ์เขียนเฉพาะคอลัมน์:

```sql
GRANT SELECT(policy_id, customer_id, policy_no, product_code)
  ON :"lab_schema".policy TO :"reader_role";
GRANT SELECT(customer_id, customer_code, full_name)
  ON :"lab_schema".customer TO :"reader_role";
GRANT SELECT ON :"lab_schema".claim_detail_v TO :"reader_role";
GRANT INSERT(claim_no, policy_id, status, incident_at, estimated_amount)
  ON :"lab_schema".claim TO :"writer_role";
GRANT UPDATE(status) ON :"lab_schema".claim TO :"approver_role";
```

**Reader A:**

```sql
\set ON_ERROR_STOP off
SELECT email FROM :"lab_schema".customer;
\echo Expected private column 42501; actual :SQLSTATE
CREATE TABLE :"lab_schema".app_owned_table(id integer);
\echo Expected schema CREATE 42501; actual :SQLSTATE
INSERT INTO :"lab_schema".claim(claim_no, policy_id, status, incident_at, estimated_amount)
SELECT 'CLM-M4C-READER', policy_id, 'NEW', now(), 100
FROM :"lab_schema".policy WHERE policy_no = 'POL-001';
\echo Expected reader INSERT 42501; actual :SQLSTATE
\set ON_ERROR_STOP on
```

ทั้งสามกรณีต้อง error `42501`; ไม่มี table หรือเคลมดังกล่าวถูกสร้าง

**Writer:** ออกจาก psql แล้วเปิดใหม่ด้วย `-U "m4c_create_a_$STUDENT_NO"` และบล็อกเริ่ม app connection จาก B จากนั้น:

```sql
INSERT INTO :"lab_schema".claim(claim_no, policy_id, status, incident_at, estimated_amount)
SELECT 'CLM-M4C-SEQUENCE', policy_id, 'NEW', now(), 100
FROM :"lab_schema".policy WHERE policy_no = 'POL-001'
RETURNING claim_id, claim_no;

\set ON_ERROR_STOP off
SELECT nextval(pg_get_serial_sequence(format('%I.claim', :'lab_schema'), 'claim_id'));
\echo Expected direct nextval 42501; actual :SQLSTATE
\set ON_ERROR_STOP on
```

INSERT ผ่าน identity สำเร็จโดยยังไม่มี sequence USAGE แต่ `nextval` โดยตรงถูกปฏิเสธ และเคลม `CLM-M4C-SEQUENCE` อยู่จริงในสำเนา

**Instructor:**

```sql
SELECT format('GRANT USAGE ON SEQUENCE %s TO %I',
              pg_get_serial_sequence(format('%I.claim', :'lab_schema'), 'claim_id'), :'writer_role')
\gexec
```

**Writer:** รัน SELECT `nextval(...)` เดิมอีกครั้ง ต้องได้เลข และเลขที่จ่ายออกไปแล้วไม่จำเป็นต้องถูกใช้ทุกเลข Sequence ที่ขยับเป็นของ Lab เท่านั้น

## 4C.D — เปิด RLS ตามบัญชีที่ Login จริง

**Instructor:**

```sql
\i labs/module04-security-clone/03-rls-audit.sql
```

ไฟล์นี้สร้าง mapping `login_customer`, function `allowed_policy_ids()`, Policies และ audit trigger ใน Lab โดย mapping เป็นตารางส่วนตัวที่ app อ่าน/แก้ไม่ได้ Function เป็น `SECURITY DEFINER`, จำกัด `search_path`, ถอน PUBLIC EXECUTE แล้วใช้ `session_user` จับคู่กับลูกค้า ไม่รับ customer ID จากผู้เรียก

**Reader A** (`m4c_read_a_xx`):

```sql
SELECT customer_code, claim_no, status FROM :"lab_schema".claim_detail_v
WHERE claim_no LIKE 'CLM-L1-%' ORDER BY claim_no;
```

ต้องเห็น **CLM-L1-001–004 ของ CUS-001** ส่วน Reader B (`m4c_read_b_xx`) เปิดอีก connection แล้วรัน SQL เดียวกัน ต้องเห็น **CLM-L1-005–006 ของ CUS-002**

กรอง `CLM-L1-%` เพื่อให้เห็น 4/2 แถวแน่นอน แม้ clone ข้อมูลบท 3 มาด้วย ตาราง/view ทั้งก้อนจะมีเคลมอื่นของลูกค้ารายนั้น รวมเคลมที่เพิ่มใน C ด้วย

**Reader A:** ทดลองเปลี่ยน context เองและอ่าน mapping:

```sql
SET app.customer_id = '2';
SELECT customer_code, claim_no FROM :"lab_schema".claim_detail_v
WHERE claim_no LIKE 'CLM-L1-%' ORDER BY claim_no;
\set ON_ERROR_STOP off
TABLE :"lab_schema".login_customer;
\echo Expected private mapping 42501; actual :SQLSTATE
\set ON_ERROR_STOP on
```

ยังเห็น 4 แถวของ CUS-001 เพราะ Policy นี้ไม่อ่าน `app.customer_id` และตาราง mapping ต้องถูกปฏิเสธ ใน Lab ใช้ Login แยกจริงเพื่อยืนยันตัวตน; แอปที่ใช้ connection pool ร่วมกันต้องออกแบบ trusted identity ของตน ไม่ใช้ `session_user` รูปแบบนี้แทน JWT ของผู้ใช้แอปโดยตรง

**Writer:**

```sql
INSERT INTO :"lab_schema".claim(claim_no, policy_id, status, incident_at, estimated_amount)
SELECT 'CLM-M4C-OWN', policy_id, 'NEW', now(), 250
FROM :"lab_schema".policy WHERE policy_no = 'POL-001'
RETURNING claim_id, claim_no, status;

\set ON_ERROR_STOP off
INSERT INTO :"lab_schema".claim(claim_no, policy_id, status, incident_at, estimated_amount)
SELECT 'CLM-M4C-WRONG', policy_id, 'NEW', now(), 250
FROM :"lab_schema".policy WHERE policy_no = 'POL-003';
\echo Expected other customer RLS 42501; actual :SQLSTATE
INSERT INTO :"lab_schema".claim(claim_no, policy_id, status, incident_at, estimated_amount)
SELECT 'CLM-M4C-PREAPPROVED', policy_id, 'APPROVED', now(), 250
FROM :"lab_schema".policy WHERE policy_no = 'POL-001';
\echo Expected NEW-only INSERT policy 42501; actual :SQLSTATE
UPDATE :"lab_schema".claim SET status = 'APPROVED' WHERE claim_no = 'CLM-M4C-OWN';
\echo Expected writer UPDATE privilege 42501; actual :SQLSTATE
\set ON_ERROR_STOP on
```

เคลม OWN อยู่จริงและมีสถานะ NEW ส่วน WRONG/PREAPPROVED ไม่เกิดขึ้น เปิด Reader A connection ใหม่ก็ยังเห็น OWN ส่วน Reader B ต้องได้ 0 แถวเมื่อกรอง `claim_no='CLM-M4C-OWN'`

## 4C.E — อนุมัติจริง แล้วให้ Auditor ตรวจหลักฐาน

**Approver:** เชื่อมด้วย `m4c_approve_a_xx` และตั้ง app context ตาม B:

```sql
UPDATE :"lab_schema".claim SET status = 'APPROVED'
WHERE claim_no = 'CLM-L1-001'
RETURNING claim_no, status;

UPDATE :"lab_schema".claim SET status = 'APPROVED'
WHERE claim_no = 'CLM-L1-005'
RETURNING claim_no, status;

\set ON_ERROR_STOP off
UPDATE :"lab_schema".claim SET estimated_amount = 0 WHERE claim_no = 'CLM-L1-001';
\echo Expected UPDATE forbidden column 42501; actual :SQLSTATE
DELETE FROM :"lab_schema".claim WHERE claim_no = 'CLM-L1-001';
\echo Expected DELETE 42501; actual :SQLSTATE
INSERT INTO :"lab_schema".claim_audit(claim_id, claim_no, old_status, new_status, login_name)
VALUES (1, 'fake', 'NEW', 'APPROVED', session_user);
\echo Expected audit tampering 42501; actual :SQLSTATE
\set ON_ERROR_STOP on
```

คำสั่งแรกต้อง `UPDATE 1` คำสั่งที่สอง `UPDATE 0` เพราะ RLS กรองเคลมของคนอื่นออกก่อนแก้ ส่วนสามคำสั่งท้ายต้อง `42501` ทั้งหมด

`UPDATE 0` เป็นผลที่ถูกต้องของแถวที่มองไม่เห็น ไม่จำเป็นต้องเป็น permission error ทุกกรณี และการอนุมัติแถวเดิมที่เป็น APPROVED อยู่แล้วจะไม่เพิ่ม audit เพราะ trigger บันทึกเฉพาะ status ที่เปลี่ยน

**Auditor:** เชื่อมด้วย `m4c_audit_xx` และตั้ง app context ตาม B:

```sql
SELECT claim_no, old_status, new_status, login_name, changed_at
FROM :"lab_schema".claim_audit ORDER BY audit_id;
\set ON_ERROR_STOP off
SELECT claim_no FROM :"lab_schema".claim;
\echo Expected auditor has no claim SELECT 42501; actual :SQLSTATE
UPDATE :"lab_schema".claim_audit SET new_status = 'PAID';
\echo Expected read-only audit 42501; actual :SQLSTATE
\set ON_ERROR_STOP on
```

audit ของ CLM-L1-001 ต้องระบุ `login_name = m4c_approve_a_xx` และสถานะใหม่ APPROVED ค่าก่อนหน้าเป็นค่าที่ clone มาจริง (ปกติ REVIEW หลังบท 1D) Auditor ไม่ต้องมีสิทธิ์อ่าน claim จึงอ่านหลักฐาน audit แยกหน้าที่ได้

**Reader A:** ปิดแล้วเชื่อมใหม่ ต้องยังเห็น CLM-L1-001 เป็น APPROVED นี่คือหลักฐานว่าเก็บผลจริงหลังจบ connection

## 4C.F — Default privileges มีผลกับเจ้าของที่สร้าง object

**Instructor:** กลับ psql เดิมที่มี variables จาก `context.sql`:

```sql
SET ROLE :"owner_role";
CREATE TABLE :"lab_schema".note_before_default(note text);
INSERT INTO :"lab_schema".note_before_default VALUES ('created before default grant');
ALTER DEFAULT PRIVILEGES IN SCHEMA :"lab_schema"
  GRANT SELECT ON TABLES TO :"reader_role";
CREATE TABLE :"lab_schema".note_after_default(note text);
INSERT INTO :"lab_schema".note_after_default VALUES ('created by lab owner after default grant');
RESET ROLE;
```

**Reader A:**

```sql
\set ON_ERROR_STOP off
TABLE :"lab_schema".note_before_default;
\echo Expected existing table has no SELECT 42501; actual :SQLSTATE
\set ON_ERROR_STOP on
TABLE :"lab_schema".note_after_default;
```

ก่อน default grant ต้อง error ส่วนตารางที่สร้างหลังต้องอ่านได้ Default privileges ไม่ย้อนแก้ตารางเก่า และต้องตั้งให้ตรง role ที่สร้าง object; ในตัวอย่างนี้คือ `m4c_owner_xx` ไม่ใช่ `postgres`

ตาราง note เป็นข้อมูลตัวอย่างทั่วไปที่ตั้งใจให้ reader ทั้งสองอ่านร่วมกัน กฎของ claim ไม่ได้ครอบคลุมตารางที่เพิ่มใหม่อัตโนมัติ หากเพิ่มข้อมูลที่ต้องแยกตามลูกค้า ต้องออกแบบ RLS/grants ของตารางนั้นด้วย

## 4C.G — ตรวจต้นทางและสรุปสิทธิ์ที่คงอยู่

**Instructor:**

```sql
SELECT claim_no, status FROM :"lab_schema".claim
WHERE claim_no LIKE 'CLM-M4C-%' ORDER BY claim_no;
SELECT claim_no, status FROM claimsure.claim WHERE claim_no = 'CLM-L1-001';
SELECT claim_no, status FROM :"lab_schema".claim WHERE claim_no = 'CLM-L1-001';
\i labs/module04-security-clone/04-check-source.sql
```

หลังทำแต่ละขั้นครั้งเดียว ต้องมี SEQUENCE และ OWN อยู่ใน Lab; WRONG, PREAPPROVED และ READER ไม่เกิดขึ้น ต้นทางยังมีสถานะเดิม ส่วนสำเนา CLM-L1-001 เป็น APPROVED ผล `same_count`, `same_data`, `same_acl`, `same_rls`, `same_sequence` ต้องเป็น `t` ทั้งสามตาราง หากมีงานอื่นเขียนต้นทางระหว่าง Lab checksum อาจต่าง ให้ตรวจงานนั้น ไม่ล้างต้นทางเพื่อให้ผลตรง

| กรณี | ผลสุดท้าย |
| --- | --- |
| Reader A / B อ่าน CLM-L1-* | 4 / 2 แถวตามลูกค้า |
| Reader เขียน / สร้าง table / อ่าน email | 42501 |
| Writer เพิ่ม NEW ของตน | เพิ่มจริงและอยู่หลัง reconnect |
| Writer เพิ่มให้คนอื่น / ตั้ง APPROVED ตั้งแต่ INSERT / UPDATE | 42501 |
| Approver แก้ status ของตน / ของคนอื่น | UPDATE 1 / UPDATE 0 |
| Approver แก้ amount / DELETE / ปลอม audit | 42501 |
| Auditor อ่าน audit / อ่าน claim / แก้ audit | อ่านได้ / 42501 / 42501 |
| Default privileges ก่อน / หลังตั้งค่า | ตารางเก่าอ่านไม่ได้ / ตารางใหม่อ่านได้ |
| Source claimsure data, ACL/RLS และ sequences | เหมือน snapshot ก่อนทดลอง |

ชุดนี้ไม่ถูกรวมเข้า `run-labs.sh run all` ของบทต่อเนื่องโดยอัตโนมัติ หลังจบเก็บ schema/roles ไว้สำรวจ `\dp`, `\ddp`, `pg_policies` และผล audit ได้ บท 5 ยังใช้ `claimsure` เดิม

ดู [ผลตรวจบน PostgreSQL 18.6 พร้อม Login จริงห้าบัญชี](module04-security-clone/VALIDATION.md) สำหรับขอบเขตที่ทดสอบแล้ว

## เริ่มใหม่หรือลบ Lab เฉพาะเมื่อเลือกทำ

คำสั่ง INSERT ตัวอย่างเป็นการทดลองครั้งเดียว หากรันซ้ำจะชน UNIQUE ตามปกติ ไม่ใช้ `ON CONFLICT` ซ่อนผลการทดลอง หากต้องการเริ่มใหม่ ให้ปิด app connections แล้วเลือก cleanup ด้วย Instructor **โดยตั้งใจทิ้งสำเนาและ audit ของ Lab นี้**:

```sql
\set confirm_cleanup :lab_schema
\i labs/module04-security-clone/99-cleanup.sql
```

cleanup ตรวจชื่อ schema, marker และ owner ก่อน `DROP SCHEMA ... CASCADE` เฉพาะ `lab_m4_clone_xx` แล้วลบ roles ที่ใช้ในเวอร์ชันนี้ ไม่มี `DROP OWNED` และไม่ลบ `claimsure` ไม่จำเป็นต้อง cleanup เมื่อจบบท; ใช้เมื่ออยากเริ่มรอบใหม่จาก `01-roles.sql` เท่านั้น

อ้างอิง: [CREATE TABLE / LIKE](https://www.postgresql.org/docs/18/sql-createtable.html), [Row Security](https://www.postgresql.org/docs/18/ddl-rowsecurity.html), [security_invoker view](https://www.postgresql.org/docs/18/sql-createview.html), [Default privileges](https://www.postgresql.org/docs/18/sql-alterdefaultprivileges.html)
