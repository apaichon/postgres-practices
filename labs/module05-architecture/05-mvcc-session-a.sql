-- Lab 5E, complete-course PDF p. 118. Run as postgres on the seeded primary.
-- Use an interactive terminal; start B only when A reaches the prompt.
--   make lab5 LAB_NO=5E-A
\set ON_ERROR_STOP on
\pset pager off
\echo '=== Module 5 / Lab 5E: MVCC - Session A ==='
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

BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM insurance.claim
                   WHERE claim_no = 'CLM-L1-005') THEN
        RAISE EXCEPTION 'Missing seed claim: CLM-L1-005.';
    END IF;
END
$$;
SELECT pg_backend_pid() AS session_a_pid, txid_current() AS session_a_xid;
SELECT xmin, xmax, ctid, claim_no, status, created_at
FROM insurance.claim
WHERE claim_no = 'CLM-L1-005';

\prompt 'Run 05-mvcc-session-b.sql in terminal B. After B commits, press Enter: ' continue
\echo 'A still sees the original row version in the same Repeatable Read snapshot:'
SELECT xmin, xmax, ctid, claim_no, status, created_at
FROM insurance.claim
WHERE claim_no = 'CLM-L1-005';

COMMIT;
\echo 'A now takes a new snapshot and sees the version committed by B:'
SELECT xmin, xmax, ctid, claim_no, status, created_at
FROM insurance.claim
WHERE claim_no = 'CLM-L1-005';
-- VERIFY: status/created_at/ctid stay the same for A's first two reads.
-- After COMMIT, created_at/ctid change even if status was already REVIEW.
-- xmax may change on the old tuple; snapshot stability concerns visible values,
-- not immutable physical tuple headers. ctid is not a stable business key.
