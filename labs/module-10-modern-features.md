# Module 10: เพิ่ม JSONB, Search, Events และ Data API ให้เคลมชุดเดิม

[กลับสารบัญ](README.md)

สำหรับ Supabase self-hosted บน Docker Compose พร้อม Auth / Data API / RLS จริง
ให้ใช้ [Docker Lab 10](DOCKER-LABS.md#lab-10--supabase-auth-and-rls) และ
[บทฝึก Data API + Authentication](../docs/tutorials/supabase-self-hosted/API-LAB.md)
ซึ่งใช้ Database แยกจากเคลมต่อเนื่องในบทนี้ เน้น Login แล้วเรียก API เห็นข้อมูลตาม Role/RLS พร้อมทดสอบด้วย curl

ใบงาน Markdown แบบทำทีละขั้นพร้อม expected results และหลักฐานส่งงานอยู่ที่ [Supabase Labs — SB0–SB10](module-10-supabase.md)

บท 9 ต้อง ROLLBACK ครบก่อน บทนี้ต่อยอด claim/customer/policy จริง ไม่สร้าง claim_feature หรือ profile ที่ไม่เชื่อมกับเคสเดิม metadata/description และ GIN มาจากบท 3; สูตรภาษี/view ยังใช้บท 2

## 10A — เก็บค่าของเคลมตั้งต้น แล้วเติมรายละเอียด JSON

```bash
export PGAPPNAME=case-m10
psql -X -v ON_ERROR_STOP=1
```

ใช้ psql session นี้ตลอด 10A–10H เพื่อเก็บ temporary backup สำหรับคืนค่า:

```sql
\pset pager off
\timing on
SET TIME ZONE 'Asia/Bangkok';
SELECT count(*) AS expected_100006 FROM claimsure.claim;
CREATE TEMP TABLE cs_m10_before AS
SELECT claim_id,description,metadata FROM claimsure.claim WHERE claim_no LIKE 'CLM-L1-%';
UPDATE claimsure.claim
SET description=CASE claim_no WHEN 'CLM-L1-002' THEN 'urgent repair vehicle accident'
 ELSE 'standard claim review' END,
 metadata=jsonb_build_object('channel','mobile','provider',
  CASE WHEN claim_no IN ('CLM-L1-001','CLM-L1-002') THEN 'garage-a' ELSE 'garage-b' END,
  'risk_score',CASE WHEN claim_no='CLM-L1-002' THEN 90 ELSE 20 END)
WHERE claim_no LIKE 'CLM-L1-%';
SELECT claim_no,customer_code,claimsure.claim_tax(estimated_amount,approved_amount) AS tax
FROM claimsure.claim_detail_v WHERE claim_no LIKE 'CLM-L1-%' ORDER BY claim_no;
```

หกเคลม/ยอด/กรมธรรม์ยังเดิม คอลัมน์ยืดหยุ่นใช้เก็บรายละเอียดเพิ่ม ไม่ย้ายยอดเงินหรือ FK หลักไปซ่อนใน JSON

## 10B — แก้ nested path และจับคู่ index/operator

```sql
UPDATE claimsure.claim
SET metadata=jsonb_set(metadata,'{assessment}','{"priority":"high"}'::jsonb,true)
WHERE claim_no='CLM-L1-002';
CREATE INDEX cs_claim_provider ON claimsure.claim((metadata->>'provider'));
ANALYZE claimsure.claim;
SELECT claim_no,metadata#>>'{assessment,priority}' AS priority,
 (metadata->>'risk_score')::integer AS risk_score
FROM claimsure.claim WHERE claim_no LIKE 'CLM-L1-%' ORDER BY claim_no;
EXPLAIN (ANALYZE,BUFFERS)
SELECT claim_no FROM claimsure.claim WHERE metadata @> '{"provider":"garage-a"}';
EXPLAIN (ANALYZE,BUFFERS)
SELECT claim_no FROM claimsure.claim WHERE metadata->>'provider'='garage-a';
```

สอง query ต้องคืน CLM-L1-001/002 GIN cs_claim_metadata_gin ของบท 3 ใช้ containment ส่วน expression B-tree ใช้ ->> เท่ากับ อย่าคาดว่าดัชนีหนึ่งแทนได้ทุก operator

## 10C — Generated full-text column บน claim จริง

```sql
ALTER TABLE claimsure.claim ADD COLUMN search_document tsvector
GENERATED ALWAYS AS (to_tsvector('simple',coalesce(description,'')||' '||coalesce(metadata->>'provider',''))) STORED;
CREATE INDEX cs_claim_search_gin ON claimsure.claim USING gin(search_document);
SELECT claim_no,ts_rank(search_document,websearch_to_tsquery('simple','urgent repair')) AS rank
FROM claimsure.claim
WHERE claim_no LIKE 'CLM-L1-%'
 AND search_document @@ websearch_to_tsquery('simple','urgent repair') ORDER BY rank DESC;
```

เคลมตั้งต้นต้องได้ CLM-L1-002 ถ้าตัด WHERE CLM-L1-% ออกจะพบเคลม CLM-L3-* ที่มีคำเดียวกันด้วย generated column เปลี่ยนตาม source fields และ simple ไม่ได้ยืนยันคุณภาพการตัดคำภาษาไทย

## 10D — Events รายเดือนที่อ้างเคลมเดิม

สร้าง event projection จาก incident_at ของเคลมหกแถวจริง เดือนมกราคม/กุมภาพันธ์/มีนาคม 2026 ไม่สร้าง event ที่ไม่เกี่ยวกับเคส:

```sql
CREATE TABLE claimsure.cs_claim_event(
 claim_id bigint NOT NULL,policy_id bigint NOT NULL,event_time timestamptz NOT NULL,
 payload jsonb NOT NULL,PRIMARY KEY(claim_id,event_time)
) PARTITION BY RANGE(event_time);
CREATE TABLE claimsure.cs_claim_event_2026_01 PARTITION OF claimsure.cs_claim_event
FOR VALUES FROM ('2026-01-01 00:00+07') TO ('2026-02-01 00:00+07');
CREATE TABLE claimsure.cs_claim_event_2026_02 PARTITION OF claimsure.cs_claim_event
FOR VALUES FROM ('2026-02-01 00:00+07') TO ('2026-03-01 00:00+07');
CREATE TABLE claimsure.cs_claim_event_2026_03 PARTITION OF claimsure.cs_claim_event
FOR VALUES FROM ('2026-03-01 00:00+07') TO ('2026-04-01 00:00+07');
INSERT INTO claimsure.cs_claim_event
SELECT claim_id,policy_id,incident_at,jsonb_build_object('claim_no',claim_no,'status',status,'estimated_amount',estimated_amount)
FROM claimsure.claim WHERE claim_no LIKE 'CLM-L1-%';
SELECT tableoid::regclass,count(*) FROM claimsure.cs_claim_event GROUP BY tableoid ORDER BY 1;
EXPLAIN (ANALYZE,BUFFERS)
SELECT * FROM claimsure.cs_claim_event WHERE event_time >= '2026-02-01 00:00+07' AND event_time < '2026-03-01 00:00+07';
CREATE TABLE claimsure.cs_claim_event_2026_04 PARTITION OF claimsure.cs_claim_event
FOR VALUES FROM ('2026-04-01 00:00+07') TO ('2026-05-01 00:00+07');
BEGIN;
ALTER TABLE claimsure.cs_claim_event DETACH PARTITION claimsure.cs_claim_event_2026_01;
SELECT count(*) AS expected_4 FROM claimsure.cs_claim_event;
SELECT count(*) AS expected_2 FROM claimsure.cs_claim_event_2026_01;
ROLLBACK;
SELECT count(*) AS expected_6 FROM claimsure.cs_claim_event;
```

เดือนละสอง events; detach ไม่ลบแถว และ ROLLBACK คืน parent ให้ครบหก Events/report/embeddings เป็นผลอนุพันธ์ ต้องกำหนดวิธี sync/refresh หลังแก้ไขหรือ restore claim ไม่อ้างว่า INSERT projection ครั้งเดียวคือ audit history อัตโนมัติ

## 10E — Optional vector จากเอกสารของเคลมเดิม

อาจารย์ติดตั้ง pgvector ที่อนุมัติไว้ก่อน ส่วนนี้ข้ามได้เมื่อไม่มี extension ตัวเลข vector เป็น toy data ไม่ได้เรียก embedding model จริง:

```sql
SELECT EXISTS(SELECT FROM pg_extension WHERE extname='vector') AS has_vector \gset

\if :has_vector

SELECT format('SET search_path=pg_catalog,claimsure,%I',n.nspname)
FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace WHERE e.extname='vector' \gexec

CREATE TABLE claimsure.cs_claim_embedding(claim_id bigint PRIMARY KEY,embedding vector(3));
INSERT INTO claimsure.cs_claim_embedding
SELECT claim_id,CASE claim_no
 WHEN 'CLM-L1-001' THEN '[0.10,0.20,0.30]'::vector
 WHEN 'CLM-L1-002' THEN '[0.12,0.18,0.33]'::vector
 ELSE '[0.90,0.10,0.05]'::vector END
FROM claimsure.claim WHERE claim_no IN ('CLM-L1-001','CLM-L1-002','CLM-L1-005');
CREATE INDEX cs_claim_embedding_hnsw ON claimsure.cs_claim_embedding USING hnsw(embedding vector_cosine_ops);
SELECT c.claim_no,u.customer_code,e.embedding <=> '[0.11,0.19,0.31]'::vector AS distance
FROM claimsure.cs_claim_embedding e JOIN claimsure.claim c USING(claim_id)
JOIN claimsure.policy p USING(policy_id) JOIN claimsure.customer u USING(customer_id)
WHERE u.customer_code='CUS-001'
ORDER BY e.embedding <=> '[0.11,0.19,0.31]'::vector LIMIT 2;
RESET search_path;

\else

\echo 'SKIPPED: pgvector not installed.'
\endif
```

ต้องได้เฉพาะ 001/002 ของ CUS-001 เอกสาร/query จริงต้องใช้ embedding model และ dimension เดียวกัน HNSW เป็น approximate และการ JOIN/filter ไม่แทน RLS; หากเปิด embedding table ผ่าน API ต้องมี policy ของตารางนั้นด้วย

## 10F.0 — Instructor เตรียม NOLOGIN API role

แทน xx ด้วยหมายเลขสองหลักของนักเรียนที่ได้รับมอบหมาย:

```bash
psql -X -W -h 127.0.0.1 -p 5432 -U postgres -d claimsure_xx -v student_no=xx -v ON_ERROR_STOP=1
```

```sql
SELECT 'cs_api_'||:'student_no' AS api_role,'student_'||:'student_no' AS student_role \gset
CREATE ROLE :"api_role" NOLOGIN NOSUPERUSER NOCREATEROLE NOBYPASSRLS;
GRANT :"api_role" TO :"student_role" WITH INHERIT FALSE, SET TRUE;
```

## 10F.1 — Student จำลอง JWT subjects ผูกกับ customer เดิม

กลับ psql student เดิมจาก 10A ไม่ทำส่วนนี้ใน postgres ของอาจารย์ กำหนด subject A เป็น CUS-001 และ B เป็น CUS-002 ใน transaction เพื่อคืน policy/privileges เมื่อจบ:

```sql
SELECT 'cs_api_'||right(session_user,2) AS api_role \gset

BEGIN;
CREATE TABLE claimsure.cs_customer_subject(customer_id bigint PRIMARY KEY,subject_id uuid UNIQUE NOT NULL);
INSERT INTO claimsure.cs_customer_subject
SELECT customer_id,CASE customer_code WHEN 'CUS-001' THEN 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid
 ELSE 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid END
FROM claimsure.customer WHERE customer_code IN ('CUS-001','CUS-002');
CREATE FUNCTION claimsure.cs_allowed_policies() RETURNS SETOF bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,claimsure AS $$
 SELECT p.policy_id FROM claimsure.policy p
 JOIN claimsure.cs_customer_subject s USING(customer_id)
 WHERE s.subject_id=(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid
$$;
REVOKE ALL ON FUNCTION claimsure.cs_allowed_policies() FROM PUBLIC;
GRANT USAGE ON SCHEMA claimsure TO :"api_role";
GRANT EXECUTE ON FUNCTION claimsure.cs_allowed_policies() TO :"api_role";
GRANT SELECT ON claimsure.claim TO :"api_role";
ALTER TABLE claimsure.claim ENABLE ROW LEVEL SECURITY;
ALTER TABLE claimsure.claim FORCE ROW LEVEL SECURITY;
CREATE POLICY cs_api_customer ON claimsure.claim FOR SELECT TO :"api_role"
USING(policy_id IN (SELECT claimsure.cs_allowed_policies()));
SET LOCAL ROLE :"api_role";
SELECT set_config('request.jwt.claims','{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}',true);
SELECT claim_no FROM claimsure.claim WHERE claim_no LIKE 'CLM-L1-%' ORDER BY claim_no;
SELECT set_config('request.jwt.claims','{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}',true);
SELECT claim_no FROM claimsure.claim WHERE claim_no LIKE 'CLM-L1-%' ORDER BY claim_no;
SELECT set_config('request.jwt.claims','{}',true);
SELECT count(*) AS expected_0 FROM claimsure.claim;
ROLLBACK;
```

A เห็น 001–004, B เห็น 005–006, ไม่มี sub เห็น 0 แถว เป็นเพียง **context simulation** ไม่ verify token นักเรียนปลอม GUC ได้ ระบบจริงต้องให้ gateway ตรวจ signature และส่ง context ที่เชื่อถือได้ SECURITY DEFINER ถูกจำกัด search_path/EXECUTE และคืนเฉพาะ policy IDs ของ subject ไม่เปิดตาราง mapping ทั้งก้อน

## 10G — Optional Supabase จริง: เผยแพร่ snapshot เคลมจากบท 1

ใช้เฉพาะ project ฝึกที่ได้รับมอบหมาย API แยกจาก claimsure_xx ตัวอย่างนำหกเคลมเดิมไปยัง table ที่มี owner_id ชัดเจน เป็น snapshot สำหรับทดสอบ auth.uid ไม่อ้างว่า sync กับ shared อัตโนมัติ

**ค้าง psql student จาก 10A ไว้** เพื่อเก็บ cs_m10_before เปิด Terminal ใหม่ ตั้ง environment/รหัสผ่าน shared ตาม README แล้ว **Bash ใน Terminal ใหม่** export หกเคลมและอ่าน project credentials:

```bash
psql -X -v ON_ERROR_STOP=1 -c "\copy (SELECT claim_no,status,estimated_amount FROM claimsure.claim WHERE claim_no LIKE 'CLM-L1-%' ORDER BY claim_no) TO '$HOME/case-labs/claims-api.csv' WITH (FORMAT csv, HEADER true)"
read -r -s -p "Supabase project DB URL: " SUPABASE_DB_URL
printf '\n'
read -r -p "UUID of your authenticated test user: " REAL_USER_ID
psql -X "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1
```

**psql project:**

```sql
CREATE TABLE public.course_claim(claim_no text PRIMARY KEY,owner_id uuid NOT NULL,status text,estimated_amount numeric);
ALTER TABLE public.course_claim ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.course_claim TO authenticated;
CREATE POLICY course_claim_owner ON public.course_claim FOR SELECT TO authenticated USING(auth.uid()=owner_id);
```

ออก \q แล้ว **Bash** import ผ่าน TEMP staging ใน connection เดียวกัน:

```bash
psql -X "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -v real_user_id="$REAL_USER_ID" \
 -c 'CREATE TEMP TABLE staged_claim(claim_no text,status text,estimated_amount numeric);' \
 -c "\copy staged_claim FROM '$HOME/case-labs/claims-api.csv' WITH (FORMAT csv, HEADER true)" -f - <<'SQL'
INSERT INTO public.course_claim(claim_no,owner_id,status,estimated_amount)
SELECT claim_no,:'real_user_id'::uuid,status,estimated_amount FROM staged_claim;
SQL
read -r -p "Project URL (https://PROJECT.supabase.co): " SUPABASE_URL
read -r -s -p "Publishable/anon key: " SUPABASE_PUBLIC_KEY
printf '\n'
read -r -s -p "Authenticated user access token: " SUPABASE_ACCESS_TOKEN
printf '\n'
curl -fsS "$SUPABASE_URL/rest/v1/course_claim?select=claim_no,status,estimated_amount&order=claim_no" \
 -H "apikey: $SUPABASE_PUBLIC_KEY" -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN"
```

ต้องได้หกเคลมของ user UUID ที่ใส่ไว้ เปลี่ยน token เป็นผู้ใช้ทดสอบคนอื่นต้องไม่เห็นแถวเหล่านี้ ไม่ใช้ service-role key เป็น token ทดสอบ เมื่อจบใช้ project connection เดิม `DROP TABLE public.course_claim;` เฉพาะตารางฝึกนี้ แล้ว unset credentials:

```bash
unset SUPABASE_DB_URL SUPABASE_PUBLIC_KEY SUPABASE_ACCESS_TOKEN REAL_USER_ID
```

## 10H — ส่งต่อหรือคืนส่วนขยายของบท 10

หากคงส่วนขยายไว้ให้บันทึก DDL และ backup plan ใหม่ หากต้องการคืน state ก่อน 10A ให้ใช้ **student psql session เดิมที่ยังมี cs_m10_before** ส่วน 10G ใช้อีก Terminal จึงไม่ปิด connection student นี้:

```sql
ROLLBACK;
RESET ROLE;
DROP TABLE IF EXISTS claimsure.cs_claim_event,claimsure.cs_claim_embedding;
DROP INDEX IF EXISTS claimsure.cs_claim_provider;
ALTER TABLE claimsure.claim DROP COLUMN search_document;
UPDATE claimsure.claim c SET metadata=b.metadata,description=b.description
FROM cs_m10_before b WHERE c.claim_id=b.claim_id;
SELECT count(*) AS expected_100006 FROM claimsure.claim;
SELECT count(*) AS expected_6 FROM claimsure.claim_detail_v WHERE claim_no LIKE 'CLM-L1-%';
SELECT relrowsecurity,relforcerowsecurity FROM pg_class WHERE oid='claimsure.claim'::regclass;
```

คง metadata/description และ indexes บท 3 ไว้ DROP COLUMN ของบทนี้ถอด search index ที่ผูกไว้ด้วย ไม่มี DROP ตารางหลัก อาจารย์กลับ connection 10F.0 เพื่อลบ role ที่ไม่มี grants เหลือหลัง ROLLBACK:

```sql
DROP ROLE :"api_role";
```

อ้างอิง: [JSONB](https://www.postgresql.org/docs/18/datatype-json.html), [pgvector](https://github.com/pgvector/pgvector), [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
