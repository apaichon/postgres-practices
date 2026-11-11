-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 01-basic-sql.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/01-basic-sql.sql
-- @teacher LOGIN / DATABASE เริ่มต้น: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อ่าน README.md ใน Directory นี้ก่อนสอน; ใช้ไฟล์นี้เป็นคู่มือเลือกรันทีละส่วน
-- @teacher แต่ละ SQL มี START/END, Lab, Login, เหตุผล และผลที่ต้องสังเกต; Source Line อ้างไฟล์ต้นฉบับ
-- @teacher START/END ราย SQL ใช้ค้นคำอธิบาย ไม่ใช่ขอบเขต Commit: Transaction/Function ต้องรันครบชุด
-- @teacher คำสั่ง psql ขึ้นต้นด้วย Backslash; SQL Editor ทั่วไปให้ข้ามและจัด Branch/Variables เอง
-- @teacher ทุกบรรทัดที่เพิ่มขึ้นต้น -- @teacher; SQL/psql ต้นฉบับคงเดิม รวมคำสั่งเปลี่ยนข้อมูลและ Expected Errors
-- @teacher เป้าหมาย: สร้าง Relational Model → Seed → CRUD/Transaction → JOIN/Set/Aggregation
-- @teacher เตรียม student_xx/claimsure_xx และสิทธิ์ CREATE Schema โดยผู้ดูแลก่อนเริ่ม; xx คือเลขนักเรียน
-- @teacher จุดตรวจเมื่อ Fixture ว่าง: 3 Customers, 3 Policies, 6 Claims; 1D Commit, 1E Rollback
-- @teacher ==============================================================================
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP on
-- @teacher PSQL: ตั้งรูปแบบแสดงผลของ psql ไม่เปลี่ยนข้อมูลใน Database
\pset pager off
\echo '=== Module 1: Basic SQL ==='
-- @teacher PSQL: ยืนยัน Host/Port/Database/User ของ Connection ปัจจุบันก่อนรัน Lab
\conninfo

-- @teacher [START 01-SQL001] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: ตรวจ Database, Login และ Endpoint ก่อนสอน เพื่อไม่ให้แก้ฐานผิดชุด
-- @teacher ผล/ชวนสังเกต: ชื่อฐาน/Role ต้องตรง Connection ที่ตั้งไว้; inet_server_port เป็น Port ฝั่ง PostgreSQL ไม่ใช่ Port ของ Proxy
-- @teacher SOURCE: 01-basic-sql.sql:6 | รัน SQL นี้ครบทั้ง Statement
SELECT current_database() AS database_name,
       current_user AS login_role,
       inet_server_addr() AS server_address,
       inet_server_port() AS server_port;
-- @teacher [END 01-SQL001]
-- @teacher [START 01-SQL002] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: อ่านเวอร์ชันจริงของ Server ที่ Connection นี้ใช้อยู่
-- @teacher ผล/ชวนสังเกต: อธิบายว่าเวอร์ชัน psql Client กับ Server อาจต่างกัน
-- @teacher SOURCE: 01-basic-sql.sql:10 | รัน SQL นี้ครบทั้ง Statement
SELECT version();
-- @teacher [END 01-SQL002]

-- Lab 1 — Build and Verify
-- เป้าหมาย: สร้าง schema/table, CRUD, transaction, JOIN และ aggregate
-- รันทีละส่วน: ./scripts/shells/run-lab01.sh --student xx --ask-pass A
-- Common course schema: insurance (reused by Module 2)

\echo '\n-- Lab 1A: create schema and related tables'

-- @teacher [START 01-SQL003] Lab 1A | create schema and related tables
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: สร้าง Namespace insurance เพื่อจัดกลุ่ม Objects ของ Lab 1–2
-- @teacher ผล/ชวนสังเกต: IF NOT EXISTS ช่วยให้รันซ้ำได้ แต่ไม่ได้ตรวจว่าโครงสร้างเดิมตรงกับ Lab
-- @teacher SOURCE: 01-basic-sql.sql:19 | รัน SQL นี้ครบทั้ง Statement
CREATE SCHEMA IF NOT EXISTS insurance;
-- @teacher [END 01-SQL003]

-- @teacher [START 01-SQL004] Lab 1A | create schema and related tables
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: แปลงชื่อ Schema เป็น OID/ชื่อที่ระบบรู้จักโดยไม่ Error เมื่อไม่พบ
-- @teacher ผล/ชวนสังเกต: ต้องได้ insurance; NULL หมายถึงยังไม่มี Schema
-- @teacher SOURCE: 01-basic-sql.sql:21 | รัน SQL นี้ครบทั้ง Statement
SELECT to_regnamespace('insurance') AS schema_name;
-- @teacher [END 01-SQL004]

