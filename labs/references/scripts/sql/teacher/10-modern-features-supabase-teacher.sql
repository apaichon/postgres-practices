-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 10-modern-features-supabase.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/10-modern-features-supabase.sql
-- @teacher LOGIN / DATABASE เริ่มต้น: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อ่าน README.md ใน Directory นี้ก่อนสอน; ใช้ไฟล์นี้เป็นคู่มือเลือกรันทีละส่วน
-- @teacher แต่ละ SQL มี START/END, Lab, Login, เหตุผล และผลที่ต้องสังเกต; Source Line อ้างไฟล์ต้นฉบับ
-- @teacher START/END ราย SQL ใช้ค้นคำอธิบาย ไม่ใช่ขอบเขต Commit: Transaction/Function ต้องรันครบชุด
-- @teacher คำสั่ง psql ขึ้นต้นด้วย Backslash; SQL Editor ทั่วไปให้ข้ามและจัด Branch/Variables เอง
-- @teacher ทุกบรรทัดที่เพิ่มขึ้นต้น -- @teacher; SQL/psql ต้นฉบับคงเดิม รวมคำสั่งเปลี่ยนข้อมูลและ Expected Errors
-- @teacher เป้าหมาย: JSONB → Full-text Search → Partition → Optional Vector → จำลอง JWT Context/RLS
-- @teacher CREATE ROLE ต้องเป็น postgres/CREATEROLE; Runtime Role lab_m10_authenticated เป็นชื่อระดับ Cluster ไม่แยก xx
-- @teacher ใช้ฐานฝึกที่ผู้สอนจัดแยก; ไม่มอบ CREATEROLE ให้นักเรียนเพื่อข้ามขั้น Setup
-- @teacher Vector Section ข้ามหากไม่มี Extension; Embeddings 3D เป็นข้อมูลสังเคราะห์
-- @teacher Custom request.jwt.claim.sub จำลอง Context เท่านั้น ไม่ได้ตรวจ JWT; RESET ROLE ไม่ล้าง Custom GUC
-- @teacher หลังจบให้ RESET request.jwt.claim.sub; ด้วยตนเองหรือ Disconnect; ไม่ถือการ SET ROLE ว่าเป็น Supabase Auth Login
-- @teacher ==============================================================================
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP on
-- @teacher PSQL: ตั้งรูปแบบแสดงผลของ psql ไม่เปลี่ยนข้อมูลใน Database
\pset pager off
\echo '=== Module 10: Modern PostgreSQL Features and Supabase ==='

-- @teacher [START 10-SQL001] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: สร้าง Schema lab_m10 เพื่อแยก Features ตัวอย่างจากข้อมูลธุรกิจ
-- @teacher ผล/ชวนสังเกต: ใช้ฐาน PostgreSQL สำหรับ Lab นี้ ไม่ใช่ Auth Schema ของ Supabase Self-hosted โดยอัตโนมัติ
-- @teacher SOURCE: 10-modern-features-supabase.sql:5 | รัน SQL นี้ครบทั้ง Statement
CREATE SCHEMA IF NOT EXISTS lab_m10;
-- @teacher [END 10-SQL001]

-- @teacher [START 10-SQL002] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: สร้าง Hybrid Model: Columns ที่ต้องคุมชนิดข้อมูล + metadata แบบ JSONB
-- @teacher ผล/ชวนสังเกต: Claim Number/Tenant/Status ยังเป็น Relational Columns; JSONB ไม่แทน Constraints ทุกอย่าง
-- @teacher SOURCE: 10-modern-features-supabase.sql:7 | รัน SQL นี้ครบทั้ง Statement
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
-- @teacher [END 10-SQL002]

-- @teacher [START 10-SQL003] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: Upsert Claims จำลองสามรายพร้อม Attributes ต่างกันใน metadata
-- @teacher ผล/ชวนสังเกต: การรันซ้ำจะคืน Status/Description/Metadata ของ MOD-001 ถึง 003 ตาม Seed
-- @teacher SOURCE: 10-modern-features-supabase.sql:18 | รัน SQL นี้ครบทั้ง Statement
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
-- @teacher [END 10-SQL003]

