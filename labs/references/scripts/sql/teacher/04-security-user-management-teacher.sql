-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 04-security-user-management.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/04-security-user-management.sql
-- @teacher LOGIN / DATABASE เริ่มต้น: postgres | claimsure_xx; เปลี่ยนตาม LOGIN ของแต่ละ START block
-- @teacher อ่าน README.md ใน Directory นี้ก่อนสอน; ใช้ไฟล์นี้เป็นคู่มือเลือกรันทีละส่วน
-- @teacher แต่ละ SQL มี START/END, Lab, Login, เหตุผล และผลที่ต้องสังเกต; Source Line อ้างไฟล์ต้นฉบับ
-- @teacher START/END ราย SQL ใช้ค้นคำอธิบาย ไม่ใช่ขอบเขต Commit: Transaction/Function ต้องรันครบชุด
-- @teacher คำสั่ง psql ขึ้นต้นด้วย Backslash; SQL Editor ทั่วไปให้ข้ามและจัด Branch/Variables เอง
-- @teacher ทุกบรรทัดที่เพิ่มขึ้นต้น -- @teacher; SQL/psql ต้นฉบับคงเดิม รวมคำสั่งเปลี่ยนข้อมูลและ Expected Errors
-- @teacher เป้าหมาย: Identity → Group Privileges → RLS → Column Grants → Audit → Default Privileges
-- @teacher Pure SQL: แทน xx ทุกจุดด้วยเลขเดียวกัน เช่น 03; student_xx/claimsure_xx ต้องมีอยู่แล้ว
-- @teacher A=postgres เฉพาะ 0/4A; S=student_xx ใช้ SET LOCAL ROLE owner; B=claim_app_xx; C=internal_auditor_xx; D=manager_th_xx
-- @teacher ห้าม Execute All: มีการสลับ Login และ Expected Errors; รันครบ START/END ของต้นฉบับทีละขั้น
-- @teacher ตั้ง Password ที่ใช้จริงก่อน Connection B/C/D; change_me_* เป็น Placeholder ไม่ใช่ Password มาตรฐาน
-- @teacher หาก can_set_owner=false ให้ postgres ทำ 4A.4 ให้ครบ; student_xx ไม่ต้องได้ SUPERUSER/CREATEROLE
-- @teacher Expected Errors: SQL075/090/107/116/138; อ่านเหตุผลแล้วรัน ROLLBACK ใน Recovery block ถัดไป
-- @teacher ==============================================================================
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
-- @teacher [START 04-SQL001] Lab 0 | ตรวจ Connection ก่อนสร้างสิ่งใด
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | DATABASE: claimsure_xx
-- @teacher อธิบาย: ตรวจ Database/Login/Effective User และเวอร์ชันก่อน Bootstrap Roles
-- @teacher ผล/ชวนสังเกต: ต้องได้ correct_database/administrator/postgresql_18=true; แทน xx ทุกแห่งให้ตรงเลขผู้เรียนก่อนรัน
-- @teacher SOURCE: 04-security-user-management.sql:57 | รัน SQL นี้ครบทั้ง Statement
SELECT current_database() AS database_name,
       session_user AS login_user,
       current_user AS effective_user,
       current_database() = 'claimsure_xx' AS correct_database,
       current_user = session_user AND rolsuper AS administrator,
       current_setting('server_version_num')::int >= 180000 AS postgresql_18
FROM pg_roles
WHERE rolname = current_user;
-- @teacher [END 04-SQL001]
-- END 0


-- =============================================================================
-- LAB 4A: สร้าง Role ให้ครบก่อนให้สิทธิ์
-- =============================================================================

-- START 4A.1 | สร้าง Owner, Group และ Login
-- LOGIN: A = postgres (SUPERUSER)
-- RUN: ตั้งแต่ BEGIN ถึง COMMIT รวม COMMENT ON ROLE ทั้งหมด
-- EXPECT: สร้าง 11 Role; ยังไม่มีสิทธิ์ Table
-- @teacher [START 04-SQL002] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:76 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL002]

-- @teacher [START 04-SQL003] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: สร้าง Role claimsure_owner_xx เป็น Owner/Capability Group แบบ NOLOGIN
-- @teacher ผล/ชวนสังเกต: รันเป็น postgres ใน 4A เท่านั้น; Role เป็นระดับ Cluster ใช้ xx ไม่ซ้ำ; สร้าง Role ยังไม่ให้สิทธิ์ Table หรือ Membership
-- @teacher SOURCE: 04-security-user-management.sql:78 | รัน SQL นี้ครบทั้ง Statement
CREATE ROLE claimsure_owner_xx NOLOGIN;
-- @teacher [END 04-SQL003]
-- @teacher [START 04-SQL004] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: สร้าง Role claimsure_read_xx เป็น Owner/Capability Group แบบ NOLOGIN
-- @teacher ผล/ชวนสังเกต: รันเป็น postgres ใน 4A เท่านั้น; Role เป็นระดับ Cluster ใช้ xx ไม่ซ้ำ; สร้าง Role ยังไม่ให้สิทธิ์ Table หรือ Membership
-- @teacher SOURCE: 04-security-user-management.sql:79 | รัน SQL นี้ครบทั้ง Statement
CREATE ROLE claimsure_read_xx NOLOGIN;
-- @teacher [END 04-SQL004]
-- @teacher [START 04-SQL005] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: สร้าง Role claimsure_write_xx เป็น Owner/Capability Group แบบ NOLOGIN
-- @teacher ผล/ชวนสังเกต: รันเป็น postgres ใน 4A เท่านั้น; Role เป็นระดับ Cluster ใช้ xx ไม่ซ้ำ; สร้าง Role ยังไม่ให้สิทธิ์ Table หรือ Membership
-- @teacher SOURCE: 04-security-user-management.sql:80 | รัน SQL นี้ครบทั้ง Statement
CREATE ROLE claimsure_write_xx NOLOGIN;
-- @teacher [END 04-SQL005]
-- @teacher [START 04-SQL006] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: สร้าง Role claimsure_approve_xx เป็น Owner/Capability Group แบบ NOLOGIN
-- @teacher ผล/ชวนสังเกต: รันเป็น postgres ใน 4A เท่านั้น; Role เป็นระดับ Cluster ใช้ xx ไม่ซ้ำ; สร้าง Role ยังไม่ให้สิทธิ์ Table หรือ Membership
-- @teacher SOURCE: 04-security-user-management.sql:81 | รัน SQL นี้ครบทั้ง Statement
CREATE ROLE claimsure_approve_xx NOLOGIN;
-- @teacher [END 04-SQL006]
-- @teacher [START 04-SQL007] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: สร้าง Role claimsure_audit_xx เป็น Owner/Capability Group แบบ NOLOGIN
-- @teacher ผล/ชวนสังเกต: รันเป็น postgres ใน 4A เท่านั้น; Role เป็นระดับ Cluster ใช้ xx ไม่ซ้ำ; สร้าง Role ยังไม่ให้สิทธิ์ Table หรือ Membership
-- @teacher SOURCE: 04-security-user-management.sql:82 | รัน SQL นี้ครบทั้ง Statement
CREATE ROLE claimsure_audit_xx NOLOGIN;
-- @teacher [END 04-SQL007]

-- @teacher [START 04-SQL008] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: สร้าง Role claim_app_xx เป็น Login ที่ไม่มีสิทธิ์ Superuser/CREATEDB/CREATEROLE/BYPASSRLS
-- @teacher ผล/ชวนสังเกต: รันเป็น postgres ใน 4A เท่านั้น; Role เป็นระดับ Cluster ใช้ xx ไม่ซ้ำ; สร้าง Role ยังไม่ให้สิทธิ์ Table หรือ Membership
-- @teacher SOURCE: 04-security-user-management.sql:84 | รัน SQL นี้ครบทั้ง Statement
CREATE ROLE claim_app_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
-- @teacher [END 04-SQL008]
-- @teacher [START 04-SQL009] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: สร้าง Role adjuster_bkk_xx เป็น Login ที่ไม่มีสิทธิ์ Superuser/CREATEDB/CREATEROLE/BYPASSRLS
-- @teacher ผล/ชวนสังเกต: รันเป็น postgres ใน 4A เท่านั้น; Role เป็นระดับ Cluster ใช้ xx ไม่ซ้ำ; สร้าง Role ยังไม่ให้สิทธิ์ Table หรือ Membership
-- @teacher SOURCE: 04-security-user-management.sql:86 | รัน SQL นี้ครบทั้ง Statement
CREATE ROLE adjuster_bkk_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
-- @teacher [END 04-SQL009]
-- @teacher [START 04-SQL010] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: สร้าง Role manager_th_xx เป็น Login ที่ไม่มีสิทธิ์ Superuser/CREATEDB/CREATEROLE/BYPASSRLS
-- @teacher ผล/ชวนสังเกต: รันเป็น postgres ใน 4A เท่านั้น; Role เป็นระดับ Cluster ใช้ xx ไม่ซ้ำ; สร้าง Role ยังไม่ให้สิทธิ์ Table หรือ Membership
-- @teacher SOURCE: 04-security-user-management.sql:88 | รัน SQL นี้ครบทั้ง Statement
CREATE ROLE manager_th_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
-- @teacher [END 04-SQL010]
-- @teacher [START 04-SQL011] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: สร้าง Role internal_auditor_xx เป็น Login ที่ไม่มีสิทธิ์ Superuser/CREATEDB/CREATEROLE/BYPASSRLS
-- @teacher ผล/ชวนสังเกต: รันเป็น postgres ใน 4A เท่านั้น; Role เป็นระดับ Cluster ใช้ xx ไม่ซ้ำ; สร้าง Role ยังไม่ให้สิทธิ์ Table หรือ Membership
-- @teacher SOURCE: 04-security-user-management.sql:90 | รัน SQL นี้ครบทั้ง Statement
CREATE ROLE internal_auditor_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
-- @teacher [END 04-SQL011]
-- @teacher [START 04-SQL012] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: สร้าง Role claim_monitor_xx เป็น Login ที่ไม่มีสิทธิ์ Superuser/CREATEDB/CREATEROLE/BYPASSRLS
-- @teacher ผล/ชวนสังเกต: รันเป็น postgres ใน 4A เท่านั้น; Role เป็นระดับ Cluster ใช้ xx ไม่ซ้ำ; สร้าง Role ยังไม่ให้สิทธิ์ Table หรือ Membership
-- @teacher SOURCE: 04-security-user-management.sql:92 | รัน SQL นี้ครบทั้ง Statement
CREATE ROLE claim_monitor_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
-- @teacher [END 04-SQL012]
-- @teacher [START 04-SQL013] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: สร้าง Role claim_dba_xx เป็น Login ที่ไม่มีสิทธิ์ Superuser/CREATEDB/CREATEROLE/BYPASSRLS
-- @teacher ผล/ชวนสังเกต: รันเป็น postgres ใน 4A เท่านั้น; Role เป็นระดับ Cluster ใช้ xx ไม่ซ้ำ; สร้าง Role ยังไม่ให้สิทธิ์ Table หรือ Membership
-- @teacher SOURCE: 04-security-user-management.sql:94 | รัน SQL นี้ครบทั้ง Statement
CREATE ROLE claim_dba_xx
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
-- @teacher [END 04-SQL013]

