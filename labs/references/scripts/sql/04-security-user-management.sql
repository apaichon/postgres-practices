-- =============================================================================
-- MODULE 4: PURE SQL WALKTHROUGH — STUDENT xx — PostgreSQL 18
-- =============================================================================
-- วิธีใช้: เลือกรันทีละชุด ตั้งแต่ START <เลขขั้น> ถึง END <เลขขั้น>
-- อ่าน LOGIN ก่อนรันทุกชุด แล้วเปลี่ยน Connection ใน SQL editor ให้ตรง
-- ห้ามเลือก Execute All เพราะแต่ละชุดใช้ Login ต่างกัน และมี Expected error
-- ใช้ SQL editor ที่เปิด Auto-commit; แต่ละ Transaction ระบุ BEGIN/COMMIT ชัดเจน
--
-- Database ของทุก Connection: claimsure_xx (Host/Port เดียวกัน)
-- A = postgres             SUPERUSER: ใช้เฉพาะขั้น 0 และ Lab 4A
-- S = student_xx           ผู้ดูแล Lab ของตน: ใช้ตั้งแต่ 4B ถึง 4H
-- B = claim_app_xx         ผู้ใช้ปกติ: ทดสอบ Application
-- C = internal_auditor_xx  ผู้ใช้ปกติ: ทดสอบ Auditor
-- D = manager_th_xx        ผู้ใช้ปกติ: ทดสอบ Manager
--
-- postgres สร้าง Role, ตั้ง Password, สร้าง Schema, ให้ CONNECT/Membership
-- และมอบ SET ROLE ของ Owner ให้ student_xx ใน 4A.4 แล้วจบงานผู้ดูแลระบบ
-- student_xx ไม่มี SUPERUSER/CREATEROLE และไม่ต้องได้รับสิทธิ์เพิ่มทั้ง Cluster
-- claimsure_owner_xx เป็น NOLOGIN: S ใช้ SET LOCAL ROLE เพื่อทำ DDL ในนาม Owner
-- student_xx เป็นผู้ดูแล Object ของ Lab; App/Manager/Auditor ไม่มี Owner membership
--
-- Lab      Login ที่ใช้                 สิ่งที่ทำ
-- 0, 4A    postgres                    Bootstrap และมอบสิทธิ์ให้ student_xx
-- 4B       student_xx -> Owner         สร้าง Table และ Seed ใน Schema ที่เตรียมไว้
-- 4C       student_xx / claim_app_xx    ให้ Object grants และทดสอบ App
-- 4D       student_xx / claim_app_xx    ตั้ง RLS และทดสอบ Tenant
-- 4E       student_xx / Auditor/Manager จำกัด Column และทดสอบสอง Login
-- 4F       student_xx / App / Auditor  สร้าง Routine/Trigger และตรวจ Audit
-- 4G       student_xx / claim_app_xx    ตั้ง Default privileges และอ่าน Table ใหม่
-- 4H       student_xx                  ตรวจสิทธิ์ Membership และ Ownership
--
-- ลำดับ: 0 -> 4A -> 4B -> 4C -> 4D -> 4E -> 4F -> 4G -> 4H
-- ก่อนรัน: แทน xx ทุกแห่งด้วยเลขนักเรียนสองหลักของตน และเปลี่ยน marker
-- 'Module 4 student xx' ให้ตรงกันด้วย ใช้ชื่อลงท้ายเดียวกันตลอดไฟล์
--
-- เริ่มจาก Role/Schema ของ Module 4 ที่ยังไม่มี หากเคยรันมาก่อน ให้ใช้ไฟล์
-- 04-security-user-management-reset.sql ตามคู่มือเพื่อเริ่มใหม่ก่อน
-- ไฟล์นี้ตั้งใจใช้ CREATE ROLE/CREATE TABLE ตรง ๆ เพื่อให้เห็นขั้นตอน
-- ไม่มี psql variables, metacommands, dynamic SQL หรือการเปลี่ยน Login อัตโนมัติ
--
-- LOGIN != current_user:
--   S ปกติ: session_user = current_user = student_xx
--   S หลัง SET LOCAL ROLE Owner: session_user=student_xx; current_user=Owner
--   S หลัง COMMIT/ROLLBACK: current_user กลับเป็น student_xx
--   B/C/D: session_user และ current_user เป็น Login ของตนจริง
--
-- เมื่อเจอ Expected error ให้รันชุด RECOVERY ที่อยู่ถัดไปทันที
-- ถ้าเจอ Error อื่น: หยุด ตรวจ Login แล้ว ROLLBACK ก่อนลองใหม่
-- =============================================================================


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


