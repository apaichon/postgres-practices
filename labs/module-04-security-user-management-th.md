# Module 4 — Security และ User Management ตามสไลด์ภาษาไทย

[กลับสารบัญ](README.md) · [สไลด์ 38 หน้า](../slides/module-04-security-user-management-th.md) · [Source SQL ฉบับเต็ม](module04-security-th/04-security-user-management.sql)

คู่มือนี้เขียนจากสไลด์ `module-04-security-user-management-th.md` ที่คัดลอกจากโครงการ `setup-postgres-server/postgres-admin-labs` โดยใช้ลำดับ **0, 4A–4H**, schema, objects และผลคาดหวังตาม Source SQL ที่สไลด์อ้างถึง พร้อมปรับชื่อ NOLOGIN roles ให้ขึ้นต้นด้วย `role_` ดู [ที่มาและ SHA-256](module04-security-th/upstream.json)

แกนการทดลองคือให้ `postgres` bootstrap แล้วส่งต่อการจัดการ Lab ให้ `student_xx` ผ่าน Owner role และพิสูจน์สิทธิ์ด้วย App/Auditor/Manager ที่ Login จริง เวอร์ชันนี้สร้างข้อมูล Security จำลองใน **`lab_m4_xx`** และคง `COMMIT`/`ROLLBACK` ตามขอบเขตของแต่ละ Source Block โดยขั้น 4F.3 commit ทั้งการเปลี่ยนสถานะและ audit ให้อีก connection ตรวจได้

## ก่อนเริ่ม

NOLOGIN roles ใช้ prefix `role_`: `role_claimsure_owner_xx`, `role_claimsure_read_xx`, `role_claimsure_write_xx`, `role_claimsure_approve_xx`, `role_claimsure_audit_xx` ส่วนบัญชี Login ใช้ชื่อเดิมตามตาราง Connections

- PostgreSQL **18 ขึ้นไป** พร้อม SQL Editor ที่เปิด **Auto-commit** หรือ `psql`
- มี `student_xx` และ database `claimsure_xx` ของตนจากการเตรียมห้องเรียน ใช้หมายเลขสองหลักที่ได้รับ `01`–`20`
- มี Instructor Login (`postgres`) สำหรับ 0/4A และ HBA ที่อนุญาตการ Login ของ App/Auditor/Manager ตามวิธี Authentication ของห้องเรียน
- เริ่มเมื่อ roles ทั้ง 11 และ schema ของ Lab หมายเลขนี้ยังไม่มี ไม่ Execute All และไม่รันข้าม Login

บทนี้มีข้อมูลตั้งต้นของตนเอง ไม่ต้องนำ 100,006 เคลมจาก Lab Clone มาใช้ ส่วน `claimsure` ของบทต่อเนื่องและ `lab_m4_clone_xx` อยู่คนละขอบเขตกับ Lab นี้

### เตรียมสำเนาคำสั่งของหมายเลขตน

**Bash จาก root ของ repository:** แทน `xx` ใน STUDENT_NO ก่อนรัน จะได้ไฟล์ SQL สำหรับเปิดใน SQL Editor ที่แทนชื่อครบแล้ว:

```bash
STUDENT_NO=xx
case "$STUDENT_NO" in
  0[1-9]|1[0-9]|20) ;;
  *) printf 'Replace xx with your assigned number (01-20).\n' >&2; exit 1 ;;
esac
umask 077
mkdir -p "$HOME/case-labs"
M4_SQL="$HOME/case-labs/module04-security-$STUDENT_NO.sql"
sed "s/xx/$STUDENT_NO/g" \
  labs/module04-security-th/04-security-user-management.sql > "$M4_SQL"
printf 'Open this file and run one START/END block at a time: %s\n' "$M4_SQL"
```

ไฟล์ยังมี Password placeholders ของ 4A.3 ต้องตั้งรหัสจริงตามคำแนะนำในขั้นนั้นก่อนเปิด B/C/D ไม่ใช้ `change_me_*` เป็นรหัสจริงและไม่ commit ไฟล์ที่มี secrets กลับ repository

Code ในคู่มือด้านล่างใช้ `xx` เพื่อให้ตรงกับสไลด์ หากคัดจากคู่มือให้แทนเลขก่อนทุกจุด; หากใช้ working copy ด้านบน ชื่อ roles/database/marker จะตรงกันแล้ว

Tenant IDs **101 / 202** และรหัสเคลม SEC-* เป็นข้อมูลธุรกิจของตัวอย่าง ให้คงไว้ตาม Source ไม่เปลี่ยนเป็นหมายเลขนักเรียน

### Connections A / S / B / C / D

| Connection | Login | ใช้เมื่อใด |
| --- | --- | --- |
| A | postgres | เฉพาะ 0 และ 4A |
| S | student_xx | จัดการ Lab ตั้งแต่ 4B–4H ผ่าน Owner |
| B | claim_app_xx | Application tests |
| C | internal_auditor_xx | Column และ audit tests |
| D | manager_th_xx | UPDATE status และ denied amount |

ทุก Connection ใช้ **database `claimsure_xx`, Host และ Port เดียวกัน** Owner `role_claimsure_owner_xx` เป็น NOLOGIN จึงไม่สร้าง Connection ให้ Owner เพิ่ม

Source สร้าง Login หกชื่อ แต่เส้นทางทดสอบใช้ B/C/D สามชื่อที่ตั้ง Password ใน 4A.3 ส่วนชื่อ `claim_monitor_xx` / `claim_dba_xx` ไม่ได้รับสิทธิ์พิเศษเพียงเพราะชื่อมีคำว่า monitor หรือ dba

ถ้าใช้ `psql` ให้เปิด Terminal แยกตามตัวอักษร โดยแทนเลขและ Login ให้ตรง ใน A เริ่มด้วย:

```bash
psql -X -W -h 127.0.0.1 -p 5432 -U postgres -d claimsure_xx
```

หลัง 4A.4 เปิด S/B/C/D ด้วยคำสั่งรูปแบบเดียวกันและเปลี่ยน `-U` เป็น `student_xx`, `claim_app_xx`, `internal_auditor_xx`, `manager_th_xx` ตามลำดับ `-W` ถาม Password ของ Login นั้นผ่าน prompt พอร์ต 5432 เป็นตัวอย่าง direct PostgreSQL ของห้องเรียน ให้ใช้ค่าที่ Instructor กำหนด

ใน psql ของทุก connection:

```sql
\set AUTOCOMMIT on
\set VERBOSITY verbose
\pset pager off
SELECT current_database(), session_user, current_user;
```

ใช้ psql เป็น Interactive session แล้ววางทีละ Block ห้ามใช้ `psql -f` หรือเปิด `ON_ERROR_STOP` เพื่อ Execute All เพราะมีขั้นที่ตั้งใจให้ error และต้องใช้ recovery ใน connection เดิม หากใช้ SQL Editor ให้เลือกตั้งแต่ START ถึง END ให้ครบ รวม Function body และ transaction boundary

### ตรวจว่าชื่อ Lab ยังว่าง — A