-- Marker ช่วยระบุว่า Role เป็นของ Module 4 และเลขนักเรียนนี้
-- @teacher [START 04-SQL014] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ติดป้าย Module/Student ให้ claimsure_owner_xx เพื่อค้นหา Roles ของ Lab รอบนี้
-- @teacher ผล/ชวนสังเกต: เป็น Metadata ไม่เพิ่ม Permissions; 4A.2 ใช้ Marker นี้ตรวจว่ามีครบ 11 Roles
-- @teacher SOURCE: 04-security-user-management.sql:98 | รัน SQL นี้ครบทั้ง Statement
COMMENT ON ROLE claimsure_owner_xx IS 'Module 4 student xx';
-- @teacher [END 04-SQL014]
-- @teacher [START 04-SQL015] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ติดป้าย Module/Student ให้ claimsure_read_xx เพื่อค้นหา Roles ของ Lab รอบนี้
-- @teacher ผล/ชวนสังเกต: เป็น Metadata ไม่เพิ่ม Permissions; 4A.2 ใช้ Marker นี้ตรวจว่ามีครบ 11 Roles
-- @teacher SOURCE: 04-security-user-management.sql:99 | รัน SQL นี้ครบทั้ง Statement
COMMENT ON ROLE claimsure_read_xx IS 'Module 4 student xx';
-- @teacher [END 04-SQL015]
-- @teacher [START 04-SQL016] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ติดป้าย Module/Student ให้ claimsure_write_xx เพื่อค้นหา Roles ของ Lab รอบนี้
-- @teacher ผล/ชวนสังเกต: เป็น Metadata ไม่เพิ่ม Permissions; 4A.2 ใช้ Marker นี้ตรวจว่ามีครบ 11 Roles
-- @teacher SOURCE: 04-security-user-management.sql:100 | รัน SQL นี้ครบทั้ง Statement
COMMENT ON ROLE claimsure_write_xx IS 'Module 4 student xx';
-- @teacher [END 04-SQL016]
-- @teacher [START 04-SQL017] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ติดป้าย Module/Student ให้ claimsure_approve_xx เพื่อค้นหา Roles ของ Lab รอบนี้
-- @teacher ผล/ชวนสังเกต: เป็น Metadata ไม่เพิ่ม Permissions; 4A.2 ใช้ Marker นี้ตรวจว่ามีครบ 11 Roles
-- @teacher SOURCE: 04-security-user-management.sql:101 | รัน SQL นี้ครบทั้ง Statement
COMMENT ON ROLE claimsure_approve_xx IS 'Module 4 student xx';
-- @teacher [END 04-SQL017]
-- @teacher [START 04-SQL018] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ติดป้าย Module/Student ให้ claimsure_audit_xx เพื่อค้นหา Roles ของ Lab รอบนี้
-- @teacher ผล/ชวนสังเกต: เป็น Metadata ไม่เพิ่ม Permissions; 4A.2 ใช้ Marker นี้ตรวจว่ามีครบ 11 Roles
-- @teacher SOURCE: 04-security-user-management.sql:102 | รัน SQL นี้ครบทั้ง Statement
COMMENT ON ROLE claimsure_audit_xx IS 'Module 4 student xx';
-- @teacher [END 04-SQL018]
-- @teacher [START 04-SQL019] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ติดป้าย Module/Student ให้ claim_app_xx เพื่อค้นหา Roles ของ Lab รอบนี้
-- @teacher ผล/ชวนสังเกต: เป็น Metadata ไม่เพิ่ม Permissions; 4A.2 ใช้ Marker นี้ตรวจว่ามีครบ 11 Roles
-- @teacher SOURCE: 04-security-user-management.sql:103 | รัน SQL นี้ครบทั้ง Statement
COMMENT ON ROLE claim_app_xx IS 'Module 4 student xx';
-- @teacher [END 04-SQL019]
-- @teacher [START 04-SQL020] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ติดป้าย Module/Student ให้ adjuster_bkk_xx เพื่อค้นหา Roles ของ Lab รอบนี้
-- @teacher ผล/ชวนสังเกต: เป็น Metadata ไม่เพิ่ม Permissions; 4A.2 ใช้ Marker นี้ตรวจว่ามีครบ 11 Roles
-- @teacher SOURCE: 04-security-user-management.sql:104 | รัน SQL นี้ครบทั้ง Statement
COMMENT ON ROLE adjuster_bkk_xx IS 'Module 4 student xx';
-- @teacher [END 04-SQL020]
-- @teacher [START 04-SQL021] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ติดป้าย Module/Student ให้ manager_th_xx เพื่อค้นหา Roles ของ Lab รอบนี้
-- @teacher ผล/ชวนสังเกต: เป็น Metadata ไม่เพิ่ม Permissions; 4A.2 ใช้ Marker นี้ตรวจว่ามีครบ 11 Roles
-- @teacher SOURCE: 04-security-user-management.sql:105 | รัน SQL นี้ครบทั้ง Statement
COMMENT ON ROLE manager_th_xx IS 'Module 4 student xx';
-- @teacher [END 04-SQL021]
-- @teacher [START 04-SQL022] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ติดป้าย Module/Student ให้ internal_auditor_xx เพื่อค้นหา Roles ของ Lab รอบนี้
-- @teacher ผล/ชวนสังเกต: เป็น Metadata ไม่เพิ่ม Permissions; 4A.2 ใช้ Marker นี้ตรวจว่ามีครบ 11 Roles
-- @teacher SOURCE: 04-security-user-management.sql:106 | รัน SQL นี้ครบทั้ง Statement
COMMENT ON ROLE internal_auditor_xx IS 'Module 4 student xx';
-- @teacher [END 04-SQL022]
-- @teacher [START 04-SQL023] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ติดป้าย Module/Student ให้ claim_monitor_xx เพื่อค้นหา Roles ของ Lab รอบนี้
-- @teacher ผล/ชวนสังเกต: เป็น Metadata ไม่เพิ่ม Permissions; 4A.2 ใช้ Marker นี้ตรวจว่ามีครบ 11 Roles
-- @teacher SOURCE: 04-security-user-management.sql:107 | รัน SQL นี้ครบทั้ง Statement
COMMENT ON ROLE claim_monitor_xx IS 'Module 4 student xx';
-- @teacher [END 04-SQL023]
-- @teacher [START 04-SQL024] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ติดป้าย Module/Student ให้ claim_dba_xx เพื่อค้นหา Roles ของ Lab รอบนี้
-- @teacher ผล/ชวนสังเกต: เป็น Metadata ไม่เพิ่ม Permissions; 4A.2 ใช้ Marker นี้ตรวจว่ามีครบ 11 Roles
-- @teacher SOURCE: 04-security-user-management.sql:108 | รัน SQL นี้ครบทั้ง Statement
COMMENT ON ROLE claim_dba_xx IS 'Module 4 student xx';
-- @teacher [END 04-SQL024]

-- @teacher [START 04-SQL025] Lab 4A.1 | สร้าง Owner, Group และ Login
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 04-security-user-management.sql:110 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 04-SQL025]
-- END 4A.1


-- START 4A.2 | ตรวจ Role ที่เพิ่งสร้าง
-- LOGIN: A = postgres (SUPERUSER)
-- EXPECT: 11 แถว; Owner/Groups เป็น NOLOGIN; Runtime roles ไม่มีสิทธิ์พิเศษ
-- @teacher [START 04-SQL026] Lab 4A.2 | ตรวจ Role ที่เพิ่งสร้าง
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ตรวจ Roles ตาม Marker ของ Module 4 สำหรับผู้เรียนคนนี้
-- @teacher ผล/ชวนสังเกต: ควรได้ 11 Roles และ Runtime Roles ไม่มี SUPERUSER/CREATEROLE/BYPASSRLS
-- @teacher SOURCE: 04-security-user-management.sql:117 | รัน SQL นี้ครบทั้ง Statement
SELECT rolname, rolcanlogin, rolsuper, rolcreaterole, rolbypassrls
FROM pg_roles
WHERE shobj_description(oid, 'pg_authid') = 'Module 4 student xx'
ORDER BY rolname;
-- @teacher [END 04-SQL026]
-- END 4A.2


-- START 4A.3 | ตั้ง Password สำหรับ Connection B/C/D
-- LOGIN: A = postgres (SUPERUSER)
-- BEFORE RUN: แก้ CHANGE_ME_* ให้เป็น Password ที่จะใช้จริงก่อนเลือก Execute
-- Password ด้านล่างเป็น Placeholder ไม่ใช่ Password ของ Server
-- RUN: ALTER ROLE ทั้งสามคำสั่ง ยังไม่ต้องเปิด B/C/D จนกว่าจะจบ 4A.4
-- @teacher [START 04-SQL027] Lab 4A.3 | ตั้ง Password สำหรับ Connection B/C/D
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ตั้ง Password ของ claim_app_xx สำหรับเปิด Connection ด้วย Login จริง
-- @teacher ผล/ชวนสังเกต: แทน Placeholder ด้วย Secret ก่อนรัน; ไม่ Commit Secret ที่ใช้จริงลง Repository และไม่ใช้ SET ROLE แทน Login ในการทดสอบ Runtime
-- @teacher SOURCE: 04-security-user-management.sql:129 | รัน SQL นี้ครบทั้ง Statement
ALTER ROLE claim_app_xx PASSWORD 'change_me_app_xx';
-- @teacher [END 04-SQL027]
-- @teacher [START 04-SQL028] Lab 4A.3 | ตั้ง Password สำหรับ Connection B/C/D
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ตั้ง Password ของ internal_auditor_xx สำหรับเปิด Connection ด้วย Login จริง
-- @teacher ผล/ชวนสังเกต: แทน Placeholder ด้วย Secret ก่อนรัน; ไม่ Commit Secret ที่ใช้จริงลง Repository และไม่ใช้ SET ROLE แทน Login ในการทดสอบ Runtime
-- @teacher SOURCE: 04-security-user-management.sql:130 | รัน SQL นี้ครบทั้ง Statement
ALTER ROLE internal_auditor_xx PASSWORD 'change_me_auditor_xx';
-- @teacher [END 04-SQL028]
-- @teacher [START 04-SQL029] Lab 4A.3 | ตั้ง Password สำหรับ Connection B/C/D
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ตั้ง Password ของ manager_th_xx สำหรับเปิด Connection ด้วย Login จริง
-- @teacher ผล/ชวนสังเกต: แทน Placeholder ด้วย Secret ก่อนรัน; ไม่ Commit Secret ที่ใช้จริงลง Repository และไม่ใช้ SET ROLE แทน Login ในการทดสอบ Runtime
-- @teacher SOURCE: 04-security-user-management.sql:131 | รัน SQL นี้ครบทั้ง Statement
ALTER ROLE manager_th_xx PASSWORD 'change_me_manager_xx';
-- @teacher [END 04-SQL029]
-- END 4A.3


-- START 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย
-- LOGIN: A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres
-- PREREQUISITE: มี student_xx จากระบบชั้นเรียน และสร้าง Role ใน 4A.1 ครบแล้ว
-- RUN: BEGIN ถึง COMMIT ทั้งชุด แล้วจึงเปิด Connection S เป็น student_xx
-- Group membership ให้ไว้ก่อน แต่ Group ยังไม่มี Table privileges จนถึง 4C
-- @teacher [START 04-SQL030] Lab 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:140 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL030]
-- @teacher [START 04-SQL031] Lab 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres | claimsure_xx
-- @teacher อธิบาย: ให้ Owner Role เป็นเจ้าของ Schema ตั้งแต่แรกโดย postgres
-- @teacher ผล/ชวนสังเกต: การตั้ง AUTHORIZATION ต้องมีสิทธิ์ SET ROLE เป็น Owner; ไม่ให้ student_xx สร้างขั้นนี้ก่อน Grant Owner membership
-- @teacher SOURCE: 04-security-user-management.sql:141 | รัน SQL นี้ครบทั้ง Statement
CREATE SCHEMA IF NOT EXISTS lab_m4_xx AUTHORIZATION claimsure_owner_xx;
-- @teacher [END 04-SQL031]

-- @teacher [START 04-SQL032] Lab 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres | claimsure_xx
-- @teacher อธิบาย: มอบสิทธิ์ให้ student_xx Activate Owner อย่างชัดเจน โดยไม่รับ Owner privileges อัตโนมัติ
-- @teacher ผล/ชวนสังเกต: SET TRUE แก้ปัญหา must be able to SET ROLE; INHERIT FALSE แยกงาน DDL จาก Login ปกติ
-- @teacher SOURCE: 04-security-user-management.sql:143 | รัน SQL นี้ครบทั้ง Statement
GRANT claimsure_owner_xx TO student_xx
WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
-- @teacher [END 04-SQL032]

-- @teacher [START 04-SQL033] Lab 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres | claimsure_xx
-- @teacher อธิบาย: เปิดประตูเชื่อม Database ให้ Logins ที่สร้างแล้ว
-- @teacher ผล/ชวนสังเกต: CONNECT ไม่ใช่ USAGE Schema และไม่ใช่ SELECT Table; PUBLIC อาจมี CONNECT เดิมอยู่แล้ว
-- @teacher SOURCE: 04-security-user-management.sql:146 | รัน SQL นี้ครบทั้ง Statement
GRANT CONNECT ON DATABASE claimsure_xx
TO student_xx, claim_app_xx, adjuster_bkk_xx,
   manager_th_xx, internal_auditor_xx;
-- @teacher [END 04-SQL033]

