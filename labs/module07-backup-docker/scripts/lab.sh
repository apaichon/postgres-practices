#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACT_DIR="$LAB_DIR/artifacts"
ARCHIVE_DIR="$LAB_DIR/archive"

compose() {
  docker compose --project-directory "$LAB_DIR" -f "$LAB_DIR/compose.yaml" "$@"
}

prepare_host_dirs() {
  mkdir -p "$ARTIFACT_DIR" "$ARCHIVE_DIR"
}

wait_ready() {
  local service="$1" user="$2" database="$3"
  local attempt
  for attempt in $(seq 1 90); do
    if compose exec -T "$service" pg_isready -U "$user" -d "$database" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  compose logs "$service" >&2
  printf 'Service %s did not become ready.\n' "$service" >&2
  return 1
}

ensure_primary() {
  prepare_host_dirs
  compose up -d primary
  wait_ready primary postgres backup_lab
}

ensure_logical_target() {
  prepare_host_dirs
  compose up -d logical-target
  wait_ready logical-target restore_admin restore_admin
}

show_source_rows() {
  compose exec -T primary psql -X -U postgres -d backup_lab -v ON_ERROR_STOP=1 \
    -c "SELECT event_id,claim_no,event_type,amount FROM claims.claim_event ORDER BY event_id;"
}

backup_globals() {
  ensure_primary
  compose exec -T --user root primary sh -ceu \
    'mkdir -p /artifacts/globals && chown postgres:postgres /artifacts/globals'
  compose exec -T primary pg_dumpall -U postgres --globals-only \
    --no-role-passwords --file=/artifacts/globals/globals.sql
  compose exec -T primary sh -ceu \
    "sed -E 's/ GRANTED BY [A-Za-z_][A-Za-z0-9_]*;/;/' \
       /artifacts/globals/globals.sql > /artifacts/globals/globals-for-restore.sql
     cd /artifacts/globals
     sha256sum globals.sql globals-for-restore.sql > CHECKSUMS.sha256"
  printf '\nGlobal objects: %s/globals/globals.sql\n' "$ARTIFACT_DIR"
  compose exec -T primary sh -ceu \
    "grep -E '^(CREATE ROLE|ALTER ROLE|GRANT .* TO )' /artifacts/globals/globals.sql || true"
}

logical_backup() {
  ensure_primary
  compose exec -T --user root primary sh -ceu \
    'mkdir -p /artifacts/logical && chown postgres:postgres /artifacts/logical'
  compose exec -T primary pg_dump -U postgres -d backup_lab \
    --create --format=custom --file=/artifacts/logical/backup_lab.dump
  compose exec -T primary sh -ceu \
    'pg_restore --list /artifacts/logical/backup_lab.dump > /artifacts/logical/backup_lab.list'
  backup_globals
  compose exec -T primary sh -ceu \
    'cd /artifacts && sha256sum logical/backup_lab.dump globals/globals.sql globals/globals-for-restore.sql > logical/CHECKSUMS.sha256'
  printf '\nLogical backup files:\n'
  compose exec -T primary ls -lh \
    /artifacts/logical/backup_lab.dump \
    /artifacts/logical/backup_lab.list \
    /artifacts/logical/CHECKSUMS.sha256
}

logical_damage() {
  ensure_primary
  compose exec -T primary psql -X -U postgres -d backup_lab -v ON_ERROR_STOP=1 <<'SQL'
DELETE FROM claims.claim_event WHERE claim_no='CLM-0002';
INSERT INTO claims.claim_event (claim_no,event_type,amount)
VALUES ('CLM-BAD-LOGICAL','ACCIDENTAL',9999.00)
ON CONFLICT (claim_no) DO UPDATE
SET event_type=EXCLUDED.event_type,amount=EXCLUDED.amount;
SQL
  printf '\nSource after committed damage:\n'
  show_source_rows
}

