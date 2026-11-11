-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 03-performance-tuning.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/03-performance-tuning.sql
-- @teacher LOGIN / DATABASE เริ่มต้น: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อ่าน README.md ใน Directory นี้ก่อนสอน; ใช้ไฟล์นี้เป็นคู่มือเลือกรันทีละส่วน
-- @teacher แต่ละ SQL มี START/END, Lab, Login, เหตุผล และผลที่ต้องสังเกต; Source Line อ้างไฟล์ต้นฉบับ
-- @teacher START/END ราย SQL ใช้ค้นคำอธิบาย ไม่ใช่ขอบเขต Commit: Transaction/Function ต้องรันครบชุด
-- @teacher คำสั่ง psql ขึ้นต้นด้วย Backslash; SQL Editor ทั่วไปให้ข้ามและจัด Branch/Variables เอง
-- @teacher ทุกบรรทัดที่เพิ่มขึ้นต้น -- @teacher; SQL/psql ต้นฉบับคงเดิม รวมคำสั่งเปลี่ยนข้อมูลและ Expected Errors
-- @teacher เป้าหมาย: วัด Baseline → Index → Maintenance → Partition → Reporting Snapshot
-- @teacher สร้างใหม่เฉพาะ *_perf Fixture 2 ล้าน Claims/1200 Policies; DROP/TRUNCATE ล้างข้อมูลทดลองเดิม
-- @teacher Autocommit เปิด; VACUUM ห้ามอยู่ใน BEGIN; EXPLAIN ANALYZE รัน Query จริง
-- @teacher ข้ออธิบาย Memory จากสูตร /6 เดิมเป็นตัวอย่างก่อน PG17; PG17+ ใช้ TidStore อย่าใช้สูตรนั้นคำนวณ Capacity จริง
-- @teacher ==============================================================================
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP on
-- @teacher PSQL: ตั้งรูปแบบแสดงผลของ psql ไม่เปลี่ยนข้อมูลใน Database
\pset pager off
-- @teacher PSQL: แสดงเวลาใน Client; แยกจาก Execution Time ใน EXPLAIN
\timing on
\echo '=== Module 3: Performance Tuning ==='

-- Lab 3 — Performance Evidence and Reporting Structures
-- Run all: ./scripts/shells/run-lab03.sh --student xx --ask-pass all
-- Run one: ./scripts/shells/run-lab03.sh --student xx --ask-pass A
--
-- Lab 3A  Compare a slow plan with a partial covering index
-- Lab 3B  Match expression, GIN, and BRIN indexes to query shapes
-- Lab 3C  Collect index and autovacuum maintenance evidence
-- Lab 3D  Build and verify a monthly range-partitioned report table
-- Lab 3E  Build a materialized summary and dashboard snapshot

-- Workload: 2,000,000 claims across 1,200 policies.
-- Lower the claim series (for example 20000) on a slow client.
-- These are plain integers so SQLTools and other non-psql clients can run the INSERT.
-- Dedicated *_perf tables stay separate from ClaimSure starter data.

-- @teacher [START 03-SQL001] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: เตรียม Schema insurance เป็น Namespace ของ Objects ใน Lab
-- @teacher ผล/ชวนสังเกต: ต้องมี CREATE บน Database; IF NOT EXISTS ไม่ล้างข้อมูลหรือแก้ Owner ของ Schema เดิม
-- @teacher SOURCE: 03-performance-tuning.sql:21 | รัน SQL นี้ครบทั้ง Statement
CREATE SCHEMA IF NOT EXISTS insurance;
-- @teacher [END 03-SQL001]

-- @teacher [START 03-SQL002] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: ลบ Table ทดลอง insurance.claim_perf เดิมพร้อมข้อมูลเพื่อเริ่มรอบที่เทียบกันได้
-- @teacher ผล/ชวนสังเกต: ตรวจชื่อและ Database ให้ตรงก่อนรัน; ไม่ใช้คำสั่งนี้กับ Table ธุรกิจที่ต้องเก็บ
-- @teacher SOURCE: 03-performance-tuning.sql:23 | รัน SQL นี้ครบทั้ง Statement
DROP TABLE IF EXISTS insurance.claim_perf;
-- @teacher [END 03-SQL002]
-- @teacher [START 03-SQL003] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: ลบ Table ทดลอง insurance.policy_perf เดิมพร้อมข้อมูลเพื่อเริ่มรอบที่เทียบกันได้
-- @teacher ผล/ชวนสังเกต: ตรวจชื่อและ Database ให้ตรงก่อนรัน; ไม่ใช้คำสั่งนี้กับ Table ธุรกิจที่ต้องเก็บ
-- @teacher SOURCE: 03-performance-tuning.sql:24 | รัน SQL นี้ครบทั้ง Statement
DROP TABLE IF EXISTS insurance.policy_perf;
-- @teacher [END 03-SQL003]