-- @teacher [START 04-SQL034] Lab 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres | claimsure_xx
-- @teacher อธิบาย: ทำ Group Hierarchy: Write เป็นสมาชิก Read เพื่อรวมความสามารถอ่าน+เขียน
-- @teacher ผล/ชวนสังเกต: INHERIT TRUE ทำให้สมาชิกใช้สิทธิ์ Group ได้; ADMIN FALSE ไม่ให้มอบ Membership ต่อ
-- @teacher SOURCE: 04-security-user-management.sql:150 | รัน SQL นี้ครบทั้ง Statement
GRANT claimsure_read_xx TO claimsure_write_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
-- @teacher [END 04-SQL034]
-- @teacher [START 04-SQL035] Lab 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres | claimsure_xx
-- @teacher อธิบาย: ผูก App Login เข้ากับ Write Group ที่มี Read ต่อทอดมา
-- @teacher ผล/ชวนสังเกต: ยังไม่มี Table Grants จน 4C.2; Membership ไม่ได้สร้าง Objects ให้เอง
-- @teacher SOURCE: 04-security-user-management.sql:152 | รัน SQL นี้ครบทั้ง Statement
GRANT claimsure_write_xx TO claim_app_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
-- @teacher [END 04-SQL035]
-- @teacher [START 04-SQL036] Lab 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres | claimsure_xx
-- @teacher อธิบาย: ผูก Adjuster Login เข้ากับ Read Group
-- @teacher ผล/ชวนสังเกต: เป็นกลุ่มสิทธิ์ฐาน ยังต้องผ่าน RLS/Column Privileges ที่ตั้งต่อไป
-- @teacher SOURCE: 04-security-user-management.sql:154 | รัน SQL นี้ครบทั้ง Statement
GRANT claimsure_read_xx TO adjuster_bkk_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
-- @teacher [END 04-SQL036]
-- @teacher [START 04-SQL037] Lab 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres | claimsure_xx
-- @teacher อธิบาย: ผูก Manager Login เข้ากับ Approve Group
-- @teacher ผล/ชวนสังเกต: สิทธิ์เฉพาะ Columns จะให้ใน 4E ไม่ใช่การเป็น Owner
-- @teacher SOURCE: 04-security-user-management.sql:156 | รัน SQL นี้ครบทั้ง Statement
GRANT claimsure_approve_xx TO manager_th_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
-- @teacher [END 04-SQL037]
-- @teacher [START 04-SQL038] Lab 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres | claimsure_xx
-- @teacher อธิบาย: ผูก Auditor Login เข้ากับ Audit Group
-- @teacher ผล/ชวนสังเกต: ไม่ให้ Owner membership; อ่านหลักฐานผ่าน Grants เท่านั้น
-- @teacher SOURCE: 04-security-user-management.sql:158 | รัน SQL นี้ครบทั้ง Statement
GRANT claimsure_audit_xx TO internal_auditor_xx
WITH INHERIT TRUE, SET TRUE, ADMIN FALSE;
-- @teacher [END 04-SQL038]
-- @teacher [START 04-SQL039] Lab 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย
-- @teacher LOGIN / DATABASE: A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres | claimsure_xx
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 04-security-user-management.sql:160 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 04-SQL039]
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
-- @teacher [START 04-SQL040] Lab 4B.1 | เปิด Connection S ตรวจสิทธิ์ที่ได้รับ แล้วใช้ Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ใช้ปกติ); เปิด Connection ใหม่ด้วย Login นักเรียนเดิม | claimsure_xx
-- @teacher อธิบาย: ตรวจการส่งมอบ Owner ก่อนเปิด Transaction ของ student_xx
-- @teacher ผล/ชวนสังเกต: can_set_owner=true, is_superuser=false และ owns_schema_exists=true; หาก false กลับ 4A.4 ไม่เพิ่ม SUPERUSER
-- @teacher SOURCE: 04-security-user-management.sql:177 | รัน SQL นี้ครบทั้ง Statement
SELECT session_user, current_user,
       rolsuper AS is_superuser,
       pg_has_role(session_user, 'claimsure_owner_xx', 'SET') AS can_set_owner,
       EXISTS (
           SELECT 1 FROM pg_namespace
           WHERE nspname = 'lab_m4_xx'
             AND pg_get_userbyid(nspowner) = 'claimsure_owner_xx'
       ) AS owns_schema_exists
FROM pg_roles WHERE rolname = current_user;
-- @teacher [END 04-SQL040]

-- @teacher [START 04-SQL041] Lab 4B.1 | เปิด Connection S ตรวจสิทธิ์ที่ได้รับ แล้วใช้ Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ใช้ปกติ); เปิด Connection ใหม่ด้วย Login นักเรียนเดิม | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:187 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL041]
-- @teacher [START 04-SQL042] Lab 4B.1 | เปิด Connection S ตรวจสิทธิ์ที่ได้รับ แล้วใช้ Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ใช้ปกติ); เปิด Connection ใหม่ด้วย Login นักเรียนเดิม | claimsure_xx
-- @teacher อธิบาย: ใช้สิทธิ์ claimsure_owner_xx เฉพาะ Transaction เพื่อสร้าง/จัดการ Object ในนาม Owner
-- @teacher ผล/ชวนสังเกต: session_user ยังเป็น student_xx; current_user เปลี่ยนเป็น Owner; ต้องผ่าน 4A.4 และเริ่ม BEGIN แล้ว
-- @teacher SOURCE: 04-security-user-management.sql:188 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL ROLE claimsure_owner_xx;
-- @teacher [END 04-SQL042]
-- @teacher [START 04-SQL043] Lab 4B.1 | เปิด Connection S ตรวจสิทธิ์ที่ได้รับ แล้วใช้ Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ใช้ปกติ); เปิด Connection ใหม่ด้วย Login นักเรียนเดิม | claimsure_xx
-- @teacher อธิบาย: ปิดสิทธิ์เริ่มต้นของ PUBLIC บน Schema ของ Lab
-- @teacher ผล/ชวนสังเกต: ไม่กระทบ insurance หรือ Schema ของนักเรียนอื่น; Role ที่ต้องใช้จะได้รับ USAGE อย่างชัดเจนใน 4C
-- @teacher SOURCE: 04-security-user-management.sql:189 | รัน SQL นี้ครบทั้ง Statement
REVOKE ALL ON SCHEMA lab_m4_xx FROM PUBLIC;
-- @teacher [END 04-SQL043]
-- @teacher [START 04-SQL044] Lab 4B.1 | เปิด Connection S ตรวจสิทธิ์ที่ได้รับ แล้วใช้ Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ใช้ปกติ); เปิด Connection ใหม่ด้วย Login นักเรียนเดิม | claimsure_xx
-- @teacher อธิบาย: พิสูจน์ความต่างระหว่าง Login กับ Effective Role หลัง SET LOCAL ROLE
-- @teacher ผล/ชวนสังเกต: session_user=student_xx แต่ current_user=claimsure_owner_xx ภายใน Transaction
-- @teacher SOURCE: 04-security-user-management.sql:190 | รัน SQL นี้ครบทั้ง Statement
SELECT session_user, current_user;
-- @teacher [END 04-SQL044]
-- @teacher [START 04-SQL045] Lab 4B.1 | เปิด Connection S ตรวจสิทธิ์ที่ได้รับ แล้วใช้ Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ใช้ปกติ); เปิด Connection ใหม่ด้วย Login นักเรียนเดิม | claimsure_xx
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 04-security-user-management.sql:191 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 04-SQL045]
-- หลัง COMMIT Connection S กลับเป็น student_xx
-- END 4B.1


-- START 4B.2 | สร้าง Table ทั้งสามในนาม Owner
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- EFFECTIVE ROLE ภายใน Transaction: claimsure_owner_xx
-- RUN: BEGIN ถึง COMMIT ทั้งชุด
-- EXPECT: Table/Sequence เป็นของ Owner; ยังไม่เปิด RLS
-- @teacher [START 04-SQL046] Lab 4B.2 | สร้าง Table ทั้งสามในนาม Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:201 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL046]
-- @teacher [START 04-SQL047] Lab 4B.2 | สร้าง Table ทั้งสามในนาม Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ใช้สิทธิ์ claimsure_owner_xx เฉพาะ Transaction เพื่อสร้าง/จัดการ Object ในนาม Owner
-- @teacher ผล/ชวนสังเกต: session_user ยังเป็น student_xx; current_user เปลี่ยนเป็น Owner; ต้องผ่าน 4A.4 และเริ่ม BEGIN แล้ว
-- @teacher SOURCE: 04-security-user-management.sql:202 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL ROLE claimsure_owner_xx;
-- @teacher [END 04-SQL047]

-- @teacher [START 04-SQL048] Lab 4B.2 | สร้าง Table ทั้งสามในนาม Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: Owner สร้าง Claims Table ที่มี Tenant และ Identity สำหรับทดสอบ Grants/RLS
-- @teacher ผล/ชวนสังเกต: Owner ของ Object ต้องเป็น claimsure_owner_xx; ยังไม่เปิด RLS จน 4D
-- @teacher SOURCE: 04-security-user-management.sql:204 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE lab_m4_xx.claim_secure (
    claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id bigint NOT NULL,
    claim_no text NOT NULL UNIQUE,
    status text NOT NULL,
    estimated_amount numeric(14,2) NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);
-- @teacher [END 04-SQL048]

-- @teacher [START 04-SQL049] Lab 4B.2 | สร้าง Table ทั้งสามในนาม Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: Owner สร้าง Policyholder Table ที่มี Columns ข้อมูลติดต่อสำหรับ Column Grants
-- @teacher ผล/ชวนสังเกต: เตรียมแยกสิทธิ์อ่านชื่อออกจาก Email/Phone ของ Auditor
-- @teacher SOURCE: 04-security-user-management.sql:213 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE lab_m4_xx.policyholder_secure (
    policyholder_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id bigint NOT NULL,
    full_name text NOT NULL,
    email text NOT NULL,
    phone text NOT NULL,
    UNIQUE (tenant_id, email)
);
-- @teacher [END 04-SQL049]

-- @teacher [START 04-SQL050] Lab 4B.2 | สร้าง Table ทั้งสามในนาม Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: Owner สร้าง Audit Table ที่มี actor/role_setting และ Old/New Row แบบ JSONB
-- @teacher ผล/ชวนสังเกต: ยังไม่เกิด Audit อัตโนมัติจนสร้าง Trigger ใน 4F
-- @teacher SOURCE: 04-security-user-management.sql:222 | รัน SQL นี้ครบทั้ง Statement
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
-- @teacher [END 04-SQL050]

-- @teacher [START 04-SQL051] Lab 4B.2 | สร้าง Table ทั้งสามในนาม Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ถอน Table Privileges ของ PUBLIC ใน Schema นี้เพื่อให้เริ่มแบบ Least Privilege
-- @teacher ผล/ชวนสังเกต: อย่าสรุปว่าเป็น REVOKE ของ Groups ทุกตัว; Privileges จาก Role อื่นต้องตรวจแยก
-- @teacher SOURCE: 04-security-user-management.sql:233 | รัน SQL นี้ครบทั้ง Statement
REVOKE ALL ON ALL TABLES IN SCHEMA lab_m4_xx FROM PUBLIC;
-- @teacher [END 04-SQL051]
-- @teacher [START 04-SQL052] Lab 4B.2 | สร้าง Table ทั้งสามในนาม Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ถอนสิทธิ์ PUBLIC บน Sequences ที่สร้างแล้ว
-- @teacher ผล/ชวนสังเกต: Identity/Sequence Privileges เป็นคนละ Object กับ Table Grants
-- @teacher SOURCE: 04-security-user-management.sql:234 | รัน SQL นี้ครบทั้ง Statement
REVOKE ALL ON ALL SEQUENCES IN SCHEMA lab_m4_xx FROM PUBLIC;
-- @teacher [END 04-SQL052]
-- @teacher [START 04-SQL053] Lab 4B.2 | สร้าง Table ทั้งสามในนาม Owner
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 04-security-user-management.sql:235 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 04-SQL053]
-- END 4B.2


-- START 4B.3 | เพิ่มข้อมูลตั้งต้น
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner
-- RUN: BEGIN ถึง COMMIT
-- EXPECT: Tenant 101 สองเคลม และ Tenant 202 หนึ่งเคลม
-- @teacher [START 04-SQL054] Lab 4B.3 | เพิ่มข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:243 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL054]
-- @teacher [START 04-SQL055] Lab 4B.3 | เพิ่มข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner | claimsure_xx
-- @teacher อธิบาย: ใช้สิทธิ์ claimsure_owner_xx เฉพาะ Transaction เพื่อสร้าง/จัดการ Object ในนาม Owner
-- @teacher ผล/ชวนสังเกต: session_user ยังเป็น student_xx; current_user เปลี่ยนเป็น Owner; ต้องผ่าน 4A.4 และเริ่ม BEGIN แล้ว
-- @teacher SOURCE: 04-security-user-management.sql:244 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL ROLE claimsure_owner_xx;
-- @teacher [END 04-SQL055]

