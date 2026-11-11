-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 08-replication.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/08-replication.sql
-- @teacher LOGIN / DATABASE เริ่มต้น: postgres | claimsure | Primary สำหรับ Setup/Publication; ดู Session ของแต่ละ Lab
-- @teacher อ่าน README.md ใน Directory นี้ก่อนสอน; ใช้ไฟล์นี้เป็นคู่มือเลือกรันทีละส่วน
-- @teacher แต่ละ SQL มี START/END, Lab, Login, เหตุผล และผลที่ต้องสังเกต; Source Line อ้างไฟล์ต้นฉบับ
-- @teacher START/END ราย SQL ใช้ค้นคำอธิบาย ไม่ใช่ขอบเขต Commit: Transaction/Function ต้องรันครบชุด
-- @teacher คำสั่ง psql ขึ้นต้นด้วย Backslash; SQL Editor ทั่วไปให้ข้ามและจัด Branch/Variables เอง
-- @teacher ทุกบรรทัดที่เพิ่มขึ้นต้น -- @teacher; SQL/psql ต้นฉบับคงเดิม รวมคำสั่งเปลี่ยนข้อมูลและ Expected Errors
-- @teacher เป้าหมาย: Primary/Standby → WAL Lag/Slots → Publication → Routing
-- @teacher Setup SQL001–003 และ Publication 8D ทำบน Primary; อย่า Execute All บน Standby เพราะเริ่มด้วย DDL/DML
-- @teacher 8A/B อ่านทั้งสองฝั่ง; 8C Query pg_current_wal_lsn ทำบน Primary; 8E ต่อแต่ละ Endpoint แล้วเทียบผล
-- @teacher Publication ไม่สร้าง Subscription ให้เอง; ยังต้องตั้ง Subscriber/Permissions/Network ตาม Environment
-- @teacher ==============================================================================
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP on
-- @teacher PSQL: ตั้งรูปแบบแสดงผลของ psql ไม่เปลี่ยนข้อมูลใน Database
\pset pager off
\echo '=== Module 8: Replication and High Availability ==='
-- @teacher PSQL: ยืนยัน Host/Port/Database/User ของ Connection ปัจจุบันก่อนรัน Lab
\conninfo