-- @teacher [START 03-SQL004] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง UNLOGGED Policy Fixture สำหรับ Benchmark แยกจากข้อมูลเริ่มต้น
-- @teacher ผล/ชวนสังเกต: UNLOGGED ลดภาระ WAL ของข้อมูล แต่ไม่ใช่รูปแบบเก็บ Claim ที่ต้องทนต่อ Crash/Replica
-- @teacher SOURCE: 03-performance-tuning.sql:26 | รัน SQL นี้ครบทั้ง Statement
CREATE UNLOGGED TABLE insurance.policy_perf (
    policy_id bigint PRIMARY KEY,
    tenant_id bigint NOT NULL,
    policy_no text NOT NULL UNIQUE,
    product_code text NOT NULL,
    status text NOT NULL
);
-- @teacher [END 03-SQL004]

-- @teacher [START 03-SQL005] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง UNLOGGED Claim Fixture ที่มี Columns สำหรับหลายรูปแบบค้นหา
-- @teacher ผล/ชวนสังเกต: ไม่มี Foreign Key บน policy_id ใน Fixture นี้; อย่านำความเรียบง่ายของ Benchmark ไปแทน Model Production
-- @teacher SOURCE: 03-performance-tuning.sql:34 | รัน SQL นี้ครบทั้ง Statement
CREATE UNLOGGED TABLE insurance.claim_perf (
    claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id bigint NOT NULL,
    policy_id bigint NOT NULL,
    policy_no text NOT NULL,
    claim_no text NOT NULL UNIQUE,
    branch_code text NOT NULL,
    status text NOT NULL,
    incident_at timestamptz NOT NULL,
    estimated_amount numeric(14,2) NOT NULL,
    description text,
    metadata jsonb NOT NULL DEFAULT '{}'
);
-- @teacher [END 03-SQL005]

-- @teacher [START 03-SQL006] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง 1200 Policies แบบกำหนดรูปแบบด้วย generate_series และ modulo
-- @teacher ผล/ชวนสังเกต: การกระจาย Tenant/Product/Status ถูกสังเคราะห์ ไม่ใช่สถิติจาก ClaimSure จริง
-- @teacher SOURCE: 03-performance-tuning.sql:48 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO insurance.policy_perf
    (policy_id, tenant_id, policy_no, product_code, status)
SELECT g,
       1 + (g % 20),
       'POL-PERF-' || lpad(g::text, 5, '0'),
       (ARRAY['AUTO','HOME','TRAVEL','HEALTH'])[1 + (g % 4)],
       (ARRAY['ACTIVE','ACTIVE','ACTIVE','EXPIRED','CANCELLED'])[1 + (g % 5)]
FROM generate_series(1, 1200) AS g;
-- @teacher [END 03-SQL006]

-- @teacher [START 03-SQL007] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: ล้างทุกแถวใน insurance.claim_perf เพื่อ Reset Dataset ของ Lab และเริ่ม Identity ใหม่
-- @teacher ผล/ชวนสังเกต: TRUNCATE ไม่ใช่ DELETE มี WHERE; ตรวจ Scope ก่อนรันและทำก่อนเก็บ Baseline ของรอบใหม่
-- @teacher SOURCE: 03-performance-tuning.sql:57 | รัน SQL นี้ครบทั้ง Statement
TRUNCATE insurance.claim_perf RESTART IDENTITY;
-- @teacher [END 03-SQL007]
-- @teacher [START 03-SQL008] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง Claims 2000000 แถว พร้อม JSONB, วันที่และคำอธิบายที่ควบคุมได้
-- @teacher ผล/ชวนสังเกต: เตรียมเวลา/พื้นที่ก่อนเริ่ม; ถ้าปรับ Row Count ต้องระบุในผลทดลองทุกครั้ง และใช้โหลดเดียวกันก่อน–หลัง
-- @teacher SOURCE: 03-performance-tuning.sql:58 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO insurance.claim_perf
    (tenant_id, policy_id, policy_no, claim_no, branch_code, status,
     incident_at, estimated_amount, description, metadata)
SELECT 1 + (g % 20),
       1 + (g % 1200),
       'POL-PERF-' || lpad((1 + (g % 1200))::text, 5, '0'),
       'PERF-' || lpad(g::text, 8, '0'),
       (ARRAY['BKK','CNX','HKT','KKN'])[1 + (g % 4)],
       (ARRAY['NEW','UNDER_REVIEW','APPROVED','REJECTED','PAID','CLOSED'])[1 + (g % 6)],
       TIMESTAMPTZ '2025-01-01 00:00+07' + (g % 525600) * interval '1 minute',
       1000 + (g % 150000),
       CASE WHEN g % 20 = 0 THEN 'urgent vehicle accident' ELSE 'standard claim intake' END,
       jsonb_build_object(
           'channel', (ARRAY['web','mobile','agent'])[1 + (g % 3)],
           'risk_score', g % 100,
           'vehicle', jsonb_build_object('province', (ARRAY['Bangkok','Chiang Mai','Phuket'])[1 + (g % 3)])
       )