-- @teacher [START 04-SQL056] Lab 4B.3 | เพิ่มข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner | claimsure_xx
-- @teacher อธิบาย: Seed Claims ของ Tenant 101 และ 202 ใน Table ของผู้เรียน
-- @teacher ผล/ชวนสังเกต: เป็นข้อมูลสำหรับพิสูจน์การกรอง; ก่อน RLS App ที่มี SELECT อาจเห็นทั้งสอง Tenant
-- @teacher SOURCE: 04-security-user-management.sql:246 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m4_xx.claim_secure
    (tenant_id, claim_no, status, estimated_amount)
VALUES
    (101, 'SEC-101-001', 'NEW', 10000),
    (101, 'SEC-101-002', 'UNDER_REVIEW', 25000),
    (202, 'SEC-202-001', 'NEW', 18000);
-- @teacher [END 04-SQL056]

-- @teacher [START 04-SQL057] Lab 4B.3 | เพิ่มข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner | claimsure_xx
-- @teacher อธิบาย: Seed Policyholder จำลองเพื่อทดสอบ Column-level SELECT
-- @teacher ผล/ชวนสังเกต: ใช้ข้อมูลตัวอย่างเท่านั้น ไม่ใส่ข้อมูลติดต่อจริงในคลาส
-- @teacher SOURCE: 04-security-user-management.sql:253 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m4_xx.policyholder_secure
    (tenant_id, full_name, email, phone)
VALUES
    (101, 'Demo Policyholder', 'demo@example.invalid', '000-000-0000');
-- @teacher [END 04-SQL057]

-- @teacher [START 04-SQL058] Lab 4B.3 | เพิ่มข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner | claimsure_xx
-- @teacher อธิบาย: นับ Seed Claims แยก Tenant ก่อนมอบให้ Runtime ใช้
-- @teacher ผล/ชวนสังเกต: Tenant 101 มี 2 Claims และ 202 มี 1 Claim ใน Fixture เดิม
-- @teacher SOURCE: 04-security-user-management.sql:258 | รัน SQL นี้ครบทั้ง Statement
SELECT tenant_id, count(*) AS claims
FROM lab_m4_xx.claim_secure
GROUP BY tenant_id
ORDER BY tenant_id;
-- @teacher [END 04-SQL058]
-- @teacher [START 04-SQL059] Lab 4B.3 | เพิ่มข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner | claimsure_xx
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 04-security-user-management.sql:262 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 04-SQL059]
-- END 4B.3


-- =============================================================================
-- LAB 4C: CONNECT -> Object privileges -> Membership -> App tests
-- =============================================================================

-- START 4C.1 | ตรวจ CONNECT ที่ postgres ให้ไว้แล้วใน 4A.4
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- EXPECT: app_can_connect=true; CONNECT ไม่ได้ให้สิทธิ์ Table
-- @teacher [START 04-SQL060] Lab 4C.1 | ตรวจ CONNECT ที่ postgres ให้ไว้แล้วใน 4A.4
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ตรวจว่า App ผ่านประตู CONNECT ที่เตรียมใน 4A.4
-- @teacher ผล/ชวนสังเกต: true ไม่ได้พิสูจน์ว่าอ่าน Table หรือ SET ROLE Owner ได้
-- @teacher SOURCE: 04-security-user-management.sql:273 | รัน SQL นี้ครบทั้ง Statement
SELECT has_database_privilege('claim_app_xx', 'claimsure_xx', 'CONNECT')
       AS app_can_connect;
-- @teacher [END 04-SQL060]
-- PUBLIC อาจมี CONNECT อยู่ก่อนแล้ว Lab ไม่เปลี่ยนสิทธิ์ Database ของส่วนรวม
-- END 4C.1


-- START 4C.2 | ให้สิทธิ์ Object กับ Group
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner
-- EXPECT: Read group ได้ SELECT; Write group ได้ INSERT/UPDATE
-- @teacher [START 04-SQL061] Lab 4C.2 | ให้สิทธิ์ Object กับ Group
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:282 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL061]
-- @teacher [START 04-SQL062] Lab 4C.2 | ให้สิทธิ์ Object กับ Group
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner | claimsure_xx
-- @teacher อธิบาย: ใช้สิทธิ์ claimsure_owner_xx เฉพาะ Transaction เพื่อสร้าง/จัดการ Object ในนาม Owner
-- @teacher ผล/ชวนสังเกต: session_user ยังเป็น student_xx; current_user เปลี่ยนเป็น Owner; ต้องผ่าน 4A.4 และเริ่ม BEGIN แล้ว
-- @teacher SOURCE: 04-security-user-management.sql:283 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL ROLE claimsure_owner_xx;
-- @teacher [END 04-SQL062]

-- @teacher [START 04-SQL063] Lab 4C.2 | ให้สิทธิ์ Object กับ Group
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner | claimsure_xx
-- @teacher อธิบาย: เปิด USAGE Schema ให้ Capability Groups ที่ต้องใช้ Objects
-- @teacher ผล/ชวนสังเกต: การเห็นชื่อ Schema ได้ยังต้องมี Privileges บน Table/Function เพิ่ม
-- @teacher SOURCE: 04-security-user-management.sql:285 | รัน SQL นี้ครบทั้ง Statement
GRANT USAGE ON SCHEMA lab_m4_xx
TO claimsure_read_xx, claimsure_write_xx,
   claimsure_approve_xx, claimsure_audit_xx;
-- @teacher [END 04-SQL063]

-- @teacher [START 04-SQL064] Lab 4C.2 | ให้สิทธิ์ Object กับ Group
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner | claimsure_xx
-- @teacher อธิบาย: ให้ Read Group อ่าน Claim Table
-- @teacher ผล/ชวนสังเกต: Write/App จะรับสิทธิ์นี้ผ่าน Membership ที่ให้ใน 4A.4
-- @teacher SOURCE: 04-security-user-management.sql:289 | รัน SQL นี้ครบทั้ง Statement
GRANT SELECT ON lab_m4_xx.claim_secure TO claimsure_read_xx;
-- @teacher [END 04-SQL064]
-- @teacher [START 04-SQL065] Lab 4C.2 | ให้สิทธิ์ Object กับ Group
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner | claimsure_xx
-- @teacher อธิบาย: ให้ Write Group INSERT/UPDATE Claim Table โดยไม่ให้ DELETE/CREATE
-- @teacher ผล/ชวนสังเกต: เป็น Object Privileges ไม่ใช่ Ownership จึงแก้ DDL ไม่ได้
-- @teacher SOURCE: 04-security-user-management.sql:290 | รัน SQL นี้ครบทั้ง Statement
GRANT INSERT, UPDATE ON lab_m4_xx.claim_secure TO claimsure_write_xx;
-- @teacher [END 04-SQL065]
-- @teacher [START 04-SQL066] Lab 4C.2 | ให้สิทธิ์ Object กับ Group
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner | claimsure_xx
-- @teacher อธิบาย: ให้ Write Group ใช้ Sequences ใน Schema นี้ตามที่ Lab เตรียมไว้
-- @teacher ผล/ชวนสังเกต: อย่าคิดว่า INSERT Grant บน Table ครอบคลุม Sequence ทุกรูปแบบ; ต้องตรวจ Object ที่ใช้งานจริง
-- @teacher SOURCE: 04-security-user-management.sql:291 | รัน SQL นี้ครบทั้ง Statement
GRANT USAGE ON ALL SEQUENCES IN SCHEMA lab_m4_xx TO claimsure_write_xx;
-- @teacher [END 04-SQL066]

-- @teacher [START 04-SQL067] Lab 4C.2 | ให้สิทธิ์ Object กับ Group
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner | claimsure_xx
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 04-security-user-management.sql:293 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 04-SQL067]
-- Sequence grant เป็นสิทธิ์แยกสำหรับการใช้ Sequence โดยตรง/Default ที่ต้องใช้
-- การ INSERT Column แบบ IDENTITY ในตัวอย่างนี้ไม่ได้พิสูจน์ว่าจำเป็นต้องมี grant นี้
-- END 4C.2


-- START 4C.3 | ตรวจ Membership ที่ postgres เตรียมใน 4A.4
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- EXPECT: App รับ Write -> Read; ไม่มี Owner membership และ ADMIN เป็น false
-- หลัง 4C.2 Group จึงมี Object privileges ให้ Login ใช้ผ่าน Membership ได้
-- @teacher [START 04-SQL068] Lab 4C.3 | ตรวจ Membership ที่ postgres เตรียมใน 4A.4
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ตรวจ Membership Options ที่ postgres เตรียม ไม่ใช้ student_xx GRANT Roles เพิ่ม
-- @teacher ผล/ชวนสังเกต: แยก inherit_option, set_option, admin_option ว่าใช้สิทธิ์ เปลี่ยน Role และมอบสมาชิกต่อคนละเรื่อง
-- @teacher SOURCE: 04-security-user-management.sql:303 | รัน SQL นี้ครบทั้ง Statement
SELECT r.rolname AS group_role, m.rolname AS member,
       am.inherit_option, am.set_option, am.admin_option
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE m.rolname IN ('claimsure_write_xx', 'claim_app_xx', 'adjuster_bkk_xx',
                   'manager_th_xx', 'internal_auditor_xx')
ORDER BY member, group_role;
-- @teacher [END 04-SQL068]
-- END 4C.3


-- START 4C.4 | เปิด Connection B แล้วทดสอบอ่านและเพิ่มข้อมูล
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ ไม่ใช่ SUPERUSER)
-- CONNECTION: เปิด Connection ใหม่ใน SQL editor ด้วย Password จาก 4A.3
-- DATABASE: claimsure_xx; EXPECT: session_user=current_user=claim_app_xx
-- RUN: BEGIN ถึง ROLLBACK; EXPECT: อ่านสาม Seed rows และ INSERT ผ่าน
-- @teacher [START 04-SQL069] Lab 4C.4 | เปิด Connection B แล้วทดสอบอ่านและเพิ่มข้อมูล
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ ไม่ใช่ SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:319 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL069]
-- @teacher [START 04-SQL070] Lab 4C.4 | เปิด Connection B แล้วทดสอบอ่านและเพิ่มข้อมูล
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ ไม่ใช่ SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ตรวจ Connection B ว่า Login เป็น App จริง ไม่ได้ SET ROLE จาก postgres
-- @teacher ผล/ชวนสังเกต: session_user และ current_user ควรเป็น claim_app_xx เพื่อให้ผลทดสอบสะท้อน Runtime
-- @teacher SOURCE: 04-security-user-management.sql:320 | รัน SQL นี้ครบทั้ง Statement
SELECT session_user, current_user;
-- @teacher [END 04-SQL070]

-- @teacher [START 04-SQL071] Lab 4C.4 | เปิด Connection B แล้วทดสอบอ่านและเพิ่มข้อมูล
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ ไม่ใช่ SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: อ่าน Claims ก่อนเปิด RLS เพื่อแสดงผลของ Table SELECT Grant
-- @teacher ผล/ชวนสังเกต: ยังอาจเห็น Tenant 101 และ 202; นี่คือเหตุผลที่ Membership อย่างเดียวไม่แยก Tenant
-- @teacher SOURCE: 04-security-user-management.sql:322 | รัน SQL นี้ครบทั้ง Statement
SELECT claim_no, tenant_id, status
FROM lab_m4_xx.claim_secure
ORDER BY claim_no;
-- @teacher [END 04-SQL071]

-- @teacher [START 04-SQL072] Lab 4C.4 | เปิด Connection B แล้วทดสอบอ่านและเพิ่มข้อมูล
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ ไม่ใช่ SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ทดลอง App INSERT Tenant 101 ด้วย Write Grant และคืนค่าใน ROLLBACK
-- @teacher ผล/ชวนสังเกต: RETURNING แสดง Claim ใหม่ภายใน Transaction; ไม่เก็บ SEC-C-ALLOWED เป็นข้อมูลถาวร
-- @teacher SOURCE: 04-security-user-management.sql:326 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m4_xx.claim_secure
    (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-C-ALLOWED', 'NEW', 500)
RETURNING claim_id, claim_no;
-- @teacher [END 04-SQL072]
-- @teacher [START 04-SQL073] Lab 4C.4 | เปิด Connection B แล้วทดสอบอ่านและเพิ่มข้อมูล
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ ไม่ใช่ SUPERUSER) | claimsure_xx
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 04-security-user-management.sql:330 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 04-SQL073]
-- ROLLBACK ย้อนข้อมูลทดลอง แต่ Login ของ Connection B ยังเป็น claim_app_xx
-- END 4C.4


