-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 06-configuration-claim.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/06-configuration-claim.sql
-- @teacher LOGIN / DATABASE เริ่มต้น: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อ่าน README.md ใน Directory นี้ก่อนสอน; ใช้ไฟล์นี้เป็นคู่มือเลือกรันทีละส่วน
-- @teacher แต่ละ SQL มี START/END, Lab, Login, เหตุผล และผลที่ต้องสังเกต; Source Line อ้างไฟล์ต้นฉบับ
-- @teacher START/END ราย SQL ใช้ค้นคำอธิบาย ไม่ใช่ขอบเขต Commit: Transaction/Function ต้องรันครบชุด
-- @teacher คำสั่ง psql ขึ้นต้นด้วย Backslash; SQL Editor ทั่วไปให้ข้ามและจัด Branch/Variables เอง
-- @teacher ทุกบรรทัดที่เพิ่มขึ้นต้น -- @teacher; SQL/psql ต้นฉบับคงเดิม รวมคำสั่งเปลี่ยนข้อมูลและ Expected Errors
-- @teacher เป้าหมาย: Connections, Memory, WAL/Checkpoint, Planner/I/O, Parallelism, Autovacuum
-- @teacher อ่าน labs/module06/README.md; SQL Track อย่างเดียวไม่จบ File Exercises ทั้งหกกลุ่ม
-- @teacher File บน Host: labs/module06/config/conf.d/*.conf; ใน Container: /etc/postgresql/module06/conf.d/*.conf
-- @teacher 6A 10-connections.conf max_connections 40→60: Restart; 6B 20-memory.conf shared_buffers 128→192MB: Restart
-- @teacher 6C 30-wal.conf max_wal_size 1→2GB: Reload; 6D 40-planning.conf random_page_cost 4→1.1: Reload + New Session
-- @teacher 6E 50-parallel.conf max_worker_processes 4→8: Restart; 6F 60-autovacuum.conf cost_limit 200→400: Reload
-- @teacher เก็บ Baseline → เปลี่ยนหนึ่งกลุ่ม → Activate → ตรวจค่าจริง/pending_restart → วัดงานเดิม → คืน Baseline
-- @teacher psql: กำหนด m6_lab=A..F ก่อน Load; ค่า all ทำเฉพาะ SQL Track; m6_reset_table=true จึงทำ Cleanup 6F.3
-- @teacher รักษา Connection เดิมภายใน 6C เพื่อใช้ TEMP Snapshot; หลัง Restart เปิด Connection ใหม่
-- @teacher ==============================================================================
-- =============================================================================
-- Module 6 NEW LABS: six groups, six independent SQL experiments + file exercises.
-- Full sequence / activation / rollback: labs/module06/README.md
-- Slides: docs/slides/module-06-configuration-claim.md
-- LOGIN: postgres | DATABASE: claimsure_m6 | SERVER: dedicated Module 6 instance
-- No Module 1 dependency. Only lab_m6c generated objects are created/changed.
-- Never touches insurance.claim. No SQL statement edits server configuration.
-- Use run-lab06-docker.sh: sql A ... sql F, interleaved with set/reload/restart.
-- sql all runs the SQL track only; it does NOT complete the six file exercises.
-- SQL editor: run complete START/END blocks; exclude psql backslash commands.
-- Keep one connection within each lettered lab. Reconnect after every restart.
-- =============================================================================
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP on
-- @teacher PSQL: ตั้งรูปแบบแสดงผลของ psql ไม่เปลี่ยนข้อมูลใน Database
\pset pager off
-- @teacher PSQL: แสดงเวลาใน Client; แยกจาก Execution Time ใน EXPLAIN
\timing on
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :{?m6_lab}
-- @teacher PSQL: Branch ทางเลือกของ psql; ไม่เลือก Execute ทั้งสอง Branch ใน SQL Editor
\else
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server
  \set m6_lab all
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :{?m6_reset_table}
-- @teacher PSQL: Branch ทางเลือกของ psql; ไม่เลือก Execute ทั้งสอง Branch ใน SQL Editor
\else
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server
  \set m6_reset_table false
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif
-- @teacher [START 06-SQL001] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: แปลงตัวเลือก m6_lab เป็นตัวแปร run_a ถึง run_f สำหรับ psql Branch
-- @teacher ผล/ชวนสังเกต: gset เก็บผลไว้ใน Client; หากใช้ SQL Editor ให้เลือก START/END ของ Lab แทนคำสั่งนี้
-- @teacher SOURCE: 06-configuration-claim.sql:24 | รัน SQL นี้ครบทั้ง Statement
SELECT :'m6_lab' IN ('all','A') AS run_a,
       :'m6_lab' IN ('all','B') AS run_b,
       :'m6_lab' IN ('all','C') AS run_c,
       :'m6_lab' IN ('all','D') AS run_d,
       :'m6_lab' IN ('all','E') AS run_e,
       :'m6_lab' IN ('all','F') AS run_f \gset
-- @teacher [END 06-SQL001]

-- START 0.1 | Verify the dedicated instance and create reusable generated data
-- LOGIN: postgres | RUN: once; subsequent letters reuse the same fixture
-- EXPECT: PostgreSQL 18, claimsure_m6, cluster claimsure-module06; 100000 claim rows
-- @teacher [START 06-SQL002] Lab 0.1 | Verify the dedicated instance and create reusable generated data
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ตรวจ PG18, Primary, Database, cluster_name และ Superuser ก่อนทำ Lab
-- @teacher ผล/ชวนสังเกต: ต้องเป็น Dedicated Module 6 Instance; หาก Guard ไม่ผ่านให้เปลี่ยน Connection ไม่ลบเงื่อนไขทิ้ง
-- @teacher SOURCE: 06-configuration-claim.sql:34 | รัน SQL นี้ครบทั้ง Statement
DO $$
BEGIN
 IF current_setting('server_version_num')::int / 10000 <> 18 THEN
   RAISE EXCEPTION 'This lab targets PostgreSQL 18.';
 END IF;
 IF pg_is_in_recovery() OR current_database() <> 'claimsure_m6'
    OR current_setting('cluster_name') <> 'claimsure-module06' THEN
   RAISE EXCEPTION 'Use the dedicated Module 6 primary (labs/module06), not a classroom/production database.';
 END IF;
 IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname=current_user AND rolsuper) THEN
   RAISE EXCEPTION 'Log in as the dedicated lab postgres superuser.';
 END IF;
END $$;
-- @teacher [END 06-SQL002]
-- @teacher [START 06-SQL003] Lab 0.1 | Verify the dedicated instance and create reusable generated data
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: สร้าง Schema เฉพาะข้อมูลสังเคราะห์ของ Module 6
-- @teacher ผล/ชวนสังเกต: Lab นี้ไม่พึ่ง insurance.claim และไม่ต้องรัน Module 1 ก่อน
-- @teacher SOURCE: 06-configuration-claim.sql:47 | รัน SQL นี้ครบทั้ง Statement
CREATE SCHEMA IF NOT EXISTS lab_m6c;
-- @teacher [END 06-SQL003]
-- @teacher [START 06-SQL004] Lab 0.1 | Verify the dedicated instance and create reusable generated data
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: สร้าง Claim Fixture ที่ใช้ร่วมกันทั้งหกกลุ่ม Parameter
-- @teacher ผล/ชวนสังเกต: IF NOT EXISTS ไม่ตรวจว่า Table เดิมมี Definition ตรงกัน; เริ่มจาก Dedicated Environment ที่กำหนด
-- @teacher SOURCE: 06-configuration-claim.sql:48 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS lab_m6c.claim (
 claim_id bigint PRIMARY KEY, claim_no text UNIQUE NOT NULL,
 policy_id bigint NOT NULL, status text NOT NULL,
 incident_at timestamptz NOT NULL, estimated_amount numeric(14,2) NOT NULL,
 approved_amount numeric(14,2), created_at timestamptz NOT NULL
);
-- @teacher [END 06-SQL004]
-- @teacher [START 06-SQL005] Lab 0.1 | Verify the dedicated instance and create reusable generated data
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: สร้าง Claims 100000 แถวเฉพาะเมื่อ Table ยังว่าง
-- @teacher ผล/ชวนสังเกต: หากมีข้อมูลบางส่วนอยู่จะไม่เติมให้ครบ; ตรวจ generated_claim_rows ก่อนเปรียบเทียบผล
-- @teacher SOURCE: 06-configuration-claim.sql:54 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m6c.claim
SELECT g, 'CLM-M6-' || lpad(g::text,7,'0'), 1+(g%500),
 (ARRAY['NEW','REVIEW','APPROVED','REJECTED','PAID'])[1+(g%5)],
 timestamptz '2026-01-01 00:00:00+00' + g*interval '1 minute',
 1000+(g%150000), CASE WHEN g%5 IN (2,4) THEN 800+(g%100000) END,
 timestamptz '2026-01-01 00:00:00+00' + g*interval '1 minute'
FROM generate_series(1,100000) g
WHERE NOT EXISTS (SELECT FROM lab_m6c.claim);
-- @teacher [END 06-SQL005]
-- @teacher [START 06-SQL006] Lab 0.1 | Verify the dedicated instance and create reusable generated data
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: เก็บ Planner Statistics ของ lab_m6c.claim หลังเตรียมหรือเปลี่ยนข้อมูล
-- @teacher ผล/ชวนสังเกต: ช่วยให้ Estimated Rows/Plan มีฐานข้อมูลล่าสุด; ไม่สร้าง Index และไม่ใช่ VACUUM เก็บ Dead Tuples
-- @teacher SOURCE: 06-configuration-claim.sql:62 | รัน SQL นี้ครบทั้ง Statement
ANALYZE lab_m6c.claim;
-- @teacher [END 06-SQL006]
-- @teacher [START 06-SQL007] Lab 0.1 | Verify the dedicated instance and create reusable generated data
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ยืนยัน Database/User/เวลาเริ่ม Server และจำนวนข้อมูลทดลอง
-- @teacher ผล/ชวนสังเกต: ควรเป็น claimsure_m6 และ 100000 แถว; เวลาเริ่ม Server ใช้เทียบก่อน–หลัง Restart
-- @teacher SOURCE: 06-configuration-claim.sql:63 | รัน SQL นี้ครบทั้ง Statement
SELECT current_database(), session_user, current_user,
       pg_postmaster_start_time(), count(*) AS generated_claim_rows
FROM lab_m6c.claim;
-- @teacher [END 06-SQL007]
-- END 0.1

\echo '\n-- Lab 6A: Connections: intake capacity and time budget'
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :run_a

-- START 6A.1 | Read connection capacity and file activation
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Baseline 40/37 ordinary slots; candidate 60/57 after restart. Slot count is not throughput.
-- @teacher [START 06-SQL008] Lab 6A.1 | Read connection capacity and file activation
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่าน Connection Settings พร้อม Context, Source File และ pending_restart
-- @teacher ผล/ชวนสังเกต: max_connections เป็น postmaster Context; เปลี่ยนไฟล์แล้วต้อง Restart จึงมีผล
-- @teacher SOURCE: 06-configuration-claim.sql:74 | รัน SQL นี้ครบทั้ง Statement
SELECT name, setting, unit, context, sourcefile, pending_restart
FROM pg_settings WHERE name IN ('max_connections','superuser_reserved_connections','reserved_connections')
ORDER BY name;
-- @teacher [END 06-SQL008]
-- @teacher [START 06-SQL009] Lab 6A.1 | Read connection capacity and file activation
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: คำนวณเพดาน Connections ที่ผู้ใช้ทั่วไปใช้ได้หลังหัก Reserved Slots
-- @teacher ผล/ชวนสังเกต: เป็น Capacity ของ Cluster ไม่ใช่จำนวน Active Requests ที่ระบบรองรับได้จริง
-- @teacher SOURCE: 06-configuration-claim.sql:77 | รัน SQL นี้ครบทั้ง Statement
SELECT current_setting('max_connections')::int
 - current_setting('superuser_reserved_connections')::int
 - current_setting('reserved_connections')::int AS ordinary_client_ceiling;
-- @teacher [END 06-SQL009]
-- @teacher [START 06-SQL010] Lab 6A.1 | Read connection capacity and file activation
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: นับ Client Sessions แยก State เพื่อเทียบกับ Connection Budget
-- @teacher ผล/ชวนสังเกต: idle ยังครอง Connection; Pooling ช่วยลด Sessions แต่ต้องดูการรอด้วย
-- @teacher SOURCE: 06-configuration-claim.sql:80 | รัน SQL นี้ครบทั้ง Statement
SELECT state, count(*) AS sessions FROM pg_stat_activity
WHERE backend_type='client backend' GROUP BY state ORDER BY state;
-- @teacher [END 06-SQL010]
-- @teacher [START 06-SQL011] Lab 6A.1 | Read connection capacity and file activation
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่านเวลาเริ่ม PostgreSQL Process เพื่อยืนยันว่าเกิด Restart จริง
-- @teacher ผล/ชวนสังเกต: pg_reload_conf() อย่างเดียวไม่เปลี่ยนเวลานี้; บันทึกค่าก่อน–หลัง File Exercise 6A
-- @teacher SOURCE: 06-configuration-claim.sql:82 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_postmaster_start_time();
-- @teacher [END 06-SQL011]
-- END 6A.1

-- START 6A.2 | Test a claim-intake statement budget and restore it
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: 1s / 500ms / 2min inside; prior defaults return after ROLLBACK. No intentional timeout error.
-- @teacher [START 06-SQL012] Lab 6A.2 | Test a claim-intake statement budget and restore it
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่านค่า statement_timeout ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 06-configuration-claim.sql:88 | รัน SQL นี้ครบทั้ง Statement
SHOW statement_timeout;
-- @teacher [END 06-SQL012]
-- @teacher [START 06-SQL013] Lab 6A.2 | Test a claim-intake statement budget and restore it
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 06-configuration-claim.sql:89 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 06-SQL013]
-- @teacher [START 06-SQL014] Lab 6A.2 | Test a claim-intake statement budget and restore it
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ทดลอง statement_timeout='1s' เฉพาะ Transaction นี้
-- @teacher ผล/ชวนสังเกต: ไม่แก้ Configuration File; ตรวจด้วย current_setting/SHOW และต้อง COMMIT/ROLLBACK เพื่อคืนค่า
-- @teacher SOURCE: 06-configuration-claim.sql:90 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL statement_timeout = '1s';
-- @teacher [END 06-SQL014]
-- @teacher [START 06-SQL015] Lab 6A.2 | Test a claim-intake statement budget and restore it
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ทดลอง lock_timeout='500ms' เฉพาะ Transaction นี้
-- @teacher ผล/ชวนสังเกต: ไม่แก้ Configuration File; ตรวจด้วย current_setting/SHOW และต้อง COMMIT/ROLLBACK เพื่อคืนค่า
-- @teacher SOURCE: 06-configuration-claim.sql:91 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL lock_timeout = '500ms';
-- @teacher [END 06-SQL015]
-- @teacher [START 06-SQL016] Lab 6A.2 | Test a claim-intake statement budget and restore it
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ทดลอง idle_in_transaction_session_timeout='2min' เฉพาะ Transaction นี้
-- @teacher ผล/ชวนสังเกต: ไม่แก้ Configuration File; ตรวจด้วย current_setting/SHOW และต้อง COMMIT/ROLLBACK เพื่อคืนค่า
-- @teacher SOURCE: 06-configuration-claim.sql:92 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL idle_in_transaction_session_timeout = '2min';
-- @teacher [END 06-SQL016]
-- @teacher [START 06-SQL017] Lab 6A.2 | Test a claim-intake statement budget and restore it
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่าน Timeout ทั้งสามภายใน Transaction ที่ใช้ SET LOCAL
-- @teacher ผล/ชวนสังเกต: แสดงค่าชั่วคราว 1s/500ms/2min; Statement Timeout นับเวลาของ Statement ส่วน Lock Timeout นับเวลารอ Lock
-- @teacher SOURCE: 06-configuration-claim.sql:93 | รัน SQL นี้ครบทั้ง Statement
SELECT current_setting('statement_timeout'), current_setting('lock_timeout'),
       current_setting('idle_in_transaction_session_timeout');
-- @teacher [END 06-SQL017]
-- @teacher [START 06-SQL018] Lab 6A.2 | Test a claim-intake statement budget and restore it
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: รันงานค้นหา NEW ภายใต้ Time Budget โดยไม่จงใจสร้าง Timeout
-- @teacher ผล/ชวนสังเกต: ได้ 20000 แถวตาม Fixture; Query นี้มักเสร็จเร็วกว่า 1s จึงไม่จำเป็นต้องมี Error
-- @teacher SOURCE: 06-configuration-claim.sql:95 | รัน SQL นี้ครบทั้ง Statement
SELECT count(*) FROM lab_m6c.claim WHERE status='NEW';
-- @teacher [END 06-SQL018]
-- @teacher [START 06-SQL019] Lab 6A.2 | Test a claim-intake statement budget and restore it
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 06-configuration-claim.sql:96 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 06-SQL019]
-- @teacher [START 06-SQL020] Lab 6A.2 | Test a claim-intake statement budget and restore it
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่านค่า statement_timeout ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 06-configuration-claim.sql:97 | รัน SQL นี้ครบทั้ง Statement
SHOW statement_timeout;
-- @teacher [END 06-SQL020]
-- END 6A.2

-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif

\echo '\n-- Lab 6B: Memory: shared cache versus report workspace'
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :run_b

-- START 6B.1 | Inspect the cache allocation separately from the workspace
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: shared_buffers baseline 128MB, candidate 192MB only after restart; work_mem stays 4MB.
-- @teacher [START 06-SQL021] Lab 6B.1 | Inspect the cache allocation separately from the workspace
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: แยก Shared Cache, Per-operation Workspace และ Maintenance Memory
-- @teacher ผล/ชวนสังเกต: shared_buffers ต้อง Restart; work_mem ไม่ใช่ Memory จองตายตัวต่อ Connection และ Hash อาจใช้ตัวคูณ
-- @teacher SOURCE: 06-configuration-claim.sql:108 | รัน SQL นี้ครบทั้ง Statement
SELECT name, setting, unit, context, sourcefile, pending_restart
FROM pg_settings WHERE name IN ('shared_buffers','work_mem','hash_mem_multiplier','maintenance_work_mem')
ORDER BY name;
-- @teacher [END 06-SQL021]
-- @teacher [START 06-SQL022] Lab 6B.1 | Inspect the cache allocation separately from the workspace
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่านขนาด Heap เพื่อประเมิน Working Set ก่อนทดลอง Memory
-- @teacher ผล/ชวนสังเกต: ไม่รวม Index/TOAST ทั้งหมด; ขนาดเล็กอาจทำให้ผล Cache และ Memory ไม่เหมือน Production
-- @teacher SOURCE: 06-configuration-claim.sql:111 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_size_pretty(pg_relation_size('lab_m6c.claim')) AS claim_table_size;
-- @teacher [END 06-SQL022]
-- END 6B.1

-- START 6B.2 | Compare three work_mem values with three repeated report sorts
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Nine results; compare temp blocks, sort space and median time. SET LOCAL inside function ends at statement completion.
-- @teacher [START 06-SQL023] Lab 6B.2 | Compare three work_mem values with three repeated report sorts
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ลบ Table ทดลอง lab_m6c.work_mem_results เดิมพร้อมข้อมูลเพื่อเริ่มรอบที่เทียบกันได้
-- @teacher ผล/ชวนสังเกต: ตรวจชื่อและ Database ให้ตรงก่อนรัน; ไม่ใช้คำสั่งนี้กับ Table ธุรกิจที่ต้องเก็บ
-- @teacher SOURCE: 06-configuration-claim.sql:117 | รัน SQL นี้ครบทั้ง Statement
DROP TABLE IF EXISTS lab_m6c.work_mem_results;
-- @teacher [END 06-SQL023]
-- @teacher [START 06-SQL024] Lab 6B.2 | Compare three work_mem values with three repeated report sorts
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: สร้างตารางหลักฐานการ Sort แยก Label และ Run Number
-- @teacher ผล/ชวนสังเกต: เก็บ Sort Method/Space, Temp Blocks และเวลา แทนการสรุปจากเวลา Query ครั้งเดียว
-- @teacher SOURCE: 06-configuration-claim.sql:118 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE lab_m6c.work_mem_results (
    test_label text NOT NULL,
    tested_work_mem text NOT NULL,
    run_no integer NOT NULL,
    sort_method text,
    sort_space_type text,
    sort_space_kb bigint,
    temp_read_blocks bigint,
    temp_written_blocks bigint,
    execution_ms numeric,
    measured_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
-- @teacher [END 06-SQL024]

-- @teacher [START 06-SQL025] Lab 6B.2 | Compare three work_mem values with three repeated report sorts
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: สร้าง Function ที่ตั้ง work_mem แบบ Local แล้ว EXPLAIN JSON งาน Sort เดิมและบันทึก Metrics
-- @teacher ผล/ชวนสังเกต: ปิด Parallel/Incremental Sort เฉพาะการทดลองเพื่อให้เทียบ Full Sort ได้; Function เป็นคำสั่งเดียว ต้องรันครบถึง Dollar Quote ปิด
-- @teacher SOURCE: 06-configuration-claim.sql:131 | รัน SQL นี้ครบทั้ง Statement
CREATE OR REPLACE FUNCTION lab_m6c.measure_open_claim_report_sort(
    p_label text,
    p_work_mem text,
    p_run_no integer
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    plan_json jsonb;
    sort_node jsonb;
BEGIN
    PERFORM set_config('work_mem', p_work_mem, true);
    PERFORM set_config('max_parallel_workers_per_gather', '0', true);
    -- Keep a full Sort for this workspace experiment, including after Lab 6D's
    -- index exists. Otherwise an Incremental Sort has different JSON metrics.
    PERFORM set_config('enable_incremental_sort', 'off', true);

    EXECUTE $plan$
        EXPLAIN (ANALYZE, BUFFERS, SETTINGS, FORMAT JSON)
        SELECT claim_no, policy_id, status, incident_at,
               estimated_amount, approved_amount, created_at
        FROM lab_m6c.claim
        WHERE status IN ('NEW', 'REVIEW', 'APPROVED')
        ORDER BY policy_id, status, estimated_amount DESC, claim_no
    $plan$ INTO plan_json;

    sort_node := plan_json->0->'Plan';

    INSERT INTO lab_m6c.work_mem_results (
        test_label, tested_work_mem, run_no,
        sort_method, sort_space_type, sort_space_kb,
        temp_read_blocks, temp_written_blocks, execution_ms
    )
    VALUES (
        p_label,
        p_work_mem,
        p_run_no,
        sort_node->>'Sort Method',
        sort_node->>'Sort Space Type',
        COALESCE((sort_node->>'Sort Space Used')::bigint, 0),
        COALESCE((sort_node->>'Temp Read Blocks')::bigint, 0),
        COALESCE((sort_node->>'Temp Written Blocks')::bigint, 0),
        (plan_json->0->>'Execution Time')::numeric
    );
END
$$;
-- @teacher [END 06-SQL025]

-- @teacher [START 06-SQL026] Lab 6B.2 | Compare three work_mem values with three repeated report sorts
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ทดลอง 64kB, 4MB, 32MB อย่างละสามรอบ รวมเก้าผลการวัด
-- @teacher ผล/ชวนสังเกต: EXPLAIN ANALYZE รัน Query จริง; เก้ารอบอยู่ใน Statement เดียวและ Local Settings คืนเมื่อจบ Transaction
-- @teacher SOURCE: 06-configuration-claim.sql:178 | รัน SQL นี้ครบทั้ง Statement
SELECT lab_m6c.measure_open_claim_report_sort(v.label, v.work_mem, r.run_no)
FROM (VALUES
    ('very_small', '64kB'),
    ('middle_test', '4MB'),
    ('candidate', '32MB')
) AS v(label, work_mem)
CROSS JOIN generate_series(1, 3) AS r(run_no);
-- @teacher [END 06-SQL026]

-- @teacher [START 06-SQL027] Lab 6B.2 | Compare three work_mem values with three repeated report sorts
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: สรุปจำนวนรอบ, Temp Spill และ Median ของแต่ละ Work Memory
-- @teacher ผล/ชวนสังเกต: ควรได้สาม Labels และ Label ละสามรอบ; Space Type/เวลาเป็นผลจริงของเครื่อง ไม่รับประกันว่าค่ามากสุดเร็วสุด
-- @teacher SOURCE: 06-configuration-claim.sql:186 | รัน SQL นี้ครบทั้ง Statement
SELECT test_label,
       tested_work_mem,
       count(*) AS runs,
       min(sort_method) AS sort_method,
       min(sort_space_type) AS sort_space_type,
       max(temp_written_blocks) AS max_temp_written_blocks,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY execution_ms)::numeric, 2)
           AS median_execution_ms,
       max(sort_space_kb) AS max_sort_space_kb
FROM lab_m6c.work_mem_results
GROUP BY test_label, tested_work_mem
ORDER BY min(measured_at);
-- @teacher [END 06-SQL027]
-- END 6B.2

-- START 6B.3 | Budget report memory and verify restoration
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Illustration 256MB; session work_mem is restored. Cache size alone does not prove a faster sort.
-- @teacher [START 06-SQL028] Lab 6B.3 | Budget report memory and verify restoration
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: คูณ Budget 32MB × 4 Reports × 2 Sort Nodes × 1 Process
-- @teacher ผล/ชวนสังเกต: ได้ 256MB เป็นภาพประมาณ Workspace ไม่ใช่เพดาน RSS ทั้งระบบ; Hash/Workers/งานอื่นต้องเผื่อเพิ่ม
-- @teacher SOURCE: 06-configuration-claim.sql:203 | รัน SQL นี้ครบทั้ง Statement
SELECT 32 AS work_mem_mb, 4 AS reports, 2 AS sort_nodes, 1 AS processes,
       32*4*2*1 AS estimated_workspace_mb;
-- @teacher [END 06-SQL028]
-- @teacher [START 06-SQL029] Lab 6B.3 | Budget report memory and verify restoration
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่านค่า work_mem ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 06-configuration-claim.sql:205 | รัน SQL นี้ครบทั้ง Statement
SHOW work_mem;
-- @teacher [END 06-SQL029]
-- Add hash multipliers, launched workers and other allocations to the full budget.
-- Keep the smallest tested value meeting the workload goal; no global 32MB change.
-- END 6B.3

-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif

\echo '\n-- Lab 6C: WAL / checkpoints: event durability and pacing'
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :run_c

-- START 6C.1 | Snapshot checkpoints and the WAL insert position
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Keep same connection for 6C.1–6C.2. Baseline max_wal_size 1GB; candidate 2GB after reload.
-- @teacher [START 06-SQL030] Lab 6C.1 | Snapshot checkpoints and the WAL insert position
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: เตรียม Logged Event Table เพื่อสร้าง WAL จากงานธุรกิจจำลอง
-- @teacher ผล/ชวนสังเกต: Identity Sequence และ Index ก็มีต้นทุน; อย่าใช้ UNLOGGED แทนเมื่อกำลังวัด WAL
-- @teacher SOURCE: 06-configuration-claim.sql:218 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS lab_m6c.claim_event (
 event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 claim_no text NOT NULL, payload jsonb NOT NULL
);
-- @teacher [END 06-SQL030]
-- @teacher [START 06-SQL031] Lab 6C.1 | Snapshot checkpoints and the WAL insert position
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ล้างทุกแถวใน lab_m6c.claim_event เพื่อ Reset Dataset ของ Lab
-- @teacher ผล/ชวนสังเกต: TRUNCATE ไม่ใช่ DELETE มี WHERE; ตรวจ Scope ก่อนรันและทำก่อนเก็บ Baseline ของรอบใหม่
-- @teacher SOURCE: 06-configuration-claim.sql:222 | รัน SQL นี้ครบทั้ง Statement
TRUNCATE lab_m6c.claim_event;
-- @teacher [END 06-SQL031]
-- @teacher [START 06-SQL032] Lab 6C.1 | Snapshot checkpoints and the WAL insert position
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ลบ Table ทดลอง pg_temp.m6_wal_before เดิมพร้อมข้อมูลเพื่อเริ่มรอบที่เทียบกันได้
-- @teacher ผล/ชวนสังเกต: ตรวจชื่อและ Database ให้ตรงก่อนรัน; ไม่ใช้คำสั่งนี้กับ Table ธุรกิจที่ต้องเก็บ
-- @teacher SOURCE: 06-configuration-claim.sql:223 | รัน SQL นี้ครบทั้ง Statement
DROP TABLE IF EXISTS pg_temp.m6_wal_before;
-- @teacher [END 06-SQL032]
-- @teacher [START 06-SQL033] Lab 6C.1 | Snapshot checkpoints and the WAL insert position
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: เก็บ WAL Insert LSN และ Checkpointer Counters ลง TEMP Table ก่อนโหลด
-- @teacher ผล/ชวนสังเกต: ต้องใช้ Connection เดิมใน 6C.2; TEMP Table จะหายเมื่อ Disconnect
-- @teacher SOURCE: 06-configuration-claim.sql:224 | รัน SQL นี้ครบทั้ง Statement
CREATE TEMP TABLE m6_wal_before AS
SELECT clock_timestamp() AS sampled_at, pg_current_wal_insert_lsn() AS lsn, c.*
FROM pg_stat_checkpointer c;
-- @teacher [END 06-SQL033]
-- @teacher [START 06-SQL034] Lab 6C.1 | Snapshot checkpoints and the WAL insert position
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่าน Durability และ Checkpoint Parameters เพื่อเชื่อมกับพฤติกรรมการเขียน
-- @teacher ผล/ชวนสังเกต: File Exercise เปลี่ยน max_wal_size และ Reload; อย่าปิด fsync/full_page_writes เพื่อทำให้ตัวเลขสวย
-- @teacher SOURCE: 06-configuration-claim.sql:227 | รัน SQL นี้ครบทั้ง Statement
SELECT name, setting, unit, context, sourcefile, pending_restart
FROM pg_settings WHERE name IN ('fsync','full_page_writes','synchronous_commit',
 'max_wal_size','checkpoint_timeout','checkpoint_completion_target') ORDER BY name;
-- @teacher [END 06-SQL034]
-- END 6C.1

-- START 6C.2 | Generate 5000 claim events and read counter deltas
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: 5000 events; WAL span > 0, valid reset epoch. Zero checkpoint deltas do not prove a sizing benefit.
-- @teacher [START 06-SQL035] Lab 6C.2 | Generate 5000 claim events and read counter deltas
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: Commit การสร้าง Events 5000 รายการเพื่อให้เกิด WAL Workload
-- @teacher ผล/ชวนสังเกต: ใช้ Autocommit ตามคู่มือ; max_wal_size ไม่ได้จำกัดปริมาณ WAL แบบ Hard Limit
-- @teacher SOURCE: 06-configuration-claim.sql:235 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m6c.claim_event(claim_no,payload)
SELECT 'CLM-M6-'||lpad(g::text,7,'0'),
 jsonb_build_object('event','REVIEW','amount',1000+g)
FROM generate_series(1,5000) g;
-- @teacher [END 06-SQL035]
-- @teacher [START 06-SQL036] Lab 6C.2 | Generate 5000 claim events and read counter deltas
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ล้าง Stats Snapshot ที่ Backend Cache ไว้ก่อนอ่านผลใหม่
-- @teacher ผล/ชวนสังเกต: ไม่ได้ Reset Counters ของระบบและไม่ได้บังคับให้เกิด Checkpoint
-- @teacher SOURCE: 06-configuration-claim.sql:239 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_stat_clear_snapshot();
-- @teacher [END 06-SQL036]
-- @teacher [START 06-SQL037] Lab 6C.2 | Generate 5000 claim events and read counter deltas
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: คำนวณส่วนต่าง WAL Bytes และ Checkpoint Counters พร้อมตรวจ stats_reset
-- @teacher ผล/ชวนสังเกต: ถ้า counters_comparable=false ห้ามใช้ Delta; LSN/Counters เป็นระดับ Cluster จึงรวมงานอื่นด้วย และ Checkpoint อาจยังไม่เกิด
-- @teacher SOURCE: 06-configuration-claim.sql:240 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_wal_lsn_diff(pg_current_wal_insert_lsn(),b.lsn)::bigint AS wal_bytes,
 round(extract(epoch FROM clock_timestamp()-b.sampled_at)::numeric,3) AS elapsed_seconds,
 c.num_timed-b.num_timed AS timed_delta,
 c.num_requested-b.num_requested AS requested_delta,
 c.num_done-b.num_done AS completed_delta,
 c.buffers_written-b.buffers_written AS written_delta,
 c.stats_reset IS NOT DISTINCT FROM b.stats_reset AS counters_comparable
FROM pg_stat_checkpointer c CROSS JOIN m6_wal_before b;
-- @teacher [END 06-SQL037]
-- @teacher [START 06-SQL038] Lab 6C.2 | Generate 5000 claim events and read counter deltas
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ตรวจว่ามี Events 5000 แถวหลังจบโหลด
-- @teacher ผล/ชวนสังเกต: Row Count ยืนยันโหลดสำเร็จ แต่ไม่ใช่หลักฐานว่า Backup/Restore ใช้ได้
-- @teacher SOURCE: 06-configuration-claim.sql:248 | รัน SQL นี้ครบทั้ง Statement
SELECT count(*) AS event_rows FROM lab_m6c.claim_event;
-- @teacher [END 06-SQL038]
-- WAL span can include background work. Short checkpoint deltas may be zero.
-- Restart between runs adds a shutdown checkpoint: do not compare cumulative totals.
-- END 6C.2

-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif

\echo '\n-- Lab 6D: Planning / storage: indexed ClaimSure search'
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :run_d

-- START 6D.1 | Prepare the same index before either planner test
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Indexed baseline/candidate uses identical query, data and index; record estimated/actual rows, buffers and time.
-- @teacher [START 06-SQL039] Lab 6D.1 | Prepare the same index before either planner test
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: สร้าง Index เดียวกันก่อนทั้ง Baseline และ Candidate เพื่อแยกผล Parameter
-- @teacher ผล/ชวนสังเกต: ไม่เปลี่ยน Index ระหว่างสองรอบ; มิฉะนั้นแยกสาเหตุของผลที่ต่างไม่ได้
-- @teacher SOURCE: 06-configuration-claim.sql:261 | รัน SQL นี้ครบทั้ง Statement
CREATE INDEX IF NOT EXISTS claim_policy_status_idx
ON lab_m6c.claim(policy_id,status);
-- @teacher [END 06-SQL039]
-- @teacher [START 06-SQL040] Lab 6D.1 | Prepare the same index before either planner test
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: เก็บ Planner Statistics ของ lab_m6c.claim หลังเตรียมหรือเปลี่ยนข้อมูล
-- @teacher ผล/ชวนสังเกต: ช่วยให้ Estimated Rows/Plan มีฐานข้อมูลล่าสุด; ไม่สร้าง Index และไม่ใช่ VACUUM เก็บ Dead Tuples
-- @teacher SOURCE: 06-configuration-claim.sql:263 | รัน SQL นี้ครบทั้ง Statement
ANALYZE lab_m6c.claim;
-- @teacher [END 06-SQL040]
-- @teacher [START 06-SQL041] Lab 6D.1 | Prepare the same index before either planner test
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่าน Planner Cost, Cache Estimate, I/O และ Statistics Settings
-- @teacher ผล/ชวนสังเกต: effective_cache_size เป็น Estimate ให้ Planner ไม่ได้จัดสรร Memory; sourcefile ช่วยหาไฟล์ที่ต้องแก้
-- @teacher SOURCE: 06-configuration-claim.sql:264 | รัน SQL นี้ครบทั้ง Statement
SELECT name, setting, unit, context, sourcefile
FROM pg_settings WHERE name IN ('random_page_cost','effective_cache_size',
 'effective_io_concurrency','default_statistics_target') ORDER BY name;
-- @teacher [END 06-SQL041]
-- @teacher [START 06-SQL042] Lab 6D.1 | Prepare the same index before either planner test
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: วัด Query กรอง policy_id/status ก่อนปรับ random_page_cost
-- @teacher ผล/ชวนสังเกต: จด Plan/Actual Rows/Buffers/เวลา; ต้องใช้ Dataset, Index และ Query เดียวกับรอบ Candidate
-- @teacher SOURCE: 06-configuration-claim.sql:267 | รัน SQL นี้ครบทั้ง Statement
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT claim_no, policy_id, status, estimated_amount
FROM lab_m6c.claim WHERE policy_id=1 AND status='NEW'
ORDER BY estimated_amount DESC, claim_no;
-- @teacher [END 06-SQL042]
-- END 6D.1

-- START 6D.2 | Test random_page_cost narrowly before adopting a file default
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Prior file/session value restored. A plan change or speedup is not guaranteed; repeat comparable runs.
-- @teacher [START 06-SQL043] Lab 6D.2 | Test random_page_cost narrowly before adopting a file default
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 06-configuration-claim.sql:276 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 06-SQL043]
-- @teacher [START 06-SQL044] Lab 6D.2 | Test random_page_cost narrowly before adopting a file default
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ทดลอง random_page_cost=1.1 เฉพาะ Transaction นี้
-- @teacher ผล/ชวนสังเกต: ไม่แก้ Configuration File; ตรวจด้วย current_setting/SHOW และต้อง COMMIT/ROLLBACK เพื่อคืนค่า
-- @teacher SOURCE: 06-configuration-claim.sql:277 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL random_page_cost = 1.1;
-- @teacher [END 06-SQL044]
-- @teacher [START 06-SQL045] Lab 6D.2 | Test random_page_cost narrowly before adopting a file default
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: วัด Query เดิมภายใต้ random_page_cost=1.1 แบบ Transaction-local
-- @teacher ผล/ชวนสังเกต: Plan อาจเหมือนเดิม; ค่า Cost เป็นหน่วยเปรียบเทียบ ไม่ใช่ Milliseconds และต้องพิสูจน์กับโหลดจริง
-- @teacher SOURCE: 06-configuration-claim.sql:278 | รัน SQL นี้ครบทั้ง Statement
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT claim_no, policy_id, status, estimated_amount
FROM lab_m6c.claim WHERE policy_id=1 AND status='NEW'
ORDER BY estimated_amount DESC, claim_no;
-- @teacher [END 06-SQL045]
-- @teacher [START 06-SQL046] Lab 6D.2 | Test random_page_cost narrowly before adopting a file default
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 06-configuration-claim.sql:282 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 06-SQL046]
-- @teacher [START 06-SQL047] Lab 6D.2 | Test random_page_cost narrowly before adopting a file default
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่านค่า random_page_cost ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 06-configuration-claim.sql:283 | รัน SQL นี้ครบทั้ง Statement
SHOW random_page_cost;
-- @teacher [END 06-SQL047]
-- END 6D.2

-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif

\echo '\n-- Lab 6E: Parallelism: reserve aggregate and worker budgets'
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :run_e

-- START 6E.1 | Read worker capacity and compare serial versus eligible parallel plans
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: File capacity 4→8 requires restart. Per-query 0/2 needs no restart; actual launched workers may be zero.
-- @teacher [START 06-SQL048] Lab 6E.1 | Read worker capacity and compare serial versus eligible parallel plans
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่าน Worker Pool, Global Parallel Limit และ Per-Gather Limit
-- @teacher ผล/ชวนสังเกต: max_worker_processes ต้อง Restart; เพิ่ม Per-Gather อย่างเดียวไม่ได้สร้าง Worker Capacity เพิ่ม
-- @teacher SOURCE: 06-configuration-claim.sql:294 | รัน SQL นี้ครบทั้ง Statement
SELECT name, setting, context, sourcefile, pending_restart
FROM pg_settings WHERE name IN ('max_worker_processes','max_parallel_workers',
 'max_parallel_workers_per_gather') ORDER BY name;
-- @teacher [END 06-SQL048]
-- @teacher [START 06-SQL049] Lab 6E.1 | Read worker capacity and compare serial versus eligible parallel plans
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 06-configuration-claim.sql:297 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 06-SQL049]
-- @teacher [START 06-SQL050] Lab 6E.1 | Read worker capacity and compare serial versus eligible parallel plans
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ทดลอง max_parallel_workers_per_gather=0 เฉพาะ Transaction นี้
-- @teacher ผล/ชวนสังเกต: ไม่แก้ Configuration File; ตรวจด้วย current_setting/SHOW และต้อง COMMIT/ROLLBACK เพื่อคืนค่า
-- @teacher SOURCE: 06-configuration-claim.sql:298 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL max_parallel_workers_per_gather = 0;
-- @teacher [END 06-SQL050]
-- @teacher [START 06-SQL051] Lab 6E.1 | Read worker capacity and compare serial versus eligible parallel plans
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: วัด Aggregate โดยปิด Parallel Workers เฉพาะ Transaction นี้
-- @teacher ผล/ชวนสังเกต: ใช้เป็น Serial Baseline; อ่าน Actual Rows/Execution Time/Buffers ก่อนเปรียบเทียบ
-- @teacher SOURCE: 06-configuration-claim.sql:299 | รัน SQL นี้ครบทั้ง Statement
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT policy_id, sum(estimated_amount) AS reserve_amount
FROM lab_m6c.claim WHERE status IN ('NEW','REVIEW','APPROVED')
GROUP BY policy_id;
-- @teacher [END 06-SQL051]
-- @teacher [START 06-SQL052] Lab 6E.1 | Read worker capacity and compare serial versus eligible parallel plans
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 06-configuration-claim.sql:303 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 06-SQL052]
-- @teacher [START 06-SQL053] Lab 6E.1 | Read worker capacity and compare serial versus eligible parallel plans
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 06-configuration-claim.sql:304 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 06-SQL053]
-- @teacher [START 06-SQL054] Lab 6E.1 | Read worker capacity and compare serial versus eligible parallel plans
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ทดลอง max_parallel_workers_per_gather=2 เฉพาะ Transaction นี้
-- @teacher ผล/ชวนสังเกต: ไม่แก้ Configuration File; ตรวจด้วย current_setting/SHOW และต้อง COMMIT/ROLLBACK เพื่อคืนค่า
-- @teacher SOURCE: 06-configuration-claim.sql:305 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL max_parallel_workers_per_gather = 2;
-- @teacher [END 06-SQL054]
-- @teacher [START 06-SQL055] Lab 6E.1 | Read worker capacity and compare serial versus eligible parallel plans
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อนุญาตได้สอง Parallel Workers แล้ววัด Aggregate เดิม
-- @teacher ผล/ชวนสังเกต: อาจยังเป็น Serial ถ้า Planner ประเมินว่าเหมาะกว่า; ถ้ามี Gather ให้เทียบ Workers Planned กับ Launched
-- @teacher SOURCE: 06-configuration-claim.sql:306 | รัน SQL นี้ครบทั้ง Statement
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT policy_id, sum(estimated_amount) AS reserve_amount
FROM lab_m6c.claim WHERE status IN ('NEW','REVIEW','APPROVED')
GROUP BY policy_id;
-- @teacher [END 06-SQL055]
-- @teacher [START 06-SQL056] Lab 6E.1 | Read worker capacity and compare serial versus eligible parallel plans
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 06-configuration-claim.sql:310 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 06-SQL056]
-- @teacher [START 06-SQL057] Lab 6E.1 | Read worker capacity and compare serial versus eligible parallel plans
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่านค่า max_parallel_workers_per_gather ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 06-configuration-claim.sql:311 | รัน SQL นี้ครบทั้ง Statement
SHOW max_parallel_workers_per_gather;
-- @teacher [END 06-SQL057]
-- END 6E.1

-- START 6E.2 | Calculate a report process memory illustration
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Illustration 384MB for workspaces; do not raise concurrency from a single faster report.
-- @teacher [START 06-SQL058] Lab 6E.2 | Calculate a report process memory illustration
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ประมาณ Workspace สำหรับ Leader+2 Workers และ Reports พร้อมกันสี่งาน
-- @teacher ผล/ชวนสังเกต: 16 × 2 × 3 × 4 = 384MB เป็นตัวอย่าง Budget ไม่ใช่การวัด Memory จริง
-- @teacher SOURCE: 06-configuration-claim.sql:317 | รัน SQL นี้ครบทั้ง Statement
SELECT 16 AS work_mem_mb, 2 AS sort_nodes, 3 AS leader_plus_workers,
       4 AS concurrent_reports, 16*2*3*4 AS estimated_workspace_mb;
-- @teacher [END 06-SQL058]
-- Capacity ceilings do not allocate all those workers. Read EXPLAIN and CPU.
-- Account separately for hash multipliers, other worker users and shared memory.
-- END 6E.2

-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif

\echo '\n-- Lab 6F: Autovacuum: review queue churn and targeted thresholds'
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :run_f

-- START 6F.1 | Prepare a 20000-row review queue and baseline counters
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Fresh 20000-row queue each run; cost limit 200→400 uses reload. PostgreSQL 18 worker slots require restart.
-- @teacher [START 06-SQL059] Lab 6F.1 | Prepare a 20000-row review queue and baseline counters
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ลบ Table ทดลอง lab_m6c.claim_queue เดิมพร้อมข้อมูลเพื่อเริ่มรอบที่เทียบกันได้
-- @teacher ผล/ชวนสังเกต: ตรวจชื่อและ Database ให้ตรงก่อนรัน; ไม่ใช้คำสั่งนี้กับ Table ธุรกิจที่ต้องเก็บ
-- @teacher SOURCE: 06-configuration-claim.sql:331 | รัน SQL นี้ครบทั้ง Statement
DROP TABLE IF EXISTS lab_m6c.claim_queue;
-- @teacher [END 06-SQL059]
-- @teacher [START 06-SQL060] Lab 6F.1 | Prepare a 20000-row review queue and baseline counters
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: สร้าง Queue สำหรับทดลอง Update Churn แยกจาก Claim Fixture หลัก
-- @teacher ผล/ชวนสังเกต: การสร้างใหม่ Reset ประวัติของตารางนี้ จึงต้องเก็บ Baseline ก่อน UPDATE
-- @teacher SOURCE: 06-configuration-claim.sql:332 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE lab_m6c.claim_queue (
 claim_id bigint PRIMARY KEY, status text NOT NULL, note text NOT NULL
);
-- @teacher [END 06-SQL060]
-- @teacher [START 06-SQL061] Lab 6F.1 | Prepare a 20000-row review queue and baseline counters
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: เติม Queue 20000 แถวให้มีฐานจำนวน Rows สำหรับคำนวณ Trigger
-- @teacher ผล/ชวนสังเกต: ทุกแถวเริ่ม NEW; note ยาวพอให้ UPDATE สร้าง Tuple Versions ที่สังเกตได้
-- @teacher SOURCE: 06-configuration-claim.sql:335 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m6c.claim_queue SELECT g,'NEW',repeat('claim review ',8)
FROM generate_series(1,20000) g;
-- @teacher [END 06-SQL061]
-- @teacher [START 06-SQL062] Lab 6F.1 | Prepare a 20000-row review queue and baseline counters
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: เก็บ Planner Statistics ของ lab_m6c.claim_queue หลังเตรียมหรือเปลี่ยนข้อมูล
-- @teacher ผล/ชวนสังเกต: ช่วยให้ Estimated Rows/Plan มีฐานข้อมูลล่าสุด; ไม่สร้าง Index และไม่ใช่ VACUUM เก็บ Dead Tuples
-- @teacher SOURCE: 06-configuration-claim.sql:337 | รัน SQL นี้ครบทั้ง Statement
ANALYZE lab_m6c.claim_queue;
-- @teacher [END 06-SQL062]
-- @teacher [START 06-SQL063] Lab 6F.1 | Prepare a 20000-row review queue and baseline counters
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่านสถานะ Autovacuum พร้อม Worker/Cost Limit และ Activation Context
-- @teacher ผล/ชวนสังเกต: File Exercise เปลี่ยน autovacuum_vacuum_cost_limit แล้ว Reload; ดู pending_restart ของแต่ละ Parameter ตามจริง
-- @teacher SOURCE: 06-configuration-claim.sql:338 | รัน SQL นี้ครบทั้ง Statement
SELECT name, setting, unit, context, sourcefile, pending_restart
FROM pg_settings WHERE name IN ('autovacuum','autovacuum_vacuum_cost_limit',
 'autovacuum_max_workers','autovacuum_worker_slots') ORDER BY name;
-- @teacher [END 06-SQL063]
-- @teacher [START 06-SQL064] Lab 6F.1 | Prepare a 20000-row review queue and baseline counters
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: เก็บ Live/Dead Estimates, เวลาทำงานล่าสุดและ autovacuum_count ก่อนสร้าง Churn
-- @teacher ผล/ชวนสังเกต: Stats เป็นค่าประมาณและอาจล่าช้า; อย่ารวมหลายรอบทดลองโดยไม่จด Baseline
-- @teacher SOURCE: 06-configuration-claim.sql:341 | รัน SQL นี้ครบทั้ง Statement
SELECT relname,n_live_tup,n_dead_tup,last_autovacuum,last_autoanalyze,
       autovacuum_count FROM pg_stat_user_tables WHERE relid='lab_m6c.claim_queue'::regclass;
-- @teacher [END 06-SQL064]
-- END 6F.1

-- START 6F.2 | Apply queue thresholds and generate 2000 obsolete tuple versions
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: Threshold 1500 unless a lower PostgreSQL 18 cap applies; 2000 REVIEW rows, autovacuum runs asynchronously.
-- @teacher [START 06-SQL065] Lab 6F.2 | Apply queue thresholds and generate 2000 obsolete tuple versions
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ตั้ง Thresholds เฉพาะ Queue แทนปรับทั้ง Cluster
-- @teacher ผล/ชวนสังเกต: VACUUM: 500 + 5% ของ Rows; ANALYZE: 500 + 2%; Table Overrides ไม่ต้อง Restart
-- @teacher SOURCE: 06-configuration-claim.sql:348 | รัน SQL นี้ครบทั้ง Statement
ALTER TABLE lab_m6c.claim_queue SET (
 autovacuum_vacuum_threshold=500, autovacuum_vacuum_scale_factor=0.05,
 autovacuum_analyze_threshold=500, autovacuum_analyze_scale_factor=0.02
);
-- @teacher [END 06-SQL065]
-- @teacher [START 06-SQL066] Lab 6F.2 | Apply queue thresholds and generate 2000 obsolete tuple versions
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: คำนวณ Vacuum Trigger จาก 20000 Rows และ Max Threshold ของ PG18
-- @teacher ผล/ชวนสังเกต: ค่าปกติได้ 1500; -1 หมายถึงไม่มี Max Cap; เป็น Trigger โดยประมาณ ไม่ใช่เวลานัดทำงาน
-- @teacher SOURCE: 06-configuration-claim.sql:352 | รัน SQL นี้ครบทั้ง Statement
SELECT least(nullif(current_setting('autovacuum_vacuum_max_threshold')::numeric,-1),
             500+0.05*20000) AS effective_vacuum_threshold;
-- @teacher [END 06-SQL066]
-- @teacher [START 06-SQL067] Lab 6F.2 | Apply queue thresholds and generate 2000 obsolete tuple versions
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: UPDATE 2000 Rows ให้เกิน Vacuum Threshold และสร้าง Obsolete Versions
-- @teacher ผล/ชวนสังเกต: Commit ก่อนรอดู Autovacuum; จำนวน Dead Tuples ที่เห็นไม่จำเป็นต้องเท่ากับ 2000 ตลอดเวลา
-- @teacher SOURCE: 06-configuration-claim.sql:354 | รัน SQL นี้ครบทั้ง Statement
UPDATE lab_m6c.claim_queue SET status='REVIEW',note=note||'checked'
WHERE claim_id<=2000;
-- @teacher [END 06-SQL067]
-- @teacher [START 06-SQL068] Lab 6F.2 | Apply queue thresholds and generate 2000 obsolete tuple versions
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ขอให้ Backend Flush สถิติของตนเมื่อมีโอกาสถัดไป
-- @teacher ผล/ชวนสังเกต: ไม่ได้สั่ง Autovacuum ให้ทำงานทันที และต้องจบ Transaction ก่อนดูผลในรอบถัดไป
-- @teacher SOURCE: 06-configuration-claim.sql:356 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_stat_force_next_flush();
-- @teacher [END 06-SQL068]
-- @teacher [START 06-SQL069] Lab 6F.2 | Apply queue thresholds and generate 2000 obsolete tuple versions
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ทิ้ง Snapshot ของสถิติที่ Session จำไว้ก่อน Poll ใหม่
-- @teacher ผล/ชวนสังเกต: ใช้รอบ Autocommit แยกกัน อย่าค้าง BEGIN ขณะรอผล
-- @teacher SOURCE: 06-configuration-claim.sql:357 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_stat_clear_snapshot();
-- @teacher [END 06-SQL069]
-- @teacher [START 06-SQL070] Lab 6F.2 | Apply queue thresholds and generate 2000 obsolete tuple versions
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ตรวจ reloptions ว่า Table Overrides ถูกบันทึกจริง
-- @teacher ผล/ชวนสังเกต: ควรเห็น Threshold/Scale Factor ทั้งสี่ค่าที่เพิ่งตั้ง
-- @teacher SOURCE: 06-configuration-claim.sql:358 | รัน SQL นี้ครบทั้ง Statement
SELECT reloptions FROM pg_class WHERE oid='lab_m6c.claim_queue'::regclass;
-- @teacher [END 06-SQL070]
-- @teacher [START 06-SQL071] Lab 6F.2 | Apply queue thresholds and generate 2000 obsolete tuple versions
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: อ่านหลักฐาน Autovacuum หลัง UPDATE และ Commit
-- @teacher ผล/ชวนสังเกต: Poll ใหม่เป็นช่วง 10–60 วินาที; เปรียบเทียบ last_autovacuum/autovacuum_count กับ Baseline ไม่ใช่ Dead Count อย่างเดียว
-- @teacher SOURCE: 06-configuration-claim.sql:359 | รัน SQL นี้ครบทั้ง Statement
SELECT relname,n_live_tup,n_dead_tup,last_autovacuum,last_autoanalyze,
       autovacuum_count FROM pg_stat_user_tables WHERE relid='lab_m6c.claim_queue'::regclass;
-- @teacher [END 06-SQL071]
-- @teacher [START 06-SQL072] Lab 6F.2 | Apply queue thresholds and generate 2000 obsolete tuple versions
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: หา Sessions ที่ถือ xmin เก่าและอาจทำให้เก็บ Tuple เก่าไว้
-- @teacher ผล/ชวนสังเกต: Transaction เก่าอาจทำให้ Cleanup ยังเอา Version ออกไม่ได้ แม้ Vacuum ทำงานแล้ว
-- @teacher SOURCE: 06-configuration-claim.sql:361 | รัน SQL นี้ครบทั้ง Statement
SELECT pid,xact_start,backend_xmin,state FROM pg_stat_activity
WHERE backend_xmin IS NOT NULL ORDER BY xact_start;
-- @teacher [END 06-SQL072]
-- Poll the statistics SELECT in a NEW autocommit statement after 10–60 seconds.
-- Eligibility is not immediate completion. Tuple counts are estimates.
-- Table options persist; reset them explicitly in 6F.3.
-- END 6F.2

-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :m6_reset_table
-- START 6F.3 | Reset only the four lab table overrides
-- LOGIN: postgres | DATABASE: claimsure_m6
-- EXPECT: reloptions cleared. Optional: keep this block until AFTER observing the automatic cleanup in 6F.2.
-- @teacher [START 06-SQL073] Lab 6F.3 | Reset only the four lab table overrides
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: คืนค่า Table Overrides ทั้งสี่หลังเก็บผลทดลองเสร็จ
-- @teacher ผล/ชวนสังเกต: 6F.3 เป็น Cleanup แบบเลือกทำผ่าน m6_reset_table; ไม่ควร Reset ก่อนสังเกต 6F.2 ครบ
-- @teacher SOURCE: 06-configuration-claim.sql:372 | รัน SQL นี้ครบทั้ง Statement
ALTER TABLE lab_m6c.claim_queue RESET (
 autovacuum_vacuum_threshold, autovacuum_vacuum_scale_factor,
 autovacuum_analyze_threshold, autovacuum_analyze_scale_factor
);
-- @teacher [END 06-SQL073]
-- @teacher [START 06-SQL074] Lab 6F.3 | Reset only the four lab table overrides
-- @teacher LOGIN / DATABASE: postgres | claimsure_m6 | Dedicated PG18 cluster_name=claimsure-module06
-- @teacher อธิบาย: ยืนยันว่าการ Reset ลบเฉพาะสี่ Table Options ตาม Lab
-- @teacher ผล/ชวนสังเกต: NULL หรือ Options อื่นที่ยังอยู่ได้ตามสภาพ Table; Cluster Defaults ไม่ถูกเปลี่ยนด้วย RESET นี้
-- @teacher SOURCE: 06-configuration-claim.sql:376 | รัน SQL นี้ครบทั้ง Statement
SELECT reloptions FROM pg_class WHERE oid='lab_m6c.claim_queue'::regclass;
-- @teacher [END 06-SQL074]
-- Resetting table options does NOT restore the file's cost limit.
-- Restore baseline F separately with set F baseline + reload.
-- END 6F.3
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif

-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif

-- Optional data cleanup, only after finishing all six labs:
-- DROP SCHEMA lab_m6c CASCADE;
-- File rollback is separate: follow the baseline steps in labs/module06/README.md.