```sql
SELECT to_regnamespace('lab_m4_xx') AS existing_lab_schema;
SELECT rolname, shobj_description(oid, 'pg_authid') AS marker
FROM pg_roles
WHERE rolname IN (
  'role_claimsure_owner_xx', 'role_claimsure_read_xx', 'role_claimsure_write_xx',
  'role_claimsure_approve_xx', 'role_claimsure_audit_xx', 'claim_app_xx',
  'adjuster_bkk_xx', 'manager_th_xx', 'internal_auditor_xx',
  'claim_monitor_xx', 'claim_dba_xx'
) ORDER BY rolname;
```

ก่อนรอบแรกควรได้ schema เป็น NULL และ roles ศูนย์แถว หากมีของเดิมให้หยุดตรวจที่มา ใช้ reset ท้ายบทเฉพาะเมื่อตั้งใจลบผลของ Lab นี้ ไม่ใช้ DROP แบบเดาสุ่มเพื่อให้ CREATE ผ่าน

## แผนเดินตามสไลด์

| หัวข้อ | สไลด์ | Connection หลัก | หลักฐาน |
| --- | --- | --- | --- |
| 0 / 4A | 6–10 | A | 11 roles และ Owner delegation |
| 4B | 11–14 | S | ตาราง/sequence เป็นของ Owner, seed 2/1 เคลม |
| 4C | 15–18 | S / B | grants/membership และปฏิเสธ CREATE |
| 4D | 19–23 | S / B | RLS อ่าน 2 แถวของ tenant 101 และปฏิเสธข้าม tenant |
| 4E | 24–27 | S / C / D | อ่านชื่อได้, contact fields/amount ถูกปฏิเสธ |
| 4F | 28–31 | S / B / C | function, UPDATE ที่ commit และ audit ของ App |
| 4G | 32–34 | S / B | อ่าน future_note ผ่าน default ACL |
| 4H | 35–36 | S | effective privileges, membership, owner และ RLS flags |
| ทบทวน | 37–38 | ทุก Connection | error/recovery ห้าคู่และการอธิบายผล |

## 0 — ตรวจ Connection และพื้นที่ของ Lab

**สไลด์ 6** — Instructor ใช้ Connection A ตรวจ database, identity และ PostgreSQL version ก่อนสร้างสิ่งใด ทุกค่าตรวจต้องเป็น true

### 0 — ตรวจ Connection ก่อนสร้างสิ่งใด

**Connection A** · ต้องได้ correct_database=true, administrator=true และ postgresql_18=true หากไม่ครบให้แก้ connection ก่อนทำต่อ

```sql
-- START 0 | ตรวจ Connection ก่อนสร้างสิ่งใด
-- LOGIN: A = postgres (SUPERUSER) | DATABASE: claimsure_xx
-- RUN: SELECT ต่อไปนี้หนึ่งคำสั่ง
-- EXPECT: correct_database, administrator, postgresql_18 = true ทั้งหมด
-- หากข้อใด false ให้หยุดและแก้ Connection ก่อนทำ 4A
SELECT current_database() AS database_name,
       session_user AS login_user,
       current_user AS effective_user,
       current_database() = 'claimsure_xx' AS correct_database,
       current_user = session_user AND rolsuper AS administrator,
       current_setting('server_version_num')::int >= 180000 AS postgresql_18
FROM pg_roles
WHERE rolname = current_user;
-- END 0
```

## 4A — Identity, Capability และ Ownership

**สไลด์ 7–10** — Instructor สร้าง 11 roles: Owner/Groups ห้าตัว และ Login หกตัว จากนั้นตั้ง Password ให้ App/Auditor/Manager และส่งต่อ SET ROLE Owner ให้ student_xx ขั้น 4A.4 เป็นงานสุดท้ายของ postgres ในเส้นทางเรียนปกติ

### 4A.1 — สร้าง Owner, Group และ Login

**Connection A** · ครบ 11 roles และมี marker Module 4 student xx แต่ยังไม่มี table privileges; owner/groups เป็น NOLOGIN ส่วน runtime logins ไม่มีสิทธิ์พิเศษ

```sql
-- START 4A.1 | สร้าง Owner, Group และ Login
-- LOGIN: A = postgres (SUPERUSER)
-- RUN: ตั้งแต่ BEGIN ถึง COMMIT รวม COMMENT ON ROLE ทั้งหมด
-- EXPECT: สร้าง 11 Role; ยังไม่มีสิทธิ์ Table
BEGIN;

CREATE ROLE role_claimsure_owner_xx NOLOGIN;
CREATE ROLE role_claimsure_read_xx NOLOGIN;
CREATE ROLE role_claimsure_write_xx NOLOGIN;
CREATE ROLE role_claimsure_approve_xx NOLOGIN;
CREATE ROLE role_claimsure_audit_xx NOLOGIN;

CREATE ROLE claim_app_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE ROLE adjuster_bkk_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE ROLE manager_th_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE ROLE internal_auditor_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE ROLE claim_monitor_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE ROLE claim_dba_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;

-- Marker ช่วยระบุว่า Role เป็นของ Module 4 และเลขนักเรียนนี้
COMMENT ON ROLE role_claimsure_owner_xx IS 'Module 4 student xx';
COMMENT ON ROLE role_claimsure_read_xx IS 'Module 4 student xx';
COMMENT ON ROLE role_claimsure_write_xx IS 'Module 4 student xx';
COMMENT ON ROLE role_claimsure_approve_xx IS 'Module 4 student xx';
COMMENT ON ROLE role_claimsure_audit_xx IS 'Module 4 student xx';
COMMENT ON ROLE claim_app_xx IS 'Module 4 student xx';
COMMENT ON ROLE adjuster_bkk_xx IS 'Module 4 student xx';
COMMENT ON ROLE manager_th_xx IS 'Module 4 student xx';
COMMENT ON ROLE internal_auditor_xx IS 'Module 4 student xx';
COMMENT ON ROLE claim_monitor_xx IS 'Module 4 student xx';
COMMENT ON ROLE claim_dba_xx IS 'Module 4 student xx';

COMMIT;
-- END 4A.1
```

### 4A.2 — ตรวจ Role ที่เพิ่งสร้าง

**Connection A** · ผลตรวจต้องมี 11 แถว Owner/Groups เป็น NOLOGIN ส่วน Logins ที่สร้างต้องไม่มี SUPERUSER/CREATEROLE/BYPASSRLS

```sql
-- START 4A.2 | ตรวจ Role ที่เพิ่งสร้าง
-- LOGIN: A = postgres (SUPERUSER)
-- EXPECT: 11 แถว; Owner/Groups เป็น NOLOGIN; Runtime roles ไม่มีสิทธิ์พิเศษ
SELECT rolname, rolcanlogin, rolsuper, rolcreaterole, rolbypassrls
FROM pg_roles
WHERE shobj_description(oid, 'pg_authid') = 'Module 4 student xx'
ORDER BY rolname;
-- END 4A.2
```

### 4A.3 — ตั้ง Password สำหรับ Connection B/C/D

**Connection A** · แก้ password placeholders ก่อนรันเฉพาะบล็อกนี้ ห้ามใช้ change_me_* ตามตัวอย่างจริง หากใช้ psql สามารถใช้ \password claim_app_xx, \password internal_auditor_xx และ \password manager_th_xx แทน ALTER ROLE เพื่อรับรหัสผ่านทาง prompt โดยไม่บันทึกรหัสจริงลงไฟล์