-- START 4C.5 | EXPECTED ERROR: App สร้าง Table ไม่ได้
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN และ CREATE TABLE; EXPECT: SQLSTATE 42501 / permission denied
-- เมื่อเห็น Error ให้เลือกชุด 4C.6 แยกต่างหากทันที
-- @teacher [START 04-SQL074] Lab 4C.5 | EXPECTED ERROR: App สร้าง Table ไม่ได้
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:339 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL074]
-- @teacher [START 04-SQL075] Lab 4C.5 | EXPECTED ERROR: App สร้าง Table ไม่ได้
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: Expected Error: ให้ App พยายาม CREATE TABLE ใน Schema ที่มีเพียง USAGE
-- @teacher ผล/ชวนสังเกต: คาด 42501 permission denied for schema; รัน Recovery 4C.6 ใน Connection เดิมทันที
-- @teacher SOURCE: 04-security-user-management.sql:340 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE lab_m4_xx.owned_by_app (id integer);
-- @teacher [END 04-SQL075]
-- END 4C.5


-- START 4C.6 | RECOVERY หลัง Expected error ของ 4C.5
-- LOGIN: B = claim_app_xx (Connection เดิม)
-- RUN: ROLLBACK หนึ่งคำสั่ง เพื่อออกจาก Transaction aborted
-- @teacher [START 04-SQL076] Lab 4C.6 | RECOVERY หลัง Expected error ของ 4C.5
-- @teacher LOGIN / DATABASE: B = claim_app_xx (Connection เดิม) | claimsure_xx
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 04-security-user-management.sql:347 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 04-SQL076]
-- END 4C.6


-- =============================================================================
-- LAB 4D: Owner เพิ่ม RLS; App ทดสอบ Tenant
-- =============================================================================

-- START 4D.1 | เปิด RLS และสร้าง Policy บนตารางเดิม
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน); กลับมาที่ Connection S
-- RUN: BEGIN ถึง COMMIT; EFFECTIVE ROLE: Owner
-- @teacher [START 04-SQL077] Lab 4D.1 | เปิด RLS และสร้าง Policy บนตารางเดิม
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); กลับมาที่ Connection S | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:358 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL077]
-- @teacher [START 04-SQL078] Lab 4D.1 | เปิด RLS และสร้าง Policy บนตารางเดิม
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); กลับมาที่ Connection S | claimsure_xx
-- @teacher อธิบาย: ใช้สิทธิ์ claimsure_owner_xx เฉพาะ Transaction เพื่อสร้าง/จัดการ Object ในนาม Owner
-- @teacher ผล/ชวนสังเกต: session_user ยังเป็น student_xx; current_user เปลี่ยนเป็น Owner; ต้องผ่าน 4A.4 และเริ่ม BEGIN แล้ว
-- @teacher SOURCE: 04-security-user-management.sql:359 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL ROLE claimsure_owner_xx;
-- @teacher [END 04-SQL078]

-- @teacher [START 04-SQL079] Lab 4D.1 | เปิด RLS และสร้าง Policy บนตารางเดิม
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); กลับมาที่ Connection S | claimsure_xx
-- @teacher อธิบาย: เปิด Row-level Security บน Claims Table
-- @teacher ผล/ชวนสังเกต: เริ่มใช้ Policies กับ Runtime Roles; ยังต้องมีกฎอนุญาตสำหรับงานที่จะทำ
-- @teacher SOURCE: 04-security-user-management.sql:361 | รัน SQL นี้ครบทั้ง Statement
ALTER TABLE lab_m4_xx.claim_secure ENABLE ROW LEVEL SECURITY;
-- @teacher [END 04-SQL079]
-- @teacher [START 04-SQL080] Lab 4D.1 | เปิด RLS และสร้าง Policy บนตารางเดิม
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); กลับมาที่ Connection S | claimsure_xx
-- @teacher อธิบาย: ใช้ FORCE RLS ให้ Table Owner อยู่ใต้ Policy ด้วย
-- @teacher ผล/ชวนสังเกต: SUPERUSER/BYPASSRLS ยังข้ามได้ จึงทดสอบด้วย App Login จริง
-- @teacher SOURCE: 04-security-user-management.sql:362 | รัน SQL นี้ครบทั้ง Statement
ALTER TABLE lab_m4_xx.claim_secure FORCE ROW LEVEL SECURITY;
-- @teacher [END 04-SQL080]

-- @teacher [START 04-SQL081] Lab 4D.1 | เปิด RLS และสร้าง Policy บนตารางเดิม
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); กลับมาที่ Connection S | claimsure_xx
-- @teacher อธิบาย: สร้าง Tenant Policy ทั้ง USING และ WITH CHECK จาก app.tenant_id
-- @teacher ผล/ชวนสังเกต: USING กรองแถวเดิม; WITH CHECK ตรวจแถวหลังเขียน; GUC นี้เป็น Context จำลองที่ SQL Client เปลี่ยนเองได้ ไม่ใช่ Identity ที่ยืนยันแล้ว
-- @teacher SOURCE: 04-security-user-management.sql:364 | รัน SQL นี้ครบทั้ง Statement
CREATE POLICY claim_tenant_access ON lab_m4_xx.claim_secure
TO claimsure_read_xx, claimsure_write_xx,
   claimsure_approve_xx, claimsure_owner_xx
USING (
    tenant_id = nullif(current_setting('app.tenant_id', true), '')::bigint
)
WITH CHECK (
    tenant_id = nullif(current_setting('app.tenant_id', true), '')::bigint
);
-- @teacher [END 04-SQL081]
-- @teacher [START 04-SQL082] Lab 4D.1 | เปิด RLS และสร้าง Policy บนตารางเดิม
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน); กลับมาที่ Connection S | claimsure_xx
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 04-security-user-management.sql:373 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 04-SQL082]
-- Owner อยู่ใน Policy เพราะ Count function ของ 4F ทำงานเป็น Owner ตาม FORCE RLS
-- END 4D.1


-- START 4D.2 | App อ่านและเพิ่มเฉพาะ Tenant ของตน
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง ROLLBACK
-- EXPECT: SELECT ได้สองแถวของ Tenant 101; INSERT Tenant 101 ผ่าน
-- @teacher [START 04-SQL083] Lab 4D.2 | App อ่านและเพิ่มเฉพาะ Tenant ของตน
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:382 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL083]
-- @teacher [START 04-SQL084] Lab 4D.2 | App อ่านและเพิ่มเฉพาะ Tenant ของตน
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ตั้ง Tenant 101 เฉพาะ Transaction ของ App
-- @teacher ผล/ชวนสังเกต: true ทำให้ค่าคืนเมื่อ COMMIT/ROLLBACK; ต้องเปิด BEGIN ก่อน เพื่อให้ SELECT ถัดไปยังใช้ Context นี้
-- @teacher SOURCE: 04-security-user-management.sql:383 | รัน SQL นี้ครบทั้ง Statement
SELECT set_config('app.tenant_id', '101', true);
-- @teacher [END 04-SQL084]
-- @teacher [START 04-SQL085] Lab 4D.2 | App อ่านและเพิ่มเฉพาะ Tenant ของตน
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: อ่าน Claims ด้วย App หลังเปิด Tenant RLS
-- @teacher ผล/ชวนสังเกต: ควรเห็นเฉพาะ 2 แถวของ Tenant 101 โดยไม่ใส่ WHERE tenant_id ใน Query
-- @teacher SOURCE: 04-security-user-management.sql:384 | รัน SQL นี้ครบทั้ง Statement
SELECT claim_no, tenant_id
FROM lab_m4_xx.claim_secure
ORDER BY claim_no;
-- @teacher [END 04-SQL085]

-- @teacher [START 04-SQL086] Lab 4D.2 | App อ่านและเพิ่มเฉพาะ Tenant ของตน
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ทดลอง INSERT ภายใต้ Tenant Context ที่ตรงกับแถวใหม่
-- @teacher ผล/ชวนสังเกต: WITH CHECK อนุญาต Tenant 101; RETURNING แสดงแถว แล้ว ROLLBACK คืน Fixture
-- @teacher SOURCE: 04-security-user-management.sql:388 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m4_xx.claim_secure
    (tenant_id, claim_no, status, estimated_amount)
VALUES (101, 'SEC-D-ALLOWED', 'NEW', 500)
RETURNING claim_no, tenant_id;
-- @teacher [END 04-SQL086]
-- @teacher [START 04-SQL087] Lab 4D.2 | App อ่านและเพิ่มเฉพาะ Tenant ของตน
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 04-security-user-management.sql:392 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 04-SQL087]
-- END 4D.2


-- START 4D.3 | EXPECTED ERROR: App เพิ่มข้อมูลข้าม Tenant ไม่ได้
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง INSERT; EXPECT: SQLSTATE 42501 / row-level security policy
-- รัน 4D.4 หลัง Error
-- @teacher [START 04-SQL088] Lab 4D.3 | EXPECTED ERROR: App เพิ่มข้อมูลข้าม Tenant ไม่ได้
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:400 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL088]
-- @teacher [START 04-SQL089] Lab 4D.3 | EXPECTED ERROR: App เพิ่มข้อมูลข้าม Tenant ไม่ได้
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ตั้ง Context ของ App เป็น Tenant 101 ก่อนลองเขียนข้าม Tenant
-- @teacher ผล/ชวนสังเกต: เป็นเงื่อนไขเดียวกับกรณีที่ผ่าน ต่างกันที่ค่าของแถวใหม่
-- @teacher SOURCE: 04-security-user-management.sql:401 | รัน SQL นี้ครบทั้ง Statement
SELECT set_config('app.tenant_id', '101', true);
-- @teacher [END 04-SQL089]
-- @teacher [START 04-SQL090] Lab 4D.3 | EXPECTED ERROR: App เพิ่มข้อมูลข้าม Tenant ไม่ได้
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: Expected Error: App ที่มี Context 101 พยายาม INSERT Tenant 202
-- @teacher ผล/ชวนสังเกต: คาด 42501 จาก RLS WITH CHECK; รัน Recovery 4D.4 ทันที
-- @teacher SOURCE: 04-security-user-management.sql:402 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m4_xx.claim_secure
    (tenant_id, claim_no, status, estimated_amount)
VALUES (202, 'SEC-D-DENIED', 'NEW', 500);
-- @teacher [END 04-SQL090]
-- END 4D.3


-- START 4D.4 | RECOVERY หลัง Expected error ของ 4D.3
-- LOGIN: B = claim_app_xx (Connection เดิม)
-- @teacher [START 04-SQL091] Lab 4D.4 | RECOVERY หลัง Expected error ของ 4D.3
-- @teacher LOGIN / DATABASE: B = claim_app_xx (Connection เดิม) | claimsure_xx
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 04-security-user-management.sql:410 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 04-SQL091]
-- END 4D.4


-- START 4D.5 | App ไม่มี Tenant context จึงเห็นศูนย์แถว
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง ROLLBACK; EXPECT: visible_claims = 0
-- @teacher [START 04-SQL092] Lab 4D.5 | App ไม่มี Tenant context จึงเห็นศูนย์แถว
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:417 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL092]
-- @teacher [START 04-SQL093] Lab 4D.5 | App ไม่มี Tenant context จึงเห็นศูนย์แถว
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ล้าง Tenant Context เป็นค่าว่างภายใน Transaction
-- @teacher ผล/ชวนสังเกต: NULLIF ใน Policy เปลี่ยนค่าว่างเป็น NULL ทำให้เงื่อนไขไม่ผ่าน
-- @teacher SOURCE: 04-security-user-management.sql:418 | รัน SQL นี้ครบทั้ง Statement
SELECT set_config('app.tenant_id', '', true);
-- @teacher [END 04-SQL093]
-- @teacher [START 04-SQL094] Lab 4D.5 | App ไม่มี Tenant context จึงเห็นศูนย์แถว
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: นับแถวที่ App เห็นเมื่อไม่มี Tenant Context
-- @teacher ผล/ชวนสังเกต: visible_claims=0 เป็น Default Deny ไม่ใช่ Table ถูกลบ
-- @teacher SOURCE: 04-security-user-management.sql:419 | รัน SQL นี้ครบทั้ง Statement
SELECT count(*) AS visible_claims FROM lab_m4_xx.claim_secure;
-- @teacher [END 04-SQL094]
-- @teacher [START 04-SQL095] Lab 4D.5 | App ไม่มี Tenant context จึงเห็นศูนย์แถว
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 04-security-user-management.sql:420 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 04-SQL095]
-- Custom setting นี้ใช้สาธิต Policy ไม่ใช่หลักฐานยืนยัน Tenant identity
-- SQL client ตั้ง GUC เองได้; ระบบจริงต้องอนุญาต Tenant ผ่านฝั่งที่เชื่อถือได้
-- END 4D.5


