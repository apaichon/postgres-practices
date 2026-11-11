-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 05-architecture.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/05-architecture.sql
-- @teacher LOGIN / DATABASE เริ่มต้น: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อ่าน README.md ใน Directory นี้ก่อนสอน; ใช้ไฟล์นี้เป็นคู่มือเลือกรันทีละส่วน
-- @teacher แต่ละ SQL มี START/END, Lab, Login, เหตุผล และผลที่ต้องสังเกต; Source Line อ้างไฟล์ต้นฉบับ
-- @teacher START/END ราย SQL ใช้ค้นคำอธิบาย ไม่ใช่ขอบเขต Commit: Transaction/Function ต้องรันครบชุด
-- @teacher คำสั่ง psql ขึ้นต้นด้วย Backslash; SQL Editor ทั่วไปให้ข้ามและจัด Branch/Variables เอง
-- @teacher ทุกบรรทัดที่เพิ่มขึ้นต้น -- @teacher; SQL/psql ต้นฉบับคงเดิม รวมคำสั่งเปลี่ยนข้อมูลและ Expected Errors
-- @teacher เป้าหมาย: Connection/Process → Memory/Page/Tuple → MVCC → WAL → PGDATA
-- @teacher ใช้ Enterprise insurance.claim (tenant_id ฯลฯ), insurance.audit_event, CLM-1001 และ CLM-L1-005
-- @teacher Fixture Module 1 อย่างเดียวไม่พอ; หาก Guard ไม่ผ่านให้เตรียม Environment ตามต้นฉบับ ไม่ข้าม Guard
-- @teacher 5A เปิดอีก Connection; 5E เปิดไฟล์ 05-mvcc-session-a-teacher.sql และ b-teacher.sql ตามลำดับ
-- @teacher 5D.1 Commit การเปลี่ยน Timestamp; 5F Commit 1000 Audit Events แล้วลบเฉพาะ Events ของรอบนั้น
-- @teacher Rollback/Cleanup ไม่คืน WAL Bytes หรือ Identity Sequence ที่ใช้ไป
-- @teacher ==============================================================================
-- =============================================================================
-- Module 5: PostgreSQL Architecture With Labs
-- Source: slides/postgres-admin-v3/
--         postgres-admin-v3-complete-course-enterprise-blue.pdf, pages 101-123.
-- The overview on page 103 uses 1A-1G; detailed slides use 5A-5G, followed here.
-- Run: make sql-v3 LAB=05-architecture.sql
-- Run one section: make lab5 LAB_NO=5D.1 (use LAB_NO=list to show choices).
-- Requires: psql, the seeded ClaimSure primary, and the postgres lab role.
-- Run with autocommit enabled, not psql --single-transaction.
-- Lab 5A needs a second connection; Lab 5E uses the two MVCC session files.
-- D.1 commits a timestamp update; C/D.2-D.4 roll back their changes.
-- F commits 1,000 audit events, measures WAL, then deletes only its own rows.
-- Rollback/cleanup do not undo WAL generation or identity sequence advances.
-- =============================================================================
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP on
-- @teacher PSQL: ตั้งรูปแบบแสดงผลของ psql ไม่เปลี่ยนข้อมูลใน Database
\pset pager off
\echo '=== Module 5: PostgreSQL Architecture ==='
-- @teacher PSQL: ยืนยัน Host/Port/Database/User ของ Connection ปัจจุบันก่อนรัน Lab
\conninfo

-- @teacher [START 05-SQL001] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ตรวจ Primary, Superuser และ Enterprise Fixtures ก่อนเริ่มสังเกต Architecture
-- @teacher ผล/ชวนสังเกต: ต้นฉบับต้องมี tenant_id, audit_event และ CLM-1001; ขั้นต่อไปใช้ CLM-L1-005 ด้วย ให้ตรวจ Fixture ทั้งสองชุดก่อนสอน
-- @teacher SOURCE: 05-architecture.sql:20 | รัน SQL นี้ครบทั้ง Statement
DO $$
BEGIN
    IF pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Run Module 5 on the ClaimSure primary, not a standby.';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'Run this architecture lab as the postgres lab superuser.';
    END IF;
    IF to_regclass('insurance.claim') IS NULL
       OR to_regclass('insurance.audit_event') IS NULL THEN
        RAISE EXCEPTION 'Load the ClaimSure schema and seed data from init/ first.';
    END IF;
    IF NOT EXISTS (SELECT FROM insurance.claim
                   WHERE tenant_id = 1 AND claim_no = 'CLM-1001') THEN
        RAISE EXCEPTION 'Missing seed claim: tenant 1 / CLM-1001.';
    END IF;
END
$$;
-- @teacher [END 05-SQL001]

\echo '\n-- Lab 5A: Observe Connections (PDF pp. 105-106)'
-- Open two terminals from the repository root:
--   ./scripts/psql.sh postgres
--   ./scripts/psql.sh claim_app
-- In each, run SELECT pg_backend_pid(); then inspect activity as postgres.
-- @teacher [START 05-SQL002] Lab 5A | Observe Connections (PDF pp. 105-106)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ดู PID ของ Backend และ Identity ของ Connection นี้
-- @teacher ผล/ชวนสังเกต: เปิดสอง Sessions แล้ว PID ต้องต่างกัน; Transaction Pooling อาจเปลี่ยน Backend ข้าม Transaction
-- @teacher SOURCE: 05-architecture.sql:44 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_backend_pid() AS backend_pid,
       current_database() AS database_name,
       current_user AS database_user,
       inet_client_addr() AS client_address,
       pg_postmaster_start_time() AS server_started_at;
-- @teacher [END 05-SQL002]

