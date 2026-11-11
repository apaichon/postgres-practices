# Module 4: ให้พนักงานเห็นเฉพาะเคลมของลูกค้าที่รับผิดชอบ

[กลับสารบัญ](README.md)

หากต้องการ Clone ข้อมูลไปยัง schema เฉพาะ แล้วทดลองสิทธิ์/เก็บผลจริงโดยไม่ใช้ ROLLBACK ให้เลือก [Module 4 — Clone schema และทดสอบ Login จริง](module-04-security-clone.md)

ต่อจากบท 3 ใช้ **claim/policy/customer และ claim_detail_v เดิม** ไม่สร้าง security_claim จำนวนเคลมรวมเพิ่มแล้ว จึงใช้ CLM-L1-* ตรวจผลที่รู้จัก บทนี้คืน RLS/ACL/audit ก่อนส่งต่อบท 5

## 4.0 — Instructor เตรียม roles ต่อหมายเลขนักเรียน

อาจารย์แทน xx ด้วยหมายเลขสองหลักของนักเรียนที่ได้รับมอบหมาย ทำครั้งเดียวด้วยบัญชี instructor:

```bash
psql -X -W -h 127.0.0.1 -p 5432 -U postgres -d claimsure_xx -v student_no=xx -v ON_ERROR_STOP=1
```

```sql
SELECT 'cs_reader_'||:'student_no' AS reader_role,
       'cs_actor_'||:'student_no' AS actor_role,
       'student_'||:'student_no' AS student_role \gset

CREATE ROLE :"reader_role" NOLOGIN NOSUPERUSER NOCREATEROLE NOBYPASSRLS;
CREATE ROLE :"actor_role" NOLOGIN NOSUPERUSER NOCREATEROLE NOBYPASSRLS;
GRANT :"reader_role" TO :"actor_role" WITH INHERIT TRUE, SET TRUE;
GRANT :"actor_role" TO :"student_role" WITH INHERIT FALSE, SET TRUE;
```

## 4A — Student ตรวจสิทธิ์ก่อนเปลี่ยน

กลับ Bash ของ student ตาม README:

```bash
export PGAPPNAME=case-m4
psql -X -v ON_ERROR_STOP=1
```

```sql
\pset pager off

\set VERBOSITY verbose

SELECT 'cs_reader_'||right(session_user,2) AS reader_role,
       'cs_actor_'||right(session_user,2) AS actor_role ;

SELECT c.customer_id AS customer_a FROM claimsure.customer c WHERE customer_code='CUS-001' ;

SELECT policy_id AS policy_a FROM claimsure.policy WHERE policy_no='POL-001' ;

SELECT policy_id AS policy_b FROM claimsure.policy WHERE policy_no='POL-003' ;

SELECT nspacl AS before_schema_acl FROM pg_namespace WHERE nspname='claimsure';
SELECT relacl,relrowsecurity,relforcerowsecurity FROM pg_class WHERE oid='claimsure.claim'::regclass;
```

ใช้ student ที่เป็นเจ้าของ objects ไม่ทดสอบ RLS ด้วย superuser หากมี RLS/GRANT จากงานอื่นอยู่แล้ว ให้ตรวจและทำให้การทดลองตรงกับสภาพจริงก่อน ไม่ลบ policy เดิมเพื่อให้ผลตรงตัวอย่าง

## 4B — Schema และ table เป็นคนละ gate

เปลี่ยนสิทธิ์ทั้งหมดใน transaction แล้วคืนด้วย ROLLBACK:

```sql
\set ON_ERROR_STOP off

BEGIN;
REVOKE USAGE ON SCHEMA claimsure FROM PUBLIC;
SET LOCAL ROLE :"actor_role";
SAVEPOINT schema_gate;
SELECT claim_no FROM claimsure.claim LIMIT 1;
ROLLBACK TO SAVEPOINT schema_gate;
RESET ROLE;
GRANT USAGE ON SCHEMA claimsure TO :"reader_role";
SET LOCAL ROLE :"actor_role";
SAVEPOINT table_gate;
SELECT claim_no FROM claimsure.claim LIMIT 1;
ROLLBACK TO SAVEPOINT table_gate;
RESET ROLE;
GRANT SELECT ON claimsure.claim TO :"reader_role";
SET LOCAL ROLE :"actor_role";
SELECT claim_no,status FROM claimsure.claim WHERE claim_no LIKE 'CLM-L1-%' ORDER BY claim_no;
ROLLBACK;
```