-- @teacher [START 01-SQL005] Lab 1A | create schema and related tables
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: สร้าง Customer พร้อม Identity PK และ Business Key customer_code ที่ UNIQUE
-- @teacher ผล/ชวนสังเกต: อธิบาย PK ต่างจาก Customer Code; NOT NULL/UNIQUE ทำให้ Database บังคับกฎข้อมูล
-- @teacher SOURCE: 01-basic-sql.sql:23 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS insurance.customer (
    customer_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_code text NOT NULL UNIQUE,
    full_name text NOT NULL,
    email text UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);
-- @teacher [END 01-SQL005]

-- @teacher [START 01-SQL006] Lab 1A | create schema and related tables
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: สร้าง Policy ที่อ้าง Customer ด้วย Foreign Key และตรวจช่วงวันที่/Status
-- @teacher ผล/ชวนสังเกต: ต้องมี Customer ก่อน INSERT Policy; ends_on ต้องไม่น้อยกว่า starts_on
-- @teacher SOURCE: 01-basic-sql.sql:31 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS insurance.policy (
    policy_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    policy_no text NOT NULL UNIQUE,
    customer_id bigint NOT NULL REFERENCES insurance.customer,
    product_code text NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    status text NOT NULL CHECK (status IN ('ACTIVE', 'EXPIRED', 'CANCELLED')),
    CHECK (ends_on >= starts_on)
);
-- @teacher [END 01-SQL006]

-- @teacher [START 01-SQL007] Lab 1A | create schema and related tables
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: สร้าง Claim ที่อ้าง Policy และจำกัด Status/Amount
-- @teacher ผล/ชวนสังเกต: approved_amount เป็น NULL ได้จนอนุมัติ; CHECK จำนวนเงินไม่ได้แปลว่าทุกแถวต้องมีค่าอนุมัติ
-- @teacher SOURCE: 01-basic-sql.sql:42 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS insurance.claim (
    claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    claim_no text NOT NULL UNIQUE,
    policy_id bigint NOT NULL REFERENCES insurance.policy,
    status text NOT NULL CHECK (status IN ('NEW', 'REVIEW', 'APPROVED', 'REJECTED', 'PAID')),
    incident_at timestamptz NOT NULL,
    estimated_amount numeric(14,2) NOT NULL CHECK (estimated_amount >= 0),
    approved_amount numeric(14,2) CHECK (approved_amount >= 0),
    created_at timestamptz NOT NULL DEFAULT now()
);
-- @teacher [END 01-SQL007]

\echo '\n-- Lab 1B: insert repeatable seed data'

-- @teacher [START 01-SQL008] Lab 1B | insert repeatable seed data
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: Upsert ลูกค้า 3 รายด้วย customer_code เพื่อให้ Seed ซ้ำโดยไม่เพิ่มรายการซ้ำ
-- @teacher ผล/ชวนสังเกต: RETURNING แสดง IDs ที่ใช้จริง; ไม่สมมติว่า Identity IDs เริ่มที่ 1 เสมอ
-- @teacher SOURCE: 01-basic-sql.sql:55 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO insurance.customer (customer_code, full_name, email)
VALUES
    ('CUS-001', 'Anan Chai', 'anan@example.com'),
    ('CUS-002', 'Mali Dee', 'mali@example.com'),
    ('CUS-003', 'Nok No-Claim', 'nok@example.com')
ON CONFLICT (customer_code) DO UPDATE
SET full_name = EXCLUDED.full_name,
    email = EXCLUDED.email
RETURNING customer_id, customer_code, full_name;
-- @teacher [END 01-SQL008]

-- @teacher [START 01-SQL009] Lab 1B | insert repeatable seed data
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: ใช้ INSERT SELECT หา customer_id จาก customer_code ก่อนสร้าง 3 Policies
-- @teacher ผล/ชวนสังเกต: JOIN แก้ปัญหาเดา Foreign Key; ควร RETURNING 3 แถวเมื่อมี Seed Customers ครบ
-- @teacher SOURCE: 01-basic-sql.sql:65 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO insurance.policy
    (policy_no, customer_id, product_code, starts_on, ends_on, status)