-- @teacher [START 05-SQL003] Lab 5A | Observe Connections (PDF pp. 105-106)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ดู Activity ของฐานเดียวกันเพื่อเชื่อม Connection กับ Backend Process
-- @teacher ผล/ชวนสังเกต: Idle ยังมี Backend; อย่าสรุปว่า Idle ไม่ใช้ทรัพยากรเลย
-- @teacher SOURCE: 05-architecture.sql:50 | รัน SQL นี้ครบทั้ง Statement
SELECT pid, backend_type, usename, application_name, client_addr, state,
       query_start, wait_event_type, wait_event, left(query, 80) AS query
FROM pg_stat_activity
WHERE datname = current_database()
ORDER BY pid;
-- @teacher [END 05-SQL003]
-- VERIFY: each direct session has a different PID; idle sessions keep a backend.

\echo '\n-- Lab 5B: Background Process Evidence (PDF pp. 107-108)'
-- @teacher [START 05-SQL004] Lab 5B | Background Process Evidence (PDF pp. 107-108)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: แยก Background Processes ออกจาก Client Backends
-- @teacher ผล/ชวนสังเกต: Autovacuum Worker อาจไม่มีในขณะนั้น; Archiver ขึ้นกับ Configuration
-- @teacher SOURCE: 05-architecture.sql:58 | รัน SQL นี้ครบทั้ง Statement
SELECT pid, backend_type, state, wait_event_type, wait_event
FROM pg_stat_activity
WHERE backend_type <> 'client backend'
ORDER BY backend_type, pid;
-- @teacher [END 05-SQL004]

-- @teacher [START 05-SQL005] Lab 5B | Background Process Evidence (PDF pp. 107-108)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่าน Counters ของ Background Writer
-- @teacher ผล/ชวนสังเกต: ใน PG17+ Checkpointer มี View แยก ไม่รวมไว้ที่นี่ทั้งหมดเหมือนเวอร์ชันเก่า
-- @teacher SOURCE: 05-architecture.sql:63 | รัน SQL นี้ครบทั้ง Statement
SELECT * FROM pg_stat_bgwriter;
-- @teacher [END 05-SQL005]
-- @teacher [START 05-SQL006] Lab 5B | Background Process Evidence (PDF pp. 107-108)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ตรวจว่ามี pg_stat_checkpointer ก่อนเลือก Branch ตามเวอร์ชัน
-- @teacher ผล/ชวนสังเกต: ผลเก็บในตัวแปร psql; GUI ให้เลือก Query ของเวอร์ชันที่มีเอง
-- @teacher SOURCE: 05-architecture.sql:64 | รัน SQL นี้ครบทั้ง Statement
SELECT to_regclass('pg_catalog.pg_stat_checkpointer') IS NOT NULL AS has_checkpointer \gset
-- @teacher [END 05-SQL006]
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :has_checkpointer
-- @teacher [START 05-SQL007] Lab 5B | Background Process Evidence (PDF pp. 107-108)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่าน Counters ของ Checkpointer แยกจาก Background Writer
-- @teacher ผล/ชวนสังเกต: เป็นค่าตั้งแต่ stats_reset ไม่ใช่จำนวน Pages ของ Query ล่าสุด
-- @teacher SOURCE: 05-architecture.sql:66 | รัน SQL นี้ครบทั้ง Statement
SELECT * FROM pg_stat_checkpointer;
-- @teacher [END 05-SQL007]
-- @teacher PSQL: Branch ทางเลือกของ psql; ไม่เลือก Execute ทั้งสอง Branch ใน SQL Editor
\else
\echo 'Before PostgreSQL 17, checkpoint counters are included in pg_stat_bgwriter.'
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif
-- @teacher [START 05-SQL008] Lab 5B | Background Process Evidence (PDF pp. 107-108)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่านภาพรวมการสร้าง/เขียน/Flush WAL ของ Cluster
-- @teacher ผล/ชวนสังเกต: แยก WAL Writer/Backend Flush ออกจาก Data Page Writeback
-- @teacher SOURCE: 05-architecture.sql:70 | รัน SQL นี้ครบทั้ง Statement
SELECT * FROM pg_stat_wal;
-- @teacher [END 05-SQL008]
-- VERIFY: find background writer, checkpointer, WAL writer and autovacuum launcher.
-- Workers appear only when needed; archiver depends on archive configuration.
-- Counters are cumulative and can lag; repeat after the writes in 5D/5F.

\echo '\n-- Lab 5C: Shared Memory in a Claim Update (PDF pp. 109-110)'
-- @teacher [START 05-SQL009] Lab 5C | Shared Memory in a Claim Update (PDF pp. 109-110)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่านค่า shared_buffers ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 05-architecture.sql:76 | รัน SQL นี้ครบทั้ง Statement
SHOW shared_buffers;
-- @teacher [END 05-SQL009]
-- @teacher [START 05-SQL010] Lab 5C | Shared Memory in a Claim Update (PDF pp. 109-110)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่านค่า wal_buffers ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 05-architecture.sql:77 | รัน SQL นี้ครบทั้ง Statement
SHOW wal_buffers;
-- @teacher [END 05-SQL010]
-- @teacher [START 05-SQL011] Lab 5C | Shared Memory in a Claim Update (PDF pp. 109-110)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่านค่า max_connections ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 05-architecture.sql:78 | รัน SQL นี้ครบทั้ง Statement
SHOW max_connections;
-- @teacher [END 05-SQL011]
-- @teacher [START 05-SQL012] Lab 5C | Shared Memory in a Claim Update (PDF pp. 109-110)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่านค่า work_mem ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 05-architecture.sql:79 | รัน SQL นี้ครบทั้ง Statement
SHOW work_mem;
-- @teacher [END 05-SQL012]
-- shared_buffers and wal_buffers are shared; work_mem is per operation.
-- effective_cache_size is a planner estimate, not allocated memory.
-- @teacher [START 05-SQL013] Lab 5C | Shared Memory in a Claim Update (PDF pp. 109-110)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: เปรียบเทียบ effective_cache_size ที่เป็น Planner Estimate กับ maintenance_work_mem
-- @teacher ผล/ชวนสังเกต: effective_cache_size ไม่จอง RAM; ต้องอ่าน setting/unit/source ร่วมกัน
-- @teacher SOURCE: 05-architecture.sql:82 | รัน SQL นี้ครบทั้ง Statement
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN ('effective_cache_size', 'maintenance_work_mem')
ORDER BY name;
-- @teacher [END 05-SQL013]

