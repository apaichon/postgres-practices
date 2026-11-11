# Module 2: Advanced SQL — View, Function, Procedure และรายงาน

[กลับสารบัญเวอร์ชันต่อเนื่อง](README.md)

> เวอร์ชันต่อเนื่อง: เก็บตารางและ view/functions ของบทนี้ไว้สำหรับบท 3–10

**ต้องทำ Module 1 ก่อน** และเก็บตาราง customer/policy/claim ใน `claimsure` ไว้

ใช้บัญชี SSH และฐานข้อมูลของตัวเองตาม [การเตรียมเครื่อง](README.md#เตรียมการเชื่อมต่อ) เปิด psql จาก Bash:

```bash
export PGAPPNAME=cli-m2
psql -X -v ON_ERROR_STOP=1
```

จากจุดนี้ให้วางบล็อก `sql` ใน psql ทีละขั้น หยุดอ่านผลก่อนทำขั้นถัดไป

```sql
\pset pager off
\timing on
SET TIME ZONE 'Asia/Bangkok';
SELECT current_database(), current_user;
```

```sql
SELECT to_regclass('claimsure.claim') AS prerequisite;
CREATE SCHEMA IF NOT EXISTS claimsure;
```

prerequisite ต้องไม่เป็น NULL ใช้ schema `claimsure` เดียวกับบท 1; view และ routines ใช้ CREATE OR REPLACE จึงรันซ้ำได้

## 2A — สร้าง View เป็นสัญญาการอ่านข้อมูล

รวม JOIN ไว้ใน view แล้วให้ผู้ใช้ SELECT จากชื่อเดียว

```sql
CREATE OR REPLACE VIEW claimsure.claim_detail_v AS
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
FROM claimsure.claim cl
JOIN claimsure.policy p USING (policy_id)
JOIN claimsure.customer c USING (customer_id);

SELECT claim_no, customer_code, policy_no, status
FROM claimsure.claim_detail_v
ORDER BY claim_no;
```

**ตรวจผล:** View แสดงหก claim แต่ไม่ได้เก็บสำเนาข้อมูล เมื่อ base table เปลี่ยน ผล SELECT จาก view เปลี่ยนตาม

## 2B — ย้ายสูตรภาษีเข้า SQL function

เปรียบเทียบสูตรเต็มกับ function ที่รับ estimated, approved และอัตราภาษี

```sql
CREATE OR REPLACE FUNCTION claimsure.claim_tax(
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

SELECT claim_no,
       round(
           greatest(coalesce(approved_amount, estimated_amount, 0), 0) * 0.07,
           2
       ) AS tax_manual
FROM claimsure.claim
ORDER BY claim_no;

SELECT claim_no,
       claimsure.claim_tax(estimated_amount, approved_amount) AS tax_function
FROM claimsure.claim
ORDER BY claim_no;
```

**ตรวจผล:** tax_manual กับ tax_function ต้องเท่ากันในแต่ละ claim ส่วน approved_amount ที่เป็น 0 ต้องคง 0 ไม่ถูกแทนด้วย estimated

## 2C — เขียน function คืนหลายแถว

RETURN QUERY คืนชุด claim โดยใช้ parameter กรอง status

```sql
CREATE OR REPLACE FUNCTION claimsure.claims_by_status(p_status text)
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
    FROM claimsure.claim_detail_v v
    WHERE v.status = upper(p_status)
    ORDER BY v.incident_at DESC;
END
$function$;

SELECT * FROM claimsure.claims_by_status('review');
```

**ตรวจผล:** ฟังก์ชันรับ review ตัวเล็กและแปลงด้วย upper จึงได้ claim ที่เป็น REVIEW; หลัง Module 1D มีสองรายการ

## 2D — ใช้ procedure ควบคุมการแก้ claim

CALL แก้ข้อมูลจริงใน transaction ที่ยังไม่ยืนยัน จากนั้นตรวจแล้ว ROLLBACK

```sql
CREATE OR REPLACE PROCEDURE claimsure.review_claim(
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

    UPDATE claimsure.claim
    SET status = 'APPROVED',
        approved_amount = p_approved_amount
    WHERE claim_no = p_claim_no;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'claim % not found', p_claim_no;
    END IF;
END
$procedure$;

BEGIN;
CALL claimsure.review_claim('CLM-L1-001', 14000.00);
SELECT claim_no, status, approved_amount
FROM claimsure.claim
WHERE claim_no = 'CLM-L1-001';
ROLLBACK; -- keep Module 1 data repeatable
```

**ตรวจผล:** ระหว่าง transaction CLM-L1-001 เป็น APPROVED ยอด 14000 หลัง ROLLBACK กลับเป็น REVIEW และ approved_amount เดิม

## 2E — ต่อ pipeline ด้วย CTE

รวมยอดภาษีก่อน แล้วจัดอันดับด้วย dense_rank

```sql
WITH claim_totals AS (
    SELECT customer_code,
           full_name,
           count(*) AS claim_count,
           sum(claimsure.claim_tax(estimated_amount, approved_amount)) AS tax_total
    FROM claimsure.claim_detail_v
    GROUP BY customer_code, full_name
), ranked AS (
    SELECT *, dense_rank() OVER (ORDER BY tax_total DESC) AS tax_rank
    FROM claim_totals
)
SELECT * FROM ranked ORDER BY tax_rank, customer_code;
```

**ตรวจผล:** ได้หนึ่งแถวต่อลูกค้าที่มี claim และอันดับตามยอด ไม่ใช่การจัดอันดับทีละ claim

## 2F — Window function รักษารายละเอียดทุกแถว

row_number และ running sum ใช้ partition ต่อ customer และลำดับเวลาที่แน่นอน

```sql
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
FROM claimsure.claim_detail_v
ORDER BY customer_code, claim_sequence;
```

**ตรวจผล:** ยังได้หกแถว ต่างจาก GROUP BY ที่ยุบรายละเอียด frame ROWS ระบุยอดสะสมทีละแถว

## 2G — Pivot ด้วย FILTER

แปลง status ที่เลือกเป็นคอลัมน์จำนวนต่อ customer

```sql
SELECT customer_code,
       count(*) FILTER (WHERE status = 'REVIEW') AS review_count,
       count(*) FILTER (WHERE status = 'APPROVED') AS approved_count,
       count(*) FILTER (WHERE status = 'PAID') AS paid_count,
       count(*) FILTER (WHERE status = 'REJECTED') AS rejected_count
FROM claimsure.claim_detail_v
GROUP BY customer_code
ORDER BY customer_code;
```

**ตรวจผล:** เปรียบเทียบจำนวน REVIEW กับ Module 1D ให้ตรงกัน status ที่ไม่อยู่ใน FILTER จะไม่รวมในคอลัมน์เหล่านี้

## 2H — ตรวจ catalog ของ routines

อ่าน pg_proc เพื่อแยก function กับ procedure

```sql
SELECT n.nspname AS schema_name,
       p.proname AS routine_name,
       CASE p.prokind WHEN 'f' THEN 'function' WHEN 'p' THEN 'procedure' END AS kind
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'claimsure'
  AND p.proname IN ('claim_tax', 'claims_by_status', 'review_claim')
ORDER BY kind, routine_name;
```

**ตรวจผล:** ควรมี function สองชื่อและ procedure หนึ่งชื่อใน claimsure

## ทางเลือกคืนค่าเมื่อจบคอร์สแล้ว

การทดสอบ procedure ใช้ ROLLBACK จึงไม่ต้องแก้ข้อมูล Module 1 คืนด้วยมือ

**ถ้าจะเรียนบท 3 ต่อ ไม่ต้องทำบล็อกด้านล่าง** สามารถรัน CREATE OR REPLACE ของบทนี้ซ้ำได้ ถ้าจบทุกบทและต้องการลบ routines ให้ออกจาก transaction ที่ค้างก่อน แล้วลบเฉพาะ objects ของบทนี้:

```sql
ROLLBACK;
DROP MATERIALIZED VIEW IF EXISTS claimsure.cs_monthly_claim_summary;
DROP VIEW IF EXISTS claimsure.claim_detail_v;
DROP FUNCTION IF EXISTS claimsure.claims_by_status(text);
DROP FUNCTION IF EXISTS claimsure.claim_tax(numeric,numeric,numeric);
DROP PROCEDURE IF EXISTS claimsure.review_claim(text,numeric);
```

คำสั่งนี้ลบเฉพาะ objects ที่ระบุใน schema claimsure รันเมื่อเก็บผลทดลองแล้ว ใช้ `\q` เพื่อออกจาก psql