\echo '\n-- Lab 10A: JSONB evolve-without-migration data'
-- @teacher [START 10-SQL004] Lab 10A | JSONB evolve-without-migration data
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: เพิ่ม assessment.priority ให้ MOD-002 ด้วย jsonb_set โดยไม่เพิ่ม Column
-- @teacher ผล/ชวนสังเกต: สร้าง Object assessment ตาม Path; updated_at เปลี่ยนด้วย Statement นี้ ไม่ใช่ Trigger อัตโนมัติ
-- @teacher SOURCE: 10-modern-features-supabase.sql:37 | รัน SQL นี้ครบทั้ง Statement
UPDATE lab_m10.claim_feature
SET metadata = jsonb_set(metadata, '{assessment}', '{"priority":"high"}'::jsonb, true),
    updated_at = clock_timestamp()
WHERE claim_no = 'MOD-002';
-- @teacher [END 10-SQL004]

-- @teacher [START 10-SQL005] Lab 10A | JSONB evolve-without-migration data
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: อ่าน JSON เป็น Text ด้วย ->>/#>> แล้ว Cast risk_score เป็น Integer
-- @teacher ผล/ชวนสังเกต: Path ที่ไม่มีคืน NULL; ค่าที่ไม่ใช่ตัวเลขจะทำให้ Cast Error จึงต้องมี Input Validation
-- @teacher SOURCE: 10-modern-features-supabase.sql:42 | รัน SQL นี้ครบทั้ง Statement
SELECT claim_no,
       metadata ->> 'channel' AS channel,
       metadata #>> '{assessment,priority}' AS priority,
       (metadata ->> 'risk_score')::integer AS risk_score
FROM lab_m10.claim_feature
ORDER BY claim_no;
-- @teacher [END 10-SQL005]

-- @teacher [START 10-SQL006] Lab 10A | JSONB evolve-without-migration data
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: สร้าง GIN ให้ตรงกับ JSONB Containment @>
-- @teacher ผล/ชวนสังเกต: jsonb_path_ops เน้น Containment ไม่ได้รองรับ Operator ทุกชนิด
-- @teacher SOURCE: 10-modern-features-supabase.sql:49 | รัน SQL นี้ครบทั้ง Statement
CREATE INDEX IF NOT EXISTS idx_claim_feature_metadata_gin
ON lab_m10.claim_feature USING gin (metadata jsonb_path_ops);
-- @teacher [END 10-SQL006]

-- @teacher [START 10-SQL007] Lab 10A | JSONB evolve-without-migration data
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: สร้าง Expression Index สำหรับ Provider ที่ Query แบบ Text เท่ากัน
-- @teacher ผล/ชวนสังเกต: ต้องใช้ Expression metadata->>'provider' ให้สัมพันธ์กับ Query; ไม่ใช่ทุก JSON Path ใช้ Index นี้
-- @teacher SOURCE: 10-modern-features-supabase.sql:52 | รัน SQL นี้ครบทั้ง Statement
CREATE INDEX IF NOT EXISTS idx_claim_feature_provider
ON lab_m10.claim_feature ((metadata ->> 'provider'));
-- @teacher [END 10-SQL007]

-- @teacher [START 10-SQL008] Lab 10A | JSONB evolve-without-migration data
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: เก็บ Planner Statistics ของ lab_m10.claim_feature หลังเตรียมหรือเปลี่ยนข้อมูล
-- @teacher ผล/ชวนสังเกต: ช่วยให้ Estimated Rows/Plan มีฐานข้อมูลล่าสุด; ไม่สร้าง Index และไม่ใช่ VACUUM เก็บ Dead Tuples
-- @teacher SOURCE: 10-modern-features-supabase.sql:55 | รัน SQL นี้ครบทั้ง Statement
ANALYZE lab_m10.claim_feature;
-- @teacher [END 10-SQL008]
-- @teacher [START 10-SQL009] Lab 10A | JSONB evolve-without-migration data
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: วัด Query JSONB บน Table ขนาดเล็กมาก
-- @teacher ผล/ชวนสังเกต: Seq Scan อาจเหมาะกว่า GIN เมื่อมีเพียง 3 แถว; ไม่บังคับปิด Seq Scan เพื่อให้กราฟดูดี
-- @teacher SOURCE: 10-modern-features-supabase.sql:56 | รัน SQL นี้ครบทั้ง Statement
EXPLAIN (ANALYZE, BUFFERS)
SELECT claim_no
FROM lab_m10.claim_feature
WHERE metadata @> '{"provider":"garage-a"}'::jsonb;
-- @teacher [END 10-SQL009]