สอง error เป็น 42501 แต่ object ที่ขาดสิทธิ์ต่างกัน ครั้งสุดท้ายเห็นหกแถว สิทธิ์ schema เดิมและ grants ของ transaction นี้กลับคืนทั้งหมด

## 4C — Identity ไม่เหมือน bigserial ในเรื่อง sequence permission

claim_id เดิมเป็น GENERATED ALWAYS AS IDENTITY การ INSERT ผ่าน identity ไม่ต้อง GRANT USAGE sequence แยก ส่วนการเรียก nextval โดยตรงต้องมีสิทธิ์:

```sql
BEGIN;
GRANT USAGE ON SCHEMA claimsure TO :"reader_role";
GRANT SELECT ON claimsure.claim TO :"reader_role";
GRANT INSERT ON claimsure.claim TO :"actor_role";
SET LOCAL ROLE :"actor_role";
INSERT INTO claimsure.claim(claim_no,policy_id,status,incident_at,estimated_amount)
VALUES('CLM-SEC-DEMO',:policy_a,'NEW','2026-01-10 09:00+07',100) RETURNING claim_id;
SAVEPOINT direct_sequence;

\set ON_ERROR_STOP off

SELECT nextval('claimsure.claim_claim_id_seq');

\echo Expected direct nextval 42501; actual :SQLSTATE

ROLLBACK TO SAVEPOINT direct_sequence;

\set ON_ERROR_STOP on

RESET ROLE;
GRANT USAGE ON SEQUENCE claimsure.claim_claim_id_seq TO :"actor_role";
SET LOCAL ROLE :"actor_role";
SELECT nextval('claimsure.claim_claim_id_seq');
ROLLBACK;
```

ไม่มี CLM-SEC-DEMO หลัง ROLLBACK แต่ sequence อาจข้ามเลขได้ ไม่ reset sequence เพราะรหัสตัวเลขไม่จำเป็นต้องติดกัน และเคลมบทถัดไปอ้างผ่าน claim_no

## 4D — RLS ตาม customer ที่ถือกรมธรรม์

ใช้ customer_id จาก CUS-001 ที่อ่านใน 4A และ policy เดิม ต้องกรองได้สี่เคลมตั้งต้นของ CUS-001 และปฏิเสธการเพิ่มให้ POL-003 ของ CUS-002:

```sql
BEGIN;
GRANT USAGE ON SCHEMA claimsure TO :"reader_role";
GRANT SELECT ON claimsure.claim TO :"reader_role";
GRANT SELECT(policy_id,customer_id,policy_no,product_code) ON claimsure.policy TO :"reader_role";
GRANT SELECT(customer_id,customer_code,full_name) ON claimsure.customer TO :"reader_role";
GRANT SELECT ON claimsure.claim_detail_v TO :"reader_role";
GRANT INSERT ON claimsure.claim TO :"actor_role";
ALTER TABLE claimsure.claim ENABLE ROW LEVEL SECURITY;
ALTER TABLE claimsure.claim FORCE ROW LEVEL SECURITY;
CREATE POLICY cs_customer_access ON claimsure.claim
USING(policy_id IN (SELECT policy_id FROM claimsure.policy
 WHERE customer_id=nullif(current_setting('app.customer_id',true),'')::bigint))
WITH CHECK(policy_id IN (SELECT policy_id FROM claimsure.policy
 WHERE customer_id=nullif(current_setting('app.customer_id',true),'')::bigint));
ALTER VIEW claimsure.claim_detail_v SET(security_invoker=true);
SET LOCAL ROLE :"actor_role";
SELECT set_config('app.customer_id',:'customer_a',true);
SELECT customer_code,claim_no,status FROM claimsure.claim_detail_v
WHERE claim_no LIKE 'CLM-L1-%' ORDER BY claim_no;
SAVEPOINT wrong_customer;

\set ON_ERROR_STOP off

INSERT INTO claimsure.claim(claim_no,policy_id,status,incident_at,estimated_amount)
VALUES('CLM-SEC-WRONG',:policy_b,'NEW',now(),100);

\echo Expected RLS 42501; actual :SQLSTATE

ROLLBACK TO SAVEPOINT wrong_customer;

\set ON_ERROR_STOP on

ROLLBACK;
```