-- =============================================================================
-- LAB 4A: สร้าง Role ให้ครบก่อนให้สิทธิ์
-- =============================================================================

-- START 4A.1 | สร้าง Owner, Group และ Login
-- LOGIN: A = postgres (SUPERUSER)
-- RUN: ตั้งแต่ BEGIN ถึง COMMIT รวม COMMENT ON ROLE ทั้งหมด
-- EXPECT: สร้าง 11 Role; ยังไม่มีสิทธิ์ Table
BEGIN;

CREATE ROLE claimsure_owner_xx NOLOGIN;
CREATE ROLE claimsure_read_xx NOLOGIN;
CREATE ROLE claimsure_write_xx NOLOGIN;
CREATE ROLE claimsure_approve_xx NOLOGIN;
CREATE ROLE claimsure_audit_xx NOLOGIN;

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
COMMENT ON ROLE claimsure_owner_xx IS 'Module 4 student xx';
COMMENT ON ROLE claimsure_read_xx IS 'Module 4 student xx';
COMMENT ON ROLE claimsure_write_xx IS 'Module 4 student xx';
COMMENT ON ROLE claimsure_approve_xx IS 'Module 4 student xx';
COMMENT ON ROLE claimsure_audit_xx IS 'Module 4 student xx';
COMMENT ON ROLE claim_app_xx IS 'Module 4 student xx';
COMMENT ON ROLE adjuster_bkk_xx IS 'Module 4 student xx';
COMMENT ON ROLE manager_th_xx IS 'Module 4 student xx';
COMMENT ON ROLE internal_auditor_xx IS 'Module 4 student xx';
COMMENT ON ROLE claim_monitor_xx IS 'Module 4 student xx';
COMMENT ON ROLE claim_dba_xx IS 'Module 4 student xx';

COMMIT;
-- END 4A.1


-- START 4A.2 | ตรวจ Role ที่เพิ่งสร้าง
-- LOGIN: A = postgres (SUPERUSER)
-- EXPECT: 11 แถว; Owner/Groups เป็น NOLOGIN; Runtime roles ไม่มีสิทธิ์พิเศษ
SELECT rolname, rolcanlogin, rolsuper, rolcreaterole, rolbypassrls
FROM pg_roles
WHERE shobj_description(oid, 'pg_authid') = 'Module 4 student xx'
ORDER BY rolname;
-- END 4A.2


-- START 4A.3 | ตั้ง Password สำหรับ Connection B/C/D
-- LOGIN: A = postgres (SUPERUSER)
-- BEFORE RUN: แก้ CHANGE_ME_* ให้เป็น Password ที่จะใช้จริงก่อนเลือก Execute
-- Password ด้านล่างเป็น Placeholder ไม่ใช่ Password ของ Server
-- RUN: ALTER ROLE ทั้งสามคำสั่ง ยังไม่ต้องเปิด B/C/D จนกว่าจะจบ 4A.4
ALTER ROLE claim_app_xx PASSWORD 'change_me_app_xx';
ALTER ROLE internal_auditor_xx PASSWORD 'change_me_auditor_xx';
ALTER ROLE manager_th_xx PASSWORD 'change_me_manager_xx';
-- END 4A.3


