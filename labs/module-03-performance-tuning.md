# Module 3: ทำให้รายงานเคลมจากบท 2 รองรับข้อมูลมากขึ้น

[กลับสารบัญ](README.md)

ทำบท 1–2 ครบก่อน บทนี้เพิ่มแถวใน **claimsure.claim จริง** กรมธรรม์และลูกค้ายังคงชุดเดิม ไม่สร้าง claim_perf แยก ใช้ Bash/environment จาก README แล้วเปิด psql:

```bash
export PGAPPNAME=case-m3
psql -X -v ON_ERROR_STOP=1
```

## 3A — ตรวจข้อมูลที่รับต่อ

```sql
\pset pager off
\timing on
SET TIME ZONE 'Asia/Bangkok';
SELECT customer_code,policy_no,claim_no,status,
       claimsure.claim_tax(estimated_amount,approved_amount) AS tax
FROM claimsure.claim_detail_v
WHERE claim_no LIKE 'CLM-L1-%' ORDER BY claim_no;
SELECT count(*) AS starter_claims FROM claimsure.claim WHERE claim_no LIKE 'CLM-L1-%';
```

ต้องมี 6 เคลม และ CLM-L1-001 เป็น REVIEW หลัง 1D หากยังไม่มี view/function ให้ทำบท 2 ก่อน

## 3B — ขยายเคลมจากแม่แบบเดิม 100,000 แถว

เพิ่มคอลัมน์รายละเอียดสำหรับรายงานและบท 10; ไม่เปลี่ยน PK/FK หรือค่าเคลมเดิม ใช้ temporary table เก็บแม่แบบ 6 แถวใน psql session นี้:

```sql
ALTER TABLE claimsure.claim ADD COLUMN IF NOT EXISTS description text NOT NULL DEFAULT '';
ALTER TABLE claimsure.claim ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}';
CREATE TEMP TABLE cs_m3_template AS
SELECT row_number() OVER (ORDER BY claim_no) AS template_no,
       policy_id,status,estimated_amount,approved_amount
FROM claimsure.claim WHERE claim_no LIKE 'CLM-L1-%';
SELECT count(*)=6 AS six_templates FROM cs_m3_template;

INSERT INTO claimsure.claim
 (claim_no,policy_id,status,incident_at,estimated_amount,approved_amount,description,metadata)
SELECT 'CLM-L3-'||lpad(g::text,6,'0'),t.policy_id,t.status,
       TIMESTAMPTZ '2026-01-01 00:00+07' + (g%129600)*interval '1 minute',
       t.estimated_amount+(g%1000),t.approved_amount,
       CASE WHEN g%20=0 THEN 'urgent repair vehicle accident ' ELSE 'standard claim review ' END
         ||repeat(md5(g::text),6),
       jsonb_build_object('source','module3','channel',
         (ARRAY['web','mobile','agent'])[1+(g%3)],'risk_score',g%100)
FROM generate_series(1,100000) g
JOIN cs_m3_template t ON t.template_no=1+((g-1)%6)
ON CONFLICT(claim_no) DO NOTHING;
ANALYZE claimsure.claim;
SELECT count(*) AS total_claims,
       count(*) FILTER(WHERE claim_no LIKE 'CLM-L1-%') AS original,
       count(*) FILTER(WHERE claim_no LIKE 'CLM-L3-%') AS added
FROM claimsure.claim;
SELECT customer_code,count(*) FROM claimsure.claim_detail_v GROUP BY customer_code ORDER BY 1;
```

ฐานข้อมูลเริ่มจากบท 1–2 ต้องได้ **100006 / 6 / 100000** view เดิมเห็นแถวใหม่อัตโนมัติ CUS-003 ยังไม่มีเคลม ON CONFLICT ช่วยไม่เพิ่มรหัสซ้ำ แต่ไม่ใช้แทนการคืนสถานะหลังการทดลอง

## 3C — รายงาน REVIEW ก่อนและหลัง covering index