-- @teacher [START 08-SQL001] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure | Primary
-- @teacher อธิบาย: เตรียม Schema ทดลองบน Primary ก่อนอ่านหลักฐาน Replication
-- @teacher ผล/ชวนสังเกต: DDL ส่วน Setup นี้รันบน Standby ไม่ได้; เมื่อสลับไป Standby ให้เลือกเฉพาะ Query อ่านที่ระบุ
-- @teacher SOURCE: 08-replication.sql:6 | รัน SQL นี้ครบทั้ง Statement
CREATE SCHEMA IF NOT EXISTS lab_m8;
-- @teacher [END 08-SQL001]
-- @teacher [START 08-SQL002] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure | Primary
-- @teacher อธิบาย: สร้าง Table สำหรับ Logical Publication โดยมี Primary Key
-- @teacher ผล/ชวนสังเกต: มี Identity และ Business Key; Publisher ต้องมี Table นี้ก่อนประกาศ Publication
-- @teacher SOURCE: 08-replication.sql:7 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS lab_m8.logical_claim (
    claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    claim_no text NOT NULL UNIQUE,
    status text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
-- @teacher [END 08-SQL002]
-- @teacher [START 08-SQL003] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure | Primary
-- @teacher อธิบาย: Upsert REPL-001 บน Primary เพื่อมีข้อมูลสำหรับสังเกต
-- @teacher ผล/ชวนสังเกต: การเห็นตารางบน Physical Standby ต้องรอ Replay; Publication อย่างเดียวไม่สร้าง Subscriber
-- @teacher SOURCE: 08-replication.sql:13 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m8.logical_claim(claim_no, status)
VALUES ('REPL-001', 'NEW')
ON CONFLICT (claim_no) DO UPDATE
SET status = EXCLUDED.status, updated_at = clock_timestamp();
-- @teacher [END 08-SQL003]

\echo '\n-- Lab 8A/8B: primary or standby, senders and receiver'
-- @teacher [START 08-SQL004] Lab 8A/8B | primary or standby, senders and receiver
-- @teacher LOGIN / DATABASE: postgres | claimsure | เลือกอ่านบน Primary และ Standby แยกกัน
-- @teacher อธิบาย: แยก Primary/Standby และเลือก LSN Function ให้เหมาะกับฝั่งที่เชื่อม
-- @teacher ผล/ชวนสังเกต: Primary ได้ false; Standby ได้ true; pg_last_wal_replay_lsn อาจ NULL หากยังไม่มี Replay
-- @teacher SOURCE: 08-replication.sql:19 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_is_in_recovery() AS is_standby,
       CASE WHEN pg_is_in_recovery()
            THEN pg_last_wal_replay_lsn()
            ELSE pg_current_wal_lsn() END AS current_position;
-- @teacher [END 08-SQL004]

-- @teacher [START 08-SQL005] Lab 8A/8B | primary or standby, senders and receiver
-- @teacher LOGIN / DATABASE: postgres | claimsure | เลือกอ่านบน Primary และ Standby แยกกัน
-- @teacher อธิบาย: อ่าน Walsender และตำแหน่ง sent/write/flush/replay จาก Primary
-- @teacher ผล/ชวนสังเกต: จำนวนแถวอิง Replicas ที่เชื่อมอยู่; Byte Lag ไม่ใช่เวลาหน่วง และไม่เท่ากับ WAL ของ Slot ที่ต้องเก็บ
-- @teacher SOURCE: 08-replication.sql:24 | รัน SQL นี้ครบทั้ง Statement
SELECT pid, application_name, client_addr, state, sync_state,
       sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS byte_lag
FROM pg_stat_replication
ORDER BY application_name;
-- @teacher [END 08-SQL005]

-- @teacher [START 08-SQL006] Lab 8A/8B | primary or standby, senders and receiver
-- @teacher LOGIN / DATABASE: postgres | claimsure | เลือกอ่านบน Primary และ Standby แยกกัน
-- @teacher อธิบาย: อ่าน WAL Receiver ทาง Standby
-- @teacher ผล/ชวนสังเกต: Primary มักได้ 0 แถว; sender_host/slot_name ชี้ว่ารับ WAL จากที่ใด
-- @teacher SOURCE: 08-replication.sql:30 | รัน SQL นี้ครบทั้ง Statement
SELECT status, sender_host, sender_port, slot_name,
       written_lsn, flushed_lsn, latest_end_lsn,
       last_msg_receipt_time
FROM pg_stat_wal_receiver;
-- @teacher [END 08-SQL006]

\echo '\n-- Lab 8C: lag dimensions and replay delay'
-- @teacher [START 08-SQL007] Lab 8C | lag dimensions and replay delay
-- @teacher LOGIN / DATABASE: postgres | claimsure | Primary
-- @teacher อธิบาย: เปรียบเทียบ Write/Flush/Replay Lag บน Primary
-- @teacher ผล/ชวนสังเกต: ค่า NULL/0 เมื่อไม่มีงานใหม่ไม่ได้แปลว่า Replay ทันภายใต้ทุกภาระ; retained_bytes ใน Query นี้คือ LSN Delta ถึง Replay
-- @teacher SOURCE: 08-replication.sql:36 | รัน SQL นี้ครบทั้ง Statement
SELECT application_name,
       write_lag, flush_lag, replay_lag,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS retained_bytes
FROM pg_stat_replication
ORDER BY application_name;
-- @teacher [END 08-SQL007]

-- @teacher [START 08-SQL008] Lab 8C | lag dimensions and replay delay
-- @teacher LOGIN / DATABASE: postgres | claimsure | Primary
-- @teacher อธิบาย: ตรวจ Replication Slots ที่อาจยึด WAL แม้ Replica หยุด
-- @teacher ผล/ชวนสังเกต: active=false ไม่ได้แปลว่า Slot ถูกลบ; restart_lsn/wal_status/safe_wal_size ช่วยประเมิน Disk Risk
-- @teacher SOURCE: 08-replication.sql:42 | รัน SQL นี้ครบทั้ง Statement
SELECT slot_name, slot_type, active, restart_lsn, confirmed_flush_lsn,
       wal_status, safe_wal_size
FROM pg_replication_slots
ORDER BY slot_name;
-- @teacher [END 08-SQL008]

\echo '\n-- Synchronous replication policy (observe; do not change blindly)'
-- @teacher [START 08-SQL009] Lab 8C | lag dimensions and replay delay
-- @teacher LOGIN / DATABASE: postgres | claimsure | เลือกอ่านบน Primary และ Standby แยกกัน
-- @teacher อธิบาย: อ่านนโยบาย Synchronous Replication และกำลัง Sender/Slots
-- @teacher ผล/ชวนสังเกต: เป็นการ Observe ไม่ได้แก้ Config; synchronous_commit อย่างเดียวไม่สร้าง Synchronous Standby
-- @teacher SOURCE: 08-replication.sql:48 | รัน SQL นี้ครบทั้ง Statement
SELECT name, setting, source
FROM pg_settings
WHERE name IN ('synchronous_commit','synchronous_standby_names',
               'max_wal_senders','max_replication_slots','wal_keep_size')
ORDER BY name;
-- @teacher [END 08-SQL009]

\echo '\n-- Lab 8D: logical publication on the primary'
-- @teacher [START 08-SQL010] Lab 8D | logical publication on the primary
-- @teacher LOGIN / DATABASE: postgres | claimsure | Primary
-- @teacher อธิบาย: เก็บผลว่าเป็น Standby ลงตัวแปร psql เพื่อเลือก Branch
-- @teacher ผล/ชวนสังเกต: GUI SQL Editor ต้องอ่านผลแล้วเลือก Branch เอง; ห้ามใช้ pg_current_wal_lsn แบบ Primary บน Standby
-- @teacher SOURCE: 08-replication.sql:55 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_is_in_recovery() AS in_recovery \gset
-- @teacher [END 08-SQL010]
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :in_recovery
\echo 'Skip publication creation: this server is a standby.'
-- @teacher PSQL: Branch ทางเลือกของ psql; ไม่เลือก Execute ทั้งสอง Branch ใน SQL Editor
\else
-- @teacher [START 08-SQL011] Lab 8D | logical publication on the primary
-- @teacher LOGIN / DATABASE: postgres | claimsure | Primary
-- @teacher อธิบาย: สร้าง Publication หากยังไม่มี บน Primary เท่านั้น
-- @teacher ผล/ชวนสังเกต: ต้องมีสิทธิ์สร้าง Publication และเป็นเจ้าของ Table; การ Stream Logical ต้องเตรียม wal_level=logical ตามระบบ
-- @teacher SOURCE: 08-replication.sql:59 | รัน SQL นี้ครบทั้ง Statement
DO $block$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_publication WHERE pubname = 'lab_m8_claim_publication') THEN
        CREATE PUBLICATION lab_m8_claim_publication
        FOR TABLE lab_m8.logical_claim;
    END IF;