-- START 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย
-- LOGIN: A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres
-- PREREQUISITE: มี student_xx จากระบบชั้นเรียน และสร้าง Role ใน 4A.1 ครบแล้ว
-- RUN: BEGIN ถึง COMMIT ทั้งชุด แล้วจึงเปิด Connection S เป็น student_xx
-- Group membership ให้ไว้ก่อน แต่ Group ยังไม่มี Table privileges จนถึง 4C
BEGIN;
CREATE SCHEMA IF NOT EXISTS lab_m4_xx AUTHORIZATION claimsure_owner_xx;

GRANT claimsure_owner_xx TO student_xx
WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;

GRANT CONNECT ON DATABASE claimsure_xx
TO student_xx, claim_app_xx, adjuster_bkk_xx,
   manager_th_xx, internal_auditor_xx;

GRANT claimsure_read_xx TO claimsure_write_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
GRANT claimsure_write_xx TO claim_app_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
GRANT claimsure_read_xx TO adjuster_bkk_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
GRANT claimsure_approve_xx TO manager_th_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
GRANT claimsure_audit_xx TO internal_auditor_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
COMMIT;
-- จบงาน postgres: ต่อจากนี้ใช้ Connection S/B/C/D ตาม LOGIN ของแต่ละชุด
-- INHERIT FALSE ไม่ให้ Owner privileges ติดกับ student_xx โดยอัตโนมัติ
-- SET TRUE อนุญาตให้ student_xx เปลี่ยนเป็น Owner อย่างชัดเจนเมื่อทำ DDL
-- END 4A.4


-- =============================================================================
-- LAB 4B: student_xx ใช้ Owner สร้าง Table ใน Schema ที่เตรียมแล้ว
-- =============================================================================

-- START 4B.1 | เปิด Connection S ตรวจสิทธิ์ที่ได้รับ แล้วใช้ Owner
-- LOGIN: S = student_xx (ผู้ใช้ปกติ); เปิด Connection ใหม่ด้วย Login นักเรียนเดิม
-- DATABASE: claimsure_xx; ต้องทำ 4A.4 โดย postgres มาก่อน
-- RUN: SELECT ก่อน ต้องได้ can_set_owner=true, is_superuser=false,
--      owns_schema_exists=true แล้วจึงรัน BEGIN..COMMIT
-- หาก can_set_owner=false ให้กลับไปทำ 4A.4 ไม่ต้องให้ SUPERUSER กับ student_xx
SELECT session_user, current_user,
       rolsuper AS is_superuser,
       pg_has_role(session_user, 'claimsure_owner_xx', 'SET') AS can_set_owner,
       EXISTS (
           SELECT 1 FROM pg_namespace
           WHERE nspname = 'lab_m4_xx'
             AND pg_get_userbyid(nspowner) = 'claimsure_owner_xx'
       ) AS owns_schema_exists
FROM pg_roles WHERE rolname = current_user;

BEGIN;
SET LOCAL ROLE claimsure_owner_xx;
REVOKE ALL ON SCHEMA lab_m4_xx FROM PUBLIC;
SELECT session_user, current_user;
COMMIT;
-- หลัง COMMIT Connection S กลับเป็น student_xx
-- END 4B.1


-- START 4B.2 | สร้าง Table ทั้งสามในนาม Owner
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- EFFECTIVE ROLE ภายใน Transaction: claimsure_owner_xx
-- RUN: BEGIN ถึง COMMIT ทั้งชุด
-- EXPECT: Table/Sequence เป็นของ Owner; ยังไม่เปิด RLS
BEGIN;
SET LOCAL ROLE claimsure_owner_xx;

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


-- START 4B.3 | เพิ่มข้อมูลตั้งต้น
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner
-- RUN: BEGIN ถึง COMMIT
-- EXPECT: Tenant 101 สองเคลม และ Tenant 202 หนึ่งเคลม
BEGIN;
SET LOCAL ROLE claimsure_owner_xx;

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


-- =============================================================================
-- LAB 4C: CONNECT -> Object privileges -> Membership -> App tests
-- =============================================================================

