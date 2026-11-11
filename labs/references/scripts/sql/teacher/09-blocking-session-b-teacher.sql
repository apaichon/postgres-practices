-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 09-blocking-session-b.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/09-blocking-session-b.sql
-- @teacher LOGIN / DATABASE เริ่มต้น: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อ่าน README.md ใน Directory นี้ก่อนสอน; ใช้ไฟล์นี้เป็นคู่มือเลือกรันทีละส่วน
-- @teacher แต่ละ SQL มี START/END, Lab, Login, เหตุผล และผลที่ต้องสังเกต; Source Line อ้างไฟล์ต้นฉบับ
-- @teacher START/END ราย SQL ใช้ค้นคำอธิบาย ไม่ใช่ขอบเขต Commit: Transaction/Function ต้องรันครบชุด
-- @teacher คำสั่ง psql ขึ้นต้นด้วย Backslash; SQL Editor ทั่วไปให้ข้ามและจัด Branch/Variables เอง
-- @teacher ทุกบรรทัดที่เพิ่มขึ้นต้น -- @teacher; SQL/psql ต้นฉบับคงเดิม รวมคำสั่งเปลี่ยนข้อมูลและ Expected Errors
-- @teacher เป้าหมาย: Workload → Slow SQL → Blocking → Database/Table/WAL/Replica Health
-- @teacher Setup lock_demo ก่อนเปิด Blocking Session A/B; ใช้คนละ Connection ฐานเดียวกัน
-- @teacher pg_stat_statements ต้องติดตั้ง Extension และตั้ง shared_preload_libraries ถูกต้องก่อน
-- @teacher Observer Session C อ่าน 9C ระหว่าง B กำลังรอ A; Timeout 2s ทำให้ช่วงสังเกตสั้น
-- @teacher ไฟล์ Session คู่: เปิดคนละ Connection และรอจังหวะตาม Prompt/README
-- @teacher ==============================================================================
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP on
-- @teacher PSQL: ตั้งรูปแบบแสดงผลของ psql ไม่เปลี่ยนข้อมูลใน Database
\pset pager off
\echo '=== Module 9 Blocking — Session B ==='

\echo 'Current holder of the lab row/table locks:'
-- @teacher [START 09-SQL001] Lab 9C / Blocking Session B | A ถือ Row Lock; B รอจน Lock Timeout
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor | Session B
-- @teacher อธิบาย: B อ่านผู้ถือ Relation Locks บน Fixture ก่อนพยายาม UPDATE
-- @teacher ผล/ชวนสังเกต: แถว Lock granted=true แสดง Holder; Tuple Lock ไม่ได้แสดงครบทุกตัวใน pg_locks
-- @teacher SOURCE: 09-blocking-session-b.sql:6 | รัน SQL นี้ครบทั้ง Statement
SELECT l.pid AS holder_pid,
       l.mode,
       l.granted,
       a.state,
       left(a.query, 100) AS holder_query
FROM pg_locks l
JOIN pg_stat_activity a USING (pid)
WHERE l.relation = 'lab_m9.lock_demo'::regclass
ORDER BY l.granted DESC, l.pid;
-- @teacher [END 09-SQL001]

-- @teacher [START 09-SQL002] Lab 9C / Blocking Session B | A ถือ Row Lock; B รอจน Lock Timeout
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor | Session B
-- @teacher อธิบาย: ตรวจความสัมพันธ์ Blocker/Blocked ของ Sessions ที่มีการรออยู่จริง
-- @teacher ผล/ชวนสังเกต: ก่อน B เริ่ม UPDATE อาจยังไม่มีผู้รอ จึงได้ 0 แถว; ใช้ Session C ดูระหว่าง B รอหากต้องการเห็นคู่ PID
-- @teacher SOURCE: 09-blocking-session-b.sql:16 | รัน SQL นี้ครบทั้ง Statement
SELECT blocked.pid AS blocked_pid,
       blocker.pid AS blocker_pid,
       blocked.wait_event_type,
       blocked.wait_event,
       left(blocker.query, 100) AS blocker_query
FROM pg_stat_activity blocked
CROSS JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS b(blocker_pid)
JOIN pg_stat_activity blocker ON blocker.pid = b.blocker_pid;
-- @teacher [END 09-SQL002]

-- @teacher [START 09-SQL003] Lab 9C / Blocking Session B | A ถือ Row Lock; B รอจน Lock Timeout
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor | Session B
-- @teacher อธิบาย: กำหนดเวลารอ Lock ของ B เพียง 2 วินาทีสำหรับการสาธิต
-- @teacher ผล/ชวนสังเกต: เป็น Session Setting และจะ RESET ตอนท้าย ไม่แก้ postgresql.conf
-- @teacher SOURCE: 09-blocking-session-b.sql:25 | รัน SQL นี้ครบทั้ง Statement
SET lock_timeout = '2s';
-- @teacher [END 09-SQL003]
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP off
-- @teacher [START 09-SQL004] Lab 9C / Blocking Session B | A ถือ Row Lock; B รอจน Lock Timeout
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor | Session B
-- @teacher อธิบาย: ทดลอง UPDATE แถวที่ A ยังถือ Lock
-- @teacher ผล/ชวนสังเกต: คาด Lock Timeout ถ้า A ยังไม่ Commit; ON_ERROR_STOP off เฉพาะช่วงนี้ให้ Script ทำขั้น RESET ต่อได้
-- @teacher SOURCE: 09-blocking-session-b.sql:27 | รัน SQL นี้ครบทั้ง Statement
UPDATE lab_m9.lock_demo SET note = 'attempted by session B' WHERE id = 1;
-- @teacher [END 09-SQL004]
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP on
-- @teacher [START 09-SQL005] Lab 9C / Blocking Session B | A ถือ Row Lock; B รอจน Lock Timeout
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor | Session B
-- @teacher อธิบาย: คืน lock_timeout ของ B หลังจบกรณี Expected Error
-- @teacher ผล/ชวนสังเกต: Statement Timeout/Lock Timeout ไม่ใช่ Deadlock; การ Timeout ของ B ไม่ได้ยกเลิก Transaction ของ A
-- @teacher SOURCE: 09-blocking-session-b.sql:29 | รัน SQL นี้ครบทั้ง Statement
RESET lock_timeout;
-- @teacher [END 09-SQL005]

-- @teacher [START 09-SQL006] Lab 9C / Blocking Session B | A ถือ Row Lock; B รอจน Lock Timeout
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor | Session B
-- @teacher อธิบาย: ตรวจ State/Wait ของ Sessions หลังการทดลอง
-- @teacher ผล/ชวนสังเกต: Query อาจสั้นจนไม่เห็นช่วงรอแล้ว; ให้เก็บหลักฐานจาก Observer ขณะ B รอด้วย
-- @teacher SOURCE: 09-blocking-session-b.sql:31 | รัน SQL นี้ครบทั้ง Statement
SELECT pid, state, wait_event_type, wait_event, left(query, 100) AS query
FROM pg_stat_activity
WHERE datname = current_database()
ORDER BY pid;
-- @teacher [END 09-SQL006]