อ่าน policy_id ของ POL-001 จากตารางเดิม ไม่เดา identity เป็น 1:

```sql
SELECT policy_id AS target_policy FROM claimsure.policy WHERE policy_no='POL-001';
DROP INDEX IF EXISTS claimsure.cs_claim_review_policy_time;
ANALYZE claimsure.claim;
EXPLAIN (ANALYZE,BUFFERS,SETTINGS)
SELECT claim_id,claim_no,incident_at,estimated_amount
FROM claimsure.claim
WHERE policy_id=(SELECT policy_id FROM claimsure.policy WHERE policy_no='POL-001')
  AND status='REVIEW'
ORDER BY incident_at DESC LIMIT 50;
CREATE INDEX cs_claim_review_policy_time ON claimsure.claim(policy_id,incident_at DESC)
INCLUDE(claim_id,claim_no,estimated_amount) WHERE status='REVIEW';
ANALYZE claimsure.claim;
EXPLAIN (ANALYZE,BUFFERS,SETTINGS)
SELECT claim_id,claim_no,incident_at,estimated_amount
FROM claimsure.claim
WHERE policy_id=(SELECT policy_id FROM claimsure.policy WHERE policy_no='POL-001')
  AND status='REVIEW'
ORDER BY incident_at DESC LIMIT 50;
```

รัน query เดิมอย่างน้อย 3 ครั้งต่อช่วง จด plan, buffers, rows และ median เวลา Index-only scan ขึ้นกับ visibility map ด้วย หากทำซ้ำทั้งบทต้องตรวจ index เดิมก่อน ไม่ DROP indexes ของงานอื่น

## 3D — จับคู่ index กับ operator

```sql
CREATE INDEX cs_claim_lower_no ON claimsure.claim(lower(claim_no));
CREATE INDEX cs_claim_metadata_gin ON claimsure.claim USING gin(metadata jsonb_path_ops);
CREATE INDEX cs_claim_time_brin ON claimsure.claim USING brin(incident_at) WITH(pages_per_range=32);
EXPLAIN (ANALYZE,BUFFERS)
SELECT claim_no FROM claimsure.claim WHERE lower(claim_no)=lower('CLM-L3-001000');
EXPLAIN (ANALYZE,BUFFERS)
SELECT count(*) FROM claimsure.claim WHERE metadata @> '{"channel":"mobile"}';
SELECT indexrelname,pg_size_pretty(pg_relation_size(indexrelid)) AS bytes,idx_scan
FROM pg_stat_user_indexes WHERE relid='claimsure.claim'::regclass ORDER BY indexrelname;
VACUUM (ANALYZE) claimsure.claim;
```

GIN ใช้กับ containment; BRIN เหมาะกับข้อมูลที่ลำดับ physical สัมพันธ์กับเวลา ให้ตรวจ correlation/plan ก่อนเลือกใช้ Query ที่คืนหลายแถวอาจเลือก sequential scan ได้ ไม่บังคับปิด sequential scan เพื่อให้เห็น index

## 3E — แยกรายงานรายเดือนจากเคลมชุดเดิม

```sql
CREATE TABLE claimsure.cs_claim_report (
 claim_id bigint NOT NULL,policy_id bigint NOT NULL,status text NOT NULL,
 incident_at timestamptz NOT NULL,estimated_amount numeric(14,2) NOT NULL,
 PRIMARY KEY(claim_id,incident_at)
) PARTITION BY RANGE(incident_at);
CREATE TABLE claimsure.cs_claim_report_2026_01 PARTITION OF claimsure.cs_claim_report
FOR VALUES FROM ('2026-01-01 00:00+07') TO ('2026-02-01 00:00+07');
CREATE TABLE claimsure.cs_claim_report_2026_02 PARTITION OF claimsure.cs_claim_report
FOR VALUES FROM ('2026-02-01 00:00+07') TO ('2026-03-01 00:00+07');
CREATE TABLE claimsure.cs_claim_report_2026_03 PARTITION OF claimsure.cs_claim_report
FOR VALUES FROM ('2026-03-01 00:00+07') TO ('2026-04-01 00:00+07');
INSERT INTO claimsure.cs_claim_report
SELECT claim_id,policy_id,status,incident_at,estimated_amount FROM claimsure.claim
WHERE incident_at >= '2026-01-01 00:00+07' AND incident_at < '2026-04-01 00:00+07';
ANALYZE claimsure.cs_claim_report;
EXPLAIN (ANALYZE,BUFFERS)
SELECT count(*),sum(estimated_amount) FROM claimsure.cs_claim_report
WHERE incident_at >= '2026-02-01 00:00+07' AND incident_at < '2026-03-01 00:00+07';
SELECT tableoid::regclass,count(*) FROM claimsure.cs_claim_report GROUP BY tableoid ORDER BY 1;
```