-- =============================================================================
-- LAB 4E: จำกัด Column ให้ Auditor และ Manager
-- =============================================================================

-- START 4E.1 | Owner ให้สิทธิ์ Column กับ Group ที่มีอยู่แล้ว
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง COMMIT
-- @teacher [START 04-SQL096] Lab 4E.1 | Owner ให้สิทธิ์ Column กับ Group ที่มีอยู่แล้ว
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:433 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL096]
-- @teacher [START 04-SQL097] Lab 4E.1 | Owner ให้สิทธิ์ Column กับ Group ที่มีอยู่แล้ว
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ใช้สิทธิ์ claimsure_owner_xx เฉพาะ Transaction เพื่อสร้าง/จัดการ Object ในนาม Owner
-- @teacher ผล/ชวนสังเกต: session_user ยังเป็น student_xx; current_user เปลี่ยนเป็น Owner; ต้องผ่าน 4A.4 และเริ่ม BEGIN แล้ว
-- @teacher SOURCE: 04-security-user-management.sql:434 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL ROLE claimsure_owner_xx;
-- @teacher [END 04-SQL097]

-- @teacher [START 04-SQL098] Lab 4E.1 | Owner ให้สิทธิ์ Column กับ Group ที่มีอยู่แล้ว
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ถอน Table-level SELECT เดิมของ Audit Group ก่อนให้สิทธิ์ระดับ Column
-- @teacher ผล/ชวนสังเกต: ถ้ายังมี SELECT ทั้ง Table การจำกัดบาง Columns จะไม่หักสิทธิ์ที่กว้างกว่า
-- @teacher SOURCE: 04-security-user-management.sql:436 | รัน SQL นี้ครบทั้ง Statement
REVOKE SELECT ON lab_m4_xx.policyholder_secure FROM claimsure_audit_xx;
-- @teacher [END 04-SQL098]
-- @teacher [START 04-SQL099] Lab 4E.1 | Owner ให้สิทธิ์ Column กับ Group ที่มีอยู่แล้ว
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: อนุญาต Auditor อ่านเฉพาะ ID, Tenant และชื่อของ Policyholder
-- @teacher ผล/ชวนสังเกต: ไม่มี Email/Phone ในรายการ; RLS และ Column Grants เป็นคนละด่าน
-- @teacher SOURCE: 04-security-user-management.sql:437 | รัน SQL นี้ครบทั้ง Statement
GRANT SELECT (policyholder_id, tenant_id, full_name)
ON lab_m4_xx.policyholder_secure TO claimsure_audit_xx;
-- @teacher [END 04-SQL099]

-- @teacher [START 04-SQL100] Lab 4E.1 | Owner ให้สิทธิ์ Column กับ Group ที่มีอยู่แล้ว
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ให้ Approve Group อ่าน Claims เพื่อใช้ WHERE/RETURNING ใน UPDATE ที่อนุญาต
-- @teacher ผล/ชวนสังเกต: SELECT Table ยังอยู่ใต้ Tenant RLS ของ Manager
-- @teacher SOURCE: 04-security-user-management.sql:440 | รัน SQL นี้ครบทั้ง Statement
GRANT SELECT ON lab_m4_xx.claim_secure TO claimsure_approve_xx;
-- @teacher [END 04-SQL100]
-- @teacher [START 04-SQL101] Lab 4E.1 | Owner ให้สิทธิ์ Column กับ Group ที่มีอยู่แล้ว
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ถอน UPDATE ทั้ง Table ของ Approve Group ก่อนกำหนด Column Updates
-- @teacher ผล/ชวนสังเกต: ทำให้การอนุมัติไม่ติดสิทธิ์แก้จำนวนเงินมาด้วย
-- @teacher SOURCE: 04-security-user-management.sql:441 | รัน SQL นี้ครบทั้ง Statement
REVOKE UPDATE ON lab_m4_xx.claim_secure FROM claimsure_approve_xx;
-- @teacher [END 04-SQL101]
-- @teacher [START 04-SQL102] Lab 4E.1 | Owner ให้สิทธิ์ Column กับ Group ที่มีอยู่แล้ว
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: อนุญาต Manager UPDATE เฉพาะ status และ updated_at
-- @teacher ผล/ชวนสังเกต: INSERT/DELETE/estimated_amount ไม่ได้รับสิทธิ์จาก Grant นี้
-- @teacher SOURCE: 04-security-user-management.sql:442 | รัน SQL นี้ครบทั้ง Statement
GRANT UPDATE (status, updated_at)
ON lab_m4_xx.claim_secure TO claimsure_approve_xx;
-- @teacher [END 04-SQL102]

-- @teacher [START 04-SQL103] Lab 4E.1 | Owner ให้สิทธิ์ Column กับ Group ที่มีอยู่แล้ว
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 04-security-user-management.sql:445 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 04-SQL103]
-- END 4E.1


-- START 4E.2 | เปิด Connection C เป็น Auditor แล้วอ่านชื่อ
-- LOGIN: C = internal_auditor_xx (ผู้ใช้ปกติ)
-- CONNECTION: เปิดใหม่ด้วย Password จาก 4A.3; DATABASE: claimsure_xx
-- EXPECT: ผู้ใช้ทั้งสองเป็น internal_auditor_xx และอ่านชื่อได้
-- @teacher [START 04-SQL104] Lab 4E.2 | เปิด Connection C เป็น Auditor แล้วอ่านชื่อ
-- @teacher LOGIN / DATABASE: C = internal_auditor_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ตรวจว่า Connection C Login เป็น Auditor จริง
-- @teacher ผล/ชวนสังเกต: ห้ามใช้ postgres แทน เพราะ Superuser ทำให้กรณี Expected Error ไม่ตรงบทเรียน
-- @teacher SOURCE: 04-security-user-management.sql:453 | รัน SQL นี้ครบทั้ง Statement
SELECT session_user, current_user;
-- @teacher [END 04-SQL104]
-- @teacher [START 04-SQL105] Lab 4E.2 | เปิด Connection C เป็น Auditor แล้วอ่านชื่อ
-- @teacher LOGIN / DATABASE: C = internal_auditor_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ให้ Auditor อ่าน Columns ที่ได้รับอนุญาต
-- @teacher ผล/ชวนสังเกต: ควรสำเร็จและแสดงข้อมูลจำลองโดยไม่มี Contact Fields
-- @teacher SOURCE: 04-security-user-management.sql:454 | รัน SQL นี้ครบทั้ง Statement
SELECT policyholder_id, tenant_id, full_name
FROM lab_m4_xx.policyholder_secure;
-- @teacher [END 04-SQL105]
-- END 4E.2


-- START 4E.3 | EXPECTED ERROR: Auditor อ่าน Contact fields ไม่ได้
-- LOGIN: C = internal_auditor_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง SELECT; EXPECT: SQLSTATE 42501; แล้วรัน 4E.4
-- @teacher [START 04-SQL106] Lab 4E.3 | EXPECTED ERROR: Auditor อ่าน Contact fields ไม่ได้
-- @teacher LOGIN / DATABASE: C = internal_auditor_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:462 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL106]
-- @teacher [START 04-SQL107] Lab 4E.3 | EXPECTED ERROR: Auditor อ่าน Contact fields ไม่ได้
-- @teacher LOGIN / DATABASE: C = internal_auditor_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: Expected Error: Auditor SELECT Email/Phone ที่ไม่ได้รับ Grant
-- @teacher ผล/ชวนสังเกต: คาด 42501 column/table permission denied; ใช้ Recovery 4E.4 ก่อนคำสั่งถัดไป
-- @teacher SOURCE: 04-security-user-management.sql:463 | รัน SQL นี้ครบทั้ง Statement
SELECT email, phone FROM lab_m4_xx.policyholder_secure;
-- @teacher [END 04-SQL107]
-- END 4E.3


-- START 4E.4 | RECOVERY หลัง Expected error ของ 4E.3
-- LOGIN: C = internal_auditor_xx (Connection เดิม)
-- @teacher [START 04-SQL108] Lab 4E.4 | RECOVERY หลัง Expected error ของ 4E.3
-- @teacher LOGIN / DATABASE: C = internal_auditor_xx (Connection เดิม) | claimsure_xx
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 04-security-user-management.sql:469 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 04-SQL108]
-- END 4E.4


-- START 4E.5 | เปิด Connection D เป็น Manager แล้วแก้ Status
-- LOGIN: D = manager_th_xx (ผู้ใช้ปกติ)
-- CONNECTION: เปิดใหม่ด้วย Password จาก 4A.3; DATABASE: claimsure_xx
-- RUN: BEGIN ถึง ROLLBACK; EXPECT: UPDATE ได้หนึ่งแถว
-- @teacher [START 04-SQL109] Lab 4E.5 | เปิด Connection D เป็น Manager แล้วแก้ Status
-- @teacher LOGIN / DATABASE: D = manager_th_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:477 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL109]
-- @teacher [START 04-SQL110] Lab 4E.5 | เปิด Connection D เป็น Manager แล้วแก้ Status
-- @teacher LOGIN / DATABASE: D = manager_th_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ตรวจว่า Connection D Login เป็น Manager จริง
-- @teacher ผล/ชวนสังเกต: session_user=current_user=manager_th_xx
-- @teacher SOURCE: 04-security-user-management.sql:478 | รัน SQL นี้ครบทั้ง Statement
SELECT session_user, current_user;
-- @teacher [END 04-SQL110]
-- @teacher [START 04-SQL111] Lab 4E.5 | เปิด Connection D เป็น Manager แล้วแก้ Status
-- @teacher LOGIN / DATABASE: D = manager_th_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ตั้ง Tenant 101 ให้ Manager ภายใน Transaction
-- @teacher ผล/ชวนสังเกต: สิทธิ์ Column อย่างเดียวไม่เลือก Tenant ให้ ต้องมี Context ที่ถูกต้องด้วย
-- @teacher SOURCE: 04-security-user-management.sql:479 | รัน SQL นี้ครบทั้ง Statement
SELECT set_config('app.tenant_id', '101', true);
-- @teacher [END 04-SQL111]
-- @teacher [START 04-SQL112] Lab 4E.5 | เปิด Connection D เป็น Manager แล้วแก้ Status
-- @teacher LOGIN / DATABASE: D = manager_th_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: Manager อนุมัติ Status ของ Claim ใน Tenant ที่เห็นได้
-- @teacher ผล/ชวนสังเกต: คาด UPDATE 1 สำหรับ SEC-101-001 แล้ว ROLLBACK คืนค่าเพื่อให้ Repeat ได้
-- @teacher SOURCE: 04-security-user-management.sql:480 | รัน SQL นี้ครบทั้ง Statement
UPDATE lab_m4_xx.claim_secure
SET status = 'APPROVED', updated_at = clock_timestamp()
WHERE claim_no = 'SEC-101-001'
RETURNING claim_no, status;
-- @teacher [END 04-SQL112]
-- @teacher [START 04-SQL113] Lab 4E.5 | เปิด Connection D เป็น Manager แล้วแก้ Status
-- @teacher LOGIN / DATABASE: D = manager_th_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 04-security-user-management.sql:484 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 04-SQL113]
-- END 4E.5