FROM generate_series(1, 2000000) AS g;
-- @teacher [END 03-SQL008]

-- @teacher [START 03-SQL009] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: เก็บ Planner Statistics ของ insurance.policy_perf หลังเตรียมหรือเปลี่ยนข้อมูล
-- @teacher ผล/ชวนสังเกต: ช่วยให้ Estimated Rows/Plan มีฐานข้อมูลล่าสุด; ไม่สร้าง Index และไม่ใช่ VACUUM เก็บ Dead Tuples
-- @teacher SOURCE: 03-performance-tuning.sql:77 | รัน SQL นี้ครบทั้ง Statement
ANALYZE insurance.policy_perf;
-- @teacher [END 03-SQL009]
-- @teacher [START 03-SQL010] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: เก็บ Planner Statistics ของ insurance.claim_perf หลังเตรียมหรือเปลี่ยนข้อมูล
-- @teacher ผล/ชวนสังเกต: ช่วยให้ Estimated Rows/Plan มีฐานข้อมูลล่าสุด; ไม่สร้าง Index และไม่ใช่ VACUUM เก็บ Dead Tuples
-- @teacher SOURCE: 03-performance-tuning.sql:78 | รัน SQL นี้ครบทั้ง Statement
ANALYZE insurance.claim_perf;
-- @teacher [END 03-SQL010]

\echo '\n-- Lab 3A: baseline plan for the slow claim search'
-- @teacher [START 03-SQL011] Lab 3A | baseline plan for the slow claim search
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: ลบเฉพาะ Index ทดลองเพื่อให้มี Baseline ก่อนปรับ Query Access Path
-- @teacher ผล/ชวนสังเกต: ไม่ลบ Table Data; อย่าลบ Index ของระบบจริงตามขั้น Benchmark นี้
-- @teacher SOURCE: 03-performance-tuning.sql:81 | รัน SQL นี้ครบทั้ง Statement
DROP INDEX IF EXISTS insurance.idx_claim_perf_open_tenant_incident;
-- @teacher [END 03-SQL011]

-- @teacher [START 03-SQL012] Lab 3A | baseline plan for the slow claim search
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: รัน Query จริงพร้อม EXPLAIN ANALYZE เพื่อวัด Baseline ของ Tenant/Status/ORDER BY/LIMIT
-- @teacher ผล/ชวนสังเกต: บันทึก Plan, Actual Rows, Buffers และเวลา; คำว่า ANALYZE ใน EXPLAIN ทำให้ Query ถูก Execute จริง
-- @teacher SOURCE: 03-performance-tuning.sql:83 | รัน SQL นี้ครบทั้ง Statement
EXPLAIN (ANALYZE, BUFFERS, WAL, SETTINGS)
SELECT claim_id, claim_no, incident_at, estimated_amount
FROM insurance.claim_perf
WHERE tenant_id = 1
  AND status = 'NEW'
ORDER BY incident_at DESC
LIMIT 50;
-- @teacher [END 03-SQL012]

-- @teacher [START 03-SQL013] Lab 3A | baseline plan for the slow claim search
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง Partial B-tree ที่เก็บเฉพาะ NEW และเรียง Tenant/Incident พร้อม Included Columns
-- @teacher ผล/ชวนสังเกต: Predicate ต้องสัมพันธ์กับ WHERE; claim_id ไม่อยู่ใน INCLUDE จึงอย่ารับประกัน Index-only Scan
-- @teacher SOURCE: 03-performance-tuning.sql:91 | รัน SQL นี้ครบทั้ง Statement
CREATE INDEX IF NOT EXISTS idx_claim_perf_open_tenant_incident
ON insurance.claim_perf (tenant_id, incident_at DESC)
INCLUDE (claim_no, estimated_amount)
WHERE status = 'NEW';
-- @teacher [END 03-SQL013]
-- @teacher [START 03-SQL014] Lab 3A | baseline plan for the slow claim search
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: เก็บ Planner Statistics ของ insurance.claim_perf หลังเตรียมหรือเปลี่ยนข้อมูล
-- @teacher ผล/ชวนสังเกต: ช่วยให้ Estimated Rows/Plan มีฐานข้อมูลล่าสุด; ไม่สร้าง Index และไม่ใช่ VACUUM เก็บ Dead Tuples
-- @teacher SOURCE: 03-performance-tuning.sql:95 | รัน SQL นี้ครบทั้ง Statement
ANALYZE insurance.claim_perf;
-- @teacher [END 03-SQL014]