SELECT v.policy_no, c.customer_id, v.product_code, v.starts_on, v.ends_on, v.status
FROM (VALUES
    ('POL-001', 'CUS-001', 'AUTO', DATE '2026-01-01', DATE '2026-12-31', 'ACTIVE'),
    ('POL-002', 'CUS-001', 'HOME', DATE '2026-01-01', DATE '2026-12-31', 'ACTIVE'),
    ('POL-003', 'CUS-002', 'TRAVEL', DATE '2026-02-01', DATE '2026-08-31', 'ACTIVE')
) AS v(policy_no, customer_code, product_code, starts_on, ends_on, status)
JOIN insurance.customer c USING (customer_code)
ON CONFLICT (policy_no) DO UPDATE
SET customer_id = EXCLUDED.customer_id,
    product_code = EXCLUDED.product_code,
    starts_on = EXCLUDED.starts_on,
    ends_on = EXCLUDED.ends_on,
    status = EXCLUDED.status
RETURNING policy_id, policy_no, product_code, status;
-- @teacher [END 01-SQL009]

-- @teacher [START 01-SQL010] Lab 1B | insert repeatable seed data
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: หา policy_id ด้วย policy_no แล้ว Upsert Claims จำลอง 6 รายการ
-- @teacher ผล/ชวนสังเกต: NULL::numeric ทำให้ชนิดข้อมูลใน VALUES ชัดเจน; รัน Seed ซ้ำจะคืนค่า Status ของ Claims ชุดนี้
-- @teacher SOURCE: 01-basic-sql.sql:82 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO insurance.claim
    (claim_no, policy_id, status, incident_at, estimated_amount, approved_amount)
SELECT v.claim_no, p.policy_id, v.status, v.incident_at, v.estimated_amount, v.approved_amount
FROM (VALUES
    ('CLM-L1-001', 'POL-001', 'NEW',      TIMESTAMPTZ '2026-01-10 09:00+07', 15000.00, NULL::numeric),
    ('CLM-L1-002', 'POL-001', 'REVIEW',   TIMESTAMPTZ '2026-01-20 11:30+07', 22000.00, NULL::numeric),
    ('CLM-L1-003', 'POL-002', 'APPROVED', TIMESTAMPTZ '2026-02-05 14:10+07', 35000.00, 30000.00),
    ('CLM-L1-004', 'POL-002', 'PAID',     TIMESTAMPTZ '2026-02-12 08:45+07',  8000.00,  7500.00),
    ('CLM-L1-005', 'POL-003', 'NEW',      TIMESTAMPTZ '2026-03-02 13:00+07', 12000.00, NULL::numeric),
    ('CLM-L1-006', 'POL-003', 'REJECTED', TIMESTAMPTZ '2026-03-07 16:20+07', 18000.00,     0.00)
) AS v(claim_no, policy_no, status, incident_at, estimated_amount, approved_amount)
JOIN insurance.policy p USING (policy_no)
ON CONFLICT (claim_no) DO UPDATE
SET policy_id = EXCLUDED.policy_id,
    status = EXCLUDED.status,
    incident_at = EXCLUDED.incident_at,
    estimated_amount = EXCLUDED.estimated_amount,
    approved_amount = EXCLUDED.approved_amount
RETURNING claim_id, claim_no, status, estimated_amount;
-- @teacher [END 01-SQL010]

\echo '\n-- Lab 1C: select the sample claim rows'
-- @teacher [START 01-SQL011] Lab 1C | select the sample claim rows
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: อ่าน Claim โดยเลือกเฉพาะ Columns ที่ต้องใช้ และกำหนดลำดับด้วย ORDER BY
-- @teacher ผล/ชวนสังเกต: ควรเห็น Claim Number CLM-L1-001 ถึง 006 เมื่อเริ่มจาก Seed ชุดนี้
-- @teacher SOURCE: 01-basic-sql.sql:103 | รัน SQL นี้ครบทั้ง Statement
SELECT claim_no, status, estimated_amount
FROM insurance.claim
ORDER BY claim_no;
-- @teacher [END 01-SQL011]

\echo '\n-- Lab 1D: update one claim in a transaction'
-- @teacher [START 01-SQL012] Lab 1D | update one claim in a transaction
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 01-basic-sql.sql:108 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 01-SQL012]
-- @teacher [START 01-SQL013] Lab 1D | update one claim in a transaction
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: เปลี่ยนเฉพาะ Claim 001 ที่ยังเป็น NEW ไป REVIEW ภายใน Transaction
-- @teacher ผล/ชวนสังเกต: RETURNING ควรได้ 1 แถวครั้งแรก; 0 แถวเมื่อสถานะไม่ใช่ NEW ไม่ใช่ SQL Error
-- @teacher SOURCE: 01-basic-sql.sql:109 | รัน SQL นี้ครบทั้ง Statement
UPDATE insurance.claim
SET status = 'REVIEW'
WHERE claim_no = 'CLM-L1-001'
  AND status = 'NEW'