-- Claim columns: claim_id, claim_no, policy_id, status, incident_at,
-- estimated_amount, approved_amount, created_at.
-- CLM-L1-005 starts as NEW. The update below is rolled back.
-- @teacher [START 05-SQL014] Lab 5C | Shared Memory in a Claim Update (PDF pp. 109-110)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่าน Columns ของ Claim ที่ Query Update ถัดไปอ้างจริง
-- @teacher ผล/ชวนสังเกต: ยืนยันว่ามี CLM-L1-005 และ Columns ตรง Schema ไม่ใช่เดาจากสไลด์เก่า
-- @teacher SOURCE: 05-architecture.sql:90 | รัน SQL นี้ครบทั้ง Statement
SELECT claim_id, claim_no, policy_id, status, incident_at,
       estimated_amount, approved_amount, created_at
FROM insurance.claim
ORDER BY claim_id;
-- @teacher [END 05-SQL014]

-- @teacher [START 05-SQL015] Lab 5C | Shared Memory in a Claim Update (PDF pp. 109-110)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 05-architecture.sql:95 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 05-SQL015]
-- @teacher [START 05-SQL016] Lab 5C | Shared Memory in a Claim Update (PDF pp. 109-110)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ทดลอง UPDATE Claim 005 ภายใน Transaction เพื่อสังเกต Locks
-- @teacher ผล/ชวนสังเกต: UPDATE คืน REVIEW แล้วท้าย Block ROLLBACK; ไม่ใช่การอนุมัติ Claim ถาวร
-- @teacher SOURCE: 05-architecture.sql:96 | รัน SQL นี้ครบทั้ง Statement
UPDATE insurance.claim
SET status = 'REVIEW'
WHERE claim_no = 'CLM-L1-005'
RETURNING claim_id, claim_no, policy_id, status, incident_at,
          estimated_amount, approved_amount, created_at;
-- @teacher [END 05-SQL016]

-- @teacher [START 05-SQL017] Lab 5C | Shared Memory in a Claim Update (PDF pp. 109-110)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ดู Locks ของ PID ปัจจุบันก่อน Transaction จบ
-- @teacher ผล/ชวนสังเกต: Relation/Transaction Locks ควรปรากฏ; Row Locks ส่วนมากอยู่ใน Tuple Headers จึงไม่ครบทุกแถวใน View นี้
-- @teacher SOURCE: 05-architecture.sql:102 | รัน SQL นี้ครบทั้ง Statement
SELECT locktype, relation::regclass AS relation, transactionid, mode, granted
FROM pg_locks
WHERE pid = pg_backend_pid()
ORDER BY locktype, mode;
-- @teacher [END 05-SQL017]
-- @teacher [START 05-SQL018] Lab 5C | Shared Memory in a Claim Update (PDF pp. 109-110)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 05-architecture.sql:106 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 05-SQL018]

-- VERIFY: the read lists the claim columns above.
-- UPDATE returns CLM-L1-005 with status REVIEW.
-- ROLLBACK restores NEW. Relation/transaction locks exist before rollback.
-- Row locks are normally stored in tuple headers, not all listed in pg_locks.

\echo '\n-- Lab 5D: Data Page and Tuple States (PDF pp. 111-112)'
-- Dirty/clean describes a buffer page; live/old/deleted/dead describes tuples.
-- ctid is (block number, tuple slot), not a stable business key.
-- xmin identifies the inserting transaction. xmax can represent deletion,
-- update or locking; a nonzero xmax alone does not prove a tuple is dead.
-- Ask: show the example data stored in one tuple.
-- Header: ctid, xmin, xmax. Column values: the CLM-L1-005 claim row.
-- @teacher [START 05-SQL019] Lab 5D | Data Page and Tuple States (PDF pp. 111-112)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่าน ctid/xmin/xmax คู่กับ Business Columns ของ Claim เดียว
-- @teacher ผล/ชวนสังเกต: ctid ไม่ใช่ Permanent ID; xmax ที่ไม่เป็น 0 ไม่ได้บอกว่า Tuple Dead เสมอ
-- @teacher SOURCE: 05-architecture.sql:120 | รัน SQL นี้ครบทั้ง Statement
SELECT ctid, xmin, xmax,
       claim_id, claim_no, policy_id, status,
       incident_at, estimated_amount, approved_amount, created_at
FROM insurance.claim
WHERE claim_no = 'CLM-L1-005';
-- @teacher [END 05-SQL019]


