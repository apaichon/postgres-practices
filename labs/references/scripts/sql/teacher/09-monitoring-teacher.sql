-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 09-monitoring.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/09-monitoring.sql
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
-- @teacher ==============================================================================
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP on
-- @teacher PSQL: ตั้งรูปแบบแสดงผลของ psql ไม่เปลี่ยนข้อมูลใน Database
\pset pager off
\echo '=== Module 9: Monitoring and Troubleshooting ==='

-- @teacher [START 09-SQL001] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: เตรียม Namespace ของ Blocking Fixture
-- @teacher ผล/ชวนสังเกต: ทำครั้งแรกบน Primary ที่อนุญาตให้สร้าง Lab Objects
-- @teacher SOURCE: 09-monitoring.sql:5 | รัน SQL นี้ครบทั้ง Statement
CREATE SCHEMA IF NOT EXISTS lab_m9;
-- @teacher [END 09-SQL001]
-- @teacher [START 09-SQL002] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: สร้างแถวเป้าหมายที่สอง Sessions จะแข่งขัน UPDATE
-- @teacher ผล/ชวนสังเกต: Primary Key id ทำให้เลือกแถวเดียวได้แน่นอน
-- @teacher SOURCE: 09-monitoring.sql:6 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS lab_m9.lock_demo (
    id integer PRIMARY KEY,
    note text NOT NULL
);
-- @teacher [END 09-SQL002]
-- @teacher [START 09-SQL003] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: ตั้งแถว id=1 เป็น ready สำหรับเริ่มการสาธิต
-- @teacher ผล/ชวนสังเกต: รันตอนที่ไม่มี Session A/B ถือ Lock แล้ว; Upsert อาจรอ Lock หากเริ่มทับการสาธิต
-- @teacher SOURCE: 09-monitoring.sql:10 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m9.lock_demo VALUES (1, 'ready')
ON CONFLICT (id) DO UPDATE SET note = EXCLUDED.note;
-- @teacher [END 09-SQL003]

\echo '\n-- Lab 9A: connection and workload snapshot'
-- @teacher [START 09-SQL004] Lab 9A | connection and workload snapshot
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: นับ Client Backends แยก State และ Wait Events เพื่อดูภาพรวมโหลด
-- @teacher ผล/ชวนสังเกต: Scope เป็นทั้ง Cluster ตาม SQL นี้; idle ไม่ใช่ Active Query และ Wait Event ไม่ได้แปลว่าเป็น Lock เสมอ
-- @teacher SOURCE: 09-monitoring.sql:14 | รัน SQL นี้ครบทั้ง Statement
SELECT state, wait_event_type, wait_event, count(*) AS sessions
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state, wait_event_type, wait_event
ORDER BY sessions DESC;
-- @teacher [END 09-SQL004]

-- @teacher [START 09-SQL005] Lab 9A | connection and workload snapshot
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: อ่าน Query Age และ Transaction Age ของ Sessions อื่นในฐานเดียวกัน
-- @teacher ผล/ชวนสังเกต: Transaction ที่ค้างนานอาจเก็บ Snapshot แม้ State idle in transaction; Role ต้องมีสิทธิ์เห็นรายละเอียด
-- @teacher SOURCE: 09-monitoring.sql:20 | รัน SQL นี้ครบทั้ง Statement
SELECT pid, usename, application_name, state,
       clock_timestamp() - query_start AS query_age,
       clock_timestamp() - xact_start AS transaction_age,
       wait_event_type, wait_event,
       left(query, 120) AS query
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
ORDER BY query_start NULLS LAST;
-- @teacher [END 09-SQL005]

\echo '\n-- Lab 9B: slow SQL and cache efficiency'
-- @teacher [START 09-SQL006] Lab 9B | slow SQL and cache efficiency
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: ตรวจว่า Extension pg_stat_statements มีใน Database นี้ก่อนเลือก Branch
-- @teacher ผล/ชวนสังเกต: มี Extension ยังต้องมี shared_preload_libraries ที่ถูกต้อง; psql gset/if ไม่ใช่ SQL ของ Server
-- @teacher SOURCE: 09-monitoring.sql:31 | รัน SQL นี้ครบทั้ง Statement
SELECT EXISTS (SELECT FROM pg_extension WHERE extname = 'pg_stat_statements') AS has_pgss \gset
-- @teacher [END 09-SQL006]
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :has_pgss
-- @teacher [START 09-SQL007] Lab 9B | slow SQL and cache efficiency
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: จัดอันดับ Query ตาม Total Execution Time โดยแสดง Calls และ Mean ร่วมกัน
-- @teacher ผล/ชวนสังเกต: Total มากอาจเกิดจากเรียกถี่ ไม่จำเป็นต้องเป็น Query เดี่ยวช้าที่สุด; ค่านี้สะสม ไม่ใช่ช่วงเวลาล่าสุดเสมอ
-- @teacher SOURCE: 09-monitoring.sql:33 | รัน SQL นี้ครบทั้ง Statement
SELECT calls,
       round(total_exec_time::numeric, 2) AS total_ms,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       rows,
       shared_blks_hit,
       shared_blks_read,
       left(query, 120) AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY total_exec_time DESC
LIMIT 15;
-- @teacher [END 09-SQL007]
-- @teacher PSQL: Branch ทางเลือกของ psql; ไม่เลือก Execute ทั้งสอง Branch ใน SQL Editor
\else
\echo 'pg_stat_statements is not installed in this database.'
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif

-- @teacher [START 09-SQL008] Lab 9B | slow SQL and cache efficiency
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: คำนวณ Cache Hit Percent พร้อมปริมาณ Temp Spill ของ Database
-- @teacher ผล/ชวนสังเกต: NULLIF ป้องกันหารศูนย์; blks_read อาจได้ข้อมูลจาก OS Cache จึงไม่ใช่ Physical Disk Reads ทั้งหมด
-- @teacher SOURCE: 09-monitoring.sql:48 | รัน SQL นี้ครบทั้ง Statement
SELECT datname,
       blks_hit,
       blks_read,
       round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS cache_hit_percent,
       temp_files,
       pg_size_pretty(temp_bytes) AS temp_bytes
FROM pg_stat_database
WHERE datname = current_database();
-- @teacher [END 09-SQL008]

\echo '\n-- Lab 9C: blocker -> blocked relationship'
-- @teacher [START 09-SQL009] Lab 9C | blocker -> blocked relationship
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: ขยาย pg_blocking_pids เป็นความสัมพันธ์ Blocked → Blocker
-- @teacher ผล/ชวนสังเกต: ต้องมีผู้รอจริงจึงพบแถว; เปิด Observer Session C ระหว่าง A ถือ Lock และ B รอ UPDATE
-- @teacher SOURCE: 09-monitoring.sql:58 | รัน SQL นี้ครบทั้ง Statement
SELECT blocked.pid AS blocked_pid,
       blocker.pid AS blocker_pid,
       clock_timestamp() - blocked.query_start AS blocked_for,
       blocked.wait_event_type,
       blocked.wait_event,
       left(blocked.query, 100) AS blocked_query,
       left(blocker.query, 100) AS blocker_query
FROM pg_stat_activity blocked
CROSS JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS b(blocker_pid)
JOIN pg_stat_activity blocker ON blocker.pid = b.blocker_pid
ORDER BY blocked_for DESC;
-- @teacher [END 09-SQL009]

\echo '\n-- Lab 9D: database, table, maintenance, WAL and replication health'
-- @teacher [START 09-SQL010] Lab 9D | database, table, maintenance, WAL and replication health
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: อ่าน Transactions, Deadlocks และ Temp Work ของ Database
-- @teacher ผล/ชวนสังเกต: Deadlocks เป็น Counter สะสม ไม่ใช่รายชื่อ Sessions ที่รอ Lock อยู่ตอนนี้
-- @teacher SOURCE: 09-monitoring.sql:71 | รัน SQL นี้ครบทั้ง Statement
SELECT datname, numbackends, xact_commit, xact_rollback,
       deadlocks, conflicts, temp_files, pg_size_pretty(temp_bytes) AS temp_bytes
FROM pg_stat_database
WHERE datname = current_database();
-- @teacher [END 09-SQL010]

-- @teacher [START 09-SQL011] Lab 9D | database, table, maintenance, WAL and replication health
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: หา Tables ที่มี Dead Tuple Estimates และประวัติงานดูแล
-- @teacher ผล/ชวนสังเกต: Estimate อาจล่าช้า; อย่าตัดสิน Bloat หรือสั่ง VACUUM FULL จาก Counter ตัวเดียว
-- @teacher SOURCE: 09-monitoring.sql:76 | รัน SQL นี้ครบทั้ง Statement
SELECT schemaname, relname, n_live_tup, n_dead_tup,
       last_autovacuum, last_autoanalyze,
       vacuum_count, autovacuum_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 20;
-- @teacher [END 09-SQL011]

-- @teacher [START 09-SQL012] Lab 9D | database, table, maintenance, WAL and replication health
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: ตรวจความสำเร็จ/ล้มเหลวของ WAL Archiving
-- @teacher ผล/ชวนสังเกต: ต้องอ่านเวลาเกิด Failure เทียบ Success ล่าสุด; ไม่ใช่ผลทดสอบ Restore
-- @teacher SOURCE: 09-monitoring.sql:83 | รัน SQL นี้ครบทั้ง Statement
SELECT archived_count, failed_count, last_archived_wal,
       last_archived_time, last_failed_wal, last_failed_time
FROM pg_stat_archiver;
-- @teacher [END 09-SQL012]

-- @teacher [START 09-SQL013] Lab 9D | database, table, maintenance, WAL and replication health
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: อ่านสถานะ Replication และ Lag ประกอบเหตุขัดข้อง
-- @teacher ผล/ชวนสังเกต: อาจไม่มีแถวหากไม่มี Replica; ไม่สั่ง Promote/Terminate จากตัวเลขนี้เพียงอย่างเดียว
-- @teacher SOURCE: 09-monitoring.sql:87 | รัน SQL นี้ครบทั้ง Statement
SELECT application_name, state, sync_state, write_lag, flush_lag, replay_lag
FROM pg_stat_replication
ORDER BY application_name;
-- @teacher [END 09-SQL013]

-- @teacher [START 09-SQL014] Lab 9D | database, table, maintenance, WAL and replication health
-- @teacher LOGIN / DATABASE: postgres | claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor
-- @teacher อธิบาย: อ่าน Settings ที่เกี่ยวกับการเก็บหลักฐาน Slow SQL/Locks/I/O
-- @teacher ผล/ชวนสังเกต: Query นี้ไม่เปิด Logging ให้เอง; บันทึก Source และภาระก่อนเปลี่ยนระบบจริง
-- @teacher SOURCE: 09-monitoring.sql:91 | รัน SQL นี้ครบทั้ง Statement
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN ('log_min_duration_statement','log_lock_waits',
               'deadlock_timeout','track_io_timing','track_functions')
ORDER BY name;
-- @teacher [END 09-SQL014]

\echo '\nUse 09-blocking-session-a.sql and 09-blocking-session-b.sql for the live lock exercise.'