\echo '\n-- Compare: planner should prefer the partial covering index'
-- @teacher [START 03-SQL015] Lab 3A | baseline plan for the slow claim search
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: วัด Query เดิมหลังสร้าง Index ภายใต้ข้อมูลและ Environment เดิม
-- @teacher ผล/ชวนสังเกต: เปรียบเทียบงานที่ทำ/Sort/Buffers ไม่ใช่ดูเวลาเพียงครั้งเดียว; Planner มีสิทธิ์เลือก Plan อื่น
-- @teacher SOURCE: 03-performance-tuning.sql:98 | รัน SQL นี้ครบทั้ง Statement
EXPLAIN (ANALYZE, BUFFERS, WAL, SETTINGS)
SELECT claim_id, claim_no, incident_at, estimated_amount
FROM insurance.claim_perf
WHERE tenant_id = 1
  AND status = 'NEW'
ORDER BY incident_at DESC
LIMIT 50;
-- @teacher [END 03-SQL015]

\echo '\n-- Lab 3B: match index type to access pattern'
-- @teacher [START 03-SQL016] Lab 3B | match index type to access pattern
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง Expression Index ให้ตรงกับ WHERE lower(claim_no)
-- @teacher ผล/ชวนสังเกต: Index บน claim_no ธรรมดาไม่เท่ากับ Index ของ lower(claim_no)
-- @teacher SOURCE: 03-performance-tuning.sql:107 | รัน SQL นี้ครบทั้ง Statement
CREATE INDEX IF NOT EXISTS idx_claim_perf_lower_claim_no
    ON insurance.claim_perf (lower(claim_no));
-- @teacher [END 03-SQL016]
-- @teacher [START 03-SQL017] Lab 3B | match index type to access pattern
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง GIN แบบ jsonb_path_ops สำหรับ Containment Query
-- @teacher ผล/ชวนสังเกต: เหมาะกับ @>; ไม่ได้รองรับ Operators ทุกแบบของ jsonb_ops
-- @teacher SOURCE: 03-performance-tuning.sql:109 | รัน SQL นี้ครบทั้ง Statement
CREATE INDEX IF NOT EXISTS idx_claim_perf_metadata_gin
    ON insurance.claim_perf USING gin (metadata jsonb_path_ops);
-- @teacher [END 03-SQL017]
-- @teacher [START 03-SQL018] Lab 3B | match index type to access pattern
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง BRIN สรุปช่วง Heap Pages สำหรับ Incident Time
-- @teacher ผล/ชวนสังเกต: pages_per_range=32 แลกความละเอียดกับขนาด; ประสิทธิภาพขึ้นกับความสัมพันธ์ของวันที่กับตำแหน่งเก็บจริง
-- @teacher SOURCE: 03-performance-tuning.sql:111 | รัน SQL นี้ครบทั้ง Statement
CREATE INDEX IF NOT EXISTS idx_claim_perf_incident_brin
    ON insurance.claim_perf USING brin (incident_at) WITH (pages_per_range = 32);
-- @teacher [END 03-SQL018]

-- @teacher [START 03-SQL019] Lab 3B | match index type to access pattern
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: ตรวจว่า Query ใช้ Expression lower(claim_no) แบบเดียวกับ Index
-- @teacher ผล/ชวนสังเกต: ควรคืน PERF-00001000; ดู Actual Plan แทนการสรุปจากชื่อ Index
-- @teacher SOURCE: 03-performance-tuning.sql:114 | รัน SQL นี้ครบทั้ง Statement
EXPLAIN (ANALYZE, BUFFERS)
SELECT claim_no FROM insurance.claim_perf
WHERE lower(claim_no) = lower('PERF-00001000');
-- @teacher [END 03-SQL019]

-- {"channel":"mobile"} alone matches about 1/3 of the table, so GIN still
-- Bitmap-Heap-Scans hundreds of thousands of rows. Pair a second key to
-- make containment selective enough that the index looks cheap.
-- @teacher [START 03-SQL020] Lab 3B | match index type to access pattern
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: ใช้ JSONB @> สองเงื่อนไขให้ Selective กว่าการกรอง Channel อย่างเดียว
-- @teacher ผล/ชวนสังเกต: GIN ยังต้องอ่าน Heap และอาจไม่คุ้มเมื่อคืนแถวมาก; ดู Rows และ Buffers ของ Bitmap Heap Scan
-- @teacher SOURCE: 03-performance-tuning.sql:121 | รัน SQL นี้ครบทั้ง Statement
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM insurance.claim_perf
WHERE metadata @> '{"channel":"mobile","risk_score": 7}'::jsonb;
-- @teacher [END 03-SQL020]