```sql
-- START 4A.3 | ตั้ง Password สำหรับ Connection B/C/D
-- LOGIN: A = postgres (SUPERUSER)
-- BEFORE RUN: แก้ CHANGE_ME_* ให้เป็น Password ที่จะใช้จริงก่อนเลือก Execute
-- Password ด้านล่างเป็น Placeholder ไม่ใช่ Password ของ Server
-- RUN: ALTER ROLE ทั้งสามคำสั่ง ยังไม่ต้องเปิด B/C/D จนกว่าจะจบ 4A.4
ALTER ROLE claim_app_xx PASSWORD 'change_me_app_xx';
ALTER ROLE internal_auditor_xx PASSWORD 'change_me_auditor_xx';
ALTER ROLE manager_th_xx PASSWORD 'change_me_manager_xx';
-- END 4A.3
```

### 4A.4 — เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย

**Connection A** · COMMIT แล้วจึงเปิด S/B/C/D ใหม่ S ต้อง SET Owner ได้ แต่ไม่ inherit Owner โดยอัตโนมัติ App ไม่มี Owner membership และไม่มี ADMIN OPTION ห้ามให้ SUPERUSER หรือ CREATEROLE แก่ student_xx เพื่อแก้ปัญหา

```sql
-- START 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย
-- LOGIN: A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres
-- PREREQUISITE: มี student_xx จากระบบชั้นเรียน และสร้าง Role ใน 4A.1 ครบแล้ว
-- RUN: BEGIN ถึง COMMIT ทั้งชุด แล้วจึงเปิด Connection S เป็น student_xx
-- Group membership ให้ไว้ก่อน แต่ Group ยังไม่มี Table privileges จนถึง 4C
BEGIN;
CREATE SCHEMA IF NOT EXISTS lab_m4_xx AUTHORIZATION role_claimsure_owner_xx;

GRANT role_claimsure_owner_xx TO student_xx
WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;

GRANT CONNECT ON DATABASE claimsure_xx
TO student_xx, claim_app_xx, adjuster_bkk_xx,
   manager_th_xx, internal_auditor_xx;

GRANT role_claimsure_read_xx TO role_claimsure_write_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
GRANT role_claimsure_write_xx TO claim_app_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
GRANT role_claimsure_read_xx TO adjuster_bkk_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
GRANT role_claimsure_approve_xx TO manager_th_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
GRANT role_claimsure_audit_xx TO internal_auditor_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
COMMIT;
-- จบงาน postgres: ต่อจากนี้ใช้ Connection S/B/C/D ตาม LOGIN ของแต่ละชุด
-- INHERIT FALSE ไม่ให้ Owner privileges ติดกับ student_xx โดยอัตโนมัติ
-- SET TRUE อนุญาตให้ student_xx เปลี่ยนเป็น Owner อย่างชัดเจนเมื่อทำ DDL
-- END 4A.4
```

## 4B — ผู้เรียน Activate Owner แล้วสร้าง Objects

**สไลด์ 11–14** — เปลี่ยนมา Connection S ของ student_xx ใช้ SET LOCAL ROLE role_claimsure_owner_xx เฉพาะ transaction ที่ทำ DDL เมื่อ COMMIT แล้ว current_user กลับเป็น student_xx ได้ claim_secure, policyholder_secure และ claim_audit ใน lab_m4_xx

### 4B.1 — เปิด Connection S ตรวจสิทธิ์ที่ได้รับ แล้วใช้ Owner

**Connection S** · can_set_owner=true, is_superuser=false, owns_schema_exists=true ก่อน BEGIN เมื่ออยู่ใน Owner transaction session_user ยังเป็น student_xx แต่ current_user เป็น role_claimsure_owner_xx; หลัง COMMIT กลับเป็น student_xx

```sql
-- START 4B.1 | เปิด Connection S ตรวจสิทธิ์ที่ได้รับ แล้วใช้ Owner
-- LOGIN: S = student_xx (ผู้ใช้ปกติ); เปิด Connection ใหม่ด้วย Login นักเรียนเดิม
-- DATABASE: claimsure_xx; ต้องทำ 4A.4 โดย postgres มาก่อน
-- RUN: SELECT ก่อน ต้องได้ can_set_owner=true, is_superuser=false,
--      owns_schema_exists=true แล้วจึงรัน BEGIN..COMMIT
-- หาก can_set_owner=false ให้กลับไปทำ 4A.4 ไม่ต้องให้ SUPERUSER กับ student_xx
SELECT session_user, current_user,
       rolsuper AS is_superuser,
       pg_has_role(session_user, 'role_claimsure_owner_xx', 'SET') AS can_set_owner,
       EXISTS (
           SELECT 1 FROM pg_namespace
           WHERE nspname = 'lab_m4_xx'
             AND pg_get_userbyid(nspowner) = 'role_claimsure_owner_xx'
       ) AS owns_schema_exists
FROM pg_roles WHERE rolname = current_user;

BEGIN;
SET LOCAL ROLE role_claimsure_owner_xx;
REVOKE ALL ON SCHEMA lab_m4_xx FROM PUBLIC;
SELECT session_user, current_user;
COMMIT;
-- หลัง COMMIT Connection S กลับเป็น student_xx
-- END 4B.1
```

### 4B.2 — สร้าง Table ทั้งสามในนาม Owner

**Connection S** · Table และ identity sequences เป็นของ role_claimsure_owner_xx ถอน PUBLIC access แล้ว และยังไม่เปิด RLS ในขั้นนี้

```sql
-- START 4B.2 | สร้าง Table ทั้งสามในนาม Owner
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- EFFECTIVE ROLE ภายใน Transaction: role_claimsure_owner_xx
-- RUN: BEGIN ถึง COMMIT ทั้งชุด
-- EXPECT: Table/Sequence เป็นของ Owner; ยังไม่เปิด RLS
BEGIN;
SET LOCAL ROLE role_claimsure_owner_xx;

CREATE TABLE lab_m4_xx.claim_secure (
    claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id bigint NOT NULL,
    claim_no text NOT NULL UNIQUE,
    status text NOT NULL,
    estimated_amount numeric(14,2) NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE lab_m4_xx.policyholder_secure (
    policyholder_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id bigint NOT NULL,
    full_name text NOT NULL,
    email text NOT NULL,
    phone text NOT NULL,
    UNIQUE (tenant_id, email)
);

CREATE TABLE lab_m4_xx.claim_audit (
    audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_time timestamptz NOT NULL DEFAULT clock_timestamp(),
    actor name NOT NULL,
    role_setting text NOT NULL,
    operation text NOT NULL,
    claim_id bigint,
    old_row jsonb,
    new_row jsonb
);

REVOKE ALL ON ALL TABLES IN SCHEMA lab_m4_xx FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA lab_m4_xx FROM PUBLIC;
COMMIT;
-- END 4B.2
```

### 4B.3 — เพิ่มข้อมูลตั้งต้น

