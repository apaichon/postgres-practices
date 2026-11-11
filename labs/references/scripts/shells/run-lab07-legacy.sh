#!/usr/bin/env bash
# Classroom Module 7: logical backup, physical backup, storage snapshot, and PITR.
#
#   ./scripts/shells/run-lab07-legacy.sh --student xx --ask-pass logical
#   ./scripts/shells/run-lab07-legacy.sh --student xx --ask-pass physical
#   ./scripts/shells/run-lab07-legacy.sh --student xx --ask-pass snapshot
#   ./scripts/shells/run-lab07-legacy.sh --student xx --ask-pass pitr
#   ./scripts/shells/run-lab07-legacy.sh --student xx --ask-pass all
#   ./scripts/shells/run-lab07-legacy.sh --list
#
# Student xx reads claimsure_xx and restores schema insurance into
# claimsure_backup_xx. The shared cluster is not copied and is not recovered.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DB_HOST="31.220.82.70"
DB_PORT="6432"
STUDENT_NO=""
USER_OVERRIDE=""
ASK_PASS=0
DRY_RUN=0
LIST_ONLY=0
STUDENT_EXPLICIT=0
LAB=""

DB_USER=""
DB_NAME=""
DB_BACKUP=""
BACKUP_DIR=""
DUMP_FILE=""
STAMP=""

usage() {
  cat <<'EOF'
Usage: run-lab07-legacy.sh [options] <section>

Learn four backup boundaries on the student's own databases.

  logical    pg_dump -Fc of schema insurance, then pg_restore into the backup database
  physical   Read backup readiness. Print pg_basebackup. Do not copy the cluster.
  snapshot   Save a business validation snapshot and review storage-snapshot rules.
  pitr       Read the base-backup plus WAL chain. Do not recover the shared server.
  all        Run logical, physical, snapshot, and pitr in that order

Student mapping (xx = 01..20)
  DB user      student_xx
  Source       claimsure_xx          (read; schema insurance must already exist)
  Restore      claimsure_backup_xx   (schema insurance is replaced here only)

Options
      --student N    Student number 1..20 (also studentxx or student_xx)
      --host HOST    Database host (default: 31.220.82.70)
      --port PORT    Database port (default: 6432)
      --user USER    Must match student_xx
      --ask-pass     Ask for the database password once
      --dry-run      Print the plan without connecting
  -l, --list         List the four sections
  -h, --help         Show this help

Examples
  ./scripts/shells/run-lab07-legacy.sh --student xx --ask-pass logical
  ./scripts/shells/run-lab07-legacy.sh --student xx physical
  ./scripts/shells/run-lab07-legacy.sh --student xx snapshot
  ./scripts/shells/run-lab07-legacy.sh --student xx pitr
  ./scripts/shells/run-lab07-legacy.sh --student xx all

Copy .env.example to .env. The script loads DB_PASSWORD before connecting.
A dump file is written under backup/student_xx/ and is not a cluster backup.
pg_dump does not include roles or tablespaces. pg_dumpall and pg_basebackup
are shown and are not run against this shared server.
EOF
}

list_m7() {
  cat <<'EOF'
Module 7 sections (run-lab07-legacy.sh)

  logical    custom-format dump of insurance, restore into claimsure_backup_xx
  physical   pg_settings readiness and the pg_basebackup command (not executed)
  snapshot   lab_m7 business snapshot, then storage-snapshot rules
  pitr       base backup + archived WAL + one recovery target (not executed)
  all        logical, physical, snapshot, pitr

Run Module 1 first so claimsure_xx contains schema insurance.
The restore replaces schema insurance in claimsure_backup_xx only.
EOF
}

load_env() {
  local env_file="$REPO_ROOT/.env"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
  fi

  DB_HOST="${LAB_DB_HOST:-${PGHOST:-${SSH_HOST:-$DB_HOST}}}"
  DB_PORT="${LAB_DB_PORT:-${PGPORT:-$DB_PORT}}"
  STUDENT_NO="${LAB_STUDENT_NO:-${STUDENT_NO:-${SSH_USER:-${USER:-}}}}"
  USER_OVERRIDE="${LAB_DB_USER:-${USER_OVERRIDE:-}}"

  if [[ -z "${PGPASSWORD:-}" ]]; then
    if [[ -n "${DB_PASSWORD:-}" ]]; then
      export PGPASSWORD="$DB_PASSWORD"
    elif [[ -n "${LAB_DB_PASSWORD:-}" ]]; then
      export PGPASSWORD="$LAB_DB_PASSWORD"
    fi
  fi
}