logical_restore() {
  local dump="$ARTIFACT_DIR/logical/backup_lab.dump"
  local globals="$ARTIFACT_DIR/globals/globals-for-restore.sql"
  [[ -f "$dump" && -f "$globals" ]] || {
    printf 'Run logical-backup first.\n' >&2
    return 1
  }
  ensure_logical_target
  compose exec -T logical-target psql -X -U restore_admin -d restore_admin \
    -v ON_ERROR_STOP=1 <<'SQL'
DROP DATABASE IF EXISTS backup_lab WITH (FORCE);
DROP ROLE IF EXISTS claims_app;
DROP ROLE IF EXISTS claims_readonly;
DROP ROLE IF EXISTS postgres;
SQL
  compose exec -T logical-target psql -X -U restore_admin -d restore_admin \
    -v ON_ERROR_STOP=1 -f /artifacts/globals/globals-for-restore.sql
  compose exec -T logical-target pg_restore -U restore_admin \
    --exit-on-error --create --dbname=restore_admin /artifacts/logical/backup_lab.dump
  printf '\nLogical target restored on port %s:\n' "${M7_LOGICAL_PORT:-55433}"
  compose exec -T logical-target psql -X -U restore_admin -d backup_lab \
    -v ON_ERROR_STOP=1 <<'SQL'
SELECT current_database() AS database,current_user AS restore_login;
SELECT event_id,claim_no,event_type,amount
FROM claims.claim_event ORDER BY event_id;
SELECT rolname,rolcanlogin
FROM pg_roles WHERE rolname IN ('claims_app','claims_readonly') ORDER BY rolname;
SQL
}

physical_full() {
  ensure_primary
  compose --profile restore stop physical-restore pitr-restore >/dev/null 2>&1 || true
  compose exec -T --user root primary sh -ceu \
    'rm -rf /artifacts/physical/weekly-full /artifacts/physical/restore
     mkdir -p /artifacts/physical/weekly-full
     chown -R postgres:postgres /artifacts/physical'
  compose exec -T primary pg_basebackup -U postgres \
    --pgdata=/artifacts/physical/weekly-full \
    --format=plain --wal-method=stream --checkpoint=fast \
    --manifest-checksums=SHA256 --progress
  compose exec -T primary pg_verifybackup /artifacts/physical/weekly-full
  compose exec -T primary sh -ceu \
    "printf '%s\n' weekly-full > /artifacts/physical/latest
     printf '%s\n' weekly-full > /artifacts/physical/chain.txt"
  printf '\nWeekly full backup: %s/physical/weekly-full\n' "$ARTIFACT_DIR"
  compose exec -T primary du -sh /artifacts/physical/weekly-full
}