\echo '\n-- Lab 5D.1: Page Lifecycle (PDF p. 113)'
-- @teacher [START 05-SQL020] Lab 5D.1 | Page Lifecycle (PDF p. 113)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่านค่า shared_buffers ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 05-architecture.sql:128 | รัน SQL นี้ครบทั้ง Statement
SHOW shared_buffers;
-- @teacher [END 05-SQL020]
-- @teacher [START 05-SQL021] Lab 5D.1 | Page Lifecycle (PDF p. 113)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: เก็บ LSN ก่อนแก้แถวเพื่อวัด WAL Delta ภายหลัง
-- @teacher ผล/ชวนสังเกต: gset เก็บค่าใน Client ไม่ได้สร้าง Table; ต้องใช้ psql Session เดิมจนจบ Block
-- @teacher SOURCE: 05-architecture.sql:129 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_current_wal_insert_lsn() AS page_before_lsn \gset
-- @teacher [END 05-SQL021]
-- @teacher [START 05-SQL022] Lab 5D.1 | Page Lifecycle (PDF p. 113)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 05-architecture.sql:130 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 05-SQL022]
-- @teacher [START 05-SQL023] Lab 5D.1 | Page Lifecycle (PDF p. 113)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ตั้ง Synchronous Commit เฉพาะ Transaction ของการสาธิต
-- @teacher ผล/ชวนสังเกต: เมื่อ fsync เปิด ให้รอ Local WAL Flush ก่อนตอบ Commit ไม่ได้บังคับ Heap Page ถูกเขียนถึง Data File ทันที
-- @teacher SOURCE: 05-architecture.sql:131 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL synchronous_commit = on;
-- @teacher [END 05-SQL023]
-- claim has created_at, not updated_at.
-- This commit replaces created_at on CLM-L1-005. status stays NEW.
-- @teacher [START 05-SQL024] Lab 5D.1 | Page Lifecycle (PDF p. 113)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: แก้ created_at ของ Claim 005 เพื่อให้เกิด Row Version/WAL จริง
-- @teacher ผล/ชวนสังเกต: ขั้นนี้ COMMIT เปลี่ยน Timestamp ถาวรตามต้นฉบับ ส่วน Status ไม่ได้เปลี่ยน
-- @teacher SOURCE: 05-architecture.sql:134 | รัน SQL นี้ครบทั้ง Statement
UPDATE insurance.claim
SET created_at = clock_timestamp()
WHERE claim_no = 'CLM-L1-005'
RETURNING ctid, xmin, xmax, claim_no, status, created_at;
-- @teacher [END 05-SQL024]
-- @teacher [START 05-SQL025] Lab 5D.1 | Page Lifecycle (PDF p. 113)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 05-architecture.sql:138 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 05-SQL025]

-- @teacher [START 05-SQL026] Lab 5D.1 | Page Lifecycle (PDF p. 113)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: คำนวณ WAL ที่เพิ่มระหว่างจุดวัดสองครั้ง
-- @teacher ผล/ชวนสังเกต: LSN เป็นทั้ง Cluster งานอื่นอาจรวมอยู่ใน Delta; ไม่ใช่ตัววัด Buffer Dirty โดยตรง
-- @teacher SOURCE: 05-architecture.sql:140 | รัน SQL นี้ครบทั้ง Statement
SELECT :'page_before_lsn'::pg_lsn AS before_lsn,
       pg_current_wal_insert_lsn() AS after_lsn,
       pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'page_before_lsn'::pg_lsn) AS wal_bytes;
-- @teacher [END 05-SQL026]
-- VERIFY: WAL advanced. With fsync enabled and synchronous_commit=on, commit
-- waits for local WAL flush; it need not wait for the changed heap page write.
-- Background writer/checkpointer (and sometimes backends) write dirty pages.
-- An LSN change is WAL evidence, not a direct measurement of buffer dirtiness.

\echo '\n-- Lab 5D.2: INSERT New Live Tuple (PDF p. 114)'
-- @teacher [START 05-SQL027] Lab 5D.2 | INSERT New Live Tuple (PDF p. 114)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 05-architecture.sql:149 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 05-SQL027]
-- @teacher [START 05-SQL028] Lab 5D.2 | INSERT New Live Tuple (PDF p. 114)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: INSERT Audit Fixture เพื่อสังเกต Tuple ใหม่ใน Transaction ของตน
-- @teacher ผล/ชวนสังเกต: RETURNING แสดง ctid/xmin; ROLLBACK คืนแถว แต่ไม่ย้อน Sequence Advance/WAL ที่เกิดแล้ว
-- @teacher SOURCE: 05-architecture.sql:150 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO insurance.audit_event (
    tenant_id, actor, action, entity_type, entity_id, details
)
VALUES (1, current_user, 'PAGE_STATE_LAB', 'claim', 'CLM-1001',
        '{"activity":"insert"}'::jsonb)
RETURNING ctid, xmin, xmax, event_id, action;
-- @teacher [END 05-SQL028]
-- @teacher [START 05-SQL029] Lab 5D.2 | INSERT New Live Tuple (PDF p. 114)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 05-architecture.sql:156 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 05-SQL029]
-- VERIFY: INSERT returns a tuple with xmin. This transaction sees its own insert;
-- other sessions would see it only after commit. Here rollback removes it.

\echo '\n-- Lab 5D.3: UPDATE Old Tuple Plus New Tuple (PDF p. 115)'
-- @teacher [START 05-SQL030] Lab 5D.3 | UPDATE Old Tuple Plus New Tuple (PDF p. 115)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 05-architecture.sql:161 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 05-SQL030]
-- @teacher [START 05-SQL031] Lab 5D.3 | UPDATE Old Tuple Plus New Tuple (PDF p. 115)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่าน Tuple ก่อน UPDATE เพื่อใช้เทียบ Header/Visible Values
-- @teacher ผล/ชวนสังเกต: ใช้ Claim เดียวกันและ Transaction เดียวกันกับ UPDATE ถัดไป
-- @teacher SOURCE: 05-architecture.sql:162 | รัน SQL นี้ครบทั้ง Statement
SELECT ctid, xmin, xmax, claim_no, status
FROM insurance.claim
WHERE claim_no = 'CLM-L1-005';
-- @teacher [END 05-SQL031]