normalize_student_no() {
  local raw="$1"
  local number

  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  raw="${raw#claimsure_backup_}"
  raw="${raw#claimsure_}"
  raw="${raw#student_}"
  raw="${raw#student-}"
  raw="${raw#student}"
  if [[ ! "$raw" =~ ^[0-9]{1,2}$ ]]; then
    echo "Invalid student number: $1. Use 1..20, studentxx, or student_xx." >&2
    return 1
  fi

  number=$((10#$raw))
  if (( number < 1 || number > 20 )); then
    echo "Invalid student number: $1. Use 1..20." >&2
    return 1
  fi

  printf '%02d\n' "$number"
}

suffix_from_user() {
  if [[ "$1" =~ ^student[_-]?([0-9]{1,2})$ ]]; then
    normalize_student_no "${BASH_REMATCH[1]}"
    return
  fi
  echo "Invalid user: $1. Expected studentxx or student_xx (xx = assigned number 01-20)." >&2
  return 1
}

resolve_identity() {
  local requested_no user_no

  requested_no="$(normalize_student_no "$STUDENT_NO")"
  user_no=""
  if [[ -n "$USER_OVERRIDE" ]]; then
    user_no="$(suffix_from_user "$USER_OVERRIDE")"
  fi
  if [[ "$STUDENT_EXPLICIT" -eq 0 && -n "$user_no" ]]; then
    requested_no="$user_no"
  elif [[ -n "$user_no" && "$user_no" != "$requested_no" ]]; then
    echo "Access mapping mismatch: $USER_OVERRIDE is not student_${requested_no}." >&2
    return 1
  fi

  STUDENT_NO="$requested_no"
  DB_USER="student_${STUDENT_NO}"
  DB_NAME="claimsure_${STUDENT_NO}"
  DB_BACKUP="claimsure_backup_${STUDENT_NO}"
  BACKUP_DIR="$REPO_ROOT/backup/student_${STUDENT_NO}"
}

normalize_lab() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    all|07|lab07) printf '%s\n' "all" ;;
    logical|lab07_logical) printf '%s\n' "logical" ;;
    physical|lab07_physical) printf '%s\n' "physical" ;;
    snapshot|lab07_snapshot) printf '%s\n' "snapshot" ;;
    pitr|lab07_pitr) printf '%s\n' "pitr" ;;
    *)
      echo "Unknown Module 7 section: $1" >&2
      echo "Use logical, physical, snapshot, pitr, all, or --list." >&2
      return 1
      ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -l|--list|list)
        LIST_ONLY=1
        shift
        ;;
      --student)
        STUDENT_NO="$2"
        STUDENT_EXPLICIT=1
        shift 2
        ;;
      --host)
        DB_HOST="$2"
        shift 2
        ;;
      --port)
        DB_PORT="$2"
        shift 2
        ;;
      --user)
        USER_OVERRIDE="$2"
        shift 2
        ;;
      --ask-pass)
        ASK_PASS=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
      *)
        if [[ -n "$LAB" ]]; then
          echo "Unexpected extra argument: $1" >&2
          exit 2
        fi
        LAB="$1"
        shift
        ;;
    esac
  done
}

prefer_postgres18_client() {
  local candidate
  for candidate in \
    /opt/homebrew/opt/postgresql@18/bin \
    /usr/local/opt/postgresql@18/bin \
    /usr/lib/postgresql/18/bin
  do
    if [[ -x "$candidate/psql" ]]; then
      export PATH="$candidate:$PATH"
      return 0
    fi
  done
}