\echo '\n-- Full-text search with a stored generated tsvector'
-- @teacher [START 10-SQL010] Lab Full-text Search | Full-text search with a stored generated tsvector
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: เพิ่ม Stored Generated tsvector จาก Description + Provider
-- @teacher ผล/ชวนสังเกต: simple เป็น Text Search Configuration ของตัวอย่าง; ไม่ใช่ Thai Word Segmentation ที่พร้อมใช้งานเอง
-- @teacher SOURCE: 10-modern-features-supabase.sql:62 | รัน SQL นี้ครบทั้ง Statement
ALTER TABLE lab_m10.claim_feature
ADD COLUMN IF NOT EXISTS search_document tsvector
GENERATED ALWAYS AS (
    to_tsvector('simple',
        coalesce(description, '') || ' ' || coalesce(metadata ->> 'provider', ''))
) STORED;
-- @teacher [END 10-SQL010]

-- @teacher [START 10-SQL011] Lab Full-text Search | Full-text search with a stored generated tsvector
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: ใช้ GIN รองรับ @@ บน search_document
-- @teacher ผล/ชวนสังเกต: เป็น Index ของเอกสารค้นหา ไม่ใช่ GIN บน JSONB เดียวกับข้อก่อน
-- @teacher SOURCE: 10-modern-features-supabase.sql:69 | รัน SQL นี้ครบทั้ง Statement
CREATE INDEX IF NOT EXISTS idx_claim_feature_search
ON lab_m10.claim_feature USING gin (search_document);
-- @teacher [END 10-SQL011]

-- @teacher [START 10-SQL012] Lab Full-text Search | Full-text search with a stored generated tsvector
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: แปลงคำค้นเป็น tsquery คัดแถวที่ตรง แล้วจัดอันดับ ts_rank
-- @teacher ผล/ชวนสังเกต: plainto_tsquery จับคำ urgent และ repair ตาม Configuration; MOD-002 ควรเป็นแถวที่ตรง
-- @teacher SOURCE: 10-modern-features-supabase.sql:72 | รัน SQL นี้ครบทั้ง Statement
SELECT claim_no,
       ts_rank(search_document, plainto_tsquery('simple', 'urgent repair')) AS rank
FROM lab_m10.claim_feature
WHERE search_document @@ plainto_tsquery('simple', 'urgent repair')
ORDER BY rank DESC;
-- @teacher [END 10-SQL012]

\echo '\n-- Declarative partitioning and lifecycle operations'
-- @teacher [START 10-SQL013] Lab Partitioning | Declarative partitioning and lifecycle operations
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: สร้าง Range-partitioned Event Parent พร้อม PK รวม occurred_at
-- @teacher ผล/ชวนสังเกต: Partition Key จำเป็นต่อความเป็นเอกลักษณ์ของ PK บน Parent แบบนี้
-- @teacher SOURCE: 10-modern-features-supabase.sql:79 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS lab_m10.claim_event (
    event_id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    occurred_at timestamptz NOT NULL,
    payload jsonb NOT NULL,
    PRIMARY KEY (event_id, occurred_at)
) PARTITION BY RANGE (occurred_at);
-- @teacher [END 10-SQL013]