GUC app.customer_id เป็นการจำลอง context ไม่ใช่ authentication นักเรียนตั้งเองได้ ระบบจริงต้องรับตัวตนที่ server ตรวจแล้ว ROLLBACK คืน policy, FORCE/ENABLE RLS, security_invoker และ grants ทั้งหมด

## 4E — อนุญาตแก้ status พร้อม audit จากเคลมเดิม

```sql
BEGIN;
GRANT USAGE ON SCHEMA claimsure TO :"reader_role";
GRANT SELECT ON claimsure.claim TO :"reader_role";
GRANT UPDATE(status) ON claimsure.claim TO :"actor_role";
CREATE TABLE claimsure.cs_claim_audit(
 audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 claim_id bigint NOT NULL,old_status text,new_status text,login_name text
);
CREATE FUNCTION claimsure.cs_audit_claim() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,claimsure AS $$
BEGIN
 INSERT INTO claimsure.cs_claim_audit(claim_id,old_status,new_status,login_name)
 VALUES(NEW.claim_id,OLD.status,NEW.status,session_user);
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION claimsure.cs_audit_claim() FROM PUBLIC;
CREATE TRIGGER cs_claim_status_audit AFTER UPDATE OF status ON claimsure.claim
FOR EACH ROW EXECUTE FUNCTION claimsure.cs_audit_claim();
SET LOCAL ROLE :"actor_role";
UPDATE claimsure.claim SET status='APPROVED' WHERE claim_no='CLM-L1-001';
SAVEPOINT forbidden_column;

\set ON_ERROR_STOP off

UPDATE claimsure.claim SET estimated_amount=0 WHERE claim_no='CLM-L1-001';

\echo Expected column 42501; actual :SQLSTATE

ROLLBACK TO SAVEPOINT forbidden_column;

\set ON_ERROR_STOP on

RESET ROLE;
TABLE claimsure.cs_claim_audit;
ROLLBACK;
```

audit ได้หนึ่งแถว REVIEW → APPROVED แต่ ROLLBACK คืนเคลมเป็น REVIEW และถอด table/function/trigger ทดลอง จึงไม่ติด trigger ไปทำ WAL/restore ในบทอื่น

## 4F — Default privileges และการส่งต่อ

```sql
BEGIN;
GRANT USAGE ON SCHEMA claimsure TO :"reader_role";
ALTER DEFAULT PRIVILEGES IN SCHEMA claimsure GRANT SELECT ON TABLES TO :"reader_role";
CREATE TABLE claimsure.cs_future_claim_note(note text);
INSERT INTO claimsure.cs_future_claim_note VALUES('claim review note');
SET LOCAL ROLE :"actor_role";
TABLE claimsure.cs_future_claim_note;
ROLLBACK;
SELECT relacl,relrowsecurity,relforcerowsecurity FROM pg_class WHERE oid='claimsure.claim'::regclass;
SELECT nspacl AS restored_schema_acl FROM pg_namespace WHERE nspname='claimsure';
SELECT count(*) AS expected_100006 FROM claimsure.claim;
```

default privileges ของเจ้าของและ schema ACL ต้องตรงก่อนเริ่ม ทุก transaction จบแล้ว **Instructor** กลับ connection 4.0 เพื่อลบเฉพาะ roles ที่เตรียม:

```sql
DROP ROLE :"actor_role";
DROP ROLE :"reader_role";
```

ไม่ DROP OWNED หรือ DROP SCHEMA บท 5 ใช้ claim และ view เดิมต่อ

อ้างอิง: [Identity columns](https://www.postgresql.org/docs/18/ddl-identity-columns.html), [RLS](https://www.postgresql.org/docs/18/ddl-rowsecurity.html)
