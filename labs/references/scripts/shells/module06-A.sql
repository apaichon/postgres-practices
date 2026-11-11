\echo '6A BEFORE: PostgreSQL boot default, current value, RESET target and source'
\ir module06-baseline.sql
SELECT d.datname,r.rolname,s.setconfig
FROM pg_db_role_setting s LEFT JOIN pg_database d ON d.oid=s.setdatabase
LEFT JOIN pg_roles r ON r.oid=s.setrole
WHERE (s.setdatabase=0 OR d.datname=current_database()) AND (s.setrole=0 OR r.rolname=current_user);
SELECT current_setting('work_mem') AS original_work_mem \gset
BEGIN;
SET LOCAL work_mem='32MB';
\echo '6A AFTER: transaction-local test'
SELECT name,current_setting(name) AS effective_value,boot_val,reset_val,source
FROM pg_settings WHERE name='work_mem';
-- Demonstrate only the current student's role/database; catalog change rolls back.
SELECT format('ALTER ROLE %I IN DATABASE %I SET work_mem=%L',current_user,current_database(),'32MB') \gexec
SELECT s.setconfig FROM pg_db_role_setting s
WHERE setrole=(SELECT oid FROM pg_roles WHERE rolname=current_user)
AND setdatabase=(SELECT oid FROM pg_database WHERE datname=current_database());
ROLLBACK;
\echo '6A RESTORED: original session value (role defaults also rolled back)'
SELECT current_setting('work_mem') AS restored, current_setting('work_mem')=:'original_work_mem' AS original_restored;
