\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $$ DECLARE n text; v text; BEGIN
 FOREACH n IN ARRAY ARRAY['lab_m4_shell','lab_m5_shell'] LOOP
  IF to_regnamespace(n) IS NOT NULL THEN
   IF (SELECT nspowner FROM pg_namespace WHERE nspname=n)<>(SELECT oid FROM pg_roles WHERE rolname=current_user)
      OR to_regclass(n||'.course_identity') IS NULL THEN
    RAISE EXCEPTION 'Unowned/unmarked course schema: %',n;
   END IF;
   EXECUTE format('SELECT identity FROM %I.course_identity WHERE id=1',n) INTO v;
   IF v IS DISTINCT FROM (CASE WHEN n='lab_m4_shell' THEN 'course-m4-v1' ELSE 'course-m5-v1' END) THEN
    RAISE EXCEPTION 'Invalid course marker: %',n;
   END IF;
  END IF;
 END LOOP;
END $$;
CREATE SCHEMA IF NOT EXISTS lab_m4_shell;
CREATE TABLE IF NOT EXISTS lab_m4_shell.course_identity(id int PRIMARY KEY CHECK(id=1),identity text CHECK(identity='course-m4-v1'));
INSERT INTO lab_m4_shell.course_identity VALUES(1,'course-m4-v1') ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS lab_m4_shell.claim_secure(id int PRIMARY KEY,tenant_id int,note text,amount numeric);
INSERT INTO lab_m4_shell.claim_secure VALUES(1,101,'ready',100),(2,101,'ready',200),(3,202,'ready',300) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS lab_m4_shell.claim_audit(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,actor text,operation text,claim_id int);
CREATE SCHEMA IF NOT EXISTS lab_m5_shell;
CREATE TABLE IF NOT EXISTS lab_m5_shell.course_identity(id int PRIMARY KEY CHECK(id=1),identity text CHECK(identity='course-m5-v1'));
INSERT INTO lab_m5_shell.course_identity VALUES(1,'course-m5-v1') ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS lab_m5_shell.claim(id int PRIMARY KEY,status text,amount numeric);
INSERT INTO lab_m5_shell.claim VALUES(1,'NEW',100),(2,'NEW',200) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS lab_m5_shell.event(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,batch text,payload text);
COMMIT;