-- @teacher [START 10-SQL014] Lab Partitioning | Declarative partitioning and lifecycle operations
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: เตรียม Partition Q1 ก่อนรับข้อมูลเดือน ม.ค.–มี.ค.
-- @teacher ผล/ชวนสังเกต: ช่วงบน 1 เม.ย. ไม่รวมอยู่ใน Partition นี้
-- @teacher SOURCE: 10-modern-features-supabase.sql:87 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS lab_m10.claim_event_2026_q1
PARTITION OF lab_m10.claim_event
FOR VALUES FROM ('2026-01-01 00:00+07') TO ('2026-04-01 00:00+07');
-- @teacher [END 10-SQL014]
-- @teacher [START 10-SQL015] Lab Partitioning | Declarative partitioning and lifecycle operations
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: เตรียม Partition Q2 ต่อจาก Q1
-- @teacher ผล/ชวนสังเกต: หากส่งข้อมูลไตรมาสอื่นโดยไม่เตรียม Partition จะ INSERT ไม่ได้
-- @teacher SOURCE: 10-modern-features-supabase.sql:90 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS lab_m10.claim_event_2026_q2
PARTITION OF lab_m10.claim_event
FOR VALUES FROM ('2026-04-01 00:00+07') TO ('2026-07-01 00:00+07');
-- @teacher [END 10-SQL015]

-- @teacher [START 10-SQL016] Lab Partitioning | Declarative partitioning and lifecycle operations
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: INSERT ผ่าน Parent ให้ PostgreSQL Route สอง Events ไป Q1/Q2
-- @teacher ผล/ชวนสังเกต: ON CONFLICT อ้าง Composite Key event_id/occurred_at; เวลาเดียวกันต่าง Tenant ไม่ได้แยก PK เพิ่มให้เอง
-- @teacher SOURCE: 10-modern-features-supabase.sql:94 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m10.claim_event(event_id, tenant_id, occurred_at, payload)
VALUES
    (1, 101, TIMESTAMPTZ '2026-02-01 10:00+07', '{"action":"created"}'),
    (2, 202, TIMESTAMPTZ '2026-05-01 11:00+07', '{"action":"approved"}')
ON CONFLICT (event_id, occurred_at) DO UPDATE SET payload = EXCLUDED.payload;
-- @teacher [END 10-SQL016]

-- @teacher [START 10-SQL017] Lab Partitioning | Declarative partitioning and lifecycle operations
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: ใช้ Time Predicate ช่วง Q2 เพื่อตรวจ Partition Pruning
-- @teacher ผล/ชวนสังเกต: ควรเห็นเฉพาะ Partition ที่เกี่ยวข้องตาม Plan และได้ Event 2
-- @teacher SOURCE: 10-modern-features-supabase.sql:100 | รัน SQL นี้ครบทั้ง Statement
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab_m10.claim_event
WHERE occurred_at >= TIMESTAMPTZ '2026-04-01 00:00+07'
  AND occurred_at <  TIMESTAMPTZ '2026-07-01 00:00+07';
-- @teacher [END 10-SQL017]

-- @teacher [START 10-SQL018] Lab Partitioning | Declarative partitioning and lifecycle operations
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: พิสูจน์การกระจายแถวจริงด้วย tableoid
-- @teacher ผล/ชวนสังเกต: แต่ละ Partition มี 1 แถวจาก Fixture; Lifecycle DROP/DETACH ด้านล่างยังเป็น Comment ไม่ได้รัน
-- @teacher SOURCE: 10-modern-features-supabase.sql:105 | รัน SQL นี้ครบทั้ง Statement
SELECT tableoid::regclass AS partition_name, count(*) AS rows
FROM lab_m10.claim_event
GROUP BY tableoid
ORDER BY tableoid::regclass::text;
-- @teacher [END 10-SQL018]

-- Lifecycle examples; review retention policy before executing:
-- ALTER TABLE lab_m10.claim_event DETACH PARTITION lab_m10.claim_event_2026_q1;
-- DROP TABLE lab_m10.claim_event_2026_q1;