\echo '\n-- Lab 3C: index and autovacuum maintenance evidence'
-- @teacher [START 03-SQL021] Lab 3C | index and autovacuum maintenance evidence
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: อ่านจำนวนใช้และขนาด Index เพื่อประเมินประโยชน์เทียบต้นทุน
-- @teacher ผล/ชวนสังเกต: idx_scan เป็น Counter สะสมตั้งแต่ Reset; ค่า 0 ใน Lab สั้นไม่ได้พิสูจน์ว่าควร DROP
-- @teacher SOURCE: 03-performance-tuning.sql:126 | รัน SQL นี้ครบทั้ง Statement
SELECT indexrelname,
       idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'insurance'
ORDER BY pg_relation_size(indexrelid) DESC;
-- @teacher [END 03-SQL021]

-- Practice: size table autovacuum from live rows and a dead-tuple budget.
-- vacuum_trigger = threshold + scale_factor * n_live_tup
-- scale_factor   = (desired_dead - threshold) / n_live_tup
-- @teacher [START 03-SQL022] Lab 3C | index and autovacuum maintenance evidence
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: คำนวณ Vacuum Trigger และ Scale Factor จาก n_live_tup เพื่อคุยเรื่อง Dead-tuple Budget
-- @teacher ผล/ชวนสังเกต: n_live_tup เป็น Estimate; สูตรนี้ยังต้องพิจารณา PostgreSQL 18 maximum threshold และเงื่อนไขอื่น
-- @teacher SOURCE: 03-performance-tuning.sql:136 | รัน SQL นี้ครบทั้ง Statement
SELECT relname,
       n_live_tup,
       current_setting('autovacuum_vacuum_threshold')::numeric AS cluster_threshold,
       current_setting('autovacuum_vacuum_scale_factor')::numeric AS cluster_scale,
       (current_setting('autovacuum_vacuum_threshold')::numeric
          + current_setting('autovacuum_vacuum_scale_factor')::numeric
            * n_live_tup)::bigint AS cluster_trigger,
       1000 AS table_threshold,
       0.05::numeric AS table_scale,
       (1000 + 0.05 * n_live_tup)::bigint AS lab_table_trigger,
       round((100000 - 1000) / GREATEST(n_live_tup, 1)::numeric, 4)
           AS scale_for_100k_dead
FROM pg_stat_user_tables
WHERE schemaname = 'insurance'
  AND relname = 'claim_perf';
-- @teacher [END 03-SQL022]

-- one_pass_tids ≈ autovacuum_work_mem / 6 bytes (uses maintenance_work_mem when -1)
-- @teacher [START 03-SQL023] Lab 3C | index and autovacuum maintenance evidence
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: อ่าน Memory Settings แล้วคำนวณจำนวน TIDs ตามสูตรประมาณในต้นฉบับ
-- @teacher ผล/ชวนสังเกต: สูตร work_mem/6 เป็นภาพจำแบบเก่า ไม่ใช่ความจุจริงของ PostgreSQL 18 ซึ่งใช้ TidStore; ไม่ใช้เป็น Hard Capacity
-- @teacher SOURCE: 03-performance-tuning.sql:153 | รัน SQL นี้ครบทั้ง Statement
SELECT current_setting('shared_buffers') AS shared_buffers,
       current_setting('maintenance_work_mem') AS maintenance_work_mem,
       current_setting('autovacuum_work_mem') AS autovacuum_work_mem,
       current_setting('autovacuum_max_workers') AS autovacuum_max_workers,
       (pg_size_bytes(COALESCE(NULLIF(current_setting('autovacuum_work_mem'), '-1'),
                               current_setting('maintenance_work_mem'))) / 6)
           AS one_pass_dead_tids;
-- @teacher [END 03-SQL023]

-- @teacher [START 03-SQL024] Lab 3C | index and autovacuum maintenance evidence
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: ตั้ง Table-specific Autovacuum/Analyze Thresholds เฉพาะ claim_perf
-- @teacher ผล/ชวนสังเกต: Table Options คงอยู่หลัง Statement จบ; ไม่ต้อง Reload และไม่ใช่การแก้ Cluster Defaults
-- @teacher SOURCE: 03-performance-tuning.sql:161 | รัน SQL นี้ครบทั้ง Statement
ALTER TABLE insurance.claim_perf SET (
    autovacuum_vacuum_scale_factor = 0.05,
    autovacuum_analyze_scale_factor = 0.02,
    autovacuum_vacuum_threshold = 1000,
    autovacuum_analyze_threshold = 500
);
-- @teacher [END 03-SQL024]

