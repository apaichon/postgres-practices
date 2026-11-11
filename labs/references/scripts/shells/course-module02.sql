\set ON_ERROR_STOP on
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
DO $block$
BEGIN
    IF to_regclass('insurance.claim') IS NULL THEN
        RAISE EXCEPTION 'Run 01-basic-sql.sql before Module 2';
    END IF;
END
$block$;

CREATE SCHEMA IF NOT EXISTS insurance;

\echo '\n-- Lab 2A: View contract for claim details'
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

SELECT claim_no, customer_code, policy_no, status
FROM insurance.claim_detail_v
ORDER BY claim_no;

\echo '\n-- Lab 2B: SQL function for a shorter claim-tax calculation'
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

\echo '\nManual calculation: repeat the full tax expression'
SELECT claim_no,
       round(
           greatest(coalesce(approved_amount, estimated_amount, 0), 0) * 0.07,
           2
       ) AS tax_manual
FROM insurance.claim
ORDER BY claim_no;

\echo '\nFunction call: use the shorter reusable rule'
SELECT claim_no,
       insurance.claim_tax(estimated_amount, approved_amount) AS tax_function
FROM insurance.claim
ORDER BY claim_no;

\echo '\n-- Lab 2C: PL/pgSQL row-set function filtered by status'
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

SELECT * FROM insurance.claims_by_status('review');

\echo '\n-- Lab 2D: Procedure for controlled claim review'
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

BEGIN;
CALL insurance.review_claim('CLM-L1-001', 14000.00);
SELECT claim_no, status, approved_amount
FROM insurance.claim
WHERE claim_no = 'CLM-L1-001';
ROLLBACK; -- keep Module 1 data repeatable

\echo '\n-- Lab 2E: CTE pipeline for ranked customer tax totals'
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

\echo '\n-- Lab 2F: Window functions for sequence and running total'
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

\echo '\n-- Lab 2G: Conditional-aggregation pivot by customer and status'
SELECT customer_code,
       count(*) FILTER (WHERE status = 'REVIEW') AS review_count,
       count(*) FILTER (WHERE status = 'APPROVED') AS approved_count,
       count(*) FILTER (WHERE status = 'PAID') AS paid_count,
       count(*) FILTER (WHERE status = 'REJECTED') AS rejected_count
FROM insurance.claim_detail_v
GROUP BY customer_code
ORDER BY customer_code;

\echo '\n-- Lab 2H: Catalog validation for functions and procedures'
SELECT n.nspname AS schema_name,
       p.proname AS routine_name,
       CASE p.prokind WHEN 'f' THEN 'function' WHEN 'p' THEN 'procedure' END AS kind
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'insurance'
  AND p.proname IN ('claim_tax', 'claims_by_status', 'review_claim')
ORDER BY kind, routine_name;