client_major() {
  local version
  version="$("$1" --version 2>/dev/null || true)"
  if [[ "$version" =~ PostgreSQL\)\ ([0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  printf '%s\n' "0"
}

require_client() {
  local missing=0
  local tool major
  prefer_postgres18_client

  if ! command -v psql >/dev/null 2>&1; then
    echo "Missing client tool: psql" >&2
    missing=1
  fi
  if [[ "$LAB" == "logical" || "$LAB" == "all" ]]; then
    for tool in pg_dump pg_restore; do
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing client tool: $tool" >&2
        missing=1
      fi
    done
  fi
  if [[ "$missing" -ne 0 ]]; then
    echo "A PostgreSQL client is required. This script does not install the server." >&2
    return 1
  fi

  if [[ "$LAB" == "logical" || "$LAB" == "all" ]]; then
    major="$(client_major pg_dump)"
    if [[ "$major" != "18" ]]; then
      echo "pg_dump is PostgreSQL ${major}. The classroom server is PostgreSQL 18." >&2
      echo "A logical dump of a version 18 server needs a version 18 pg_dump and pg_restore." >&2
      echo "This script does not install the client. physical, snapshot, and pitr can still be read with psql." >&2
      return 1
    fi
  fi
}

prepare_password() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  if [[ "$ASK_PASS" -eq 1 ]]; then
    read -r -s -p "Database password for ${DB_USER}: " PGPASSWORD
    echo
    export PGPASSWORD
  fi
  unset PGSERVICE PGSERVICEFILE
  export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"
}

psql_db() {
  local database="$1"
  shift
  psql -X -v ON_ERROR_STOP=1 \
    -h "$DB_HOST" -p "$DB_PORT" \
    -U "$DB_USER" -d "$database" \
    "$@"
}

section() {
  echo
  echo "========== $* =========="
}

ensure_source_schema() {
  local present
  present="$(psql_db "$DB_NAME" -tA -c "SELECT to_regclass('insurance.claim') IS NOT NULL")"
  if [[ "$present" != "t" ]]; then
    echo "Schema insurance.claim is missing in ${DB_NAME}." >&2
    echo "Run Module 1 first: ./scripts/shells/run-lab01.sh --student ${STUDENT_NO#0} A" >&2
    return 1
  fi
}

ensure_lab_tables() {
  local database="$1"
  psql_db "$database" <<'SQL'
CREATE SCHEMA IF NOT EXISTS lab_m7;

CREATE TABLE IF NOT EXISTS lab_m7.validation_run (
    run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    snapshot_name text NOT NULL,
    captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    database_name name NOT NULL,
    claim_count bigint NOT NULL,
    customer_count bigint,
    policy_count bigint
);

CREATE TABLE IF NOT EXISTS lab_m7.claim_validation (
    run_id bigint NOT NULL REFERENCES lab_m7.validation_run ON DELETE CASCADE,
    claim_no text NOT NULL,
    status text NOT NULL,
    estimated_amount numeric,
    PRIMARY KEY (run_id, claim_no)
);

CREATE TABLE IF NOT EXISTS lab_m7.recovery_evidence (
    evidence_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    exercise_name text NOT NULL,
    artifact_uri text,
    verification_method text NOT NULL,
    result text NOT NULL CHECK (result IN ('PASS', 'FAIL', 'NOT_RUN')),
    notes text,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
SQL
}

capture_business_snapshot() {
  local database="$1"
  local snapshot_name="$2"
  ensure_lab_tables "$database"
  psql_db "$database" \
    -v snapshot_name="$snapshot_name" <<'SQL'
WITH inserted AS (
    INSERT INTO lab_m7.validation_run (
        snapshot_name, database_name, claim_count, customer_count, policy_count
    )
    SELECT :'snapshot_name', current_database(),
           (SELECT count(*) FROM insurance.claim),
           (SELECT count(*) FROM insurance.customer),
           (SELECT count(*) FROM insurance.policy)
    RETURNING run_id, snapshot_name, database_name, captured_at,
              claim_count, customer_count, policy_count
), saved_claims AS (
    INSERT INTO lab_m7.claim_validation (run_id, claim_no, status, estimated_amount)
    SELECT inserted.run_id, claim.claim_no, claim.status, claim.estimated_amount
    FROM insurance.claim AS claim
    CROSS JOIN inserted
    RETURNING run_id
)
SELECT run_id, snapshot_name, database_name, captured_at,
       claim_count, customer_count, policy_count
FROM inserted;
SQL
}

record_evidence() {
  local exercise="$1"
  local result="$2"
  local method="$3"
  local notes="$4"
  local artifact="${5:-}"
  ensure_lab_tables "$DB_NAME"
  psql_db "$DB_NAME" \
    -v exercise="$exercise" \
    -v result="$result" \
    -v method="$method" \
    -v notes="$notes" \
    -v artifact="$artifact" <<'SQL'
INSERT INTO lab_m7.recovery_evidence (
    exercise_name, artifact_uri, verification_method, result, notes
)
VALUES (
    :'exercise', NULLIF(:'artifact', ''), :'method', :'result', :'notes'
)
RETURNING evidence_id, exercise_name, result, recorded_at;
SQL
}

claim_signature() {
  local database="$1"
  local output="$2"
  psql_db "$database" -tA -c \
    "COPY (
        SELECT claim_no, status,
               to_char(estimated_amount, 'FM9999999990.00')
        FROM insurance.claim
        ORDER BY claim_no
     ) TO STDOUT WITH (FORMAT csv)" >"$output"
}

run_logical() {
  local partial source_sig backup_sig result notes
  section "Logical backup: pg_dump -Fc, then restore into ${DB_BACKUP}"
  echo "pg_dump exports one database or selected objects. This drill exports schema insurance."
  echo "Roles and tablespaces stay outside the archive. pg_dumpall --globals-only is not run:"
  echo "a student login cannot dump cluster globals, and this server already has the roles."
  echo "Source ${DB_NAME} is only read. Schema insurance in ${DB_BACKUP} is replaced."

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Dry run: pg_dump --schema=insurance from ${DB_NAME} to ${BACKUP_DIR}/"
    echo "Dry run: DROP SCHEMA insurance and pg_restore into ${DB_BACKUP}"
    return 0
  fi

  ensure_source_schema
  capture_business_snapshot "$DB_NAME" "before_backup"
  mkdir -p "$BACKUP_DIR"
  DUMP_FILE="$BACKUP_DIR/${DB_NAME}-${STAMP}.dump"
  partial="${DUMP_FILE}.partial"
  rm -f "$partial"

  echo
  echo "Writing a custom-format archive. A partial file is renamed only after pg_dump succeeds."
  pg_dump \
    -h "$DB_HOST" -p "$DB_PORT" \
    -U "$DB_USER" -d "$DB_NAME" \
    --format=custom \
    --schema=insurance \
    --no-owner \
    --no-privileges \
    --file="$partial"
  mv "$partial" "$DUMP_FILE"

  echo
  echo "Archive contents (pg_restore --list). Custom format can restore one object later."
  pg_restore --list "$DUMP_FILE"

  echo
  echo "Restoring into isolated database ${DB_BACKUP} from an empty insurance schema."
  psql_db "$DB_BACKUP" -c "DROP SCHEMA IF EXISTS insurance CASCADE;"
  pg_restore \
    -h "$DB_HOST" -p "$DB_PORT" \
    -U "$DB_USER" -d "$DB_BACKUP" \
    --no-owner \
    --no-privileges \
    --exit-on-error \
    "$DUMP_FILE"
  psql_db "$DB_BACKUP" -c "ANALYZE;"

  source_sig="$(mktemp)"
  backup_sig="$(mktemp)"
  claim_signature "$DB_NAME" "$source_sig"
  claim_signature "$DB_BACKUP" "$backup_sig"
  echo
  echo "Claim signature: claim_no, status, estimated_amount"
  if cmp -s "$source_sig" "$backup_sig"; then
    result="PASS"
    notes="insurance.claim rows match between ${DB_NAME} and ${DB_BACKUP}"
    echo "PASS: restored claims match the source signature."
  else
    result="FAIL"
    notes="insurance.claim signature differs; inspect both databases before using this archive"
    echo "FAIL: restored claims differ from ${DB_NAME}." >&2
    diff -u "$source_sig" "$backup_sig" || true
  fi
  rm -f "$source_sig" "$backup_sig"
  capture_business_snapshot "$DB_BACKUP" "after_restore"
  record_evidence \
    "logical restore" \
    "$result" \
    "pg_restore --list plus claim_no, status, estimated_amount" \
    "$notes" \
    "$DUMP_FILE"
  if [[ "$result" != "PASS" ]]; then
    return 1
  fi
}

run_physical() {
  section "Physical backup: pg_basebackup copies the whole cluster"
  echo "A physical backup is not a dump of ${DB_NAME}. pg_basebackup copies every database"
  echo "in the PostgreSQL instance, so it is not run on this shared classroom server."
  echo "The command below is the one an operator runs on an isolated server with a"
  echo "replication role. -Fp writes a plain directory. -Xs streams the WAL needed to"
  echo "start that backup. --checkpoint=spread avoids one sharp checkpoint."
  echo
  echo "  pg_basebackup -h HOST -p PORT -U replicator \\"
  echo "    -D backup/base-STAMP -Fp -Xs -P --checkpoint=spread"
  echo "  pg_verifybackup backup/base-STAMP"
  echo
  echo "Restore boundary: copy that directory into an empty PGDATA on another host."
  echo "It cannot replace one database inside the running server."
  echo "pg_verifybackup must pass before the directory is kept. This script does not"
  echo "call pg_basebackup or pg_verifybackup."

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Dry run: would read archive_mode, wal_level, and max_wal_senders from ${DB_NAME}."
    return 0
  fi

  echo
  echo "Readiness visible to ${DB_USER}. A change to archive_mode needs a restart and a superuser."
  psql_db "$DB_NAME" <<'SQL'
SELECT name, setting, unit, context, pending_restart
FROM pg_settings
WHERE name IN (
    'archive_mode', 'archive_command', 'wal_level', 'max_wal_senders',
    'max_replication_slots', 'wal_keep_size', 'full_page_writes', 'data_checksums'
)
ORDER BY name;
SQL

  echo
  echo "Archive counters. failed_count above zero means a WAL segment did not reach the archive."
  if ! psql_db "$DB_NAME" -c \
    "SELECT archived_count, failed_count, last_archived_wal, last_archived_time,
            last_failed_wal, last_failed_time
     FROM pg_stat_archiver;"; then
    echo "pg_stat_archiver is not readable by ${DB_USER}. The physical lesson can continue."
  fi

  record_evidence \
    "physical backup lesson" \
    "NOT_RUN" \
    "read pg_settings; pg_basebackup was not executed" \
    "Shared cluster was not copied. A physical backup needs a replication role and an empty target directory on an isolated host." \
    ""
}

run_snapshot() {
  section "Snapshot: business evidence and storage snapshot"
  echo "This section uses the word snapshot for two different tools."
  echo "A business snapshot is a row in lab_m7.validation_run. It records claim counts"
  echo "so a later restore can be compared. It is not a disk copy."
  echo "A storage snapshot is a platform copy of the whole data directory. A plain file"
  echo "copy of a running cluster is not consistent. The snapshot must include PGDATA,"
  echo "pg_wal, and every tablespace at the same instant. Recovery then replays WAL as"
  echo "it would after a crash. CHECKPOINT before the snapshot can shorten that replay."
  echo "CHECKPOINT is not run here: it needs a superuser, and this server is shared."

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Dry run: would insert lab_m7.validation_run snapshot_name=before_backup on ${DB_NAME}."
    return 0
  fi

  ensure_source_schema
  capture_business_snapshot "$DB_NAME" "before_backup"
  echo
  echo "Latest business snapshots in ${DB_NAME}:"
  psql_db "$DB_NAME" -c \
    "SELECT run_id, snapshot_name, database_name, claim_count,
            customer_count, policy_count, captured_at
     FROM lab_m7.validation_run
     ORDER BY run_id DESC
     LIMIT 5;"

  local restored
  restored="$(psql_db "$DB_BACKUP" -tA -c "SELECT to_regclass('insurance.claim') IS NOT NULL" || true)"
  if [[ "$restored" == "t" ]]; then
    echo
    echo "Comparing claim signatures with ${DB_BACKUP}. Run logical first if this is the first drill."
    local source_sig backup_sig
    source_sig="$(mktemp)"
    backup_sig="$(mktemp)"
    claim_signature "$DB_NAME" "$source_sig"
    claim_signature "$DB_BACKUP" "$backup_sig"
    if cmp -s "$source_sig" "$backup_sig"; then
      echo "PASS: ${DB_BACKUP} still matches the source claim signature."
      record_evidence \
        "business snapshot compare" \
        "PASS" \
        "claim_no, status, estimated_amount" \
        "Backup database matches the source. This does not prove a storage snapshot." \
        ""
    else
      echo "REVIEW: ${DB_BACKUP} does not match ${DB_NAME}. Restore with the logical section before treating it as the backup copy."
      diff -u "$source_sig" "$backup_sig" || true
      record_evidence \
        "business snapshot compare" \
        "FAIL" \
        "claim_no, status, estimated_amount" \
        "Backup database differs from the source. Run the logical section." \
        ""
    fi
    rm -f "$source_sig" "$backup_sig"
  else
    echo "${DB_BACKUP} has no insurance.claim yet. Run the logical section to create the isolated copy."
    record_evidence \
      "business snapshot compare" \
      "NOT_RUN" \
      "claim signature" \
      "No restored insurance.claim in ${DB_BACKUP}." \
      ""
  fi
}

run_pitr() {
  section "PITR: base backup plus every required WAL segment"
  echo "Point-in-time recovery is not a logical dump and it is not a storage snapshot."
  echo "The chain is: one verified base backup taken before the target, then every"
  echo "archived WAL segment through that target. Recovery runs in an empty PGDATA."
  echo "Choose one target only: a time, an LSN, a transaction, or a restore-point name."
  echo "Stop before the unwanted change, validate the claims, then promote or copy"
  echo "the repaired rows back. Do not restore an old dump over the live primary."
  echo
  echo "Isolated recovery settings, written into the new data directory, look like this:"
  echo "  restore_command = 'cp /wal_archive/%f %p'"
  echo "  recovery_target_name = 'claimsure_before_recovery_drill'"
  echo "  recovery_target_action = 'promote'"
  echo "  touch PGDATA/recovery.signal"
  echo
  echo "archive_mode and pg_create_restore_point are superuser operations."
  echo "This script does not switch WAL, create a restore point, or start PostgreSQL."
  echo "A named restore point is useful only when the base backup and the following"
  echo "WAL files are both retained."

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Dry run: would record a NOT_RUN evidence row in ${DB_NAME}."
    return 0
  fi

  record_evidence \
    "pitr lesson" \
    "NOT_RUN" \
    "read the base backup plus WAL chain; no recovery.signal was created" \
    "Shared primary was not recovered. PITR belongs on an isolated PGDATA with a verified base backup and continuous archived WAL." \
    ""
}

print_target() {
  echo "Lab:      $LAB"
  echo "Host:     ${DB_HOST}:${DB_PORT}"
  echo "DB user:  $DB_USER"
  echo "Source:   $DB_NAME"
  echo "Restore:  $DB_BACKUP"
  echo "Dump dir: $BACKUP_DIR"
}

main() {
  load_env
  parse_args "$@"

  if [[ "$LIST_ONLY" -eq 1 ]]; then
    list_m7
    exit 0
  fi
  if [[ -z "$LAB" ]]; then
    usage >&2
    exit 2
  fi

  LAB="$(normalize_lab "$LAB")"
  resolve_identity
  STAMP="$(date +%Y%m%d-%H%M%S)"
  print_target
  require_client
  prepare_password

  case "$LAB" in
    logical) run_logical ;;
    physical) run_physical ;;
    snapshot) run_snapshot ;;
    pitr) run_pitr ;;
    all)
      run_logical
      run_physical
      run_snapshot
      run_pitr
      ;;
  esac

  echo
  echo "Module 7 ${LAB} finished."
  echo "Evidence rows are in ${DB_NAME}, schema lab_m7."
  echo "The shared cluster was not copied and was not used as a recovery target."
}

main "$@"
