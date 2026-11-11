# Module 1: Basic SQL — สร้าง อ่าน แก้ และคืนค่า

[กลับสารบัญเวอร์ชันต่อเนื่อง](README.md)

> เวอร์ชันต่อเนื่อง: เก็บตารางและ view/functions ของบทนี้ไว้สำหรับบท 3–10

ใช้บัญชี SSH และฐานข้อมูลของตัวเองตาม [การเตรียมเครื่อง](README.md#เตรียมการเชื่อมต่อ) เปิด psql จาก Bash:

```bash
export PGAPPNAME=cli-m1
psql -X -v ON_ERROR_STOP=1
```

จากจุดนี้ให้วางบล็อก `sql` ใน psql ทีละขั้น หยุดอ่านผลก่อนทำขั้นถัดไป

```sql
\pset pager off
\timing on
SET TIME ZONE 'Asia/Bangkok';
SELECT current_database(), current_user;
```

## 1A — สร้าง schema และตารางที่สัมพันธ์กัน

สร้าง customer, policy และ claim โดยมี primary key, foreign key, UNIQUE และ CHECK

```sql
CREATE SCHEMA IF NOT EXISTS claimsure;

SELECT to_regnamespace('claimsure') AS schema_name;

CREATE TABLE IF NOT EXISTS claimsure.customer (
    customer_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_code text NOT NULL UNIQUE,
    full_name text NOT NULL,
    email text UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS claimsure.policy (
    policy_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    policy_no text NOT NULL UNIQUE,
    customer_id bigint NOT NULL REFERENCES claimsure.customer,
    product_code text NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    status text NOT NULL CHECK (status IN ('ACTIVE', 'EXPIRED', 'CANCELLED')),
    CHECK (ends_on >= starts_on)
);

CREATE TABLE IF NOT EXISTS claimsure.claim (
    claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    claim_no text NOT NULL UNIQUE,
    policy_id bigint NOT NULL REFERENCES claimsure.policy,
    status text NOT NULL CHECK (status IN ('NEW', 'REVIEW', 'APPROVED', 'REJECTED', 'PAID')),
    incident_at timestamptz NOT NULL,
    estimated_amount numeric(14,2) NOT NULL CHECK (estimated_amount >= 0),
    approved_amount numeric(14,2) CHECK (approved_amount >= 0),
    created_at timestamptz NOT NULL DEFAULT now()
);
```

**ตรวจผล:** ใช้ `\dt claimsure.*` และ `\d claimsure.claim` ตรวจตาราง ควรพบ customer, policy และ claim; ถ้าทำบทอื่นแล้วอาจมีตารางเพิ่ม Constraints อยู่ที่ฐานข้อมูล ไม่ใช่เฉพาะหน้าจอ

## 1B — เพิ่มข้อมูลตัวอย่าง

INSERT ลูกค้าก่อน policy แล้วจึง claim เพื่อให้ foreign key อ้างถึงแถวที่มีอยู่

```sql
INSERT INTO claimsure.customer (customer_code, full_name, email)
VALUES
    ('CUS-001', 'Anan Chai', 'anan@example.com'),
    ('CUS-002', 'Mali Dee', 'mali@example.com'),
    ('CUS-003', 'Nok No-Claim', 'nok@example.com')
ON CONFLICT (customer_code) DO UPDATE
SET full_name = EXCLUDED.full_name,
    email = EXCLUDED.email
RETURNING customer_id, customer_code, full_name;

INSERT INTO claimsure.policy
    (policy_no, customer_id, product_code, starts_on, ends_on, status)
SELECT v.policy_no, c.customer_id, v.product_code, v.starts_on, v.ends_on, v.status
FROM (VALUES
    ('POL-001', 'CUS-001', 'AUTO', DATE '2026-01-01', DATE '2026-12-31', 'ACTIVE'),
    ('POL-002', 'CUS-001', 'HOME', DATE '2026-01-01', DATE '2026-12-31', 'ACTIVE'),
    ('POL-003', 'CUS-002', 'TRAVEL', DATE '2026-02-01', DATE '2026-08-31', 'ACTIVE')
) AS v(policy_no, customer_code, product_code, starts_on, ends_on, status)
JOIN claimsure.customer c USING (customer_code)
ON CONFLICT (policy_no) DO UPDATE
SET customer_id = EXCLUDED.customer_id,
    product_code = EXCLUDED.product_code,
    starts_on = EXCLUDED.starts_on,
    ends_on = EXCLUDED.ends_on,
    status = EXCLUDED.status
RETURNING policy_id, policy_no, product_code, status;

INSERT INTO claimsure.claim
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
JOIN claimsure.policy p USING (policy_no)
ON CONFLICT (claim_no) DO UPDATE
SET policy_id = EXCLUDED.policy_id,
    status = EXCLUDED.status,
    incident_at = EXCLUDED.incident_at,
    estimated_amount = EXCLUDED.estimated_amount,
    approved_amount = EXCLUDED.approved_amount
RETURNING claim_id, claim_no, status, estimated_amount;
```

**ตรวจผล:** คาดหวังลูกค้า 3 ราย, policy 3 รายการ, claim 6 รายการ `ON CONFLICT` ทำให้ seed เดิมรันซ้ำได้โดยไม่เพิ่ม claim ซ้ำ

## 1C — อ่านข้อมูลโดยระบุลำดับ

SELECT เฉพาะคอลัมน์ที่ต้องการและใช้ ORDER BY ให้ผลมีลำดับแน่นอน

```sql
SELECT claim_no, status, estimated_amount
FROM claimsure.claim
ORDER BY claim_no;
```

**ตรวจผล:** ควรเห็น CLM-L1-001 ถึง CLM-L1-006 จำนวนหกแถว ลองเพิ่ม WHERE status = 'NEW' แล้วเทียบจำนวนแถว

## 1D — UPDATE ภายใน transaction

BEGIN เปิด transaction; RETURNING แสดงแถวที่แก้; COMMIT ยืนยันการเปลี่ยน

```sql
BEGIN;
UPDATE claimsure.claim
SET status = 'REVIEW'
WHERE claim_no = 'CLM-L1-001'
  AND status = 'NEW'
RETURNING claim_no, status;

SELECT status, count(*) AS claims
FROM claimsure.claim
GROUP BY status
ORDER BY status;

COMMIT;
```

**ตรวจผล:** CLM-L1-001 เปลี่ยนจาก NEW เป็น REVIEW และคงอยู่หลัง COMMIT ถ้ารันซ้ำ UPDATE อาจได้ศูนย์แถว เพราะเงื่อนไข status เปลี่ยนไปแล้ว

## 1E — DELETE แล้ว ROLLBACK

ลบ claim ที่ระบุ แล้วสั่งย้อนการเปลี่ยนภายใน transaction เดียวกัน

```sql
BEGIN;
DELETE FROM claimsure.claim
WHERE claim_no = 'CLM-L1-006'
  AND status = 'REJECTED'
RETURNING claim_no, status;
ROLLBACK; -- preserve all six seed claims
```

**ตรวจผล:** DELETE แสดงหนึ่งแถว แต่หลัง ROLLBACK claim นั้นกลับมา ตรวจด้วย SELECT ไม่ใช่ดูเฉพาะข้อความ DELETE 1

## 1F — JOIN และ set operations

ดูความสัมพันธ์ customer-policy-claim แล้วเปรียบเทียบ INTERSECT กับ UNION

```sql
SELECT c.full_name, p.policy_no, cl.claim_no, cl.status
FROM claimsure.customer c
JOIN claimsure.policy p USING (customer_id)
LEFT JOIN claimsure.claim cl USING (policy_id)
ORDER BY c.full_name, p.policy_no, cl.claim_no;

SELECT c.customer_code, c.full_name
FROM claimsure.customer c
LEFT JOIN claimsure.policy p USING (customer_id)
LEFT JOIN claimsure.claim cl USING (policy_id)
GROUP BY c.customer_id, c.customer_code, c.full_name
HAVING count(cl.claim_id) = 0
ORDER BY c.customer_code;

WITH a(status) AS (
    VALUES ('NEW'), ('REVIEW')
), b(status) AS (
    VALUES ('REVIEW'), ('APPROVED')
)
SELECT status FROM a
INTERSECT
SELECT status FROM b;

WITH a(status) AS (
    VALUES ('NEW'), ('REVIEW')
), b(status) AS (
    VALUES ('REVIEW'), ('APPROVED')
)
SELECT status FROM a
UNION
SELECT status FROM b
ORDER BY status;
```

**ตรวจผล:** CUS-003 ไม่มี claim จึงปรากฏในคำถาม customers with no claims; INTERSECT ได้ REVIEW; UNION ได้สาม status ที่ไม่ซ้ำ

## 1G — GROUP BY และ HAVING

รวมจำนวนและยอดเงิน แยกตาม status และลูกค้า

```sql
SELECT status,
       count(*) AS claim_count,
       sum(estimated_amount) AS estimated_total,
       avg(estimated_amount) AS estimated_average
FROM claimsure.claim
GROUP BY status
ORDER BY status;

SELECT c.customer_code,
       c.full_name,
       count(cl.claim_id) AS total_claims,
       sum(cl.estimated_amount) AS total_estimated
FROM claimsure.customer c
JOIN claimsure.policy p USING (customer_id)
JOIN claimsure.claim cl USING (policy_id)
GROUP BY c.customer_id, c.customer_code, c.full_name
HAVING count(cl.claim_id) >= 2
ORDER BY total_estimated DESC;

SELECT
    (SELECT count(*) FROM claimsure.customer) AS customers,
    (SELECT count(*) FROM claimsure.policy) AS policies,
    (SELECT count(*) FROM claimsure.claim) AS claims;
```

**ตรวจผล:** ผลตรวจท้ายขั้นต้องเป็น customers=3, policies=3, claims=6 อย่าบวกค่า AVG ของหลายกลุ่มเพื่อแทนค่าเฉลี่ยทั้งหมด

## ลองอธิบายผล

เหตุใดต้อง INSERT customer ก่อน policy? COMMIT ต่างจาก ROLLBACK อย่างไร? ถ้าใช้ INNER JOIN อย่างเดียว จะเห็นลูกค้าที่ไม่มี claim หรือไม่?

## คืนค่าและทำซ้ำ

Module 2 ใช้ `claimsure.customer`, `claimsure.policy`, `claimsure.claim` ต่อ ให้เก็บตารางเหล่านี้ไว้

เมื่อต้องการคืนข้อมูลตัวอย่าง ให้ออกจาก transaction ที่ค้าง แล้วรัน INSERT ทั้งสามคำสั่งใน **1B** ซ้ำ `ON CONFLICT` คืนค่าเฉพาะรหัสตัวอย่างเดิมโดยไม่เพิ่มแถวซ้ำ:

```sql
ROLLBACK;
```

ไม่ต้องลบ schema หรือตารางเพื่อทำบทนี้ซ้ำ ใช้ `\q` เพื่อออกจาก psql