\echo '\n-- Vector similarity when pgvector is installed'
-- @teacher [START 10-SQL019] Lab Vector Search | Vector similarity when pgvector is installed
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: ตรวจ Extension vector ก่อนทำ Branch ตัวอย่าง Vector Search
-- @teacher ผล/ชวนสังเกต: ไม่ CREATE EXTENSION อัตโนมัติ; ถ้ายังไม่ได้ติดตั้งให้ข้ามตาม psql Branch
-- @teacher SOURCE: 10-modern-features-supabase.sql:115 | รัน SQL นี้ครบทั้ง Statement
SELECT EXISTS (SELECT FROM pg_extension WHERE extname = 'vector') AS has_vector \gset
-- @teacher [END 10-SQL019]
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :has_vector
-- @teacher [START 10-SQL020] Lab Vector Search | Vector similarity when pgvector is installed
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: สร้าง Embedding Fixture ขนาด 3 มิติสำหรับอธิบาย Distance
-- @teacher ผล/ชวนสังเกต: เป็นเวกเตอร์สังเคราะห์ ไม่ใช่ Embeddings จากเอกสารจริงหรือมิติของ Model Production
-- @teacher SOURCE: 10-modern-features-supabase.sql:117 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS lab_m10.claim_embedding (
    claim_id bigint PRIMARY KEY,
    embedding vector(3) NOT NULL
);
-- @teacher [END 10-SQL020]
-- @teacher [START 10-SQL021] Lab Vector Search | Vector similarity when pgvector is installed
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: Upsert ตัวอย่างเวกเตอร์ 3 แถว
-- @teacher ผล/ชวนสังเกต: ยังไม่มี Tenant Column/RLS ใน Table นี้; อย่าใช้เป็นตัวอย่าง Tenant-safe Search โดยไม่เพิ่มการควบคุม
-- @teacher SOURCE: 10-modern-features-supabase.sql:121 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m10.claim_embedding(claim_id, embedding)
VALUES
    (1, '[0.10,0.20,0.30]'),
    (2, '[0.12,0.18,0.33]'),
    (3, '[0.90,0.10,0.05]')
ON CONFLICT (claim_id) DO UPDATE SET embedding = EXCLUDED.embedding;
-- @teacher [END 10-SQL021]

-- @teacher [START 10-SQL022] Lab Vector Search | Vector similarity when pgvector is installed
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: คำนวณ Cosine Distance ด้วย <=> แล้วเรียงจากน้อยไปมาก
-- @teacher ผล/ชวนสังเกต: ใกล้ query vector มากกว่าจะอยู่ก่อน; ไม่ใช่ Probability และยังไม่ได้สร้าง ANN Index
-- @teacher SOURCE: 10-modern-features-supabase.sql:128 | รัน SQL นี้ครบทั้ง Statement
SELECT claim_id, embedding <=> '[0.11,0.19,0.31]'::vector AS cosine_distance
FROM lab_m10.claim_embedding
ORDER BY cosine_distance
LIMIT 3;
-- @teacher [END 10-SQL022]
-- @teacher PSQL: Branch ทางเลือกของ psql; ไม่เลือก Execute ทั้งสอง Branch ใน SQL Editor
\else
\echo 'pgvector is not installed; vector section skipped.'
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif

\echo '\n-- Supabase-style JWT context + RLS readiness'
-- @teacher [START 10-SQL023] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: สร้าง Profile Fixture เพื่อจำลอง Owner-based RLS
-- @teacher ผล/ชวนสังเกต: owner_id เป็น UUID จำลอง ไม่ใช่ Foreign Key ที่ยืนยันตัวตนกับ auth.users
-- @teacher SOURCE: 10-modern-features-supabase.sql:137 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS lab_m10.profile (
    profile_id uuid PRIMARY KEY,
    owner_id uuid NOT NULL,
    display_name text NOT NULL
);
-- @teacher [END 10-SQL023]

-- @teacher [START 10-SQL024] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: Seed Alice/Bob ที่มี Owner ต่างกัน
-- @teacher ผล/ชวนสังเกต: มี 2 แถวก่อน RLS; ต้องดูผ่าน Runtime Role จึงพิสูจน์การจำกัดแถวได้
-- @teacher SOURCE: 10-modern-features-supabase.sql:143 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m10.profile(profile_id, owner_id, display_name)
VALUES
    ('00000000-0000-0000-0000-000000000001',
     'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Alice'),
    ('00000000-0000-0000-0000-000000000002',
     'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Bob')