**Connection S** · Tenant 101 มีสองเคลม (SEC-101-001/002), tenant 202 มีหนึ่งเคลม (SEC-202-001); policyholder มีข้อมูลจำลองหนึ่งแถว ยังไม่มี audit records

```sql
-- START 4B.3 | เพิ่มข้อมูลตั้งต้น
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner
-- RUN: BEGIN ถึง COMMIT
-- EXPECT: Tenant 101 สองเคลม และ Tenant 202 หนึ่งเคลม
BEGIN;
SET LOCAL ROLE role_claimsure_owner_xx;

INSERT INTO lab_m4_xx.claim_secure
    (tenant_id, claim_no, status, estimated_amount)
VALUES
    (101, 'SEC-101-001', 'NEW', 10000),
    (101, 'SEC-101-002', 'UNDER_REVIEW', 25000),
    (202, 'SEC-202-001', 'NEW', 18000);

INSERT INTO lab_m4_xx.policyholder_secure
    (tenant_id, full_name, email, phone)
VALUES
    (101, 'Demo Policyholder', 'demo@example.invalid', '000-000-0000');

SELECT tenant_id, count(*) AS claims
FROM lab_m4_xx.claim_secure
GROUP BY tenant_id
ORDER BY tenant_id;
COMMIT;
-- END 4B.3
```

## 4C — CONNECT, Schema และ Object Privileges

**สไลด์ 15–18** — S ให้สิทธิ์กับ Group ที่เตรียมไว้ ส่วน B Login เป็น App จริงเพื่อทดลอง Membership เปิดการอ่าน/เขียนตามหน้าที่และปฏิเสธการ CREATE TABLE ใน schema

### 4C.1 — ตรวจ CONNECT ที่ postgres ให้ไว้แล้วใน 4A.4

**Connection S** · CONNECT=true เพียงยืนยันสิทธิ์เชื่อม database การอ่าน table ยังต้องผ่าน schema/table grants; ไม่ถอน PUBLIC CONNECT ของห้องเรียนเพื่อทดลอง

```sql
-- START 4C.1 | ตรวจ CONNECT ที่ postgres ให้ไว้แล้วใน 4A.4
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- EXPECT: app_can_connect=true; CONNECT ไม่ได้ให้สิทธิ์ Table
SELECT has_database_privilege('claim_app_xx', 'claimsure_xx', 'CONNECT')
       AS app_can_connect;
-- PUBLIC อาจมี CONNECT อยู่ก่อนแล้ว Lab ไม่เปลี่ยนสิทธิ์ Database ของส่วนรวม
-- END 4C.1
```

### 4C.2 — ให้สิทธิ์ Object กับ Group

**Connection S** · USAGE เปิด schema, reader ให้ SELECT, writer ให้ INSERT/UPDATE และ sequence USAGE เป็นอีกสิทธิ์หนึ่ง การ INSERT ผ่าน identity ในตัวอย่างนี้ไม่ได้ใช้พิสูจน์ว่าจำเป็นต้อง grant sequence เพิ่ม

```sql
-- START 4C.2 | ให้สิทธิ์ Object กับ Group
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner
-- EXPECT: Read group ได้ SELECT; Write group ได้ INSERT/UPDATE
BEGIN;
SET LOCAL ROLE role_claimsure_owner_xx;

GRANT USAGE ON SCHEMA lab_m4_xx
TO role_claimsure_read_xx, role_claimsure_write_xx,
   role_claimsure_approve_xx, role_claimsure_audit_xx;

GRANT SELECT ON lab_m4_xx.claim_secure TO role_claimsure_read_xx;
GRANT INSERT, UPDATE ON lab_m4_xx.claim_secure TO role_claimsure_write_xx;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA lab_m4_xx TO role_claimsure_write_xx;

COMMIT;
-- Sequence grant เป็นสิทธิ์แยกสำหรับการใช้ Sequence โดยตรง/Default ที่ต้องใช้
-- การ INSERT Column แบบ IDENTITY ในตัวอย่างนี้ไม่ได้พิสูจน์ว่าจำเป็นต้องมี grant นี้
-- END 4C.2
```

### 4C.3 — ตรวจ Membership ที่ postgres เตรียมใน 4A.4

**Connection S** · App รับ Write และรับ Read ผ่าน Write อีกทอด โดย admin_option=false ทั้งหมด Group membership ที่มีอยู่เริ่มทำงานกับ object grants ที่เพิ่งให้ใน 4C.2

```sql
-- START 4C.3 | ตรวจ Membership ที่ postgres เตรียมใน 4A.4
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- EXPECT: App รับ Write -> Read; ไม่มี Owner membership และ ADMIN เป็น false
-- หลัง 4C.2 Group จึงมี Object privileges ให้ Login ใช้ผ่าน Membership ได้
SELECT r.rolname AS group_role, m.rolname AS member,
       am.inherit_option, am.set_option, am.admin_option
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE m.rolname IN ('role_claimsure_write_xx', 'claim_app_xx', 'adjuster_bkk_xx',
                   'manager_th_xx', 'internal_auditor_xx')
ORDER BY member, group_role;
-- END 4C.3
```

### 4C.4 — เปิด Connection B แล้วทดสอบอ่านและเพิ่มข้อมูล

**Connection B** · B ต้องมี session_user=current_user=claim_app_xx อ่าน seed ได้สามแถวและ INSERT ผ่าน แต่ SEC-C-ALLOWED ไม่คงอยู่เพราะบล็อกจบด้วย ROLLBACK

```sql
-- START 4C.4 | เปิด Connection B แล้วทดสอบอ่านและเพิ่มข้อมูล
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ ไม่ใช่ SUPERUSER)
-- CONNECTION: เปิด Connection ใหม่ใน SQL editor ด้วย Password จาก 4A.3
-- DATABASE: claimsure_xx; EXPECT: session_user=current_user=claim_app_xx
-- RUN: BEGIN ถึง ROLLBACK; EXPECT: อ่านสาม Seed rows และ INSERT ผ่าน
BEGIN;
SELECT session_user, current_user;

SELECT claim_no, tenant_id, status
FROM lab_m4_xx.claim_secure
ORDER BY claim_no;

INSERT INTO lab_m4_xx.claim_secure
    (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-C-ALLOWED', 'NEW', 500)
RETURNING claim_id, claim_no;
ROLLBACK;
-- ROLLBACK ย้อนข้อมูลทดลอง แต่ Login ของ Connection B ยังเป็น claim_app_xx
-- END 4C.4
```

### 4C.5 — EXPECTED ERROR: App สร้าง Table ไม่ได้

**Connection B** · ต้องได้ SQLSTATE 42501: App ไม่มี CREATE บน schema หลัง error transaction จะ aborted ให้ไป 4C.6 ใน B connection เดิมทันที

```sql
-- START 4C.5 | EXPECTED ERROR: App สร้าง Table ไม่ได้
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN และ CREATE TABLE; EXPECT: SQLSTATE 42501 / permission denied
-- เมื่อเห็น Error ให้เลือกชุด 4C.6 แยกต่างหากทันที
BEGIN;
CREATE TABLE lab_m4_xx.owned_by_app (id integer);
-- END 4C.5
```

