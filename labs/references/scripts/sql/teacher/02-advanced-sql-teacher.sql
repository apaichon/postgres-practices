-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 02-advanced-sql.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/02-advanced-sql.sql
-- @teacher LOGIN / DATABASE เริ่มต้น: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อ่าน README.md ใน Directory นี้ก่อนสอน; ใช้ไฟล์นี้เป็นคู่มือเลือกรันทีละส่วน
-- @teacher แต่ละ SQL มี START/END, Lab, Login, เหตุผล และผลที่ต้องสังเกต; Source Line อ้างไฟล์ต้นฉบับ
-- @teacher START/END ราย SQL ใช้ค้นคำอธิบาย ไม่ใช่ขอบเขต Commit: Transaction/Function ต้องรันครบชุด
-- @teacher คำสั่ง psql ขึ้นต้นด้วย Backslash; SQL Editor ทั่วไปให้ข้ามและจัด Branch/Variables เอง
-- @teacher ทุกบรรทัดที่เพิ่มขึ้นต้น -- @teacher; SQL/psql ต้นฉบับคงเดิม รวมคำสั่งเปลี่ยนข้อมูลและ Expected Errors
-- @teacher เป้าหมาย: View/Function/Procedure → CTE/Window/Pivot → ตรวจ Catalog
-- @teacher Prerequisite: ทำ 01-basic-sql.sql ส่วน 1A/1B ใน Database เดียวกันแล้ว
-- @teacher Procedure ทดสอบใน Transaction แล้ว ROLLBACK; ผลรวมขึ้นกับว่าได้ทำ 1D แล้วหรือยัง
-- @teacher ==============================================================================
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP on
-- @teacher PSQL: ตั้งรูปแบบแสดงผลของ psql ไม่เปลี่ยนข้อมูลใน Database
\pset pager off
\echo '=== Module 2: Advanced SQL ==='

-- Lab 2 — Reusable SQL Objects and Reports
-- Prerequisite: complete Module 1A and 1B before running this file.
-- Common course schema: insurance (tables and reusable routines)
-- Run all: ./scripts/shells/run-lab02.sh --student xx --ask-pass all
-- Run one: ./scripts/shells/run-lab02.sh --student xx --ask-pass A
--
-- Lab 2A  View contract for claim details
-- Lab 2B  SQL function for a shorter claim-tax calculation
-- Lab 2C  PL/pgSQL row-set function filtered by status
-- Lab 2D  Procedure for controlled claim review
-- Lab 2E  CTE pipeline for ranked customer tax totals
-- Lab 2F  Window functions for sequence and running total
-- Lab 2G  Conditional-aggregation pivot by customer and status
-- Lab 2H  Catalog validation for functions and procedures

-- Module 2 builds on Module 1. Stop with a useful message if prerequisite is missing.
-- @teacher [START 02-SQL001] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: ตรวจ Prerequisite ก่อนสร้าง Objects ที่พึ่ง insurance.claim
-- @teacher ผล/ชวนสังเกต: DO block หยุดด้วยข้อความชัดเจนเมื่อยังไม่ทำ Module 1; ไม่ได้ตรวจทุก Column ของ Schema เดิม
-- @teacher SOURCE: 02-advanced-sql.sql:21 | รัน SQL นี้ครบทั้ง Statement
DO $block$
BEGIN
    IF to_regclass('insurance.claim') IS NULL THEN
        RAISE EXCEPTION 'Run 01-basic-sql.sql before Module 2';
    END IF;
END
$block$;
-- @teacher [END 02-SQL001]

-- @teacher [START 02-SQL002] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: ยืนยันว่ามี Schema ปลายทางสำหรับ Objects ที่ใช้ซ้ำ
-- @teacher ผล/ชวนสังเกต: ไม่ใช่การสร้าง Claim Data ใหม่; ใช้ข้อมูลจาก Module 1
-- @teacher SOURCE: 02-advanced-sql.sql:29 | รัน SQL นี้ครบทั้ง Statement
CREATE SCHEMA IF NOT EXISTS insurance;
-- @teacher [END 02-SQL002]

\echo '\n-- Lab 2A: View contract for claim details'
-- @teacher [START 02-SQL003] Lab 2A | View contract for claim details
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: สร้าง View เป็น Query Contract รวม Claim, Policy และ Customer
-- @teacher ผล/ชวนสังเกต: View ปกติไม่เก็บสำเนาผลลัพธ์; JOIN และชื่อ Columns ถูกกำหนดไว้ให้ผู้ใช้เรียกซ้ำ
-- @teacher SOURCE: 02-advanced-sql.sql:32 | รัน SQL นี้ครบทั้ง Statement
CREATE OR REPLACE VIEW insurance.claim_detail_v AS
SELECT cl.claim_id,
       cl.claim_no,
       cl.status,
       cl.incident_at,
       cl.estimated_amount,
       cl.approved_amount,
       p.policy_no,
       p.product_code,
       c.customer_code,
       c.full_name