change_data() {
  local label="${1:-daily}"
  [[ "$label" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    printf 'Label may contain only letters, digits, dot, underscore and dash.\n' >&2
    return 1
  }
  ensure_primary
  compose exec -T primary psql -X -U postgres -d backup_lab \
    -v ON_ERROR_STOP=1 -v label="$label" <<'SQL'
INSERT INTO claims.claim_event (claim_no,event_type,amount)
SELECT 'CLM-' || :'label' || '-' || lpad(g::text,4,'0'),
       'DAILY_CHANGE',
       g::numeric
FROM generate_series(1,1000) AS g
ON CONFLICT (claim_no) DO UPDATE
SET event_type=EXCLUDED.event_type,amount=EXCLUDED.amount;
CHECKPOINT;
SELECT count(*) AS total_rows,max(created_at) AS newest
FROM claims.claim_event;
SQL
  compose exec -T primary psql -X -U postgres -d postgres \
    -v ON_ERROR_STOP=1 -c "SELECT pg_switch_wal();"
}

physical_incremental() {
  local label="${1:-daily-$(date -u +%Y%m%dT%H%M%SZ)}"
  local latest_file="$ARTIFACT_DIR/physical/latest"
  local parent manifest
  [[ "$label" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    printf 'Backup label may contain only letters, digits, dot, underscore and dash.\n' >&2
    return 1
  }
  [[ -f "$latest_file" ]] || {
    printf 'Run physical-full before an incremental backup.\n' >&2
    return 1
  }
  parent="$(tr -d '\r\n' < "$latest_file")"
  [[ "$parent" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    printf 'Invalid parent backup label: %s\n' "$parent" >&2
    return 1
  }
  manifest="/artifacts/physical/$parent/backup_manifest"
  ensure_primary
  compose exec -T primary test -f "$manifest"
  compose exec -T --user root primary sh -ceu \
    "rm -rf '/artifacts/physical/$label'
     mkdir -p '/artifacts/physical/$label'
     chown postgres:postgres '/artifacts/physical/$label'"
  compose exec -T primary pg_basebackup -U postgres \
    --pgdata="/artifacts/physical/$label" \
    --format=plain --wal-method=stream --checkpoint=fast \
    --incremental="$manifest" --manifest-checksums=SHA256 --progress
  compose exec -T primary pg_verifybackup "/artifacts/physical/$label"
  compose exec -T primary sh -ceu \
    "printf '%s\n' '$label' > /artifacts/physical/latest
     printf '%s\n' '$label' >> /artifacts/physical/chain.txt"
  printf '\nIncremental backup: %s/physical/%s\n' "$ARTIFACT_DIR" "$label"
  compose exec -T primary du -sh \
    "/artifacts/physical/$parent" "/artifacts/physical/$label"
}

combine_physical_chain() {
  local chain_file="$ARTIFACT_DIR/physical/chain.txt"
  local item
  local -a backup_paths=()
  [[ -f "$chain_file" ]] || {
    printf 'Run physical-full first.\n' >&2
    return 1
  }
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    [[ "$item" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
      printf 'Invalid chain entry: %s\n' "$item" >&2
      return 1
    }
    backup_paths+=("/artifacts/physical/$item")
  done < "$chain_file"
  ((${#backup_paths[@]} > 0)) || {
    printf 'Physical backup chain is empty.\n' >&2
    return 1
  }
  compose --profile restore stop physical-restore >/dev/null 2>&1 || true
  compose exec -T --user root primary sh -ceu \
    'rm -rf /artifacts/physical/restore
     mkdir -p /artifacts/physical/restore
     chown postgres:postgres /artifacts/physical/restore'
  compose exec -T primary pg_combinebackup \
    --output=/artifacts/physical/restore "${backup_paths[@]}"
  compose exec -T primary pg_verifybackup /artifacts/physical/restore
  compose exec -T --user root primary chown -R postgres:postgres /artifacts/physical/restore
}

physical_restore() {
  ensure_primary
  combine_physical_chain
  compose --profile restore up -d physical-restore
  wait_ready physical-restore postgres backup_lab
  printf '\nPhysical restore target on port %s:\n' "${M7_PHYSICAL_PORT:-55434}"
  compose exec -T physical-restore psql -X -U postgres -d backup_lab \
    -v ON_ERROR_STOP=1 <<'SQL'
SELECT current_database(),count(*) AS restored_rows
FROM claims.claim_event GROUP BY current_database();
SELECT claim_no,event_type,amount
FROM claims.claim_event ORDER BY event_id DESC LIMIT 5;
SQL
}

wait_for_archived_wal() {
  local wal_name="$1" attempt
  for attempt in $(seq 1 60); do
    if compose exec -T primary test -f "/archive/$wal_name"; then
      return 0
    fi
    sleep 1
  done
  printf 'WAL %s was not archived in time.\n' "$wal_name" >&2
  return 1
}

pitr_demo() {
  local run_id restore_point base_claim good_claim bad_claim wal_name
  ensure_primary
  run_id="$(date -u +%Y%m%dT%H%M%SZ)"
  restore_point="m7_before_mistake_$run_id"
  base_claim="PITR-BASE-$run_id"
  good_claim="PITR-GOOD-$run_id"
  bad_claim="PITR-BAD-$run_id"

  compose exec -T primary psql -X -U postgres -d backup_lab \
    -v ON_ERROR_STOP=1 -v base_claim="$base_claim" <<'SQL'
INSERT INTO claims.claim_event (claim_no,event_type,amount)
VALUES (:'base_claim','IN_BASE_BACKUP',500.00);
SQL
  physical_full

  compose exec -T primary psql -X -U postgres -d backup_lab \
    -v ON_ERROR_STOP=1 \
    -v good_claim="$good_claim" \
    -v restore_point="$restore_point" <<'SQL'
INSERT INTO claims.claim_event (claim_no,event_type,amount)
VALUES (:'good_claim','BEFORE_TARGET',700.00);
SELECT pg_create_restore_point(:'restore_point') AS restore_point_lsn;
SQL

  compose exec -T primary psql -X -U postgres -d backup_lab \
    -v ON_ERROR_STOP=1 -v base_claim="$base_claim" -v bad_claim="$bad_claim" <<'SQL'
DELETE FROM claims.claim_event WHERE claim_no=:'base_claim';
INSERT INTO claims.claim_event (claim_no,event_type,amount)
VALUES (:'bad_claim','AFTER_TARGET_MISTAKE',9999.00);
SQL

  wal_name="$(compose exec -T primary psql -X -U postgres -d postgres -Atc \
    'SELECT pg_walfile_name(pg_current_wal_lsn());' | tr -d '\r')"
  compose exec -T primary psql -X -U postgres -d postgres \
    -v ON_ERROR_STOP=1 -c "SELECT pg_switch_wal();"
  wait_for_archived_wal "$wal_name"

  compose --profile restore stop pitr-restore >/dev/null 2>&1 || true
  compose exec -T --user root primary sh -ceu \
    'rm -rf /artifacts/pitr/data
     mkdir -p /artifacts/pitr/data
     cp -a /artifacts/physical/weekly-full/. /artifacts/pitr/data/
     chown -R postgres:postgres /artifacts/pitr'
  {
    printf "\nrestore_command = 'cp /archive/%%f %%p'\n"
    printf "recovery_target_name = '%s'\n" "$restore_point"
    printf "recovery_target_action = 'promote'\n"
    printf "recovery_target_timeline = 'current'\n"
  } | compose exec -T primary sh -ceu \
    'cat >> /artifacts/pitr/data/postgresql.auto.conf'
  compose exec -T primary touch /artifacts/pitr/data/recovery.signal
  compose exec -T primary sh -ceu \
    "printf '%s\n' \
       'restore_point=$restore_point' \
       'base_claim=$base_claim' \
       'good_claim=$good_claim' \
       'bad_claim=$bad_claim' \
       > /artifacts/pitr/expected.txt"

  compose --profile restore up -d pitr-restore
  wait_ready pitr-restore postgres backup_lab
  printf '\nPITR target on port %s, stopped at %s:\n' \
    "${M7_PITR_PORT:-55435}" "$restore_point"
  compose exec -T pitr-restore psql -X -U postgres -d backup_lab \
    -v ON_ERROR_STOP=1 \
    -v base_claim="$base_claim" \
    -v good_claim="$good_claim" \
    -v bad_claim="$bad_claim" <<'SQL'
SELECT EXISTS (
         SELECT 1 FROM claims.claim_event WHERE claim_no=:'base_claim'
       ) AS deleted_row_recovered,
       EXISTS (
         SELECT 1 FROM claims.claim_event WHERE claim_no=:'good_claim'
       ) AS before_target_present,
       NOT EXISTS (
         SELECT 1 FROM claims.claim_event WHERE claim_no=:'bad_claim'
       ) AS after_target_mistake_absent;
SELECT claim_no,event_type,amount
FROM claims.claim_event
WHERE claim_no IN (:'base_claim',:'good_claim',:'bad_claim')
ORDER BY claim_no;
SQL
}

list_files() {
  local -a paths=()
  local wal_count
  prepare_host_dirs
  shopt -s nullglob
  paths=(
    "$ARTIFACT_DIR"/logical/*
    "$ARTIFACT_DIR"/globals/*
    "$ARTIFACT_DIR"/physical/*
    "$ARTIFACT_DIR"/pitr/*
  )
  printf 'Backup artefacts (one line per file or backup directory):\n'
  if ((${#paths[@]} > 0)); then
    du -sh "${paths[@]}" | sort -k2
  else
    printf '  no backup artefacts yet\n'
  fi
  wal_count="$(find "$ARCHIVE_DIR" -type f | wc -l | tr -d ' ')"
  printf '\nArchived WAL files: %s\n' "$wal_count"
  if ((wal_count > 0)); then
    ls -lht "$ARCHIVE_DIR" | sed -n '1,11p'
  fi
}

status() {
  compose ps
  if compose ps --status running primary 2>/dev/null | grep -q primary; then
    compose exec -T primary psql -X -U postgres -d backup_lab \
      -v ON_ERROR_STOP=1 <<'SQL'
SELECT version();
SELECT name,setting
FROM pg_settings
WHERE name IN ('archive_mode','archive_command','summarize_wal','wal_summary_keep_time')
ORDER BY name;
SELECT archived_count,last_archived_wal,last_archived_time,failed_count
FROM pg_stat_archiver;
SQL
  fi
}

clean_lab() {
  [[ "${1:-}" == "--yes" ]] || {
    printf 'Use: bash scripts/lab.sh clean --yes\n' >&2
    return 1
  }
  [[ "$ARTIFACT_DIR" == "$LAB_DIR/artifacts" && "$ARCHIVE_DIR" == "$LAB_DIR/archive" ]] || {
    printf 'Refusing to clean unexpected paths.\n' >&2
    return 1
  }
  compose --profile restore down -v --remove-orphans
  find "$ARTIFACT_DIR" -depth -mindepth 1 ! -name .gitkeep -delete
  find "$ARCHIVE_DIR" -depth -mindepth 1 ! -name .gitkeep -delete
  printf 'Removed this lab containers, volumes, backup artefacts and archived WAL.\n'
}

usage() {
  cat <<'HELP'
PostgreSQL 18 backup/restore Docker lab

Commands:
  up                         Start source and logical target
  status                     Show containers, PostgreSQL and archive settings
  globals                    Back up cluster global objects
  logical-backup             Create custom logical dump + globals + checksums
  logical-damage             Commit a delete and an accidental insert
  logical-restore            Restore into the separate logical target
  physical-full              Create/verify a weekly full physical backup
  change [LABEL]             Generate 1,000 changed rows and switch WAL
  physical-incremental [ID]  Create/verify the next incremental backup
  physical-restore           Combine the chain and start a restored server
  pitr-demo                  Full backup, mistake, WAL archive and PITR
  files                      List backup files and archived WAL
  stop                       Stop containers and keep all data
  down                       Remove containers but keep volumes/files
  clean --yes                Remove only this lab's containers, volumes and files
HELP
}

command="${1:-help}"
shift || true
case "$command" in
  up)
    ensure_primary
    ensure_logical_target
    show_source_rows
    ;;
  status) status ;;
  globals) backup_globals ;;
  logical-backup) logical_backup ;;
  logical-damage) logical_damage ;;
  logical-restore) logical_restore ;;
  physical-full) physical_full ;;
  change) change_data "${1:-daily}" ;;
  physical-incremental) physical_incremental "${1:-}" ;;
  physical-restore) physical_restore ;;
  pitr-demo) pitr_demo ;;
  files) list_files ;;
  stop) compose --profile restore stop ;;
  down) compose --profile restore down --remove-orphans ;;
  clean) clean_lab "${1:-}" ;;
  help|-h|--help) usage ;;
  *)
    printf 'Unknown command: %s\n\n' "$command" >&2
    usage >&2
    exit 2
    ;;
esac