-- @teacher [START 03-SQL025] Lab 3C | index and autovacuum maintenance evidence
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: ทำ VACUUM และ ANALYZE ด้วยมือเพื่อคืนพื้นที่ที่ปลอดภัยและอัปเดต Statistics
-- @teacher ผล/ชวนสังเกต: ต้องรันใน Autocommit นอก BEGIN; ไม่ใช่ VACUUM FULL และไม่รับประกันคืนพื้นที่ให้ OS
-- @teacher SOURCE: 03-performance-tuning.sql:168 | รัน SQL นี้ครบทั้ง Statement
VACUUM (ANALYZE) insurance.claim_perf;
-- @teacher [END 03-SQL025]

-- @teacher [START 03-SQL026] Lab 3C | index and autovacuum maintenance evidence
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: ตรวจ Estimates และเวลาที่ Autovacuum/Autoanalyze เคยทำงาน
-- @teacher ผล/ชวนสังเกต: Manual VACUUM ไม่ได้เปลี่ยน last_autovacuum; ใช้ร่วมกับ last_vacuum/vacuum_count หากต้องแยกงาน Manual
-- @teacher SOURCE: 03-performance-tuning.sql:170 | รัน SQL นี้ครบทั้ง Statement
SELECT relname, n_live_tup, n_dead_tup,
       last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'insurance';
-- @teacher [END 03-SQL026]

-- Use only after measuring bloat and during a suitable maintenance window:
-- REINDEX INDEX CONCURRENTLY insurance.idx_claim_perf_lower_claim_no;

\echo '\n-- Lab 3D: monthly range partition table'
-- @teacher [START 03-SQL027] Lab 3D | monthly range partition table
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง Partitioned Parent สำหรับรายงาน โดยรวม Partition Key ใน Primary Key
-- @teacher ผล/ชวนสังเกต: Parent กำหนด Routing; PRIMARY KEY(claim_id,incident_at) สอดคล้องข้อกำหนด Range Partitioning
-- @teacher SOURCE: 03-performance-tuning.sql:179 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS insurance.claim_report (
    claim_id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    status text NOT NULL,
    incident_at timestamptz NOT NULL,
    estimated_amount numeric(14,2) NOT NULL,
    PRIMARY KEY (claim_id, incident_at)
) PARTITION BY RANGE (incident_at);
-- @teacher [END 03-SQL027]

-- @teacher [START 03-SQL028] Lab 3D | monthly range partition table
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง Partition มกราคมแบบช่วง [FROM,TO)
-- @teacher ผล/ชวนสังเกต: รวม 1 ม.ค. แต่ไม่รวม 1 ก.พ.; เวลา +07 ต้องตรงกับข้อมูล
-- @teacher SOURCE: 03-performance-tuning.sql:188 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS insurance.claim_report_2025_01
PARTITION OF insurance.claim_report
FOR VALUES FROM ('2025-01-01 00:00+07') TO ('2025-02-01 00:00+07');
-- @teacher [END 03-SQL028]
-- @teacher [START 03-SQL029] Lab 3D | monthly range partition table
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง Partition กุมภาพันธ์ต่อเนื่องโดยไม่ทับช่วงก่อนหน้า
-- @teacher ผล/ชวนสังเกต: ช่วงบนไม่รวม 1 มี.ค.; ข้อมูลนอก Partitions จะ INSERT ไม่ได้หากไม่มี Default Partition
-- @teacher SOURCE: 03-performance-tuning.sql:191 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS insurance.claim_report_2025_02
PARTITION OF insurance.claim_report
FOR VALUES FROM ('2025-02-01 00:00+07') TO ('2025-03-01 00:00+07');
-- @teacher [END 03-SQL029]
-- @teacher [START 03-SQL030] Lab 3D | monthly range partition table
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง Partition มีนาคมให้ครอบคลุมข้อมูล Q1 ของ Fixture
-- @teacher ผล/ชวนสังเกต: ยังไม่มี Partition สำหรับเดือนอื่น; ต้องเตรียมก่อนส่งข้อมูลช่วงใหม่
-- @teacher SOURCE: 03-performance-tuning.sql:194 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS insurance.claim_report_2025_03
PARTITION OF insurance.claim_report
FOR VALUES FROM ('2025-03-01 00:00+07') TO ('2025-04-01 00:00+07');
-- @teacher [END 03-SQL030]