FROM insurance.claim cl
JOIN insurance.policy p USING (policy_id)
JOIN insurance.customer c USING (customer_id);
-- @teacher [END 02-SQL003]

-- @teacher [START 02-SQL004] Lab 2A | View contract for claim details
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: อ่านข้อมูลผ่าน View เพื่อยืนยัน Contract และการเชื่อม Foreign Keys
-- @teacher ผล/ชวนสังเกต: ควรมี 6 Claims จาก Seed; เปรียบเทียบ SQL สั้นลงกับ JOIN ใน Module 1
-- @teacher SOURCE: 02-advanced-sql.sql:47 | รัน SQL นี้ครบทั้ง Statement
SELECT claim_no, customer_code, policy_no, status
FROM insurance.claim_detail_v
ORDER BY claim_no;
-- @teacher [END 02-SQL004]

\echo '\n-- Lab 2B: SQL function for a shorter claim-tax calculation'
-- @teacher [START 02-SQL005] Lab 2B | SQL function for a shorter claim-tax calculation
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: รวมกฎ Tax เป็น SQL Function: ใช้ Approved ก่อน Estimated, จัดการ NULL/ค่าติดลบ และปัด 2 ตำแหน่ง
-- @teacher ผล/ชวนสังเกต: IMMUTABLE เหมาะเพราะขึ้นกับ Arguments เท่านั้น; DEFAULT Tax Rate คือ 0.07 ไม่ใช่กฎภาษีที่ยืนยันสำหรับ Production
-- @teacher SOURCE: 02-advanced-sql.sql:52 | รัน SQL นี้ครบทั้ง Statement
CREATE OR REPLACE FUNCTION insurance.claim_tax(
    p_estimated numeric,
    p_approved numeric,
    p_tax_rate numeric DEFAULT 0.07
) RETURNS numeric
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
RETURN round(
    greatest(coalesce(p_approved, p_estimated, 0), 0) * p_tax_rate,
    2
);
-- @teacher [END 02-SQL005]

\echo '\nManual calculation: repeat the full tax expression'
-- @teacher [START 02-SQL006] Lab 2B | SQL function for a shorter claim-tax calculation
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: คำนวณ Tax ด้วย Expression เต็มทุกแถวเป็น Baseline
-- @teacher ผล/ชวนสังเกต: COALESCE เลือกค่าที่มีอยู่; GREATEST ป้องกันฐานคำนวณติดลบ; ผลนี้ใช้เทียบ Function
-- @teacher SOURCE: 02-advanced-sql.sql:66 | รัน SQL นี้ครบทั้ง Statement
SELECT claim_no,
       round(
           greatest(coalesce(approved_amount, estimated_amount, 0), 0) * 0.07,
           2
       ) AS tax_manual
FROM insurance.claim
ORDER BY claim_no;
-- @teacher [END 02-SQL006]

\echo '\nFunction call: use the shorter reusable rule'
-- @teacher [START 02-SQL007] Lab 2B | SQL function for a shorter claim-tax calculation
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: เรียก Function แทน Expression ซ้ำ เพื่อให้กฎเดียวอยู่ที่เดียว
-- @teacher ผล/ชวนสังเกต: Tax ต้องตรงกับ Baseline ทุก Claim; การใช้ Function ไม่รับประกันว่า Query เร็วขึ้น
-- @teacher SOURCE: 02-advanced-sql.sql:75 | รัน SQL นี้ครบทั้ง Statement
SELECT claim_no,
       insurance.claim_tax(estimated_amount, approved_amount) AS tax_function
FROM insurance.claim
ORDER BY claim_no;
-- @teacher [END 02-SQL007]

\echo '\n-- Lab 2C: PL/pgSQL row-set function filtered by status'
-- @teacher [START 02-SQL008] Lab 2C | PL/pgSQL row-set function filtered by status
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: สร้าง PL/pgSQL Table-returning Function เพื่อค้น Claims ตาม Status
-- @teacher ผล/ชวนสังเกต: UPPER ทำให้รับ review ได้; STABLE สื่อว่า Function อ่านข้อมูลตาม Snapshot ไม่ได้แก้แถว
-- @teacher SOURCE: 02-advanced-sql.sql:81 | รัน SQL นี้ครบทั้ง Statement
CREATE OR REPLACE FUNCTION insurance.claims_by_status(p_status text)
RETURNS TABLE (
    claim_no text,
    customer_name text,
    estimated_amount numeric
)
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT v.claim_no, v.full_name, v.estimated_amount
    FROM insurance.claim_detail_v v
    WHERE v.status = upper(p_status)
    ORDER BY v.incident_at DESC;
