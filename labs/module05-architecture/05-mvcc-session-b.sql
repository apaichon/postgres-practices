-- Lab 5E, complete-course PDF p. 118. Run after A reaches its prompt.
-- Connect as postgres to the same seeded primary/database as Session A.
-- This commits CLM-L1-005 as REVIEW, as in the slides.
\set ON_ERROR_STOP on
\pset pager off
\echo '=== Module 5 / Lab 5E: MVCC - Session B ==='
\conninfo

DO $$
BEGIN
    IF current_database() !~ '^architecture_m5_(0[1-9]|1[0-9]|20)$' THEN
        RAISE EXCEPTION 'Use a dedicated architecture_m5_01..20 database';
    END IF;
    IF pg_is_in_recovery() OR NOT EXISTS
       (SELECT FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'Use the instructor superuser on the writable lab server';
    END IF;
END $$;

BEGIN;
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM insurance.claim
                   WHERE claim_no = 'CLM-L1-005') THEN
        RAISE EXCEPTION 'Missing seed claim: CLM-L1-005.';
    END IF;
END
$$;
UPDATE insurance.claim
SET status = 'REVIEW', created_at = clock_timestamp()
WHERE claim_no = 'CLM-L1-005'
RETURNING xmin, xmax, ctid, claim_no, status, created_at;
SELECT pg_backend_pid() AS session_b_pid, txid_current() AS session_b_xid;
COMMIT;

\echo 'Session B committed. Return to Session A and press Enter.'
-- VERIFY: UPDATE 1 completes while A's plain SELECT snapshot remains open.
-- Readers using SELECT FOR UPDATE would introduce different locking behavior.