END
$block$;
-- @teacher [END 08-SQL011]

-- @teacher [START 08-SQL012] Lab 8D | logical publication on the primary
-- @teacher LOGIN / DATABASE: postgres | claimsure | Primary
-- @teacher อธิบาย: ตรวจ Publication และสมาชิก Table จาก Catalog
-- @teacher ผล/ชวนสังเกต: การพบ Publication ยืนยันเพียงฝั่ง Publisher ยังไม่ใช่หลักฐานว่ามี Subscriber รับข้อมูลแล้ว
-- @teacher SOURCE: 08-replication.sql:68 | รัน SQL นี้ครบทั้ง Statement
SELECT p.pubname, p.pubinsert, p.pubupdate, p.pubdelete,
       n.nspname AS schema_name, c.relname AS table_name
FROM pg_publication p
LEFT JOIN pg_publication_rel pr ON pr.prpubid = p.oid
LEFT JOIN pg_class c ON c.oid = pr.prrelid
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE p.pubname = 'lab_m8_claim_publication';
-- @teacher [END 08-SQL012]
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif

\echo '\n-- Subscription health (empty until a subscriber is configured)'
-- @teacher [START 08-SQL013] Lab 8D | logical publication on the primary
-- @teacher LOGIN / DATABASE: postgres | Database ฝั่ง Subscriber ถ้ามี Subscription
-- @teacher อธิบาย: อ่าน Subscription Workers หากมีการตั้ง Subscriber ไว้แล้ว
-- @teacher ผล/ชวนสังเกต: 0 แถวเป็นผลปกติเมื่อยังไม่มี Subscription; ไม่สรุปว่า Physical Replication เสีย
-- @teacher SOURCE: 08-replication.sql:78 | รัน SQL นี้ครบทั้ง Statement
SELECT subname, pid, relid::regclass, received_lsn,
       last_msg_send_time, last_msg_receipt_time,
       latest_end_lsn, latest_end_time
FROM pg_stat_subscription
ORDER BY subname, relid;
-- @teacher [END 08-SQL013]

\echo '\n-- Lab 8E: routing evidence for direct/PgBouncer/HAProxy connections'
-- @teacher [START 08-SQL014] Lab 8E | routing evidence for direct/PgBouncer/HAProxy connections
-- @teacher LOGIN / DATABASE: Role ของ Lab | claimsure | ต่อแต่ละ Direct/Pooler/HAProxy Endpoint แล้วรัน Query เดิม
-- @teacher อธิบาย: ตรวจ Backend จริงที่ปลายทางหลังเชื่อม Direct/Pooler/HAProxy
-- @teacher ผล/ชวนสังเกต: server_port เป็น Port ภายใน PostgreSQL; ต้องใช้ pg_is_in_recovery/read_only ร่วมกับข้อมูล Endpoint ของ Client
-- @teacher SOURCE: 08-replication.sql:85 | รัน SQL นี้ครบทั้ง Statement
SELECT inet_server_addr() AS server_ip,
       inet_server_port() AS server_port,
       pg_is_in_recovery() AS is_replica,
       current_setting('transaction_read_only') AS transaction_read_only;
-- @teacher [END 08-SQL014]

\echo 'From the host, compare endpoints:'
\echo '  make psql             # direct primary'
\echo '  make replica          # direct replica'
\echo '  make pgbouncer        # pooled write connection'
\echo '  make haproxy-write    # HAProxy primary endpoint'
\echo '  make haproxy-read     # HAProxy replica endpoint'
\echo 'Inside PgBouncer admin DB use SHOW POOLS; and SHOW STATS;'