-- START 4C.1 | ตรวจ CONNECT ที่ postgres ให้ไว้แล้วใน 4A.4
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- EXPECT: app_can_connect=true; CONNECT ไม่ได้ให้สิทธิ์ Table
SELECT has_database_privilege('claim_app_xx', 'claimsure_xx', 'CONNECT')
       AS app_can_connect;
-- PUBLIC อาจมี CONNECT อยู่ก่อนแล้ว Lab ไม่เปลี่ยนสิทธิ์ Database ของส่วนรวม
-- END 4C.1


-- START 4C.2 | ให้สิทธิ์ Object กับ Group
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner
-- EXPECT: Read group ได้ SELECT; Write group ได้ INSERT/UPDATE
BEGIN;
SET LOCAL ROLE claimsure_owner_xx;

GRANT USAGE ON SCHEMA lab_m4_xx
TO claimsure_read_xx, claimsure_write_xx,
   claimsure_approve_xx, claimsure_audit_xx;

GRANT SELECT ON lab_m4_xx.claim_secure TO claimsure_read_xx;
GRANT INSERT, UPDATE ON lab_m4_xx.claim_secure TO claimsure_write_xx;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA lab_m4_xx TO claimsure_write_xx;

COMMIT;
-- Sequence grant เป็นสิทธิ์แยกสำหรับการใช้ Sequence โดยตรง/Default ที่ต้องใช้
-- การ INSERT Column แบบ IDENTITY ในตัวอย่างนี้ไม่ได้พิสูจน์ว่าจำเป็นต้องมี grant นี้
-- END 4C.2


-- START 4C.3 | ตรวจ Membership ที่ postgres เตรียมใน 4A.4
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- EXPECT: App รับ Write -> Read; ไม่มี Owner membership และ ADMIN เป็น false
-- หลัง 4C.2 Group จึงมี Object privileges ให้ Login ใช้ผ่าน Membership ได้
SELECT r.rolname AS group_role, m.rolname AS member,
       am.inherit_option, am.set_option, am.admin_option
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE m.rolname IN ('claimsure_write_xx', 'claim_app_xx', 'adjuster_bkk_xx',
                   'manager_th_xx', 'internal_auditor_xx')
ORDER BY member, group_role;
-- END 4C.3


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


-- START 4C.5 | EXPECTED ERROR: App สร้าง Table ไม่ได้
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN และ CREATE TABLE; EXPECT: SQLSTATE 42501 / permission denied
-- เมื่อเห็น Error ให้เลือกชุด 4C.6 แยกต่างหากทันที
BEGIN;
CREATE TABLE lab_m4_xx.owned_by_app (id integer);
-- END 4C.5


-- START 4C.6 | RECOVERY หลัง Expected error ของ 4C.5
-- LOGIN: B = claim_app_xx (Connection เดิม)
-- RUN: ROLLBACK หนึ่งคำสั่ง เพื่อออกจาก Transaction aborted
ROLLBACK;
-- END 4C.6


-- =============================================================================
-- LAB 4D: Owner เพิ่ม RLS; App ทดสอบ Tenant
-- =============================================================================

-- START 4D.1 | เปิด RLS และสร้าง Policy บนตารางเดิม
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน); กลับมาที่ Connection S
-- RUN: BEGIN ถึง COMMIT; EFFECTIVE ROLE: Owner
BEGIN;
SET LOCAL ROLE claimsure_owner_xx;

ALTER TABLE lab_m4_xx.claim_secure ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_m4_xx.claim_secure FORCE ROW LEVEL SECURITY;

CREATE POLICY claim_tenant_access ON lab_m4_xx.claim_secure
TO claimsure_read_xx, claimsure_write_xx,
   claimsure_approve_xx, claimsure_owner_xx
USING (
    tenant_id = nullif(current_setting('app.tenant_id', true), '')::bigint
)
WITH CHECK (
    tenant_id = nullif(current_setting('app.tenant_id', true), '')::bigint
);
COMMIT;
-- Owner อยู่ใน Policy เพราะ Count function ของ 4F ทำงานเป็น Owner ตาม FORCE RLS
-- END 4D.1


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