-- START 4E.6 | EXPECTED ERROR: Manager แก้จำนวนเงินไม่ได้
-- LOGIN: D = manager_th_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง UPDATE; EXPECT: SQLSTATE 42501; แล้วรัน 4E.7
-- @teacher [START 04-SQL114] Lab 4E.6 | EXPECTED ERROR: Manager แก้จำนวนเงินไม่ได้
-- @teacher LOGIN / DATABASE: D = manager_th_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:491 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL114]
-- @teacher [START 04-SQL115] Lab 4E.6 | EXPECTED ERROR: Manager แก้จำนวนเงินไม่ได้
-- @teacher LOGIN / DATABASE: D = manager_th_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ตั้ง Context Tenant 101 สำหรับ Negative Test ของ Manager
-- @teacher ผล/ชวนสังเกต: ทำให้การปฏิเสธครั้งนี้มาจาก Column Grant ไม่ใช่แค่ Context หาย
-- @teacher SOURCE: 04-security-user-management.sql:492 | รัน SQL นี้ครบทั้ง Statement
SELECT set_config('app.tenant_id', '101', true);
-- @teacher [END 04-SQL115]
-- @teacher [START 04-SQL116] Lab 4E.6 | EXPECTED ERROR: Manager แก้จำนวนเงินไม่ได้
-- @teacher LOGIN / DATABASE: D = manager_th_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: Expected Error: Manager UPDATE estimated_amount ที่ไม่ได้รับอนุญาต
-- @teacher ผล/ชวนสังเกต: คาด 42501 แล้ว Recovery 4E.7; การตั้ง status ได้ไม่ได้แปลว่าตั้งทุก Column ได้
-- @teacher SOURCE: 04-security-user-management.sql:493 | รัน SQL นี้ครบทั้ง Statement
UPDATE lab_m4_xx.claim_secure
SET estimated_amount = 1
WHERE claim_no = 'SEC-101-001';
-- @teacher [END 04-SQL116]
-- END 4E.6


-- START 4E.7 | RECOVERY หลัง Expected error ของ 4E.6
-- LOGIN: D = manager_th_xx (Connection เดิม)
-- @teacher [START 04-SQL117] Lab 4E.7 | RECOVERY หลัง Expected error ของ 4E.6
-- @teacher LOGIN / DATABASE: D = manager_th_xx (Connection เดิม) | claimsure_xx
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 04-security-user-management.sql:501 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 04-SQL117]
-- END 4E.7


-- =============================================================================
-- LAB 4F: Controlled function, Trigger และ Audit
-- =============================================================================

-- START 4F.1 | Owner สร้าง Count function ก่อนให้ EXECUTE
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง COMMIT ทั้งชุด รวม Function body ระหว่าง $function$
-- @teacher [START 04-SQL118] Lab 4F.1 | Owner สร้าง Count function ก่อนให้ EXECUTE
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:512 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL118]
-- @teacher [START 04-SQL119] Lab 4F.1 | Owner สร้าง Count function ก่อนให้ EXECUTE
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ใช้สิทธิ์ claimsure_owner_xx เฉพาะ Transaction เพื่อสร้าง/จัดการ Object ในนาม Owner
-- @teacher ผล/ชวนสังเกต: session_user ยังเป็น student_xx; current_user เปลี่ยนเป็น Owner; ต้องผ่าน 4A.4 และเริ่ม BEGIN แล้ว
-- @teacher SOURCE: 04-security-user-management.sql:513 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL ROLE claimsure_owner_xx;
-- @teacher [END 04-SQL119]

-- @teacher [START 04-SQL120] Lab 4F.1 | Owner สร้าง Count function ก่อนให้ EXECUTE
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: Owner สร้าง SECURITY DEFINER Count Function พร้อม Search Path ที่คุมได้
-- @teacher ผล/ชวนสังเกต: Body นับเฉพาะ Tenant และอยู่ใต้ FORCE RLS ด้วย Owner Role; เรียกด้วย EXECUTE Grant ตามกลุ่ม
-- @teacher SOURCE: 04-security-user-management.sql:515 | รัน SQL นี้ครบทั้ง Statement
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
-- @teacher [END 04-SQL120]

-- @teacher [START 04-SQL121] Lab 4F.1 | Owner สร้าง Count function ก่อนให้ EXECUTE
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ถอน EXECUTE ที่ PUBLIC อาจได้รับเป็นค่าเริ่มต้นของ Function
-- @teacher ผล/ชวนสังเกต: ปิดการเรียกจากผู้ใช้ทั่วไปก่อนมอบสิทธิ์จำกัดให้ Read Group
-- @teacher SOURCE: 04-security-user-management.sql:527 | รัน SQL นี้ครบทั้ง Statement
REVOKE ALL ON FUNCTION lab_m4_xx.claim_count_for_current_tenant() FROM PUBLIC;
-- @teacher [END 04-SQL121]
-- @teacher [START 04-SQL122] Lab 4F.1 | Owner สร้าง Count function ก่อนให้ EXECUTE
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ให้ Read Group เรียก Count Function ที่สร้างไว้แล้ว
-- @teacher ผล/ชวนสังเกต: Write/App รับผ่าน Role Hierarchy; EXECUTE ไม่ใช่ SELECT บน Audit Table
-- @teacher SOURCE: 04-security-user-management.sql:528 | รัน SQL นี้ครบทั้ง Statement
GRANT EXECUTE ON FUNCTION lab_m4_xx.claim_count_for_current_tenant()
TO claimsure_read_xx;
-- @teacher [END 04-SQL122]
-- @teacher [START 04-SQL123] Lab 4F.1 | Owner สร้าง Count function ก่อนให้ EXECUTE
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 04-security-user-management.sql:530 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 04-SQL123]
-- SECURITY DEFINER ใช้สิทธิ์ Owner ภายใน Function และคืน Role ให้ผู้เรียกเมื่อจบ
-- END 4F.1


-- START 4F.2 | Owner สร้าง Audit function และ Trigger
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง COMMIT ทั้งชุด ห้ามเลือกเพียงบางบรรทัดใน Function body
-- @teacher [START 04-SQL124] Lab 4F.2 | Owner สร้าง Audit function และ Trigger
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:538 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL124]
-- @teacher [START 04-SQL125] Lab 4F.2 | Owner สร้าง Audit function และ Trigger
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ใช้สิทธิ์ claimsure_owner_xx เฉพาะ Transaction เพื่อสร้าง/จัดการ Object ในนาม Owner
-- @teacher ผล/ชวนสังเกต: session_user ยังเป็น student_xx; current_user เปลี่ยนเป็น Owner; ต้องผ่าน 4A.4 และเริ่ม BEGIN แล้ว
-- @teacher SOURCE: 04-security-user-management.sql:539 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL ROLE claimsure_owner_xx;
-- @teacher [END 04-SQL125]

-- @teacher [START 04-SQL126] Lab 4F.2 | Owner สร้าง Audit function และ Trigger
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: สร้าง SECURITY DEFINER Trigger Function ที่เขียน Audit แทน Runtime
-- @teacher ผล/ชวนสังเกต: Body ใช้ session_user ระบุผู้ Login, TG_OP ระบุ Operation และ Old/New เป็น JSONB; Search Path ไม่ไว้ใจ Schema ของผู้เรียก
-- @teacher SOURCE: 04-security-user-management.sql:541 | รัน SQL นี้ครบทั้ง Statement
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
-- @teacher [END 04-SQL126]

-- @teacher [START 04-SQL127] Lab 4F.2 | Owner สร้าง Audit function และ Trigger
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ถอน PUBLIC EXECUTE ของ Trigger Function ที่ไม่ควรเรียกทั่วไป
-- @teacher ผล/ชวนสังเกต: การรันผ่าน Trigger มีเงื่อนไขของ Trigger เอง ไม่ได้ให้ App ใช้ Owner privileges ทั้งชุด
-- @teacher SOURCE: 04-security-user-management.sql:562 | รัน SQL นี้ครบทั้ง Statement
REVOKE ALL ON FUNCTION lab_m4_xx.audit_claim_change() FROM PUBLIC;
-- @teacher [END 04-SQL127]

-- @teacher [START 04-SQL128] Lab 4F.2 | Owner สร้าง Audit function และ Trigger
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ผูก AFTER INSERT/UPDATE/DELETE แบบ FOR EACH ROW กับ Claim Table
-- @teacher ผล/ชวนสังเกต: การเปลี่ยนแถวจึงสร้าง Audit ใน Transaction เดียวกัน; ถ้า DML Rollback Audit ก็ Rollback
-- @teacher SOURCE: 04-security-user-management.sql:564 | รัน SQL นี้ครบทั้ง Statement
CREATE TRIGGER trg_claim_secure_audit
AFTER INSERT OR UPDATE OR DELETE ON lab_m4_xx.claim_secure
FOR EACH ROW EXECUTE FUNCTION lab_m4_xx.audit_claim_change();
-- @teacher [END 04-SQL128]

-- @teacher [START 04-SQL129] Lab 4F.2 | Owner สร้าง Audit function และ Trigger
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ห้าม Runtime Write/Approve และ PUBLIC แก้ Audit Table ตรง ๆ
-- @teacher ผล/ชวนสังเกต: Trigger เขียนผ่านสิทธิ์ Owner; App ไม่ต้องได้รับ Audit INSERT/DELETE จึงใช้งานได้
-- @teacher SOURCE: 04-security-user-management.sql:568 | รัน SQL นี้ครบทั้ง Statement
REVOKE ALL ON lab_m4_xx.claim_audit
FROM claimsure_write_xx, claimsure_approve_xx, PUBLIC;
-- @teacher [END 04-SQL129]
-- @teacher [START 04-SQL130] Lab 4F.2 | Owner สร้าง Audit function และ Trigger
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: อนุญาต Auditor อ่าน Audit ที่ Commit แล้ว
-- @teacher ผล/ชวนสังเกต: แยกผู้สร้างเหตุการณ์ออกจากผู้ตรวจสอบหลักฐาน
-- @teacher SOURCE: 04-security-user-management.sql:570 | รัน SQL นี้ครบทั้ง Statement
GRANT SELECT ON lab_m4_xx.claim_audit TO claimsure_audit_xx;
-- @teacher [END 04-SQL130]
-- @teacher [START 04-SQL131] Lab 4F.2 | Owner สร้าง Audit function และ Trigger
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 04-security-user-management.sql:571 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 04-SQL131]
-- END 4F.2


-- START 4F.3 | App เรียก Function และ UPDATE ให้เกิด Audit
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง COMMIT
-- EXPECT: tenant_claims=2 และ UPDATE หนึ่งแถว
-- รอบนี้ COMMIT เพื่อให้ Connection C อ่าน Audit ที่ Commit แล้วได้ใน 4F.6
-- @teacher [START 04-SQL132] Lab 4F.3 | App เรียก Function และ UPDATE ให้เกิด Audit
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:580 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL132]
-- @teacher [START 04-SQL133] Lab 4F.3 | App เรียก Function และ UPDATE ให้เกิด Audit
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ตั้ง Tenant ให้ Connection B ก่อนเรียก Function และแก้ข้อมูล
-- @teacher ผล/ชวนสังเกต: Context นี้ต้องยังอยู่ใน Transaction เดียวกับ SELECT/UPDATE
-- @teacher SOURCE: 04-security-user-management.sql:581 | รัน SQL นี้ครบทั้ง Statement
SELECT set_config('app.tenant_id', '101', true);
-- @teacher [END 04-SQL133]
-- @teacher [START 04-SQL134] Lab 4F.3 | App เรียก Function และ UPDATE ให้เกิด Audit
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: เรียก SECURITY DEFINER Count Function ในฐานะ App
-- @teacher ผล/ชวนสังเกต: คาด tenant_claims=2; การใช้ Owner ใน Function ไม่ควรทำให้หลุด Tenant ที่กำหนด
-- @teacher SOURCE: 04-security-user-management.sql:582 | รัน SQL นี้ครบทั้ง Statement
SELECT lab_m4_xx.claim_count_for_current_tenant() AS tenant_claims;
-- @teacher [END 04-SQL134]

-- @teacher [START 04-SQL135] Lab 4F.3 | App เรียก Function และ UPDATE ให้เกิด Audit
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ให้ App UPDATE Claim 101 เพื่อกระตุ้น AFTER Trigger
-- @teacher ผล/ชวนสังเกต: คาด 1 แถวเปลี่ยนเป็น UNDER_REVIEW; รอบนี้ COMMIT เพื่อให้ Auditor อีก Connection เห็น Audit
-- @teacher SOURCE: 04-security-user-management.sql:584 | รัน SQL นี้ครบทั้ง Statement
UPDATE lab_m4_xx.claim_secure
SET status = 'UNDER_REVIEW', updated_at = clock_timestamp()
WHERE claim_no = 'SEC-101-001'
RETURNING claim_no, status;
-- @teacher [END 04-SQL135]
-- @teacher [START 04-SQL136] Lab 4F.3 | App เรียก Function และ UPDATE ให้เกิด Audit
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 04-security-user-management.sql:588 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 04-SQL136]
-- END 4F.3