-- @teacher [START 05-SQL032] Lab 5D.3 | UPDATE Old Tuple Plus New Tuple (PDF p. 115)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: UPDATE ทำให้เกิด Tuple Version ใหม่ ไม่ได้แก้ทุก Version ให้เหมือนกัน
-- @teacher ผล/ชวนสังเกต: เทียบ ctid/xmin ที่ RETURNING; SELECT ปกติไม่ใช่ Physical Inventory ของทุก Version ใน Heap
-- @teacher SOURCE: 05-architecture.sql:166 | รัน SQL นี้ครบทั้ง Statement
UPDATE insurance.claim
SET status = 'REVIEW'
WHERE claim_no = 'CLM-L1-005'
RETURNING ctid, xmin, xmax, claim_no, status;
-- @teacher [END 05-SQL032]
-- @teacher [START 05-SQL033] Lab 5D.3 | UPDATE Old Tuple Plus New Tuple (PDF p. 115)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 05-architecture.sql:170 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 05-SQL033]
-- VERIFY: compare ctid/xmin before and after. UPDATE creates a replacement
-- tuple; ordinary SELECT does not expose every physical version on the page.

\echo '\n-- Lab 5D.4: DELETE and SELECT Visibility (PDF p. 116)'
-- D.2 rolled back its insert, so create a dedicated row for this DELETE.
-- Track its identity: never delete other learners' PAGE_STATE_LAB events.
-- @teacher [START 05-SQL034] Lab 5D.4 | DELETE and SELECT Visibility (PDF p. 116)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 05-architecture.sql:177 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 05-SQL034]
-- @teacher [START 05-SQL035] Lab 5D.4 | DELETE and SELECT Visibility (PDF p. 116)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: สร้าง Audit Fixture อีกแถวและเก็บ event_id เพื่อทดลอง DELETE แถวของการสาธิตนี้เท่านั้น
-- @teacher ผล/ชวนสังเกต: gset ใช้ ID ที่เพิ่งได้ ไม่ลบ Audit ของผู้เรียนคนอื่น
-- @teacher SOURCE: 05-architecture.sql:178 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO insurance.audit_event (
    tenant_id, actor, action, entity_type, entity_id, details
)
VALUES (1, current_user, 'PAGE_STATE_LAB', 'claim', 'CLM-1001',
        '{"activity":"delete"}'::jsonb)
RETURNING event_id AS delete_event_id \gset
-- @teacher [END 05-SQL035]

-- @teacher [START 05-SQL036] Lab 5D.4 | DELETE and SELECT Visibility (PDF p. 116)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ตั้ง Savepoint หลัง INSERT เพื่อย้อนเฉพาะ DELETE ได้
-- @teacher ผล/ชวนสังเกต: Savepoint ไม่ใช่ Transaction ใหม่; INSERT ก่อน Savepoint ยังอยู่เมื่อ ROLLBACK TO
-- @teacher SOURCE: 05-architecture.sql:185 | รัน SQL นี้ครบทั้ง Statement
SAVEPOINT before_delete;
-- @teacher [END 05-SQL036]
-- @teacher [START 05-SQL037] Lab 5D.4 | DELETE and SELECT Visibility (PDF p. 116)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ลบ Fixture ด้วย ID ที่เก็บจาก INSERT
-- @teacher ผล/ชวนสังเกต: คาด DELETE 1; Transaction นี้จะไม่เห็นแถวนั้นผ่าน SELECT ปกติ
-- @teacher SOURCE: 05-architecture.sql:186 | รัน SQL นี้ครบทั้ง Statement
DELETE FROM insurance.audit_event
WHERE event_id = :delete_event_id
RETURNING ctid, xmin, xmax, event_id, action;
-- @teacher [END 05-SQL037]

-- @teacher [START 05-SQL038] Lab 5D.4 | DELETE and SELECT Visibility (PDF p. 116)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ตรวจจำนวนแถวที่มองเห็นหลัง DELETE
-- @teacher ผล/ชวนสังเกต: visible_after_delete=0 ไม่ได้แปลว่าพื้นที่ Heap ถูก Compact ทันที
-- @teacher SOURCE: 05-architecture.sql:190 | รัน SQL นี้ครบทั้ง Statement
SELECT count(*) AS visible_after_delete
FROM insurance.audit_event WHERE event_id = :delete_event_id;
-- @teacher [END 05-SQL038]
-- @teacher [START 05-SQL039] Lab 5D.4 | DELETE and SELECT Visibility (PDF p. 116)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ย้อนเฉพาะงานหลัง Savepoint เพื่อ Undo DELETE แต่คง Fixture ที่ INSERT ก่อนหน้า
-- @teacher ผล/ชวนสังเกต: ยังอยู่ใน Transaction เดิม ต้องทำ ROLLBACK ปิดทั้งชุดตอนท้าย
-- @teacher SOURCE: 05-architecture.sql:192 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK TO SAVEPOINT before_delete;
-- @teacher [END 05-SQL039]
-- @teacher [START 05-SQL040] Lab 5D.4 | DELETE and SELECT Visibility (PDF p. 116)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่านอีกครั้งหลัง Undo DELETE
-- @teacher ผล/ชวนสังเกต: visible_after_undo_delete=1; หลัง Outer ROLLBACK Fixture จะไม่คงอยู่
-- @teacher SOURCE: 05-architecture.sql:193 | รัน SQL นี้ครบทั้ง Statement
SELECT count(*) AS visible_after_undo_delete
FROM insurance.audit_event WHERE event_id = :delete_event_id;
-- @teacher [END 05-SQL040]

-- @teacher [START 05-SQL041] Lab 5D.4 | DELETE and SELECT Visibility (PDF p. 116)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 05-architecture.sql:196 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK;
-- @teacher [END 05-SQL041]
-- VERIFY: DELETE returns one row; visibility counts are 0 then 1.
-- The outer rollback removes the fixture. DELETE does not immediately compact
-- the heap; versions become reclaimable when no active snapshot needs them.