-- START 4D.4 | RECOVERY หลัง Expected error ของ 4D.3
-- LOGIN: B = claim_app_xx (Connection เดิม)
ROLLBACK;
-- END 4D.4


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


-- =============================================================================
-- LAB 4E: จำกัด Column ให้ Auditor และ Manager
-- =============================================================================

-- START 4E.1 | Owner ให้สิทธิ์ Column กับ Group ที่มีอยู่แล้ว
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง COMMIT
BEGIN;
SET LOCAL ROLE claimsure_owner_xx;

REVOKE SELECT ON lab_m4_xx.policyholder_secure FROM claimsure_audit_xx;
GRANT SELECT (policyholder_id, tenant_id, full_name)
ON lab_m4_xx.policyholder_secure TO claimsure_audit_xx;

GRANT SELECT ON lab_m4_xx.claim_secure TO claimsure_approve_xx;
REVOKE UPDATE ON lab_m4_xx.claim_secure FROM claimsure_approve_xx;
GRANT UPDATE (status, updated_at)
ON lab_m4_xx.claim_secure TO claimsure_approve_xx;

COMMIT;
-- END 4E.1


-- START 4E.2 | เปิด Connection C เป็น Auditor แล้วอ่านชื่อ
-- LOGIN: C = internal_auditor_xx (ผู้ใช้ปกติ)
-- CONNECTION: เปิดใหม่ด้วย Password จาก 4A.3; DATABASE: claimsure_xx
-- EXPECT: ผู้ใช้ทั้งสองเป็น internal_auditor_xx และอ่านชื่อได้
SELECT session_user, current_user;
SELECT policyholder_id, tenant_id, full_name
FROM lab_m4_xx.policyholder_secure;
-- END 4E.2


-- START 4E.3 | EXPECTED ERROR: Auditor อ่าน Contact fields ไม่ได้
-- LOGIN: C = internal_auditor_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง SELECT; EXPECT: SQLSTATE 42501; แล้วรัน 4E.4
BEGIN;
SELECT email, phone FROM lab_m4_xx.policyholder_secure;
-- END 4E.3


-- START 4E.4 | RECOVERY หลัง Expected error ของ 4E.3
-- LOGIN: C = internal_auditor_xx (Connection เดิม)
ROLLBACK;
-- END 4E.4


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


-- START 4E.6 | EXPECTED ERROR: Manager แก้จำนวนเงินไม่ได้
-- LOGIN: D = manager_th_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง UPDATE; EXPECT: SQLSTATE 42501; แล้วรัน 4E.7
BEGIN;
SELECT set_config('app.tenant_id', '101', true);
UPDATE lab_m4_xx.claim_secure
SET estimated_amount = 1
WHERE claim_no = 'SEC-101-001';
-- END 4E.6


-- START 4E.7 | RECOVERY หลัง Expected error ของ 4E.6
-- LOGIN: D = manager_th_xx (Connection เดิม)
ROLLBACK;
-- END 4E.7


-- =============================================================================
-- LAB 4F: Controlled function, Trigger และ Audit
-- =============================================================================

-- START 4F.1 | Owner สร้าง Count function ก่อนให้ EXECUTE
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง COMMIT ทั้งชุด รวม Function body ระหว่าง $function$
BEGIN;
SET LOCAL ROLE claimsure_owner_xx;

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
TO claimsure_read_xx;
COMMIT;
-- SECURITY DEFINER ใช้สิทธิ์ Owner ภายใน Function และคืน Role ให้ผู้เรียกเมื่อจบ
-- END 4F.1


-- START 4F.2 | Owner สร้าง Audit function และ Trigger
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง COMMIT ทั้งชุด ห้ามเลือกเพียงบางบรรทัดใน Function body
BEGIN;
SET LOCAL ROLE claimsure_owner_xx;

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
FROM claimsure_write_xx, claimsure_approve_xx, PUBLIC;
GRANT SELECT ON lab_m4_xx.claim_audit TO claimsure_audit_xx;
COMMIT;
-- END 4F.2


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


