-- Module 7: run as the student in their own database or private sandbox.
-- Re-running adds missing baseline rows and preserves existing changes.
\set ON_ERROR_STOP on
\pset pager off
BEGIN;
CREATE SCHEMA IF NOT EXISTS lab_m7_practice;
CREATE TABLE IF NOT EXISTS lab_m7_practice.claim_event (
    event_id integer PRIMARY KEY,
    description text NOT NULL,
    amount numeric(12,2) NOT NULL
);
-- Explicit reset affects only this disposable practice table in the selected DB.
\if :{?reset_practice}
TRUNCATE TABLE lab_m7_practice.claim_event;
\endif
INSERT INTO lab_m7_practice.claim_event VALUES
    (1, 'CLAIM_REGISTERED', 100.00),
    (2, 'CLAIM_APPROVED', 250.00)
ON CONFLICT (event_id) DO NOTHING;
COMMIT;
SELECT current_database(), current_user;
TABLE lab_m7_practice.claim_event;
SELECT count(*) AS row_count, sum(amount) AS total_amount
FROM lab_m7_practice.claim_event;