ON CONFLICT (profile_id) DO UPDATE SET display_name = EXCLUDED.display_name;
-- @teacher [END 10-SQL024]

-- @teacher [START 10-SQL025] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: สร้าง NOLOGIN Runtime Role หากยังไม่มี
-- @teacher ผล/ชวนสังเกต: ต้องใช้ postgres/CREATEROLE และสิทธิ์ SET ROLE ที่เหมาะสม; Role ชื่อนี้เป็นระดับ Cluster และไม่ใช่ Auth User
-- @teacher SOURCE: 10-modern-features-supabase.sql:151 | รัน SQL นี้ครบทั้ง Statement
DO $block$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lab_m10_authenticated') THEN
        CREATE ROLE lab_m10_authenticated NOLOGIN;
    END IF;
END
$block$;
-- @teacher [END 10-SQL025]

-- @teacher [START 10-SQL026] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: อนุญาต Runtime Role ให้ค้น Objects ใน Schema
-- @teacher ผล/ชวนสังเกต: USAGE ไม่ได้ให้ SELECT Table ตามไปด้วย จึงต้องมี Grant ถัดไป
-- @teacher SOURCE: 10-modern-features-supabase.sql:159 | รัน SQL นี้ครบทั้ง Statement
GRANT USAGE ON SCHEMA lab_m10 TO lab_m10_authenticated;
-- @teacher [END 10-SQL026]
-- @teacher [START 10-SQL027] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: ให้ Runtime Role อ่านเฉพาะ Profile Table
-- @teacher ผล/ชวนสังเกต: Table Grant เปิด Operation; RLS จะกรองว่าเห็นแถวใด
-- @teacher SOURCE: 10-modern-features-supabase.sql:160 | รัน SQL นี้ครบทั้ง Statement
GRANT SELECT ON lab_m10.profile TO lab_m10_authenticated;
-- @teacher [END 10-SQL027]
-- @teacher [START 10-SQL028] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: เปิด RLS บน Profile
-- @teacher ผล/ชวนสังเกต: การเปิดอย่างเดียวไม่มี Policy จะได้ Default Deny สำหรับ Role ที่อยู่ใต้ RLS
-- @teacher SOURCE: 10-modern-features-supabase.sql:161 | รัน SQL นี้ครบทั้ง Statement
ALTER TABLE lab_m10.profile ENABLE ROW LEVEL SECURITY;
-- @teacher [END 10-SQL028]
-- @teacher [START 10-SQL029] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: ให้เจ้าของ Table อยู่ใต้ RLS ด้วย
-- @teacher ผล/ชวนสังเกต: FORCE ไม่ได้หยุด Superuser/BYPASSRLS; ต้องทดสอบหลัง SET ROLE ไป Runtime ที่ไม่พิเศษ
-- @teacher SOURCE: 10-modern-features-supabase.sql:162 | รัน SQL นี้ครบทั้ง Statement
ALTER TABLE lab_m10.profile FORCE ROW LEVEL SECURITY;
-- @teacher [END 10-SQL029]
-- @teacher [START 10-SQL030] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: ลบเฉพาะ Policy ตัวอย่างเดิมเพื่อให้รันสร้างกฎซ้ำได้
-- @teacher ผล/ชวนสังเกต: การลบ Policy ไม่ลบ Table Data แต่เปลี่ยนกฎการเข้าถึงทันที
-- @teacher SOURCE: 10-modern-features-supabase.sql:163 | รัน SQL นี้ครบทั้ง Statement
DROP POLICY IF EXISTS profile_owner_select ON lab_m10.profile;
-- @teacher [END 10-SQL030]
-- @teacher [START 10-SQL031] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: สร้าง SELECT Policy เทียบ owner_id กับ Subject จาก Custom GUC
-- @teacher ผล/ชวนสังเกต: นี่เป็นการจำลอง Context ที่ผู้สอนตั้งเอง ไม่ใช่การตรวจลายเซ็น JWT; Production ต้องให้ Trusted Gateway สร้าง Context
-- @teacher SOURCE: 10-modern-features-supabase.sql:164 | รัน SQL นี้ครบทั้ง Statement
CREATE POLICY profile_owner_select ON lab_m10.profile
FOR SELECT
USING (owner_id::text = current_setting('request.jwt.claim.sub', true));
-- @teacher [END 10-SQL031]

