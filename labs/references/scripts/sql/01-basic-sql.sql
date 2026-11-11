\set ON_ERROR_STOP on
\pset pager off
\echo '=== Module 1: Basic SQL ==='
\conninfo

SELECT current_database() AS database_name,
       current_user AS login_role,
       inet_server_addr() AS server_address,
       inet_server_port() AS server_port;
SELECT version();

-- Lab 1 — Build and Verify
-- เป้าหมาย: สร้าง schema/table, CRUD, transaction, JOIN และ aggregate
-- รันทีละส่วน: ./scripts/shells/run-lab01.sh --student xx --ask-pass A
-- Common course schema: insurance (reused by Module 2)

\echo '\n-- Lab 1A: create schema and related tables'

CREATE SCHEMA IF NOT EXISTS insurance;

SELECT to_regnamespace('insurance') AS schema_name;

CREATE TABLE IF NOT EXISTS insurance.customer (
    customer_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_code text NOT NULL UNIQUE,
    full_name text NOT NULL,
    email text UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

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

\echo '\n-- Lab 1B: insert repeatable seed data'

INSERT INTO insurance.customer (customer_code, full_name, email)
VALUES
    ('CUS-001', 'Anan Chai', 'anan@example.com'),
    ('CUS-002', 'Mali Dee', 'mali@example.com'),
    ('CUS-003', 'Nok No-Claim', 'nok@example.com')
ON CONFLICT (customer_code) DO UPDATE
SET full_name = EXCLUDED.full_name,
    email = EXCLUDED.email
RETURNING customer_id, customer_code, full_name;

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

\echo '\n-- Lab 1C: select the sample claim rows'
SELECT claim_no, status, estimated_amount
FROM insurance.claim
ORDER BY claim_no;

\echo '\n-- Lab 1D: update one claim in a transaction'
BEGIN;
UPDATE insurance.claim
SET status = 'REVIEW'
WHERE claim_no = 'CLM-L1-001'
  AND status = 'NEW'
RETURNING claim_no, status;

SELECT status, count(*) AS claims
FROM insurance.claim
GROUP BY status
ORDER BY status;

COMMIT;

\echo '\n-- Lab 1E: delete one claim and roll back the transaction'
BEGIN;
DELETE FROM insurance.claim
WHERE claim_no = 'CLM-L1-006'
  AND status = 'REJECTED'
RETURNING claim_no, status;
ROLLBACK; -- preserve all six seed claims

\echo '\n-- Lab 1F: join related data and compare set operations'
SELECT c.full_name, p.policy_no, cl.claim_no, cl.status
FROM insurance.customer c
JOIN insurance.policy p USING (customer_id)
LEFT JOIN insurance.claim cl USING (policy_id)
ORDER BY c.full_name, p.policy_no, cl.claim_no;

\echo '\n-- Customers with no claims: LEFT JOIN plus HAVING'
SELECT c.customer_code, c.full_name
FROM insurance.customer c
LEFT JOIN insurance.policy p USING (customer_id)
LEFT JOIN insurance.claim cl USING (policy_id)
GROUP BY c.customer_id, c.customer_code, c.full_name
HAVING count(cl.claim_id) = 0
ORDER BY c.customer_code;

\echo '\n-- INTERSECT keeps rows present in both results'
WITH a(status) AS (
    VALUES ('NEW'), ('REVIEW')
), b(status) AS (
    VALUES ('REVIEW'), ('APPROVED')
)
SELECT status FROM a
INTERSECT
SELECT status FROM b;

\echo '\n-- UNION combines results and removes duplicates'
WITH a(status) AS (
    VALUES ('NEW'), ('REVIEW')
), b(status) AS (
    VALUES ('REVIEW'), ('APPROVED')
)
SELECT status FROM a
UNION
SELECT status FROM b
ORDER BY status;

\echo '\n-- Lab 1G: aggregate results and verify row counts'
SELECT status,
       count(*) AS claim_count,
       sum(estimated_amount) AS estimated_total,
       avg(estimated_amount) AS estimated_average
FROM insurance.claim
GROUP BY status
ORDER BY status;

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

\echo '\n-- Expected checkpoints: 3 customers, 3 policies, 6 claims'
SELECT
    (SELECT count(*) FROM insurance.customer) AS customers,
    (SELECT count(*) FROM insurance.policy) AS policies,
    (SELECT count(*) FROM insurance.claim) AS claims;