### 4C.6 — RECOVERY หลัง Expected error ของ 4C.5

**Connection B** · B ออกจาก failed transaction ได้ และยังเป็น Login claim_app_xx ไม่ต้องให้สิทธิ์เพิ่มเพื่อทำให้ expected error หาย

```sql
-- START 4C.6 | RECOVERY หลัง Expected error ของ 4C.5
-- LOGIN: B = claim_app_xx (Connection เดิม)
-- RUN: ROLLBACK หนึ่งคำสั่ง เพื่อออกจาก Transaction aborted
ROLLBACK;
-- END 4C.6
```

## 4D — Tenant Isolation ด้วย RLS

**สไลด์ 19–23** — S เปิด ENABLE/FORCE RLS และสร้าง USING/WITH CHECK ส่วน B ตั้ง tenant context ภายใน transaction เพื่อเห็นแถวที่อนุญาตและทดสอบการเขียนข้าม tenant ค่านี้เป็น context จำลองที่ SQL client ตั้งเองได้ ไม่ใช่ระบบ Authentication ของ tenant

### 4D.1 — เปิด RLS และสร้าง Policy บนตารางเดิม

**Connection S** · Owner อยู่ใน policy ด้วย เพราะ Count function ของ 4F ใช้ SECURITY DEFINER และ Owner ยังอยู่ภายใต้ FORCE RLS การให้ GRANT และการกำหนดแถวเป็นคนละขั้น

```sql
-- START 4D.1 | เปิด RLS และสร้าง Policy บนตารางเดิม
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน); กลับมาที่ Connection S
-- RUN: BEGIN ถึง COMMIT; EFFECTIVE ROLE: Owner
BEGIN;
SET LOCAL ROLE role_claimsure_owner_xx;

ALTER TABLE lab_m4_xx.claim_secure ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_m4_xx.claim_secure FORCE ROW LEVEL SECURITY;

CREATE POLICY claim_tenant_access ON lab_m4_xx.claim_secure
TO role_claimsure_read_xx, role_claimsure_write_xx,
   role_claimsure_approve_xx, role_claimsure_owner_xx
USING (
    tenant_id = nullif(current_setting('app.tenant_id', true), '')::bigint
)
WITH CHECK (
    tenant_id = nullif(current_setting('app.tenant_id', true), '')::bigint
);
COMMIT;
-- Owner อยู่ใน Policy เพราะ Count function ของ 4F ทำงานเป็น Owner ตาม FORCE RLS
-- END 4D.1
```

### 4D.2 — App อ่านและเพิ่มเฉพาะ Tenant ของตน

**Connection B** · SELECT เห็น tenant 101 สองแถว INSERT tenant 101 สำเร็จชั่วคราว ก่อน ROLLBACK คืนข้อมูลตั้งต้น

```sql
-- START 4D.2 | App อ่านและเพิ่มเฉพาะ Tenant ของตน
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง ROLLBACK
-- EXPECT: SELECT ได้สองแถวของ Tenant 101; INSERT Tenant 101 ผ่าน
BEGIN;
SELECT set_config('app.tenant_id', '101', true);
SELECT claim_no, tenant_id
FROM lab_m4_xx.claim_secure
ORDER BY claim_no;

INSERT INTO lab_m4_xx.claim_secure
    (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-D-ALLOWED', 'NEW', 500)
RETURNING claim_no, tenant_id;
ROLLBACK;
-- END 4D.2
```

### 4D.3 — EXPECTED ERROR: App เพิ่มข้อมูลข้าม Tenant ไม่ได้

**Connection B** · INSERT tenant 202 ขณะ context เป็น 101 ต้องได้ 42501 จาก WITH CHECK จากนั้นใช้ 4D.4 ใน B connection เดิม

```sql
-- START 4D.3 | EXPECTED ERROR: App เพิ่มข้อมูลข้าม Tenant ไม่ได้
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง INSERT; EXPECT: SQLSTATE 42501 / row-level security policy
-- รัน 4D.4 หลัง Error
BEGIN;
SELECT set_config('app.tenant_id', '101', true);
INSERT INTO lab_m4_xx.claim_secure
    (tenant_id, claim_no, status, estimated_amount)
VALUES (202, 'SEC-D-DENIED', 'NEW', 500);
-- END 4D.3
```

### 4D.4 — RECOVERY หลัง Expected error ของ 4D.3

**Connection B** · ออกจาก aborted transaction และยกเลิก tenant context ที่ตั้งแบบ transaction-local

```sql
-- START 4D.4 | RECOVERY หลัง Expected error ของ 4D.3
-- LOGIN: B = claim_app_xx (Connection เดิม)
ROLLBACK;
-- END 4D.4
```

### 4D.5 — App ไม่มี Tenant context จึงเห็นศูนย์แถว

**Connection B** · visible_claims=0 เมื่อ context เป็นค่าว่าง SQL client ตั้ง app.tenant_id เองได้ จึงยังไม่ได้พิสูจน์การยืนยัน tenant identity ของระบบจริง

```sql
-- START 4D.5 | App ไม่มี Tenant context จึงเห็นศูนย์แถว
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง ROLLBACK; EXPECT: visible_claims = 0
BEGIN;
SELECT set_config('app.tenant_id', '', true);
SELECT count(*) AS visible_claims FROM lab_m4_xx.claim_secure;
ROLLBACK;
-- Custom setting นี้ใช้สาธิต Policy ไม่ใช่หลักฐานยืนยัน Tenant identity
-- SQL client ตั้ง GUC เองได้; ระบบจริงต้องอนุญาต Tenant ผ่านฝั่งที่เชื่อถือได้
-- END 4D.5
```

## 4E — Column Privileges สำหรับ Auditor และ Manager

**สไลด์ 24–27** — S อนุญาตให้ Auditor อ่านคอลัมน์ชื่อโดยไม่ให้ contact fields และให้ Manager แก้เฉพาะ status/updated_at การทดสอบต้องใช้ C และ D เป็นคนละ Login จริง

### 4E.1 — Owner ให้สิทธิ์ Column กับ Group ที่มีอยู่แล้ว

**Connection S** · Auditor มี SELECT เฉพาะ policyholder_id/tenant_id/full_name; Manager มี SELECT claim และ UPDATE(status,updated_at) โดยไม่มี UPDATE ทั้ง table

```sql
-- START 4E.1 | Owner ให้สิทธิ์ Column กับ Group ที่มีอยู่แล้ว
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง COMMIT
BEGIN;
SET LOCAL ROLE role_claimsure_owner_xx;

REVOKE SELECT ON lab_m4_xx.policyholder_secure FROM role_claimsure_audit_xx;
GRANT SELECT (policyholder_id, tenant_id, full_name)
ON lab_m4_xx.policyholder_secure TO role_claimsure_audit_xx;

GRANT SELECT ON lab_m4_xx.claim_secure TO role_claimsure_approve_xx;
REVOKE UPDATE ON lab_m4_xx.claim_secure FROM role_claimsure_approve_xx;
GRANT UPDATE (status, updated_at)
ON lab_m4_xx.claim_secure TO role_claimsure_approve_xx;

COMMIT;
-- END 4E.1
```

