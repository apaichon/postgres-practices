#!/usr/bin/env bash
# Drop lab schemas in this SSH student's own database, ready for Module 1.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: reset-lab.sh [--all] [--backup] [--dry-run] [--yes]

Default: DROP SCHEMA IF EXISTS insurance CASCADE in your primary database.
  --all       Also drop lab_m4, lab_m6, lab_m7, lab_m8, lab_m9 and lab_m10
  --backup    Reset your separate backup database instead of your primary
  --dry-run   Validate the connection and list DROP commands without executing
  --yes       Skip the typed database-name confirmation
  --help      Show this help

Drops schema contents and dependent objects. Close other lab sessions first.
After reset, restart with ./run-lab01.sh A and ./run-lab01.sh B.
EOF
}

all_schemas=false
dry_run=false
confirmed=false
service=claimsure
for option in "$@"; do
  case "$option" in
    --all) all_schemas=true ;;
    --backup) service=backup ;;
    --dry-run) dry_run=true ;;
    --yes) confirmed=true ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$option" >&2; usage >&2; exit 2 ;;
  esac
done

account="$(id -un)"
if [[ ! "$account" =~ ^student(0[1-9]|1[0-9]|20)$ ]]; then
  echo 'Run this script while logged in as your assigned studentxx account (xx = 01-20).' >&2
  exit 2
fi
number="${BASH_REMATCH[1]}"
expected_user="student_$number"
expected_database="claimsure_$number"
if [[ "$service" == backup ]]; then expected_database="claimsure_backup_$number"; fi
printf 'Database: %s\nRole: %s\nSchemas: insurance' "$expected_database" "$expected_user"
if [[ "$all_schemas" == true ]]; then printf ', lab_m4, lab_m6, lab_m7, lab_m8, lab_m9, lab_m10'; fi
printf '\n'

if [[ "$dry_run" == false && "$confirmed" == false ]]; then
  printf 'This deletes the selected schemas and their data.\nType %s to continue: ' "$expected_database"
  answer=''
  if ! IFS= read -r answer || [[ "$answer" != "$expected_database" ]]; then
    echo 'Cancelled; no changes.' >&2
    exit 1
  fi
fi

# Keep validation and DROP in one connection and transaction. The service file
# may be edited by a student, so verify the actual database, login and owner.
PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}" psql "service=$service" -X -w \
  -v ON_ERROR_STOP=1 -P pager=off \
  -v expected_user="$expected_user" -v expected_database="$expected_database" \
  -v all_schemas="$all_schemas" -v dry_run="$dry_run" <<'SQL'
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

SELECT session_user = :'expected_user'
   AND current_user = :'expected_user'
   AND current_database() = :'expected_database'
   AND pg_get_userbyid(d.datdba) = :'expected_user'
   AND NOT r.rolsuper AS correct_target
FROM pg_database AS d
JOIN pg_roles AS r ON r.rolname = current_user
WHERE d.datname = current_database()
\gset
\if :correct_target
\else
  \echo 'Refusing reset: the database, login, ownership or privileges do not match your student account.'
  DO $reset$ BEGIN RAISE EXCEPTION 'Reset target does not match your student database and role'; END $reset$;
\endif

SELECT NOT EXISTS (
  SELECT FROM pg_namespace AS n
  WHERE (n.nspname = 'insurance' OR (:all_schemas AND n.nspname IN
    ('lab_m4','lab_m6','lab_m7','lab_m8','lab_m9','lab_m10')))
    AND n.nspowner <> (SELECT oid FROM pg_roles WHERE rolname = current_user)
) AS own_schemas
\gset
\if :own_schemas
\else
  \echo 'Refusing reset: one of the selected schemas belongs to another role. Ask your instructor.'
  DO $reset$ BEGIN RAISE EXCEPTION 'Selected schema belongs to another role'; END $reset$;
\endif

\if :dry_run
  SELECT format('DROP SCHEMA IF EXISTS %I CASCADE;', schema_name) AS planned_sql
  FROM unnest(ARRAY['insurance','lab_m4','lab_m6','lab_m7','lab_m8','lab_m9','lab_m10'])
    WITH ORDINALITY AS schemas(schema_name, position)
  WHERE schema_name = 'insurance' OR :all_schemas
  ORDER BY position;
  ROLLBACK;
  \echo 'Preview only; no changes.'
\else
  SELECT format('DROP SCHEMA IF EXISTS %I CASCADE;', schema_name)
  FROM unnest(ARRAY['insurance','lab_m4','lab_m6','lab_m7','lab_m8','lab_m9','lab_m10'])
    WITH ORDINALITY AS schemas(schema_name, position)
  WHERE schema_name = 'insurance' OR :all_schemas
  ORDER BY position
  \gexec
  COMMIT;
  \echo 'Reset complete.'
\endif
SQL
if [[ "$dry_run" == false ]]; then
  restart_flag=''
  if [[ "$service" == backup ]]; then restart_flag=' --backup'; fi
  printf 'Restart with ./run-lab01.sh%s A, then ./run-lab01.sh%s B.\n' "$restart_flag" "$restart_flag"
fi
