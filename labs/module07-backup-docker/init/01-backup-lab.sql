CREATE ROLE claims_readonly NOLOGIN;
CREATE ROLE claims_app LOGIN;
GRANT claims_readonly TO claims_app;

CREATE SCHEMA claims AUTHORIZATION claims_app;

SET ROLE claims_app;

CREATE TABLE claims.claim_event (
    event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    claim_no text NOT NULL UNIQUE,
    event_type text NOT NULL,
    amount numeric(12,2) NOT NULL CHECK (amount >= 0),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

INSERT INTO claims.claim_event (claim_no, event_type, amount) VALUES
    ('CLM-0001', 'REGISTERED', 1000.00),
    ('CLM-0002', 'APPROVED',   2500.00),
    ('CLM-0003', 'PAID',       1800.00);

RESET ROLE;

GRANT USAGE ON SCHEMA claims TO claims_readonly;
GRANT SELECT ON claims.claim_event TO claims_readonly;