\echo '\n-- Lab 5D.5: Activity to Tuple-State Map (PDF p. 117)'
-- @teacher [START 05-SQL042] Lab 5D.5 | Activity to Tuple-State Map (PDF p. 117)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่าน Estimates ของ Live/Dead Tuples และ Maintenance Counters
-- @teacher ผล/ชวนสังเกต: ไม่ใช่ Count แบบทันทีของ Physical Versions ทั้งหมด; VACUUM กับ CHECKPOINT ทำคนละหน้าที่
-- @teacher SOURCE: 05-architecture.sql:202 | รัน SQL นี้ครบทั้ง Statement
SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum,
       vacuum_count, autovacuum_count
FROM pg_stat_user_tables
WHERE schemaname = 'insurance' AND relname IN ('claim', 'audit_event')
ORDER BY relname;
-- @teacher [END 05-SQL042]
-- These are estimates, not an immediate tuple-by-tuple visibility inventory.
-- SELECT: snapshot visibility; no new version (hint bits may dirty a page).
-- INSERT: new version. UPDATE: old + new versions. DELETE: removed version.
-- VACUUM: reclaims versions no snapshot needs; space can be reused.
-- CHECKPOINT: writes dirty pages; does not change transaction visibility.
-- Discussion only: no forced CHECKPOINT or VACUUM is needed for this lab.

\echo '\n-- Lab 5E: MVCC Lab Example (PDF p. 118)'
-- @teacher [START 05-SQL043] Lab 5E | MVCC Lab Example (PDF p. 118)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ดู Visible Tuple ก่อนเริ่ม MVCC ด้วยสอง Sessions
-- @teacher ผล/ชวนสังเกต: เปิดไฟล์ Session A/B ฉบับผู้สอนตาม Timeline อย่ารันสองฝั่งต่อกันใน Connection เดียว
-- @teacher SOURCE: 05-architecture.sql:215 | รัน SQL นี้ครบทั้ง Statement
SELECT xmin, xmax, ctid, claim_no, status, created_at
FROM insurance.claim
WHERE claim_no = 'CLM-L1-005';
-- @teacher [END 05-SQL043]

-- Run these in two terminals, both connected as postgres to the same primary.
-- Terminal A (interactive; wait at its prompt):
--   docker compose exec primary psql -X -U postgres -d claimsure \
--     -f /sql/postgres-admin-v3/05-mvcc-session-a.sql
-- Terminal B (after A has taken its first snapshot):
--   docker compose exec primary psql -X -U postgres -d claimsure \
--     -f /sql/postgres-admin-v3/05-mvcc-session-b.sql
-- Return to A and press Enter only after B commits.
-- VERIFY: A keeps its original status/created_at/ctid while its Repeatable Read
-- transaction is open. Its first SELECT after COMMIT sees B's new version.
-- B commits REVIEW. On repeat runs the status may already match;
-- created_at and ctid still demonstrate that A sees an older version.
\echo 'Two-session exercise: run 05-mvcc-session-a.sql, then 05-mvcc-session-b.sql.'

\echo '\n-- Lab 5F: WAL Lab Example (PDF pp. 119-120)'
-- Capture LSNs in separate statements so the start is sampled before INSERT.
-- Retain only this batch's IDs for cleanup after the durable commit observation.
-- @teacher [START 05-SQL044] Lab 5F | WAL Lab Example (PDF pp. 119-120)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: สร้าง TEMP Table จดเฉพาะ event_ids ของ Batch ที่จะเขียน
-- @teacher ผล/ชวนสังเกต: TEMP อยู่ใน Session นี้ ใช้ Cleanup อย่างเจาะจง; หากรันซ้ำ Session เดิมและ Table ค้างให้ตรวจรอบก่อนก่อน DROP
-- @teacher SOURCE: 05-architecture.sql:236 | รัน SQL นี้ครบทั้ง Statement
CREATE TEMP TABLE lab_m5_wal_event_ids (event_id bigint PRIMARY KEY);
-- @teacher [END 05-SQL044]
-- @teacher [START 05-SQL045] Lab 5F | WAL Lab Example (PDF pp. 119-120)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: เก็บ WAL Insert LSN ก่อน Batch
-- @teacher ผล/ชวนสังเกต: ใช้ Statement แยกเพื่อให้จุดเริ่มอยู่ก่อน INSERT จริง
-- @teacher SOURCE: 05-architecture.sql:237 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_current_wal_insert_lsn() AS wal_before_lsn \gset
-- @teacher [END 05-SQL045]
-- @teacher [START 05-SQL046] Lab 5F | WAL Lab Example (PDF pp. 119-120)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 05-architecture.sql:238 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 05-SQL046]
-- @teacher [START 05-SQL047] Lab 5F | WAL Lab Example (PDF pp. 119-120)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: เปิด Synchronous Commit เฉพาะ Batch นี้เพื่อสังเกต Flush เมื่อ Commit
-- @teacher ผล/ชวนสังเกต: คืนค่าตาม Transaction; ต้องมี fsync เปิดตาม Server Setup ที่ใช้สอน
-- @teacher SOURCE: 05-architecture.sql:239 | รัน SQL นี้ครบทั้ง Statement
SET LOCAL synchronous_commit = on;
-- @teacher [END 05-SQL047]
-- @teacher [START 05-SQL048] Lab 5F | WAL Lab Example (PDF pp. 119-120)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: CTE ins INSERT Audit 1000 แถวและส่ง IDs ไป TEMP Table ใน Statement เดียว
-- @teacher ผล/ชวนสังเกต: เฉพาะ IDs ที่ RETURNING จาก Batch นี้จะถูก Cleanup; นี่เป็นการเขียนจริงแล้ว COMMIT
-- @teacher SOURCE: 05-architecture.sql:240 | รัน SQL นี้ครบทั้ง Statement
WITH ins AS (
    INSERT INTO insurance.audit_event (
        tenant_id, actor, action, entity_type, entity_id, details
    )
    SELECT 1, 'load_lab', 'CLAIM_VIEWED', 'claim', g::text,
           jsonb_build_object('source', 'lab_m5_wal')
    FROM generate_series(1, 1000) AS g
    RETURNING event_id
)
INSERT INTO lab_m5_wal_event_ids SELECT event_id FROM ins;
-- @teacher [END 05-SQL048]
-- @teacher [START 05-SQL049] Lab 5F | WAL Lab Example (PDF pp. 119-120)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: เก็บ End LSN หลังเขียน Batch แต่ก่อน Commit Record
-- @teacher ผล/ชวนสังเกต: Delta ครอบคลุมงาน Batch ตามขอบเขตวัด ไม่รวม Commit Record ที่ตามมาทั้งหมด
-- @teacher SOURCE: 05-architecture.sql:250 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_current_wal_insert_lsn() AS wal_batch_end_lsn \gset
-- @teacher [END 05-SQL049]
-- @teacher [START 05-SQL050] Lab 5F | WAL Lab Example (PDF pp. 119-120)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 05-architecture.sql:251 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 05-SQL050]