แถวรายงานมาจาก claim จริง แต่เป็นสำเนาสำหรับอ่าน การ UPDATE claim ภายหลังไม่เปลี่ยน report นี้อัตโนมัติ Plan เดือนกุมภาพันธ์ควร prune เดือนอื่น

## 3F — ต่อยอดสูตรภาษีบท 2 เป็น materialized view

```sql
CREATE MATERIALIZED VIEW claimsure.cs_monthly_claim_summary AS
SELECT date_trunc('month',incident_at AT TIME ZONE 'Asia/Bangkok')::date AS month_start,
       customer_code,status,count(*) AS claim_count,
       sum(claimsure.claim_tax(estimated_amount,approved_amount)) AS total_tax
FROM claimsure.claim_detail_v GROUP BY 1,2,3;
CREATE UNIQUE INDEX cs_monthly_claim_summary_key
ON claimsure.cs_monthly_claim_summary(month_start,customer_code,status);
SELECT sum(claim_count) AS summary_rows FROM claimsure.cs_monthly_claim_summary;
SELECT total_tax AS before_tax FROM claimsure.cs_monthly_claim_summary
WHERE month_start='2026-01-01' AND customer_code='CUS-001' AND status='REVIEW';
BEGIN;
UPDATE claimsure.claim SET estimated_amount=estimated_amount+100
WHERE claim_no='CLM-L1-001';
SELECT claimsure.claim_tax(estimated_amount,approved_amount) AS live_tax
FROM claimsure.claim WHERE claim_no='CLM-L1-001';
SELECT total_tax AS stale_tax FROM claimsure.cs_monthly_claim_summary
WHERE month_start='2026-01-01' AND customer_code='CUS-001' AND status='REVIEW';
REFRESH MATERIALIZED VIEW claimsure.cs_monthly_claim_summary;
SELECT * FROM claimsure.cs_monthly_claim_summary WHERE month_start='2026-01-01' ORDER BY customer_code,status;
ROLLBACK;
```

before_tax และ stale_tax เท่ากันแม้ live_tax เปลี่ยนแล้ว หลัง refresh ยอดกลุ่ม REVIEW/CUS-001 เดือนมกราคมเพิ่ม 7.00 จากยอดเคลม +100 หลัง ROLLBACK ทั้งยอดเคลมและ refresh กลับสถานะก่อนทดสอบ เก็บ table/index/คอลัมน์และข้อมูลนี้ไว้สำหรับบท 4–10

## ส่งต่อและทำซ้ำ

```sql
SELECT count(*) AS expected_100006 FROM claimsure.claim;
SELECT count(*) AS expected_6 FROM claimsure.claim_detail_v WHERE claim_no LIKE 'CLM-L1-%';
```

ไม่ลบ claim, customer, policy, view หรือ function หลังบทนี้ หากต้องเริ่มใหม่ให้ตรวจ objects cs_* ที่สร้างแล้วก่อน ไม่รัน CREATE ของเดิมซ้ำทั้งบท

อ้างอิง: [EXPLAIN](https://www.postgresql.org/docs/18/using-explain.html), [Indexes](https://www.postgresql.org/docs/18/indexes.html)
