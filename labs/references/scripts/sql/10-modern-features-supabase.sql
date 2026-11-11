\set ON_ERROR_STOP on
\pset pager off
\echo '=== Module 10: Modern PostgreSQL Features and Supabase ==='

CREATE SCHEMA IF NOT EXISTS lab_m10;

CREATE TABLE IF NOT EXISTS lab_m10.claim_feature (
    claim_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    claim_no text NOT NULL UNIQUE,
    tenant_id bigint NOT NULL,
    status text NOT NULL,
    incident_at timestamptz NOT NULL,
    description text,
    metadata jsonb NOT NULL DEFAULT '{}',
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

INSERT INTO lab_m10.claim_feature
    (claim_no, tenant_id, status, incident_at, description, metadata)
VALUES
    ('MOD-001', 101, 'NEW', TIMESTAMPTZ '2026-01-10 09:00+07',
     'Rear bumper damage near Bangkok',
     '{"channel":"mobile","provider":"garage-a","risk_score":42}'),
    ('MOD-002', 101, 'UNDER_REVIEW', TIMESTAMPTZ '2026-02-15 13:30+07',
     'Windshield crack and urgent repair',
     '{"channel":"web","provider":"garage-b","risk_score":71}'),
    ('MOD-003', 202, 'APPROVED', TIMESTAMPTZ '2026-04-03 08:15+07',
     'Flood damage in Chiang Mai',
     '{"channel":"agent","provider":"garage-a","risk_score":88}')
ON CONFLICT (claim_no) DO UPDATE
SET status = EXCLUDED.status,
    description = EXCLUDED.description,
    metadata = EXCLUDED.metadata,
    updated_at = clock_timestamp();

\echo '\n-- Lab 10A: JSONB evolve-without-migration data'
UPDATE lab_m10.claim_feature
SET metadata = jsonb_set(metadata, '{assessment}', '{"priority":"high"}'::jsonb, true),
    updated_at = clock_timestamp()
WHERE claim_no = 'MOD-002';

SELECT claim_no,
       metadata ->> 'channel' AS channel,
       metadata #>> '{assessment,priority}' AS priority,
       (metadata ->> 'risk_score')::integer AS risk_score
FROM lab_m10.claim_feature
ORDER BY claim_no;

CREATE INDEX IF NOT EXISTS idx_claim_feature_metadata_gin
ON lab_m10.claim_feature USING gin (metadata jsonb_path_ops);

CREATE INDEX IF NOT EXISTS idx_claim_feature_provider
ON lab_m10.claim_feature ((metadata ->> 'provider'));

ANALYZE lab_m10.claim_feature;
EXPLAIN (ANALYZE, BUFFERS)
SELECT claim_no
FROM lab_m10.claim_feature
WHERE metadata @> '{"provider":"garage-a"}'::jsonb;

\echo '\n-- Full-text search with a stored generated tsvector'
ALTER TABLE lab_m10.claim_feature
ADD COLUMN IF NOT EXISTS search_document tsvector
GENERATED ALWAYS AS (
    to_tsvector('simple',
        coalesce(description, '') || ' ' || coalesce(metadata ->> 'provider', ''))
) STORED;

CREATE INDEX IF NOT EXISTS idx_claim_feature_search
ON lab_m10.claim_feature USING gin (search_document);

SELECT claim_no,
       ts_rank(search_document, plainto_tsquery('simple', 'urgent repair')) AS rank
FROM lab_m10.claim_feature
WHERE search_document @@ plainto_tsquery('simple', 'urgent repair')
ORDER BY rank DESC;

\echo '\n-- Declarative partitioning and lifecycle operations'
CREATE TABLE IF NOT EXISTS lab_m10.claim_event (
    event_id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    occurred_at timestamptz NOT NULL,
    payload jsonb NOT NULL,
    PRIMARY KEY (event_id, occurred_at)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE IF NOT EXISTS lab_m10.claim_event_2026_q1
PARTITION OF lab_m10.claim_event
FOR VALUES FROM ('2026-01-01 00:00+07') TO ('2026-04-01 00:00+07');
CREATE TABLE IF NOT EXISTS lab_m10.claim_event_2026_q2
PARTITION OF lab_m10.claim_event
FOR VALUES FROM ('2026-04-01 00:00+07') TO ('2026-07-01 00:00+07');

INSERT INTO lab_m10.claim_event(event_id, tenant_id, occurred_at, payload)
VALUES
    (1, 101, TIMESTAMPTZ '2026-02-01 10:00+07', '{"action":"created"}'),
    (2, 202, TIMESTAMPTZ '2026-05-01 11:00+07', '{"action":"approved"}')
ON CONFLICT (event_id, occurred_at) DO UPDATE SET payload = EXCLUDED.payload;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab_m10.claim_event
WHERE occurred_at >= TIMESTAMPTZ '2026-04-01 00:00+07'
  AND occurred_at <  TIMESTAMPTZ '2026-07-01 00:00+07';

SELECT tableoid::regclass AS partition_name, count(*) AS rows
FROM lab_m10.claim_event
GROUP BY tableoid
ORDER BY tableoid::regclass::text;

-- Lifecycle examples; review retention policy before executing:
-- ALTER TABLE lab_m10.claim_event DETACH PARTITION lab_m10.claim_event_2026_q1;
-- DROP TABLE lab_m10.claim_event_2026_q1;

\echo '\n-- Vector similarity when pgvector is installed'
SELECT EXISTS (SELECT FROM pg_extension WHERE extname = 'vector') AS has_vector \gset
\if :has_vector
CREATE TABLE IF NOT EXISTS lab_m10.claim_embedding (
    claim_id bigint PRIMARY KEY,
    embedding vector(3) NOT NULL
);
INSERT INTO lab_m10.claim_embedding(claim_id, embedding)
VALUES
    (1, '[0.10,0.20,0.30]'),
    (2, '[0.12,0.18,0.33]'),
    (3, '[0.90,0.10,0.05]')
ON CONFLICT (claim_id) DO UPDATE SET embedding = EXCLUDED.embedding;

SELECT claim_id, embedding <=> '[0.11,0.19,0.31]'::vector AS cosine_distance
FROM lab_m10.claim_embedding
ORDER BY cosine_distance
LIMIT 3;
\else
\echo 'pgvector is not installed; vector section skipped.'
\endif

\echo '\n-- Supabase-style JWT context + RLS readiness'
CREATE TABLE IF NOT EXISTS lab_m10.profile (
    profile_id uuid PRIMARY KEY,
    owner_id uuid NOT NULL,
    display_name text NOT NULL
);

INSERT INTO lab_m10.profile(profile_id, owner_id, display_name)
VALUES
    ('00000000-0000-0000-0000-000000000001',
     'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Alice'),
    ('00000000-0000-0000-0000-000000000002',
     'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Bob')
ON CONFLICT (profile_id) DO UPDATE SET display_name = EXCLUDED.display_name;

DO $block$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lab_m10_authenticated') THEN
        CREATE ROLE lab_m10_authenticated NOLOGIN;
    END IF;
END
$block$;

GRANT USAGE ON SCHEMA lab_m10 TO lab_m10_authenticated;
GRANT SELECT ON lab_m10.profile TO lab_m10_authenticated;
ALTER TABLE lab_m10.profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_m10.profile FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS profile_owner_select ON lab_m10.profile;
CREATE POLICY profile_owner_select ON lab_m10.profile
FOR SELECT
USING (owner_id::text = current_setting('request.jwt.claim.sub', true));

SELECT set_config('request.jwt.claim.sub',
                  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
SET ROLE lab_m10_authenticated;
SELECT * FROM lab_m10.profile ORDER BY profile_id;
RESET ROLE;

\echo 'Expected: the authenticated role sees Alice only.'
SELECT extname, extversion
FROM pg_extension
ORDER BY extname;

SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'lab_m10'
ORDER BY tablename;