-- @teacher [START 05-SQL051] Lab 5F | WAL Lab Example (PDF pp. 119-120)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ตรวจจำนวน IDs, WAL Bytes และว่าจุด End ของ Batch ถูก Flush แล้วหรือยัง
-- @teacher ผล/ชวนสังเกต: ควรได้ 1000 แถว, WAL Bytes > 0 และ batch_wal_flushed=true หลัง COMMIT ที่ตั้งไว้
-- @teacher SOURCE: 05-architecture.sql:253 | รัน SQL นี้ครบทั้ง Statement
SELECT count(*) AS rows_inserted,
       :'wal_before_lsn'::pg_lsn AS start_lsn,
       :'wal_batch_end_lsn'::pg_lsn AS batch_end_lsn,
       pg_wal_lsn_diff(:'wal_batch_end_lsn'::pg_lsn, :'wal_before_lsn'::pg_lsn) AS wal_bytes,
       pg_size_pretty(pg_wal_lsn_diff(
           :'wal_batch_end_lsn'::pg_lsn, :'wal_before_lsn'::pg_lsn)) AS wal_generated,
       pg_current_wal_flush_lsn() >= :'wal_batch_end_lsn'::pg_lsn AS batch_wal_flushed
FROM lab_m5_wal_event_ids;
-- @teacher [END 05-SQL051]
-- VERIFY: 1,000 rows, positive WAL bytes, batch_wal_flushed = true.
-- LSNs are cluster-wide; concurrent writes can contribute to the measured delta.
-- The batch end is before COMMIT; the commit record adds further WAL.

-- Remove exactly this run's events after measuring; cleanup generates more WAL.
-- @teacher [START 05-SQL052] Lab 5F | WAL Lab Example (PDF pp. 119-120)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: Cleanup เฉพาะ Audit IDs ของ Batch โดย JOIN กับ TEMP Table
-- @teacher ผล/ชวนสังเกต: Cleanup สร้าง WAL เพิ่มเอง จึงทำหลังเก็บผลวัด ไม่ลบ Audit ด้วย Predicate กว้าง
-- @teacher SOURCE: 05-architecture.sql:266 | รัน SQL นี้ครบทั้ง Statement
DELETE FROM insurance.audit_event AS e
USING lab_m5_wal_event_ids AS batch
WHERE e.event_id = batch.event_id;
-- @teacher [END 05-SQL052]
-- @teacher [START 05-SQL053] Lab 5F | WAL Lab Example (PDF pp. 119-120)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ลบ TEMP Tracking Table เมื่อจบการวัดและ Cleanup
-- @teacher ผล/ชวนสังเกต: ไม่ลบ insurance.audit_event; ช่วยให้เริ่ม Batch ใหม่ใน Session เดิมได้
-- @teacher SOURCE: 05-architecture.sql:269 | รัน SQL นี้ครบทั้ง Statement
DROP TABLE lab_m5_wal_event_ids;
-- @teacher [END 05-SQL053]

-- @teacher [START 05-SQL054] Lab 5F | WAL Lab Example (PDF pp. 119-120)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: แยกตำแหน่ง WAL Insert, Write และ Flush พร้อมชื่อ WAL Segment ปัจจุบัน
-- @teacher ผล/ชวนสังเกต: ชื่อไฟล์ไม่ใช่คำสั่งให้ลบ pg_wal; ค่าตำแหน่งเป็นภาพของ Cluster ณ เวลาที่อ่าน
-- @teacher SOURCE: 05-architecture.sql:271 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_current_wal_insert_lsn() AS insert_lsn,
       pg_current_wal_lsn() AS write_lsn,
       pg_current_wal_flush_lsn() AS flush_lsn,
       pg_walfile_name(pg_current_wal_lsn()) AS current_wal_file;
-- @teacher [END 05-SQL054]

-- @teacher [START 05-SQL055] Lab 5F | WAL Lab Example (PDF pp. 119-120)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่านนโยบาย WAL, Checkpoint และ Durability ที่มีผลจริง
-- @teacher ผล/ชวนสังเกต: เชื่อมว่า Full Page Writes/Fsync/Archiving มีหน้าที่ต่างกัน ไม่ปิดเพียงเพื่อให้ Benchmark เร็ว
-- @teacher SOURCE: 05-architecture.sql:276 | รัน SQL นี้ครบทั้ง Statement
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN ('wal_level', 'max_wal_size', 'min_wal_size', 'checkpoint_timeout',
               'archive_mode', 'archive_command', 'fsync', 'full_page_writes',
               'synchronous_commit')
ORDER BY name;
-- @teacher [END 05-SQL055]