RETURNING claim_no, status;
-- @teacher [END 01-SQL013]

-- @teacher [START 01-SQL014] Lab 1D | update one claim in a transaction
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: สรุปจำนวน Claims ต่อ Status ก่อนตัดสินใจ COMMIT
-- @teacher ผล/ชวนสังเกต: หลัง UPDATE ครั้งแรก NEW เหลือ 1 และ REVIEW เป็น 2 สำหรับ Seed ชุดนี้
-- @teacher SOURCE: 01-basic-sql.sql:115 | รัน SQL นี้ครบทั้ง Statement
SELECT status, count(*) AS claims
FROM insurance.claim
GROUP BY status
ORDER BY status;
-- @teacher [END 01-SQL014]

-- @teacher [START 01-SQL015] Lab 1D | update one claim in a transaction
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: ยืนยันการเปลี่ยนแปลงทั้งหมดใน Transaction นี้ให้ Sessions อื่นเห็น
-- @teacher ผล/ชวนสังเกต: SET LOCAL รวมถึง SET LOCAL ROLE คืนค่าเมื่อจบ; ถ้า Transaction ถูก Abort ต้อง ROLLBACK แทนการคาดว่า Commit สำเร็จ
-- @teacher SOURCE: 01-basic-sql.sql:120 | รัน SQL นี้ครบทั้ง Statement
COMMIT;
-- @teacher [END 01-SQL015]

\echo '\n-- Lab 1E: delete one claim and roll back the transaction'
-- @teacher [START 01-SQL016] Lab 1E | delete one claim and roll back the transaction
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 01-basic-sql.sql:123 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 01-SQL016]
-- @teacher [START 01-SQL017] Lab 1E | delete one claim and roll back the transaction
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: ทดลอง DELETE เฉพาะ Claim 006 ที่ REJECTED แล้วแสดงแถวที่ลบ
-- @teacher ผล/ชวนสังเกต: แถวหายเฉพาะใน Transaction นี้; ROLLBACK ถัดไปจะคืนข้อมูล
-- @teacher SOURCE: 01-basic-sql.sql:124 | รัน SQL นี้ครบทั้ง Statement
DELETE FROM insurance.claim
WHERE claim_no = 'CLM-L1-006'
  AND status = 'REJECTED'
RETURNING claim_no, status;
-- @teacher [END 01-SQL017]
-- @teacher [START 01-SQL018] Lab 1E | delete one claim and roll back the transaction
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 01-basic-sql.sql:128 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK; -- preserve all six seed claims
-- @teacher [END 01-SQL018]

\echo '\n-- Lab 1F: join related data and compare set operations'
-- @teacher [START 01-SQL019] Lab 1F | join related data and compare set operations
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: JOIN Customer → Policy แล้ว LEFT JOIN Claim เพื่อรักษา Policy ที่ไม่มี Claim
-- @teacher ผล/ชวนสังเกต: Nok ไม่มี Policy จึงไม่อยู่ในผลนี้ เพราะ Join แรกเป็น INNER JOIN
-- @teacher SOURCE: 01-basic-sql.sql:131 | รัน SQL นี้ครบทั้ง Statement
SELECT c.full_name, p.policy_no, cl.claim_no, cl.status
FROM insurance.customer c
JOIN insurance.policy p USING (customer_id)
LEFT JOIN insurance.claim cl USING (policy_id)
ORDER BY c.full_name, p.policy_no, cl.claim_no;
-- @teacher [END 01-SQL019]

\echo '\n-- Customers with no claims: LEFT JOIN plus HAVING'
-- @teacher [START 01-SQL020] Lab 1F | join related data and compare set operations
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: เริ่มจาก Customers และ LEFT JOIN ตลอดทางเพื่อหาคนที่ยังไม่มี Claim
-- @teacher ผล/ชวนสังเกต: HAVING count(cl.claim_id)=0 ให้ CUS-003; COUNT(*) จะนับแถว NULL ที่ LEFT JOIN รักษาไว้ด้วย
-- @teacher SOURCE: 01-basic-sql.sql:138 | รัน SQL นี้ครบทั้ง Statement
SELECT c.customer_code, c.full_name
FROM insurance.customer c
LEFT JOIN insurance.policy p USING (customer_id)
LEFT JOIN insurance.claim cl USING (policy_id)
GROUP BY c.customer_id, c.customer_code, c.full_name
HAVING count(cl.claim_id) = 0
ORDER BY c.customer_code;
-- @teacher [END 01-SQL020]