### 4E.2 — เปิด Connection C เป็น Auditor แล้วอ่านชื่อ

**Connection C** · C ต้องเป็น internal_auditor_xx ทั้ง session_user/current_user และอ่านชื่อจำลองได้ policyholder_secure ใน Lab นี้ทดสอบสิทธิ์คอลัมน์ ไม่มี tenant RLS เพิ่มบนตารางนี้

```sql
-- START 4E.2 | เปิด Connection C เป็น Auditor แล้วอ่านชื่อ
-- LOGIN: C = internal_auditor_xx (ผู้ใช้ปกติ)
-- CONNECTION: เปิดใหม่ด้วย Password จาก 4A.3; DATABASE: claimsure_xx
-- EXPECT: ผู้ใช้ทั้งสองเป็น internal_auditor_xx และอ่านชื่อได้
SELECT session_user, current_user;
SELECT policyholder_id, tenant_id, full_name
FROM lab_m4_xx.policyholder_secure;
-- END 4E.2
```

### 4E.3 — EXPECTED ERROR: Auditor อ่าน Contact fields ไม่ได้

**Connection C** · อ่าน email/phone ต้องได้ 42501 แม้อ่าน full_name ได้ ไป 4E.4 ใน C connection เดิม

```sql
-- START 4E.3 | EXPECTED ERROR: Auditor อ่าน Contact fields ไม่ได้
-- LOGIN: C = internal_auditor_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง SELECT; EXPECT: SQLSTATE 42501; แล้วรัน 4E.4
BEGIN;
SELECT email, phone FROM lab_m4_xx.policyholder_secure;
-- END 4E.3
```

### 4E.4 — RECOVERY หลัง Expected error ของ 4E.3

**Connection C** · C กลับสู่สถานะพร้อม query หลัง recovery โดยไม่แก้ grants

```sql
-- START 4E.4 | RECOVERY หลัง Expected error ของ 4E.3
-- LOGIN: C = internal_auditor_xx (Connection เดิม)
ROLLBACK;
-- END 4E.4
```

### 4E.5 — เปิด Connection D เป็น Manager แล้วแก้ Status

**Connection D** · D ต้องเป็น manager_th_xx จริง เมื่อ context=101 ต้อง UPDATE SEC-101-001 ได้หนึ่งแถวชั่วคราว แล้ว ROLLBACK คืนสถานะ NEW

```sql
-- START 4E.5 | เปิด Connection D เป็น Manager แล้วแก้ Status
-- LOGIN: D = manager_th_xx (ผู้ใช้ปกติ)
-- CONNECTION: เปิดใหม่ด้วย Password จาก 4A.3; DATABASE: claimsure_xx
-- RUN: BEGIN ถึง ROLLBACK; EXPECT: UPDATE ได้หนึ่งแถว
BEGIN;
SELECT session_user, current_user;
SELECT set_config('app.tenant_id', '101', true);
UPDATE lab_m4_xx.claim_secure
SET status = 'APPROVED', updated_at = clock_timestamp()
WHERE claim_no = 'SEC-101-001'
RETURNING claim_no, status;
ROLLBACK;
-- END 4E.5
```

### 4E.6 — EXPECTED ERROR: Manager แก้จำนวนเงินไม่ได้

**Connection D** · Manager แก้ estimated_amount ไม่ได้ ต้องได้ 42501 จาก column privileges จากนั้นใช้ 4E.7 ใน D connection เดิม

```sql
-- START 4E.6 | EXPECTED ERROR: Manager แก้จำนวนเงินไม่ได้
-- LOGIN: D = manager_th_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง UPDATE; EXPECT: SQLSTATE 42501; แล้วรัน 4E.7
BEGIN;
SELECT set_config('app.tenant_id', '101', true);
UPDATE lab_m4_xx.claim_secure
SET estimated_amount = 1
WHERE claim_no = 'SEC-101-001';
-- END 4E.6
```

### 4E.7 — RECOVERY หลัง Expected error ของ 4E.6

**Connection D** · D ออกจาก failed transaction พร้อมทำขั้นถัดไป

```sql
-- START 4E.7 | RECOVERY หลัง Expected error ของ 4E.6
-- LOGIN: D = manager_th_xx (Connection เดิม)
ROLLBACK;
-- END 4E.7
```

## 4F — Controlled Routine และ Audit

**สไลด์ 28–31** — S สร้าง Count function กับ Audit trigger ภายใต้ Owner ถอน PUBLIC EXECUTE และให้สิทธิ์เฉพาะที่ใช้ B UPDATE แล้ว COMMIT ก่อนให้ C อ่าน audit จากอีก connection

### 4F.1 — Owner สร้าง Count function ก่อนให้ EXECUTE

**Connection S** · เก็บ function definition ให้ครบระหว่าง $function$ อย่ารันทีละบรรทัด SECURITY DEFINER ใช้ Owner และจำกัด search_path ส่วน RLS/tenant context ยังคงกำหนดข้อมูลที่ function นับได้

```sql
-- START 4F.1 | Owner สร้าง Count function ก่อนให้ EXECUTE
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง COMMIT ทั้งชุด รวม Function body ระหว่าง $function$
BEGIN;
SET LOCAL ROLE role_claimsure_owner_xx;

CREATE FUNCTION lab_m4_xx.claim_count_for_current_tenant()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT count(*)
    FROM lab_m4_xx.claim_secure
    WHERE tenant_id = nullif(current_setting('app.tenant_id', true), '')::bigint
$function$;

REVOKE ALL ON FUNCTION lab_m4_xx.claim_count_for_current_tenant() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION lab_m4_xx.claim_count_for_current_tenant()
TO role_claimsure_read_xx;
COMMIT;
-- SECURITY DEFINER ใช้สิทธิ์ Owner ภายใน Function และคืน Role ให้ผู้เรียกเมื่อจบ
-- END 4F.1
```

### 4F.2 — Owner สร้าง Audit function และ Trigger

**Connection S** · Trigger เก็บ old_row/new_row และ session_user เป็น actor App/Manager ไม่มีสิทธิ์เขียน/ลบ audit โดยตรง SECURITY DEFINER ไม่ได้ทำให้ audit ปลอดจากการแก้ของ Owner หรือ superuser

```sql
-- START 4F.2 | Owner สร้าง Audit function และ Trigger
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง COMMIT ทั้งชุด ห้ามเลือกเพียงบางบรรทัดใน Function body
BEGIN;
SET LOCAL ROLE role_claimsure_owner_xx;

CREATE FUNCTION lab_m4_xx.audit_claim_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $trigger$
BEGIN
    INSERT INTO lab_m4_xx.claim_audit
        (actor, role_setting, operation, claim_id, old_row, new_row)
    VALUES (
        session_user,
        current_setting('role'),
        TG_OP,
        coalesce(NEW.claim_id, OLD.claim_id),
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END
    );
    RETURN coalesce(NEW, OLD);
END
$trigger$;

REVOKE ALL ON FUNCTION lab_m4_xx.audit_claim_change() FROM PUBLIC;

CREATE TRIGGER trg_claim_secure_audit
AFTER INSERT OR UPDATE OR DELETE ON lab_m4_xx.claim_secure
FOR EACH ROW EXECUTE FUNCTION lab_m4_xx.audit_claim_change();

REVOKE ALL ON lab_m4_xx.claim_audit
FROM role_claimsure_write_xx, role_claimsure_approve_xx, PUBLIC;
GRANT SELECT ON lab_m4_xx.claim_audit TO role_claimsure_audit_xx;
COMMIT;
-- END 4F.2
```

