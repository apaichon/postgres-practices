-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 05-mvcc-session-b.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/05-mvcc-session-b.sql
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
-- @teacher ไฟล์ Session คู่: เปิดคนละ Connection และรอจังหวะตาม Prompt/README
-- @teacher ==============================================================================
-- Lab 5E, complete-course PDF p. 118. Run after A reaches its prompt.
-- Connect as postgres to the same seeded primary/database as Session A.
-- This commits CLM-L1-005 as REVIEW, as in the slides.
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP on
-- @teacher PSQL: ตั้งรูปแบบแสดงผลของ psql ไม่เปลี่ยนข้อมูลใน Database
\pset pager off
\echo '=== Module 5 / Lab 5E: MVCC - Session B ==='
-- @teacher PSQL: ยืนยัน Host/Port/Database/User ของ Connection ปัจจุบันก่อนรัน Lab
\conninfo

-- @teacher [START 05-SQL001] Lab 5E / MVCC Session B | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 | Session B
-- @teacher อธิบาย: Session B เริ่มหลัง A อ่าน Snapshot แรกและหยุดรอที่ Prompt
-- @teacher ผล/ชวนสังเกต: ต้องต่อ Database/Primary เดียวกันกับ A
-- @teacher SOURCE: 05-mvcc-session-b.sql:9 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 05-SQL001]
-- @teacher [START 05-SQL002] Lab 5E / MVCC Session B | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 | Session B
-- @teacher อธิบาย: ตรวจ Fixture ของ B โดยไม่สร้างทับข้อมูลอื่น
-- @teacher ผล/ชวนสังเกต: หากไม่พบ ให้ ROLLBACK และแจ้ง A ให้จบการทดลองก่อนแก้ Fixture
-- @teacher SOURCE: 05-mvcc-session-b.sql:10 | รัน SQL นี้ครบทั้ง Statement
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM insurance.claim
                   WHERE claim_no = 'CLM-L1-005') THEN
        RAISE EXCEPTION 'Missing seed claim: CLM-L1-005.';
    END IF;
END
$$;
-- @teacher [END 05-SQL002]
-- @teacher [START 05-SQL003] Lab 5E / MVCC Session B | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 | Session B
-- @teacher อธิบาย: สร้าง Row Version ใหม่ของ CLM-L1-005 และแสดง Tuple Header
-- @teacher ผล/ชวนสังเกต: Plain SELECT ของ A ไม่ขวาง UPDATE นี้; created_at เปลี่ยนจริงและจะ Commit
-- @teacher SOURCE: 05-mvcc-session-b.sql:18 | รัน SQL นี้ครบทั้ง Statement
UPDATE insurance.claim
SET status = 'REVIEW', created_at = clock_timestamp()
WHERE claim_no = 'CLM-L1-005'
RETURNING xmin, xmax, ctid, claim_no, status, created_at;
-- @teacher [END 05-SQL003]
-- @teacher [START 05-SQL004] Lab 5E / MVCC Session B | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 | Session B
-- @teacher อธิบาย: แสดง PID/XID ของ B เพื่อเทียบกับ A
-- @teacher ผล/ชวนสังเกต: PID ต้องไม่เท่ากัน; Transaction IDs ไม่จำเป็นต้องเรียงติดกันในระบบที่มีงานอื่น
-- @teacher SOURCE: 05-mvcc-session-b.sql:22 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_backend_pid() AS session_b_pid, txid_current() AS session_b_xid;
-- @teacher [END 05-SQL004]
-- @teacher [START 05-SQL005] Lab 5E / MVCC Session B | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 | Session B
-- @teacher อธิบาย: ยืนยัน Version ใหม่ให้ Sessions ที่มี Snapshot ใหม่เห็น
-- @teacher ผล/ชวนสังเกต: กลับไป A จึงค่อยกด Enter เพื่ออ่านซ้ำและเปรียบเทียบ
-- @teacher SOURCE: 05-mvcc-session-b.sql:23 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 05-SQL005]

\echo 'Session B committed. Return to Session A and press Enter.'
-- VERIFY: UPDATE 1 completes while A's plain SELECT snapshot remains open.
-- Readers using SELECT FOR UPDATE would introduce different locking behavior.