\echo '\n-- INTERSECT keeps rows present in both results'
-- @teacher [START 01-SQL021] Lab 1F | join related data and compare set operations
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: INTERSECT คืนค่าที่มีอยู่ในทั้งสอง Result Sets
-- @teacher ผล/ชวนสังเกต: ผลคือ REVIEW เพียงค่าเดียว
-- @teacher SOURCE: 01-basic-sql.sql:147 | รัน SQL นี้ครบทั้ง Statement
WITH a(status) AS (
    VALUES ('NEW'), ('REVIEW')
), b(status) AS (
    VALUES ('REVIEW'), ('APPROVED')
)
SELECT status FROM a
INTERSECT
SELECT status FROM b;
-- @teacher [END 01-SQL021]

\echo '\n-- UNION combines results and removes duplicates'
-- @teacher [START 01-SQL022] Lab 1F | join related data and compare set operations
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: UNION รวมสอง Result Sets และตัดค่าซ้ำ
-- @teacher ผล/ชวนสังเกต: ได้ APPROVED, NEW, REVIEW ตาม ORDER BY; เปรียบเทียบกับ UNION ALL ที่ไม่ตัดซ้ำ
-- @teacher SOURCE: 01-basic-sql.sql:157 | รัน SQL นี้ครบทั้ง Statement
WITH a(status) AS (
    VALUES ('NEW'), ('REVIEW')
), b(status) AS (
    VALUES ('REVIEW'), ('APPROVED')
)
SELECT status FROM a
UNION
SELECT status FROM b
ORDER BY status;
-- @teacher [END 01-SQL022]

\echo '\n-- Lab 1G: aggregate results and verify row counts'
-- @teacher [START 01-SQL023] Lab 1G | aggregate results and verify row counts
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: GROUP BY Status แล้วคำนวณ COUNT, SUM และ AVG ของยอดประเมิน
-- @teacher ผล/ชวนสังเกต: ชี้ความต่างระหว่างจำนวนแถวกับยอดเงิน; ผลอิงข้อมูลที่ Commit อยู่ในขณะนั้น
-- @teacher SOURCE: 01-basic-sql.sql:168 | รัน SQL นี้ครบทั้ง Statement
SELECT status,
       count(*) AS claim_count,
       sum(estimated_amount) AS estimated_total,
       avg(estimated_amount) AS estimated_average
FROM insurance.claim
GROUP BY status
ORDER BY status;
-- @teacher [END 01-SQL023]

-- @teacher [START 01-SQL024] Lab 1G | aggregate results and verify row counts
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: รวมยอดระดับ Customer แล้วใช้ HAVING กรองกลุ่มที่มีอย่างน้อย 2 Claims
-- @teacher ผล/ชวนสังเกต: CUS-001 มี 4 Claims ยอด 80000; CUS-002 มี 2 Claims ยอด 30000 ใน Seed ชุดนี้
-- @teacher SOURCE: 01-basic-sql.sql:176 | รัน SQL นี้ครบทั้ง Statement
SELECT c.customer_code,
       c.full_name,
       count(cl.claim_id) AS total_claims,
       sum(cl.estimated_amount) AS total_estimated
FROM insurance.customer c
JOIN insurance.policy p USING (customer_id)
JOIN insurance.claim cl USING (policy_id)
GROUP BY c.customer_id, c.customer_code, c.full_name
HAVING count(cl.claim_id) >= 2
ORDER BY total_estimated DESC;
-- @teacher [END 01-SQL024]

\echo '\n-- Expected checkpoints: 3 customers, 3 policies, 6 claims'
-- @teacher [START 01-SQL025] Lab 1G | aggregate results and verify row counts
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx (ฐานฝึกของตน)
-- @teacher อธิบาย: ใช้ Scalar Subqueries รวม Counts ของสาม Table มาเป็น Checkpoint แถวเดียว
-- @teacher ผล/ชวนสังเกต: หากเริ่มในฐานสะอาดควรได้ 3/3/6; ข้อมูลเดิมนอก Seed อาจทำให้ Counts มากกว่า
-- @teacher SOURCE: 01-basic-sql.sql:188 | รัน SQL นี้ครบทั้ง Statement
SELECT
    (SELECT count(*) FROM insurance.customer) AS customers,
    (SELECT count(*) FROM insurance.policy) AS policies,
    (SELECT count(*) FROM insurance.claim) AS claims;
-- @teacher [END 01-SQL025]