### 4F.3 — App เรียก Function และ UPDATE ให้เกิด Audit

**Connection B** · tenant_claims=2 และ UPDATE หนึ่งแถวเป็น UNDER_REVIEW บล็อกนี้ต้อง COMMIT เพื่อให้ C เห็น audit จากอีก connection อย่าเปลี่ยนเป็น ROLLBACK

```sql
-- START 4F.3 | App เรียก Function และ UPDATE ให้เกิด Audit
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง COMMIT
-- EXPECT: tenant_claims=2 และ UPDATE หนึ่งแถว
-- รอบนี้ COMMIT เพื่อให้ Connection C อ่าน Audit ที่ Commit แล้วได้ใน 4F.6
BEGIN;
SELECT set_config('app.tenant_id', '101', true);
SELECT lab_m4_xx.claim_count_for_current_tenant() AS tenant_claims;

UPDATE lab_m4_xx.claim_secure
SET status = 'UNDER_REVIEW', updated_at = clock_timestamp()
WHERE claim_no = 'SEC-101-001'
RETURNING claim_no, status;
COMMIT;
-- END 4F.3
```

### 4F.4 — EXPECTED ERROR: App ลบ Audit ไม่ได้

**Connection B** · App DELETE audit ต้องได้ 42501 ไป 4F.5 ใน B connection เดิม

```sql
-- START 4F.4 | EXPECTED ERROR: App ลบ Audit ไม่ได้
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง DELETE; EXPECT: SQLSTATE 42501; แล้วรัน 4F.5
BEGIN;
DELETE FROM lab_m4_xx.claim_audit;
-- END 4F.4
```

### 4F.5 — RECOVERY หลัง Expected error ของ 4F.4

**Connection B** · B recover จาก transaction ของ DELETE ที่ถูกปฏิเสธ โดย audit ที่ COMMIT ใน 4F.3 ยังอยู่

```sql
-- START 4F.5 | RECOVERY หลัง Expected error ของ 4F.4
-- LOGIN: B = claim_app_xx (Connection เดิม)
ROLLBACK;
-- END 4F.5
```

### 4F.6 — Auditor อ่านหลักฐานจาก App connection จริง

**Connection C** · C ต้องเห็น actor=claim_app_xx และ operation=UPDATE; role_setting มักเป็น none เพราะ B Login จริงโดยไม่ได้ SET ROLE ค่าตัวนี้ไม่ใช่ชื่อ Owner ของ SECURITY DEFINER

```sql
-- START 4F.6 | Auditor อ่านหลักฐานจาก App connection จริง
-- LOGIN: C = internal_auditor_xx (ผู้ใช้ปกติ)
-- EXPECT: actor=claim_app_xx, operation=UPDATE
-- role_setting มักเป็น 'none' เพราะ B Login เป็น App จริง ไม่ได้ใช้ SET ROLE
SELECT event_time, actor, role_setting, operation, claim_id
FROM lab_m4_xx.claim_audit
ORDER BY audit_id DESC
LIMIT 5;
-- END 4F.6
```

## 4G — Default Privileges ของผู้สร้าง Object

**สไลด์ 32–34** — S Activate Owner แล้วตั้ง default ACL ก่อนสร้าง future_note ด้วย Owner คนเดียวกัน App อ่านตารางใหม่นี้ได้ผ่าน Write/Read membership โดยไม่ต้อง GRANT เฉพาะตารางเพิ่ม

### 4G.1 — ตั้ง Defaults แล้วสร้าง Table ในนาม Owner เดียวกัน

**Connection S** · Default ACL ผูกกับ Owner ผู้สร้าง objects ตั้งก่อน CREATE TABLE/identity sequence ไม่ย้อนให้สิทธิ์ตารางเก่า และไม่ติดตั้ง RLS ให้ตารางใหม่อัตโนมัติ

```sql
-- START 4G.1 | ตั้ง Defaults แล้วสร้าง Table ในนาม Owner เดียวกัน
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง COMMIT
BEGIN;
SET LOCAL ROLE role_claimsure_owner_xx;

ALTER DEFAULT PRIVILEGES IN SCHEMA lab_m4_xx
GRANT SELECT ON TABLES TO role_claimsure_read_xx;
ALTER DEFAULT PRIVILEGES IN SCHEMA lab_m4_xx
GRANT USAGE ON SEQUENCES TO role_claimsure_write_xx;

CREATE TABLE lab_m4_xx.future_note (
    note_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message text NOT NULL
);
INSERT INTO lab_m4_xx.future_note (message)
VALUES ('Created by role_claimsure_owner_xx after default privileges were configured');

COMMIT;
-- Defaults ไม่ย้อนให้สิทธิ์ Table เก่า และไม่สร้าง RLS ให้ Table ใหม่
-- พิจารณาแยก Schema หาก Table อนาคตไม่ควรให้ Read group อ่าน
-- END 4G.1
```

### 4G.2 — App อ่าน Table ใหม่ได้ผ่าน Write -> Read membership

**Connection B** · B อ่าน future_note ได้หนึ่งแถวผ่าน Write → Read membership โดยไม่ต้อง GRANT SELECT บนตารางนี้เพิ่มโดยตรง

```sql
-- START 4G.2 | App อ่าน Table ใหม่ได้ผ่าน Write -> Read membership
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- EXPECT: ได้หนึ่งแถว โดยไม่ต้อง GRANT SELECT บน future_note เพิ่มเอง
SELECT note_id, message FROM lab_m4_xx.future_note;
-- END 4G.2
```

## 4H — Effective Permissions, Membership และ Ownership

**สไลด์ 35–36** — S ตรวจ privilege matrix, membership options, owner ของแต่ละตาราง และ RLS flags ใช้ Owner เฉพาะช่วงที่ต้อง resolve ชื่อ objects โดยไม่เปลี่ยน App ให้กลายเป็นเจ้าของ

### 4H.1 — ตรวจสิทธิ์ของ App และ Owner membership

**Connection S** · ค่าตามลำดับต้องเป็น true,true,false,true,false,false หลัง ROLLBACK ของ S current_user กลับเป็น student_xx

```sql
-- START 4H.1 | ตรวจสิทธิ์ของ App และ Owner membership
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง ROLLBACK; ใช้ Owner เพื่อ Resolve ชื่อตารางในการตรวจสิทธิ์
-- EXPECT: true, true, false, true, false, false ตามลำดับ
BEGIN;
SET LOCAL ROLE role_claimsure_owner_xx;
SELECT
    has_database_privilege('claim_app_xx', 'claimsure_xx', 'CONNECT')
        AS can_connect,
    has_schema_privilege('claim_app_xx', 'lab_m4_xx', 'USAGE')
        AS can_resolve_schema,
    has_schema_privilege('claim_app_xx', 'lab_m4_xx', 'CREATE')
        AS can_create_in_schema,
    has_table_privilege('claim_app_xx', 'lab_m4_xx.claim_secure', 'SELECT')
        AS can_read_claim,
    has_table_privilege('claim_app_xx', 'lab_m4_xx.claim_audit', 'DELETE')
        AS can_delete_audit,
    pg_has_role('claim_app_xx', 'role_claimsure_owner_xx', 'MEMBER')
        AS is_owner_member;
ROLLBACK;
-- END 4H.1
```