-- @teacher [START 03-SQL031] Lab 3D | monthly range partition table
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: ล้างทุกแถวใน insurance.claim_report เพื่อ Reset Dataset ของ Lab
-- @teacher ผล/ชวนสังเกต: TRUNCATE ไม่ใช่ DELETE มี WHERE; ตรวจ Scope ก่อนรันและทำก่อนเก็บ Baseline ของรอบใหม่
-- @teacher SOURCE: 03-performance-tuning.sql:198 | รัน SQL นี้ครบทั้ง Statement
TRUNCATE insurance.claim_report;
-- @teacher [END 03-SQL031]
-- @teacher [START 03-SQL032] Lab 3D | monthly range partition table
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: คัดเฉพาะ Claims ใน Q1 จาก Fixture ลง Parent เพื่อให้ PostgreSQL Route ไป Partition
-- @teacher ผล/ชวนสังเกต: ไม่ใช่สำเนา 2 ล้านแถวทั้งหมด; จำกัดช่วงก่อน INSERT ให้มี Partition รองรับ
-- @teacher SOURCE: 03-performance-tuning.sql:199 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO insurance.claim_report
SELECT claim_id, tenant_id, status, incident_at, estimated_amount
FROM insurance.claim_perf
WHERE incident_at >= TIMESTAMPTZ '2025-01-01 00:00+07'
  AND incident_at <  TIMESTAMPTZ '2025-04-01 00:00+07';
-- @teacher [END 03-SQL032]
-- @teacher [START 03-SQL033] Lab 3D | monthly range partition table
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: เก็บ Planner Statistics ของ insurance.claim_report หลังเตรียมหรือเปลี่ยนข้อมูล
-- @teacher ผล/ชวนสังเกต: ช่วยให้ Estimated Rows/Plan มีฐานข้อมูลล่าสุด; ไม่สร้าง Index และไม่ใช่ VACUUM เก็บ Dead Tuples
-- @teacher SOURCE: 03-performance-tuning.sql:204 | รัน SQL นี้ครบทั้ง Statement
ANALYZE insurance.claim_report;
-- @teacher [END 03-SQL033]

-- @teacher [START 03-SQL034] Lab 3D | monthly range partition table
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: วัด Query ที่ระบุช่วงกุมภาพันธ์เพื่อสังเกต Partition Pruning
-- @teacher ผล/ชวนสังเกต: ดูว่ามีเฉพาะ Partition ที่เกี่ยวข้องใน Plan; Partitioning ไม่ได้ทำให้ทุก Query เร็วขึ้น
-- @teacher SOURCE: 03-performance-tuning.sql:206 | รัน SQL นี้ครบทั้ง Statement
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(estimated_amount)
FROM insurance.claim_report
WHERE incident_at >= TIMESTAMPTZ '2025-02-01 00:00+07'
  AND incident_at <  TIMESTAMPTZ '2025-03-01 00:00+07';
-- @teacher [END 03-SQL034]

-- @teacher [START 03-SQL035] Lab 3D | monthly range partition table
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: ใช้ tableoid บอกว่าแต่ละแถวอยู่ใน Partition จริงใด
-- @teacher ผล/ชวนสังเกต: นับจาก Parent แล้ว GROUP BY Physical Relation เพื่อพิสูจน์ Routing
-- @teacher SOURCE: 03-performance-tuning.sql:212 | รัน SQL นี้ครบทั้ง Statement
SELECT tableoid::regclass AS partition_name, count(*) AS rows
FROM insurance.claim_report
GROUP BY tableoid
ORDER BY tableoid::regclass::text;
-- @teacher [END 03-SQL035]

\echo '\n-- Lab 3E: materialized report and denormalized snapshot'
-- @teacher [START 03-SQL036] Lab 3E | materialized report and denormalized snapshot
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง Materialized View สำหรับ Aggregate รายเดือนโดยยังไม่เติมข้อมูล
-- @teacher ผล/ชวนสังเกต: WITH NO DATA ทำให้ยัง SELECT ผลรายงานไม่ได้จน REFRESH ครั้งแรก
-- @teacher SOURCE: 03-performance-tuning.sql:218 | รัน SQL นี้ครบทั้ง Statement
CREATE MATERIALIZED VIEW IF NOT EXISTS insurance.monthly_claim_summary AS
SELECT date_trunc('month', incident_at)::date AS month_start,
       tenant_id,
       status,
       count(*) AS claim_count,
       sum(estimated_amount) AS total_estimated
FROM insurance.claim_perf
GROUP BY 1, 2, 3
WITH NO DATA;
-- @teacher [END 03-SQL036]

-- @teacher [START 03-SQL037] Lab 3E | materialized report and denormalized snapshot
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง Unique Index ของ Grain month/tenant/status ให้ Materialized View
-- @teacher ผล/ชวนสังเกต: ช่วยยืนยันความเป็นเอกลักษณ์ และเป็นหนึ่งในเงื่อนไขที่ต้องมีเมื่อต้องการ CONCURRENTLY ภายหลัง
-- @teacher SOURCE: 03-performance-tuning.sql:228 | รัน SQL นี้ครบทั้ง Statement
CREATE UNIQUE INDEX IF NOT EXISTS ux_monthly_claim_summary
ON insurance.monthly_claim_summary (month_start, tenant_id, status);
-- @teacher [END 03-SQL037]