END
$function$;
-- @teacher [END 02-SQL008]

-- @teacher [START 02-SQL009] Lab 2C | PL/pgSQL row-set function filtered by status
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: เรียก Row-set Function ใน FROM เหมือนอ่าน Table
-- @teacher ผล/ชวนสังเกต: หากผ่าน Lab 1D ควรได้ REVIEW 2 รายการ; หากทำเพียง Seed จะได้ REVIEW เดิม 1 รายการ
-- @teacher SOURCE: 02-advanced-sql.sql:99 | รัน SQL นี้ครบทั้ง Statement
SELECT * FROM insurance.claims_by_status('review');
-- @teacher [END 02-SQL009]

\echo '\n-- Lab 2D: Procedure for controlled claim review'
-- @teacher [START 02-SQL010] Lab 2D | Procedure for controlled claim review
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: สร้าง Procedure สำหรับอนุมัติ Claim พร้อมตรวจ Amount และกรณีหา Claim ไม่พบ
-- @teacher ผล/ชวนสังเกต: SECURITY INVOKER ใช้สิทธิ์ผู้เรียก; IF NOT FOUND ตรวจผล UPDATE; Procedure นี้ไม่ได้ COMMIT ภายใน
-- @teacher SOURCE: 02-advanced-sql.sql:102 | รัน SQL นี้ครบทั้ง Statement
CREATE OR REPLACE PROCEDURE insurance.review_claim(
    p_claim_no text,
    p_approved_amount numeric
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $procedure$
BEGIN
    IF p_approved_amount < 0 THEN
        RAISE EXCEPTION 'approved amount must not be negative';
    END IF;

    UPDATE insurance.claim
    SET status = 'APPROVED',
        approved_amount = p_approved_amount
    WHERE claim_no = p_claim_no;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'claim % not found', p_claim_no;
    END IF;
END
$procedure$;
-- @teacher [END 02-SQL010]

-- @teacher [START 02-SQL011] Lab 2D | Procedure for controlled claim review
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: เริ่ม Transaction สำหรับชุดคำสั่งถัดไป; อ่านจนถึง COMMIT/ROLLBACK ของชุดเดียวกัน
-- @teacher ผล/ชวนสังเกต: ใช้ Connection เดิมทั้งชุด; ถ้า Statement Error ต้อง Recovery ก่อนรันงานอื่น ไม่เลือก BEGIN เดี่ยวแล้วทิ้งค้าง
-- @teacher SOURCE: 02-advanced-sql.sql:125 | รัน SQL นี้ครบทั้ง Statement
BEGIN;
-- @teacher [END 02-SQL011]
-- @teacher [START 02-SQL012] Lab 2D | Procedure for controlled claim review
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: CALL Procedure เพื่อเปลี่ยน Claim 001 และตั้ง Approved Amount 14000
-- @teacher ผล/ชวนสังเกต: แสดงความต่าง CALL Procedure กับ SELECT Function; การเปลี่ยนแปลงยังอยู่ใน Transaction ทดสอบ
-- @teacher SOURCE: 02-advanced-sql.sql:126 | รัน SQL นี้ครบทั้ง Statement
CALL insurance.review_claim('CLM-L1-001', 14000.00);
-- @teacher [END 02-SQL012]
-- @teacher [START 02-SQL013] Lab 2D | Procedure for controlled claim review
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: ตรวจค่าหลัง CALL ก่อนยกเลิกการทดลอง
-- @teacher ผล/ชวนสังเกต: ควรเป็น APPROVED และ 14000.00 ภายใน Transaction นี้
-- @teacher SOURCE: 02-advanced-sql.sql:127 | รัน SQL นี้ครบทั้ง Statement
SELECT claim_no, status, approved_amount
FROM insurance.claim
WHERE claim_no = 'CLM-L1-001';
-- @teacher [END 02-SQL013]
-- @teacher [START 02-SQL014] Lab 2D | Procedure for controlled claim review
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: ยกเลิก Transaction ทดลอง หรือออกจาก Aborted Transaction หลัง Expected Error
-- @teacher ผล/ชวนสังเกต: ข้อมูลที่ยังไม่ Commit ถูกยกเลิกและ Local Settings คืนค่า; Identity Sequence/WAL ที่เกิดแล้วไม่ย้อนกลับ
-- @teacher SOURCE: 02-advanced-sql.sql:130 | รัน SQL นี้ครบทั้ง Statement
ROLLBACK; -- keep Module 1 data repeatable
-- @teacher [END 02-SQL014]

\echo '\n-- Lab 2E: CTE pipeline for ranked customer tax totals'
-- @teacher [START 02-SQL015] Lab 2E | CTE pipeline for ranked customer tax totals
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: ใช้ CTE แยกขั้นรวม Tax ต่อ Customer แล้วจัดอันดับด้วย DENSE_RANK
-- @teacher ผล/ชวนสังเกต: อันดับที่มี Tax เท่ากันจะได้ Rank เดียวและไม่มีช่องว่าง; CTE ไม่ได้หมายความว่าจะ Materialize เสมอ
-- @teacher SOURCE: 02-advanced-sql.sql:133 | รัน SQL นี้ครบทั้ง Statement
WITH claim_totals AS (
    SELECT customer_code,
           full_name,
           count(*) AS claim_count,
           sum(insurance.claim_tax(estimated_amount, approved_amount)) AS tax_total
    FROM insurance.claim_detail_v
    GROUP BY customer_code, full_name
), ranked AS (
    SELECT *, dense_rank() OVER (ORDER BY tax_total DESC) AS tax_rank
    FROM claim_totals
)
SELECT * FROM ranked ORDER BY tax_rank, customer_code;
-- @teacher [END 02-SQL015]

\echo '\n-- Lab 2F: Window functions for sequence and running total'
-- @teacher [START 02-SQL016] Lab 2F | Window functions for sequence and running total
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: ใช้ Window Functions เติมลำดับและยอดสะสมโดยไม่ยุบหลาย Claims ให้เหลือแถวเดียว
-- @teacher ผล/ชวนสังเกต: PARTITION BY Customer แยกกลุ่ม; ROWS กำหนด Frame; claim_no เป็น Tie-breaker ให้ลำดับแน่นอน
-- @teacher SOURCE: 02-advanced-sql.sql:147 | รัน SQL นี้ครบทั้ง Statement
SELECT customer_code,
       claim_no,
       incident_at::date,
       estimated_amount,
       row_number() OVER (
           PARTITION BY customer_code ORDER BY incident_at, claim_no
       ) AS claim_sequence,
       sum(estimated_amount) OVER (
           PARTITION BY customer_code
           ORDER BY incident_at, claim_no
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_estimated
FROM insurance.claim_detail_v
ORDER BY customer_code, claim_sequence;
-- @teacher [END 02-SQL016]

\echo '\n-- Lab 2G: Conditional-aggregation pivot by customer and status'
-- @teacher [START 02-SQL017] Lab 2G | Conditional-aggregation pivot by customer and status
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: Pivot แบบ Conditional Aggregation: นับแต่ละ Status เป็นคนละ Column
-- @teacher ผล/ชวนสังเกต: FILTER กรองเฉพาะ Aggregate นั้น ไม่ตัดแถวออกจาก Aggregate ตัวอื่น
-- @teacher SOURCE: 02-advanced-sql.sql:163 | รัน SQL นี้ครบทั้ง Statement
SELECT customer_code,
       count(*) FILTER (WHERE status = 'REVIEW') AS review_count,
       count(*) FILTER (WHERE status = 'APPROVED') AS approved_count,
       count(*) FILTER (WHERE status = 'PAID') AS paid_count,
       count(*) FILTER (WHERE status = 'REJECTED') AS rejected_count
FROM insurance.claim_detail_v
GROUP BY customer_code
ORDER BY customer_code;
-- @teacher [END 02-SQL017]

\echo '\n-- Lab 2H: Catalog validation for functions and procedures'
-- @teacher [START 02-SQL018] Lab 2H | Catalog validation for functions and procedures
-- @teacher LOGIN / DATABASE: student_xx | claimsure_xx ฐานเดียวกับ Module 1
-- @teacher อธิบาย: ตรวจ Catalog เพื่อแยก Function กับ Procedure ที่สร้างจริง
-- @teacher ผล/ชวนสังเกต: prokind f=Function และ p=Procedure; ควรพบสามชื่อที่ระบุ ไม่ใช้ชื่อไฟล์เป็นหลักฐานเพียงอย่างเดียว
-- @teacher SOURCE: 02-advanced-sql.sql:173 | รัน SQL นี้ครบทั้ง Statement
SELECT n.nspname AS schema_name,
       p.proname AS routine_name,
       CASE p.prokind WHEN 'f' THEN 'function' WHEN 'p' THEN 'procedure' END AS kind
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'insurance'
  AND p.proname IN ('claim_tax', 'claims_by_status', 'review_claim')
ORDER BY kind, routine_name;
-- @teacher [END 02-SQL018]