-- @teacher [START 10-SQL032] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: ตั้ง Subject จำลองเป็น Alice ระดับ Session เพื่อใช้ข้าม Statement
-- @teacher ผล/ชวนสังเกต: false หมายถึงไม่ใช่ Transaction-local; Context ยังค้างหลัง RESET ROLE และต้อง RESET หลังสาธิต
-- @teacher SOURCE: 10-modern-features-supabase.sql:168 | รัน SQL นี้ครบทั้ง Statement
SELECT set_config('request.jwt.claim.sub',
                  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
-- @teacher [END 10-SQL032]
-- @teacher [START 10-SQL033] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: เปลี่ยน Effective Role ไป Role ที่ถูกจำกัด เพื่อให้ RLS มีผลจริง
-- @teacher ผล/ชวนสังเกต: session_user เดิมยังเป็น Teacher; นี่ไม่ใช่การ Login ใหม่ผ่าน Supabase Auth
-- @teacher SOURCE: 10-modern-features-supabase.sql:170 | รัน SQL นี้ครบทั้ง Statement
SET ROLE lab_m10_authenticated;
-- @teacher [END 10-SQL033]
-- @teacher [START 10-SQL034] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: session_user=postgres, current_user=lab_m10_authenticated | ฐานฝึกเดียวกัน
-- @teacher อธิบาย: อ่าน Profile ภายใต้ RLS ด้วย Subject ของ Alice
-- @teacher ผล/ชวนสังเกต: ควรเห็น Alice เพียงแถวเดียว; อย่ารัน SELECT นี้เป็น Superuser แล้วสรุปว่า RLS ใช้ไม่ได้
-- @teacher SOURCE: 10-modern-features-supabase.sql:171 | รัน SQL นี้ครบทั้ง Statement
SELECT * FROM lab_m10.profile ORDER BY profile_id;
-- @teacher [END 10-SQL034]
-- @teacher [START 10-SQL035] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: กลับไป Role เดิมหลังสาธิต
-- @teacher ผล/ชวนสังเกต: RESET ROLE ไม่ได้ล้าง Custom GUC request.jwt.claim.sub; หากจบ Session ให้ RESET ค่านั้นด้วยตนเอง
-- @teacher SOURCE: 10-modern-features-supabase.sql:172 | รัน SQL นี้ครบทั้ง Statement
RESET ROLE;
-- @teacher [END 10-SQL035]

\echo 'Expected: the authenticated role sees Alice only.'
-- @teacher [START 10-SQL036] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: อ่าน Extensions และเวอร์ชันที่ Database ติดตั้งจริง
-- @teacher ผล/ชวนสังเกต: แยก Availability ของ Feature ออกจากสิ่งที่ตัวอย่างข้ามไป
-- @teacher SOURCE: 10-modern-features-supabase.sql:175 | รัน SQL นี้ครบทั้ง Statement
SELECT extname, extversion
FROM pg_extension
ORDER BY extname;
-- @teacher [END 10-SQL036]

-- @teacher [START 10-SQL037] Lab JWT Context / RLS | Supabase-style JWT context + RLS readiness
-- @teacher LOGIN / DATABASE: postgres | ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง
-- @teacher อธิบาย: ตรวจ Flag RLS ของ Tables ใน Schema ตัวอย่าง
-- @teacher ผล/ชวนสังเกต: rowsecurity=true เป็นเพียงสถานะเปิด ไม่ใช่ผลทดสอบ Policy ครบทุก Operation
-- @teacher SOURCE: 10-modern-features-supabase.sql:179 | รัน SQL นี้ครบทั้ง Statement
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'lab_m10'
ORDER BY tablename;
-- @teacher [END 10-SQL037]
