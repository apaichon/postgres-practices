-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 05-mvcc-session-a.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/05-mvcc-session-a.sql
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
-- Lab 5E, complete-course PDF p. 118. Run as postgres on the seeded primary.
-- Use an interactive terminal; start B only when A reaches the prompt.
-- docker compose exec primary psql -X -U postgres -d claimsure \
--   -f /sql/postgres-admin-v3/05-mvcc-session-a.sql
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP on
-- @teacher PSQL: ตั้งรูปแบบแสดงผลของ psql ไม่เปลี่ยนข้อมูลใน Database
\pset pager off
\echo '=== Module 5 / Lab 5E: MVCC - Session A ==='
-- @teacher PSQL: ยืนยัน Host/Port/Database/User ของ Connection ปัจจุบันก่อนรัน Lab
\conninfo

-- @teacher [START 05-SQL001] Lab 5E / MVCC Session A | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 | Session A
-- @teacher อธิบาย: Session A เริ่ม REPEATABLE READ ก่อนให้ B แก้ข้อมูล
-- @teacher ผล/ชวนสังเกต: DO/SELECT ถัดไปสร้าง Snapshot ที่ A ใช้ต่อจน COMMIT; อย่ากดผ่าน Prompt ก่อน B Commit
-- @teacher SOURCE: 05-mvcc-session-a.sql:10 | รัน SQL นี้ครบทั้ง Statement
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- @teacher [END 05-SQL001]
-- @teacher [START 05-SQL002] Lab 5E / MVCC Session A | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 | Session A
-- @teacher อธิบาย: ตรวจว่า CLM-L1-005 มีอยู่จริงในฐานเดียวกับ B
-- @teacher ผล/ชวนสังเกต: หากไม่พบให้ ROLLBACK และเตรียม Fixture ก่อนเริ่มคู่ Sessions ใหม่
-- @teacher SOURCE: 05-mvcc-session-a.sql:11 | รัน SQL นี้ครบทั้ง Statement
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM insurance.claim
                   WHERE claim_no = 'CLM-L1-005') THEN
        RAISE EXCEPTION 'Missing seed claim: CLM-L1-005.';
    END IF;
END
$$;
-- @teacher [END 05-SQL002]
-- @teacher [START 05-SQL003] Lab 5E / MVCC Session A | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 | Session A
-- @teacher อธิบาย: แสดง PID และ XID ของ A เพื่อแยกจาก B
-- @teacher ผล/ชวนสังเกต: txid_current() ทำให้ Session ขอ Transaction ID; PID ของ A/B ต้องต่างกัน
-- @teacher SOURCE: 05-mvcc-session-a.sql:19 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_backend_pid() AS session_a_pid, txid_current() AS session_a_xid;
-- @teacher [END 05-SQL003]
-- @teacher [START 05-SQL004] Lab 5E / MVCC Session A | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 | Session A
-- @teacher อธิบาย: บันทึก Visible Values และ Tuple Identity ก่อน B เปลี่ยนแถว
-- @teacher ผล/ชวนสังเกต: จด status/created_at/ctid โดยไม่คาดว่า xmax จะคงเดิมตลอด
-- @teacher SOURCE: 05-mvcc-session-a.sql:20 | รัน SQL นี้ครบทั้ง Statement
SELECT xmin, xmax, ctid, claim_no, status, created_at
FROM insurance.claim
WHERE claim_no = 'CLM-L1-005';
-- @teacher [END 05-SQL004]

-- @teacher PSQL: หยุดรอผู้สอน: ให้ Session อีกฝั่งทำตามโจทย์ก่อนกด Enter; SQL Editor ต้องหยุดเองตรงนี้
\prompt 'Run 05-mvcc-session-b.sql in terminal B. After B commits, press Enter: ' continue
\echo 'A still sees the original row version in the same Repeatable Read snapshot:'
-- @teacher [START 05-SQL005] Lab 5E / MVCC Session A | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 | Session A
-- @teacher อธิบาย: อ่านซ้ำหลัง B Commit แต่ A ยังอยู่ใน Snapshot เดิม
-- @teacher ผล/ชวนสังเกต: Visible Values ของ A ยังเหมือนเดิม; UPDATE ของ B ไม่ถูกขวางด้วย Plain SELECT นี้
-- @teacher SOURCE: 05-mvcc-session-a.sql:26 | รัน SQL นี้ครบทั้ง Statement
SELECT xmin, xmax, ctid, claim_no, status, created_at
FROM insurance.claim
WHERE claim_no = 'CLM-L1-005';
-- @teacher [END 05-SQL005]

-- @teacher [START 05-SQL006] Lab 5E / MVCC Session A | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 | Session A
-- @teacher อธิบาย: จบ Transaction ของ A แล้วคืนสิทธิ์ให้ Statement ถัดไปใช้ Snapshot ใหม่
-- @teacher ผล/ชวนสังเกต: COMMIT นี้ไม่ทำให้ข้อมูลของ B ถูก Undo
-- @teacher SOURCE: 05-mvcc-session-a.sql:30 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 05-SQL006]
\echo 'A now takes a new snapshot and sees the version committed by B:'
-- @teacher [START 05-SQL007] Lab 5E / MVCC Session A | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 | Session A
-- @teacher อธิบาย: อ่านครั้งใหม่หลัง COMMIT
-- @teacher ผล/ชวนสังเกต: ต้องเห็น Version ของ B โดยเฉพาะ created_at/ctid แม้ Status ก่อนหน้านี้อาจเป็น REVIEW อยู่แล้ว
-- @teacher SOURCE: 05-mvcc-session-a.sql:32 | รัน SQL นี้ครบทั้ง Statement
SELECT xmin, xmax, ctid, claim_no, status, created_at
FROM insurance.claim
WHERE claim_no = 'CLM-L1-005';
-- @teacher [END 05-SQL007]
-- VERIFY: status/created_at/ctid stay the same for A's first two reads.
-- After COMMIT, created_at/ctid change even if status was already REVIEW.
-- xmax may change on the old tuple; snapshot stability concerns visible values,
-- not immutable physical tuple headers. ctid is not a stable business key.