### 4H.2 — ตรวจ Membership และ Owner ของตาราง

**Connection S** · Membership ไม่มี ADMIN OPTION, ตารางเป็นของ Owner, claim_secure มี rls_enabled/force_rls=true; ตาราง policyholder/audit/future_note ไม่ได้เปิด RLS ตามไปด้วย

```sql
-- START 4H.2 | ตรวจ Membership และ Owner ของตาราง
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- EXPECT: Membership ไม่มี ADMIN; ตารางเป็นของ role_claimsure_owner_xx
-- claim_secure ต้องมี rls_enabled=true และ force_rls=true
SELECT r.rolname AS granted_role, m.rolname AS member,
       am.admin_option, am.inherit_option, am.set_option
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE shobj_description(m.oid, 'pg_authid') = 'Module 4 student xx'
ORDER BY member, granted_role;

SELECT c.relname, pg_get_userbyid(c.relowner) AS owner,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'lab_m4_xx' AND c.relkind = 'r'
ORDER BY c.relname;
-- END 4H.2
```

## สรุป Error และ Recovery ที่ต้องอยู่ใน Connection เดิม

| Expected error | Connection | สาเหตุ | Recovery |
| --- | --- | --- | --- |
| 4C.5 | B | ไม่มี CREATE บน schema | 4C.6 |
| 4D.3 | B | WITH CHECK ไม่ให้ INSERT tenant 202 | 4D.4 |
| 4E.3 | C | ไม่มี SELECT email/phone | 4E.4 |
| 4E.6 | D | ไม่มี UPDATE estimated_amount | 4E.7 |
| 4F.4 | B | ไม่มี DELETE audit | 4F.5 |

ทั้งหมดต้องเป็น **SQLSTATE 42501** หลัง error ภายใน transaction สถานะจะ failed คำสั่งธรรมดาถัดไปอาจได้ `25P02` จนกว่าจะรัน recovery `ROLLBACK` ใน connection เดิม ห้ามเปลี่ยนไป recover ที่ S/A เพราะจะไม่แก้ transaction ของ B/C/D

## หลักฐานที่ต้องเก็บตอนจบ

| รายการ | ผลที่ควรมีหลังทำครบหนึ่งรอบ |
| --- | --- |
| claim_secure | Seed สามแถว; SEC-101-001 เป็น UNDER_REVIEW จาก 4F.3 |
| SEC-C-ALLOWED / SEC-D-ALLOWED / SEC-D-DENIED | ไม่เหลือแถว เพราะ rollback หรือถูกปฏิเสธ |
| policyholder_secure | ข้อมูลจำลองหนึ่งแถว; C อ่านชื่อได้แต่ contact fields ไม่ได้ |
| claim_audit | มี UPDATE ของ claim_app_xx ที่ commit แล้ว |
| future_note | หนึ่งแถวที่ Owner สร้างหลังตั้ง default privileges |
| App effective privileges | CONNECT/USAGE/SELECT true; CREATE/DELETE audit/Owner membership false |
| claim_secure RLS | ENABLE และ FORCE เป็น true |
| Student / App / Manager / Auditor | ไม่มี SUPERUSER หรือ CREATEROLE |

บันทึก Login ที่ใช้, หมายเลข Block, ผล query และ SQLSTATE ของ expected errors โดยไม่บันทึก Passwords เก็บภาพหรือผล query ตามที่ Instructor กำหนด

**คำถามปิด Lab:** ทำไม S ยังเป็น student_xx หลัง SET LOCAL ROLE? ทำไม App รับ SELECT ผ่าน Write? ทำไม RLS ต้องมีทั้ง object grants และ policy? ทำไม C อ่านชื่อได้แต่ SELECT * ไม่ได้? ทำไม 4F.3 ต้อง COMMIT ก่อนให้ C อ่าน? Default privileges ของ Owner ให้สิทธิ์กับตารางเก่าได้หรือไม่?

## เริ่มรอบใหม่ — Reset เฉพาะเมื่อเลือกทิ้ง Lab

หลังจบเก็บ objects และผลตรวจไว้ได้ หากต้องการเริ่มใหม่ ให้ปิด S/B/C/D แล้วใช้ **A** เฉพาะสำหรับ reset ด้วยหมายเลขจริงของตน:

```bash
psql -X -W -h 127.0.0.1 -p 5432 -U postgres -d claimsure_xx \
  -v student_no=xx -v ON_ERROR_STOP=1 \
  -f labs/module04-security-th/04-security-user-management-reset.sql
```

Reset ที่คัดจากต้นทางตรวจ database, superuser, schema owner และขอบเขต objects ของ roles ก่อนใช้ `DROP OWNED ... RESTRICT` และลบเฉพาะ 11 roles ที่ระบุของ Module 4 หมายเลขนี้ ไม่ลบ database หรือ student_xx หากพบ dependencies นอกขอบเขตจะหยุด ไม่เปลี่ยนเป็น CASCADE เพื่อฝืนให้ลบผ่าน

อ่าน [Reset SQL](module04-security-th/04-security-user-management-reset.sql) ก่อนใช้ คำสั่งนี้ทิ้งตาราง ข้อมูล audit และ grants ของ Lab นี้ จึงไม่เป็นขั้นบังคับหลังทำเสร็จ

## ไฟล์ประกอบและสไลด์

- [สไลด์ภาษาไทยที่นำเข้าจากต้นทาง](../slides/module-04-security-user-management-th.md)
- [Pure SQL ต้นทางครบ 36 START/END blocks](module04-security-th/04-security-user-management.sql)
- [Reset ที่ตรวจขอบเขตก่อนลบ](module04-security-th/04-security-user-management-reset.sql)
- [ที่มาและ SHA-256 ของ Source](module04-security-th/upstream.json)
- [ผลการทดสอบ PostgreSQL 18](module04-security-th/VALIDATION.md)

เปิดสไลด์จาก root ของ repository:

```bash
make slides MODULE=4:th PORT=3046
```

บทนี้เป็น Lab แยก ไม่ถูกเพิ่มเข้า continuous runner `run-labs.sh run all` โดยอัตโนมัติ สไลด์และ Lab เวอร์ชันก่อนหน้ายังคงอยู่ตามเดิม

อ้างอิง: [PostgreSQL Privileges](https://www.postgresql.org/docs/18/ddl-priv.html), [Role Membership](https://www.postgresql.org/docs/18/role-membership.html), [RLS](https://www.postgresql.org/docs/18/ddl-rowsecurity.html), [Default Privileges](https://www.postgresql.org/docs/18/sql-alterdefaultprivileges.html)