-- START 4F.4 | EXPECTED ERROR: App ลบ Audit ไม่ได้
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- RUN: BEGIN ถึง DELETE; EXPECT: SQLSTATE 42501; แล้วรัน 4F.5
-- @teacher [START 04-SQL137] Lab 4F.4 | EXPECTED ERROR: App ลบ Audit ไม่ได้
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:595 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL137]
-- @teacher [START 04-SQL138] Lab 4F.4 | EXPECTED ERROR: App ลบ Audit ไม่ได้
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: Expected Error: App ลบ Audit Table โดยตรง
-- @teacher ผล/ชวนสังเกต: คาด 42501; ใช้ Recovery 4F.5 ไม่ให้ Transaction ที่ Aborted ค้างต่อ
-- @teacher SOURCE: 04-security-user-management.sql:596 | รัน SQL นี้ครบทั้ง Statement
DELETE FROM lab_m4_xx.claim_audit;
-- @teacher [END 04-SQL138]
-- END 4F.4


-- START 4F.5 | RECOVERY หลัง Expected error ของ 4F.4
-- LOGIN: B = claim_app_xx (Connection เดิม)
-- @teacher [START 04-SQL139] Lab 4F.5 | RECOVERY หลัง Expected error ของ 4F.4
-- @teacher LOGIN / DATABASE: B = claim_app_xx (Connection เดิม) | claimsure_xx
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 04-security-user-management.sql:602 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 04-SQL139]
-- END 4F.5


-- START 4F.6 | Auditor อ่านหลักฐานจาก App connection จริง
-- LOGIN: C = internal_auditor_xx (ผู้ใช้ปกติ)
-- EXPECT: actor=claim_app_xx, operation=UPDATE
-- role_setting มักเป็น 'none' เพราะ B Login เป็น App จริง ไม่ได้ใช้ SET ROLE
-- @teacher [START 04-SQL140] Lab 4F.6 | Auditor อ่านหลักฐานจาก App connection จริง
-- @teacher LOGIN / DATABASE: C = internal_auditor_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: Auditor อ่านเหตุการณ์ที่ App Login จริงสร้าง
-- @teacher ผล/ชวนสังเกต: ควรเห็น actor=claim_app_xx, operation=UPDATE; role_setting อาจเป็น none ต่างจาก current_user ใน Definer Function
-- @teacher SOURCE: 04-security-user-management.sql:610 | รัน SQL นี้ครบทั้ง Statement
SELECT event_time, actor, role_setting, operation, claim_id
FROM lab_m4_xx.claim_audit
ORDER BY audit_id DESC
LIMIT 5;
-- @teacher [END 04-SQL140]
-- END 4F.6


-- =============================================================================
-- LAB 4G: Default privileges สำหรับ Object ที่ Owner จะสร้าง
-- =============================================================================

-- START 4G.1 | ตั้ง Defaults แล้วสร้าง Table ในนาม Owner เดียวกัน
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง COMMIT
-- @teacher [START 04-SQL141] Lab 4G.1 | ตั้ง Defaults แล้วสร้าง Table ในนาม Owner เดียวกัน
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:624 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL141]
-- @teacher [START 04-SQL142] Lab 4G.1 | ตั้ง Defaults แล้วสร้าง Table ในนาม Owner เดียวกัน
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ใช้สิทธิ์ claimsure_owner_xx เฉพาะ Transaction เพื่อสร้าง/จัดการ Object ในนาม Owner
-- @teacher ผล/ชวนสังเกต: session_user ยังเป็น student_xx; current_user เปลี่ยนเป็น Owner; ต้องผ่าน 4A.4 และเริ่ม BEGIN แล้ว
-- @teacher SOURCE: 04-security-user-management.sql:625 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL ROLE claimsure_owner_xx;
-- @teacher [END 04-SQL142]

-- @teacher [START 04-SQL143] Lab 4G.1 | ตั้ง Defaults แล้วสร้าง Table ในนาม Owner เดียวกัน
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ตั้ง Default SELECT ของ Tables ที่ Owner นี้จะสร้างใน Schema นี้ต่อไป
-- @teacher ผล/ชวนสังเกต: มีผลตามผู้สร้าง Object ไม่ย้อนหลังไป Table เดิม และไม่ใช่ Defaults ของทุก Role
-- @teacher SOURCE: 04-security-user-management.sql:627 | รัน SQL นี้ครบทั้ง Statement
ALTER DEFAULT PRIVILEGES IN SCHEMA lab_m4_xx
GRANT SELECT ON TABLES TO claimsure_read_xx;
-- @teacher [END 04-SQL143]
-- @teacher [START 04-SQL144] Lab 4G.1 | ตั้ง Defaults แล้วสร้าง Table ในนาม Owner เดียวกัน
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ตั้ง Default USAGE ของ Sequences ที่ Owner จะสร้างในอนาคต
-- @teacher ผล/ชวนสังเกต: ต้องสร้างในนาม Owner เดิม; ไม่ใช่ Grant ย้อนหลังของ Sequences ที่มีอยู่
-- @teacher SOURCE: 04-security-user-management.sql:629 | รัน SQL นี้ครบทั้ง Statement
ALTER DEFAULT PRIVILEGES IN SCHEMA lab_m4_xx
GRANT USAGE ON SEQUENCES TO claimsure_write_xx;
-- @teacher [END 04-SQL144]

-- @teacher [START 04-SQL145] Lab 4G.1 | ตั้ง Defaults แล้วสร้าง Table ในนาม Owner เดียวกัน
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: Owner สร้าง future_note หลังตั้ง Default Privileges เพื่อพิสูจน์กฎ
-- @teacher ผล/ชวนสังเกต: Identity Sequence และ Table นี้เกิดภายใต้ Role ที่ตั้ง Defaults ไว้
-- @teacher SOURCE: 04-security-user-management.sql:632 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE lab_m4_xx.future_note (
    note_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message text NOT NULL
);
-- @teacher [END 04-SQL145]
-- @teacher [START 04-SQL146] Lab 4G.1 | ตั้ง Defaults แล้วสร้าง Table ในนาม Owner เดียวกัน
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: เพิ่มข้อความเพื่อให้ Runtime มีแถวอ่านทดสอบ Default SELECT
-- @teacher ผล/ชวนสังเกต: เป็นข้อมูลที่ Commit ให้ App อ่านใน Connection B ได้จริง
-- @teacher SOURCE: 04-security-user-management.sql:636 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m4_xx.future_note (message)
VALUES ('Created by claimsure_owner_xx after default privileges were configured');
-- @teacher [END 04-SQL146]

-- @teacher [START 04-SQL147] Lab 4G.1 | ตั้ง Defaults แล้วสร้าง Table ในนาม Owner เดียวกัน
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 04-security-user-management.sql:639 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 04-SQL147]
-- Defaults ไม่ย้อนให้สิทธิ์ Table เก่า และไม่สร้าง RLS ให้ Table ใหม่
-- พิจารณาแยก Schema หาก Table อนาคตไม่ควรให้ Read group อ่าน
-- END 4G.1


-- START 4G.2 | App อ่าน Table ใหม่ได้ผ่าน Write -> Read membership
-- LOGIN: B = claim_app_xx (ผู้ใช้ปกติ)
-- EXPECT: ได้หนึ่งแถว โดยไม่ต้อง GRANT SELECT บน future_note เพิ่มเอง
-- @teacher [START 04-SQL148] Lab 4G.2 | App อ่าน Table ใหม่ได้ผ่าน Write -> Read membership
-- @teacher LOGIN / DATABASE: B = claim_app_xx (ผู้ใช้ปกติ) | claimsure_xx
-- @teacher อธิบาย: App อ่าน Table ที่สร้างหลังตั้ง Default Privileges
-- @teacher ผล/ชวนสังเกต: ควรสำเร็จผ่าน Write → Read membership แม้ไม่ได้ GRANT SELECT Table นี้ทีละชื่อ
-- @teacher SOURCE: 04-security-user-management.sql:648 | รัน SQL นี้ครบทั้ง Statement
SELECT note_id, message FROM lab_m4_xx.future_note;
-- @teacher [END 04-SQL148]
-- END 4G.2


-- =============================================================================
-- LAB 4H: student_xx ตรวจสิทธิ์ที่มีผลจริงและ Ownership
-- =============================================================================

-- START 4H.1 | ตรวจสิทธิ์ของ App และ Owner membership
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- RUN: BEGIN ถึง ROLLBACK; ใช้ Owner เพื่อ Resolve ชื่อตารางในการตรวจสิทธิ์
-- EXPECT: true, true, false, true, false, false ตามลำดับ
-- @teacher [START 04-SQL149] Lab 4H.1 | ตรวจสิทธิ์ของ App และ Owner membership
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 04-security-user-management.sql:660 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 04-SQL149]
-- @teacher [START 04-SQL150] Lab 4H.1 | ตรวจสิทธิ์ของ App และ Owner membership
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ใช้สิทธิ์ claimsure_owner_xx เฉพาะ Transaction เพื่อสร้าง/จัดการ Object ในนาม Owner
-- @teacher ผล/ชวนสังเกต: session_user ยังเป็น student_xx; current_user เปลี่ยนเป็น Owner; ต้องผ่าน 4A.4 และเริ่ม BEGIN แล้ว
-- @teacher SOURCE: 04-security-user-management.sql:661 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL ROLE claimsure_owner_xx;
-- @teacher [END 04-SQL150]
-- @teacher [START 04-SQL151] Lab 4H.1 | ตรวจสิทธิ์ของ App และ Owner membership
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ตรวจ Effective Privileges ของ App หลายชั้นใน Query เดียว
-- @teacher ผล/ชวนสังเกต: CONNECT/USAGE/SELECT/INSERT/UPDATE ต้องเทียบกับ Owner membership; App ไม่ควร SET ROLE Owner ได้
-- @teacher SOURCE: 04-security-user-management.sql:662 | รัน SQL นี้ครบทั้ง Statement
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
-- @teacher [END 04-SQL151]
-- @teacher [START 04-SQL152] Lab 4H.1 | ตรวจสิทธิ์ของ App และ Owner membership
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 04-security-user-management.sql:675 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 04-SQL152]
-- END 4H.1


-- START 4H.2 | ตรวจ Membership และ Owner ของตาราง
-- LOGIN: S = student_xx (ผู้ดูแล Lab ของตน)
-- EXPECT: Membership ไม่มี ADMIN; ตารางเป็นของ claimsure_owner_xx
-- claim_secure ต้องมี rls_enabled=true และ force_rls=true
-- @teacher [START 04-SQL153] Lab 4H.2 | ตรวจ Membership และ Owner ของตาราง
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ตรวจ Membership Graph และ Options จาก Catalog
-- @teacher ผล/ชวนสังเกต: ยืนยัน Owner อยู่กับ student_xx และ Groups อยู่กับ Runtime ที่ตรงหน้าที่
-- @teacher SOURCE: 04-security-user-management.sql:683 | รัน SQL นี้ครบทั้ง Statement
SELECT r.rolname AS granted_role, m.rolname AS member,
       am.admin_option, am.inherit_option, am.set_option
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE shobj_description(m.oid, 'pg_authid') = 'Module 4 student xx'
ORDER BY member, granted_role;
-- @teacher [END 04-SQL153]

-- @teacher [START 04-SQL154] Lab 4H.2 | ตรวจ Membership และ Owner ของตาราง
-- @teacher LOGIN / DATABASE: S = student_xx (ผู้ดูแล Lab ของตน) | claimsure_xx
-- @teacher อธิบาย: ตรวจ Object Owner, RLS และ FORCE RLS ของ Tables ใน Lab
-- @teacher ผล/ชวนสังเกต: Owner ควรเป็น claimsure_owner_xx; Table อื่นที่ไม่ต้องแยก Tenant ไม่จำเป็นมี RLS ทุกตัว
-- @teacher SOURCE: 04-security-user-management.sql:691 | รัน SQL นี้ครบทั้ง Statement
SELECT c.relname, pg_get_userbyid(c.relowner) AS owner,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'lab_m4_xx' AND c.relkind = 'r'
ORDER BY c.relname;
-- @teacher [END 04-SQL154]
-- END 4H.2


-- จบ Module 4 แบบ Pure SQL
-- ผลที่ควรเข้าใจ: สร้างตัวตนก่อน -> ให้ Object privileges -> ให้ Membership
-- -> ทดสอบด้วย Login ปกติ -> จำกัด Row/Column -> ปกป้อง Routine/Audit
-- ถ้าต้องการเริ่มใหม่ ใช้ Reset ของ Module 4 นักเรียน xx แล้วทำตั้งแต่ 0 อีกครั้ง