-- START 4F.4 | EXPECTED ERROR: App ลบ Audit ไม่ได้
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง DELETE; EXPECT: SQLSTATE 42501; แล้วรัน 4F.5
BEGIN;
DELETE FROM lab_m4_xx.claim_audit;
-- END 4F.4


-- START 4F.5 | RECOVERY หลัง Expected error ของ 4F.4
-- LOGIN: B = claim_app_xx (Connection เดิม)
ROLLBACK;
-- END 4F.5


-- START 4F.6 | Auditor อ่านหลักฐานจาก App connection จริง
-- LOGIN: C = internal_auditor_xx (ผู้ใช้ปกติ)
-- EXPECT: actor=claim_app_xx, operation=UPDATE
-- role_setting มักเป็น 'none' เพราะ B Login เป็น App จริง ไม่ได้ใช้ SET ROLE
SELECT event_time, actor, role_setting, operation, claim_id
FROM lab_m4_xx.claim_audit
ORDER BY audit_id DESC
LIMIT 5;
-- END 4F.6


-- =============================================================================
-- LAB 4G: Default privileges สำหรับ Object ที่ Owner จะสร้าง
-- =============================================================================

-- START 4G.1 | ตั้ง Defaults แล้วสร้าง Table ในนาม Owner เดียวกัน
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง COMMIT
BEGIN;
SET LOCAL ROLE claimsure_owner_xx;

ALTER DEFAULT PRIVILEGES IN SCHEMA lab_m4_xx
GRANT SELECT ON TABLES TO claimsure_read_xx;
ALTER DEFAULT PRIVILEGES IN SCHEMA lab_m4_xx
GRANT USAGE ON SEQUENCES TO claimsure_write_xx;

CREATE TABLE lab_m4_xx.future_note (
    note_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message text NOT NULL
);
INSERT INTO lab_m4_xx.future_note (message)
VALUES ('Created by claimsure_owner_xx after default privileges were configured');

COMMIT;
-- Defaults ไม่ย้อนให้สิทธิ์ Table เก่า และไม่สร้าง RLS ให้ Table ใหม่
-- พิจารณาแยก Schema หาก Table อนาคตไม่ควรให้ Read group อ่าน
-- END 4G.1


-- START 4G.2 | App อ่าน Table ใหม่ได้ผ่าน Write -> Read membership
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- EXPECT: ได้หนึ่งแถว โดยไม่ต้อง GRANT SELECT บน future_note เพิ่มเอง
SELECT note_id, message FROM lab_m4_xx.future_note;
-- END 4G.2


-- =============================================================================
-- LAB 4H: student_xx ตรวจสิทธิ์ที่มีผลจริงและ Ownership
-- =============================================================================

-- START 4H.1 | ตรวจสิทธิ์ของ App และ Owner membership
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง ROLLBACK; ใช้ Owner เพื่อ Resolve ชื่อตารางในการตรวจสิทธิ์
-- EXPECT: true, true, false, true, false, false ตามลำดับ
BEGIN;
SET LOCAL ROLE claimsure_owner_xx;
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
    pg_has_role('claim_app_xx', 'claimsure_owner_xx', 'MEMBER')
        AS is_owner_member;
ROLLBACK;
-- END 4H.1


-- START 4H.2 | ตรวจ Membership และ Owner ของตาราง
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- EXPECT: Membership ไม่มี ADMIN; ตารางเป็นของ claimsure_owner_xx
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


-- จบ Module 4 แบบ Pure SQL
-- ผลที่ควรเข้าใจ: สร้างตัวตนก่อน -> ให้ Object privileges -> ให้ Membership
-- -> ทดสอบด้วย Login ปกติ -> จำกัด Row/Column -> ปกป้อง Routine/Audit
-- ถ้าต้องการเริ่มใหม่ ใช้ Reset ของ Module 4 นักเรียน xx แล้วทำตั้งแต่ 0 อีกครั้ง
