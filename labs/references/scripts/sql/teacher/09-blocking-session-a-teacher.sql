-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 09-blocking-session-a.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/09-blocking-session-a.sql
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
\echo '=== Module 9 Blocking — Session A ==='
-- @teacher [START 09-SQL001] Lab 9C / Blocking Session A | A ถือ Row Lock; B รอจน Lock Timeout
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor | Session A
-- @teacher อธิบาย: A เปิด Transaction เพื่อถือ Row Lock ไว้ข้าม Statements
-- @teacher ผล/ชวนสังเกต: เตรียม Fixture จาก Module 9 ก่อน และใช้ Connection เดียวตลอด A
-- @teacher SOURCE: 09-blocking-session-a.sql:4 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 09-SQL001]
-- @teacher [START 09-SQL002] Lab 9C / Blocking Session A | A ถือ Row Lock; B รอจน Lock Timeout
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor | Session A
-- @teacher อธิบาย: UPDATE id=1 แล้วคง Transaction เปิดไว้
-- @teacher ผล/ชวนสังเกต: UPDATE สำเร็จแต่ยังไม่ Commit; เมื่อ B จะ UPDATE แถวเดียวกัน B ต้องรอ
-- @teacher SOURCE: 09-blocking-session-a.sql:5 | รัน SQL นี้ครบทั้ง Statement
UPDATE lab_m9.lock_demo SET note = 'locked by session A' WHERE id = 1;
-- @teacher [END 09-SQL002]
-- @teacher [START 09-SQL003] Lab 9C / Blocking Session A | A ถือ Row Lock; B รอจน Lock Timeout
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor | Session A
-- @teacher อธิบาย: บันทึก PID ของ A ที่เป็น Blocker
-- @teacher ผล/ชวนสังเกต: ใช้ PID นี้เทียบ pg_locks/pg_blocking_pids ใน Observer
-- @teacher SOURCE: 09-blocking-session-a.sql:6 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_backend_pid() AS blocker_pid;
-- @teacher [END 09-SQL003]
\echo 'Row lock is held. Start Session B now.'
-- @teacher PSQL: หยุดรอผู้สอน: ให้ Session อีกฝั่งทำตามโจทย์ก่อนกด Enter; SQL Editor ต้องหยุดเองตรงนี้
\prompt 'After Session B shows the blocker, press Enter to COMMIT: ' continue
-- @teacher [START 09-SQL004] Lab 9C / Blocking Session A | A ถือ Row Lock; B รอจน Lock Timeout
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor | Session A
-- @teacher อธิบาย: ปล่อย Lock ด้วย COMMIT เมื่อผู้สอนสังเกตเสร็จแล้ว
-- @teacher ผล/ชวนสังเกต: Prompt ของ psql เป็นจุดหยุดสอน; หาก B รอไม่เกิน Timeout จะทำงานต่อได้ แต่ตัวอย่าง B ตั้ง Timeout สั้น
-- @teacher SOURCE: 09-blocking-session-a.sql:9 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 09-SQL004]
-- @teacher [START 09-SQL005] Lab 9C / Blocking Session A | A ถือ Row Lock; B รอจน Lock Timeout
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor | Session A
-- @teacher อธิบาย: ดูค่าหลัง A ยืนยันข้อมูล
-- @teacher ผล/ชวนสังเกต: ต้องมีแถว id=1; ค่าท้ายสุดขึ้นกับว่า B ได้ UPDATE หลัง A ปล่อย Lock หรือหมดเวลาก่อน
-- @teacher SOURCE: 09-blocking-session-a.sql:10 | รัน SQL นี้ครบทั้ง Statement
SELECT * FROM lab_m9.lock_demo;
-- @teacher [END 09-SQL005]