-- @teacher [START 03-SQL038] Lab 3E | materialized report and denormalized snapshot
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: คำนวณและเก็บผล Materialized View ใหม่
-- @teacher ผล/ชวนสังเกต: REFRESH ธรรมดาอาจ Block ผู้อ่าน; Snapshot ของรายงานไม่ได้สดตามทุก INSERT อัตโนมัติ
-- @teacher SOURCE: 03-performance-tuning.sql:231 | รัน SQL นี้ครบทั้ง Statement
REFRESH MATERIALIZED VIEW insurance.monthly_claim_summary;
-- @teacher [END 03-SQL038]

-- @teacher [START 03-SQL039] Lab 3E | materialized report and denormalized snapshot
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: อ่านผลรายงานที่ Materialize แล้วโดยจำกัด 20 แถว
-- @teacher ผล/ชวนสังเกต: อธิบาย Grain และวันที่ Refresh; ไม่ควรเทียบ Count ผลรายงานกับ Count Claim โดยตรง
-- @teacher SOURCE: 03-performance-tuning.sql:233 | รัน SQL นี้ครบทั้ง Statement
SELECT *
FROM insurance.monthly_claim_summary
ORDER BY month_start DESC, tenant_id, status
LIMIT 20;
-- @teacher [END 03-SQL039]

-- @teacher [START 03-SQL040] Lab 3E | materialized report and denormalized snapshot
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: สร้าง Dashboard Snapshot หนึ่งแถวต่อ Tenant เพื่อรองรับการอ่านซ้ำ
-- @teacher ผล/ชวนสังเกต: เป็น Denormalized Data ต้องมีแผน Refresh และตรวจความสด
-- @teacher SOURCE: 03-performance-tuning.sql:238 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS insurance.claim_dashboard_snapshot (
    tenant_id bigint PRIMARY KEY,
    open_claims bigint NOT NULL,
    total_estimated numeric(18,2) NOT NULL,
    refreshed_at timestamptz NOT NULL
);
-- @teacher [END 03-SQL040]

-- @teacher [START 03-SQL041] Lab 3E | materialized report and denormalized snapshot
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: รวมยอดทุก Claim ต่อ Tenant แล้ว Upsert Snapshot พร้อมเวลาคำนวณ
-- @teacher ผล/ชวนสังเกต: open_claims นับเฉพาะ NEW/UNDER_REVIEW แต่ total_estimated รวมทุก Status ตาม SQL นี้
-- @teacher SOURCE: 03-performance-tuning.sql:245 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO insurance.claim_dashboard_snapshot
    (tenant_id, open_claims, total_estimated, refreshed_at)
SELECT tenant_id,
       count(*) FILTER (WHERE status IN ('NEW','UNDER_REVIEW')),
       coalesce(sum(estimated_amount), 0),
       clock_timestamp()
FROM insurance.claim_perf
GROUP BY tenant_id
ON CONFLICT (tenant_id) DO UPDATE
SET open_claims = EXCLUDED.open_claims,
    total_estimated = EXCLUDED.total_estimated,
    refreshed_at = EXCLUDED.refreshed_at;
-- @teacher [END 03-SQL041]

-- @teacher [START 03-SQL042] Lab 3E | materialized report and denormalized snapshot
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: ตรวจ Snapshot ที่สร้างจริงและเวลาคำนวณ
-- @teacher ผล/ชวนสังเกต: จำนวนแถวเท่ากับจำนวน Tenant ที่มีข้อมูล ไม่ใช่จำนวน Claims
-- @teacher SOURCE: 03-performance-tuning.sql:258 | รัน SQL นี้ครบทั้ง Statement
SELECT * FROM insurance.claim_dashboard_snapshot ORDER BY tenant_id;
-- @teacher [END 03-SQL042]

\echo '\nValidation'
-- @teacher [START 03-SQL043] Lab 3E | materialized report and denormalized snapshot
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows
-- @teacher อธิบาย: ตรวจ Checkpoint ของ Benchmark หลังทำงานครบ
-- @teacher ผล/ชวนสังเกต: ต้นฉบับคาด 2000000 Claims และ 1200 Policy IDs; หากลด Fixture ให้รายงานค่าที่เปลี่ยนจริง
-- @teacher SOURCE: 03-performance-tuning.sql:261 | รัน SQL นี้ครบทั้ง Statement
SELECT count(*) AS generated_rows,
       count(DISTINCT policy_id) AS generated_policies
FROM insurance.claim_perf;
-- @teacher [END 03-SQL043]
-- @teacher PSQL: แสดงเวลาใน Client; แยกจาก Execution Time ใน EXPLAIN
\timing off