\echo '\n-- Lab 5G: Storage and PGDATA Lab Example (PDF p. 121)'
-- @teacher [START 05-SQL056] Lab 5G | Storage and PGDATA Lab Example (PDF p. 121)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่านค่า data_directory ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 05-architecture.sql:284 | รัน SQL นี้ครบทั้ง Statement
SHOW data_directory;
-- @teacher [END 05-SQL056]
-- @teacher [START 05-SQL057] Lab 5G | Storage and PGDATA Lab Example (PDF p. 121)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่านค่า config_file ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 05-architecture.sql:285 | รัน SQL นี้ครบทั้ง Statement
SHOW config_file;
-- @teacher [END 05-SQL057]
-- @teacher [START 05-SQL058] Lab 5G | Storage and PGDATA Lab Example (PDF p. 121)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่านค่า hba_file ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 05-architecture.sql:286 | รัน SQL นี้ครบทั้ง Statement
SHOW hba_file;
-- @teacher [END 05-SQL058]
-- @teacher [START 05-SQL059] Lab 5G | Storage and PGDATA Lab Example (PDF p. 121)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่านค่า block_size ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 05-architecture.sql:287 | รัน SQL นี้ครบทั้ง Statement
SHOW block_size;
-- @teacher [END 05-SQL059]
-- @teacher [START 05-SQL060] Lab 5G | Storage and PGDATA Lab Example (PDF p. 121)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่านค่า data_checksums ที่ Session นี้ใช้อยู่จริง
-- @teacher ผล/ชวนสังเกต: SHOW ไม่เปลี่ยนค่า; เทียบก่อน–หลัง Transaction/Activation ตาม Lab และดู pg_settings เมื่อจำเป็นต้องตรวจ Source/Context
-- @teacher SOURCE: 05-architecture.sql:288 | รัน SQL นี้ครบทั้ง Statement
SHOW data_checksums;
-- @teacher [END 05-SQL060]

-- @teacher [START 05-SQL061] Lab 5G | Storage and PGDATA Lab Example (PDF p. 121)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่าน Database OIDs เพื่อเชื่อมชื่อ Database กับ Storage Path
-- @teacher ผล/ชวนสังเกต: OID เป็นตัวระบุภายใน ไม่ใช่ชื่อ Directory ที่ควรเปลี่ยนเอง
-- @teacher SOURCE: 05-architecture.sql:290 | รัน SQL นี้ครบทั้ง Statement
SELECT oid, datname FROM pg_database ORDER BY oid;
-- @teacher [END 05-SQL061]
-- @teacher [START 05-SQL062] Lab 5G | Storage and PGDATA Lab Example (PDF p. 121)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: อ่าน Heap Path และขนาดเฉพาะ Heap เทียบ Total รวม Index/TOAST
-- @teacher ผล/ชวนสังเกต: pg_relation_filepath คืน Path สัมพันธ์กับ PGDATA ไม่ใช่ไฟล์ Backup
-- @teacher SOURCE: 05-architecture.sql:291 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_relation_filepath('insurance.claim') AS claim_file,
       pg_size_pretty(pg_relation_size('insurance.claim')) AS claim_heap_size,
       pg_size_pretty(pg_total_relation_size('insurance.claim')) AS claim_total_size;
-- @teacher [END 05-SQL062]

-- @teacher [START 05-SQL063] Lab 5G | Storage and PGDATA Lab Example (PDF p. 121)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: จัดอันดับ Relations ใน Schema จากขนาดรวมและดูชนิด r/i/p
-- @teacher ผล/ชวนสังเกต: Partitioned Parent ไม่มี Heap ของตนเหมือน Table ปกติ; ต้องพิจารณา Children เพิ่ม
-- @teacher SOURCE: 05-architecture.sql:295 | รัน SQL นี้ครบทั้ง Statement
SELECT c.oid::regclass AS relation, c.relkind,
       pg_relation_filepath(c.oid) AS relation_file,
       pg_size_pretty(pg_relation_size(c.oid)) AS heap_or_index,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_with_aux
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'insurance' AND c.relkind IN ('r', 'i', 'p')
ORDER BY pg_total_relation_size(c.oid) DESC
LIMIT 20;
-- @teacher [END 05-SQL063]

-- @teacher [START 05-SQL064] Lab 5G | Storage and PGDATA Lab Example (PDF p. 121)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ดู Tablespaces ที่มีการกำหนด Location
-- @teacher ผล/ชวนสังเกต: Default Tablespaces อาจได้ค่าว่าง ไม่ใช่ Error
-- @teacher SOURCE: 05-architecture.sql:305 | รัน SQL นี้ครบทั้ง Statement
SELECT spcname, pg_tablespace_location(oid) AS location
FROM pg_tablespace ORDER BY spcname;
-- @teacher [END 05-SQL064]
-- @teacher [START 05-SQL065] Lab 5G | Storage and PGDATA Lab Example (PDF p. 121)
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005
-- @teacher อธิบาย: ดูรายชื่อ WAL Segments ด้วยสิทธิ์ที่เหมาะสม
-- @teacher ผล/ชวนสังเกต: อ่านเพื่อเชื่อมแนวคิด Storage เท่านั้น ห้ามใช้ผลนี้ลบ WAL หรือแก้ไฟล์ตรง
-- @teacher SOURCE: 05-architecture.sql:307 | รัน SQL นี้ครบทั้ง Statement
SELECT name, pg_size_pretty(size) AS size, modification
FROM pg_ls_waldir()
ORDER BY modification DESC, name
LIMIT 10;
-- @teacher [END 05-SQL065]
-- VERIFY: the relation path is relative to PGDATA; its database OID matches
-- pg_database for default-tablespace storage. Never edit PGDATA/delete pg_wal.

\echo '\n-- Concept Check and Architecture Recap (PDF pp. 122-123)'
-- Narrate CLM-1001: connection -> backend -> snapshot -> shared buffers/locks
-- -> new tuple version -> WAL flush for durable commit -> later page writeback
-- -> vacuum cleanup when old versions are no longer needed.
-- Point to one observation from 5A-5G for each step.
