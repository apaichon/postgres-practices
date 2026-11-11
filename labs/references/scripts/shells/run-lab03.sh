#!/usr/bin/env bash
# Run Module 3 labs directly against each student's isolated database.
#
#   ./scripts/shells/run-lab03.sh --student xx --ask-pass A
#   ./scripts/shells/run-lab03.sh --student xx E
#   ./scripts/shells/run-lab03.sh --student xx all
#   ./scripts/shells/run-lab03.sh --list
#
# Default mapping for student xx (01-20):
#   SSH user     studentxx
#   DB user      student_xx
#   database     claimsure_xx
#   backup db    claimsure_backup_xx
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SQL_SOURCE="$REPO_ROOT/scripts/sql/03-performance-tuning.sql"

DB_HOST="31.220.82.70"
DB_PORT="6432"
STUDENT_NO="${STUDENT_NO:-}"
USER_OVERRIDE=""
DATABASE_OVERRIDE=""
USE_BACKUP=0

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
  DATABASE_OVERRIDE="${LAB_DB_NAME:-${DATABASE_OVERRIDE:-}}"

  if [[ -z "$DATABASE_OVERRIDE" && "${PGSERVICE:-}" =~ ^claimsure_([0-9]{2})$ ]]; then
    DATABASE_OVERRIDE="$PGSERVICE"
  fi
  if [[ -z "${PGPASSWORD:-}" ]]; then
    if [[ -n "${DB_PASSWORD:-}" ]]; then
      export PGPASSWORD="$DB_PASSWORD"
    elif [[ -n "${LAB_DB_PASSWORD:-}" ]]; then
      export PGPASSWORD="$LAB_DB_PASSWORD"
    fi
  fi
}

ASK_PASS=0
DRY_RUN=0
LIST_ONLY=0
STUDENT_EXPLICIT=0
LAB=""
PSQL_EXTRA=()
PAYLOAD_FILE=""

usage() {
  cat <<'EOF'
Usage: run-lab03.sh [options] <lab> [-- psql-args...]

Run Module 3 SQL directly on the student's isolated PostgreSQL database.

Student mapping (xx = 01..20)
  SSH login     studentxx
  DB user       student_xx
  Database      claimsure_xx
  Backup DB     claimsure_backup_xx

Labs
  A   compare a slow plan with a partial covering index
  B   expression, GIN, and BRIN indexes by query shape
  C   index and autovacuum maintenance evidence
  D   monthly range-partitioned reporting copy
  E   materialized summary and dashboard snapshot
  all whole Module 3 file

Options
      --student N       Student number 1..20 (also studentxx or student_xx)
      --host HOST       Database host (default: 31.220.82.70)
      --port PORT       Database port (default: 6432)
      --user USER       Must match student_xx or studentxx
      --database DB     claimsure_xx or claimsure_backup_xx for the same xx
      --backup          Use claimsure_backup_xx
      --ask-pass        Ask for the database password before connecting
      --dry-run         Print the target and SQL without running it
  -l, --list            List Module 3 labs
  -h, --help            Show this help

Examples
  ./scripts/shells/run-lab03.sh --student xx --ask-pass all
  ./scripts/shells/run-lab03.sh --student xx A
  ./scripts/shells/run-lab03.sh --student xx E
  PGPASSWORD='provided-in-class' ./scripts/shells/run-lab03.sh --student xx E

Each individual section also prepares the shared 200,000-row claim_perf
workload, so it can run independently but may take a little time.
Copy .env.example to .env. The script loads .env before connecting.
CLI flags override values from .env.
The script rejects mismatched pairs such as student_xx with claimsure_xx.
The PostgreSQL server must also grant each role CONNECT only to its own database.
EOF
}

list_m3() {
  cat <<'EOF'
Module 3 labs (03-performance-tuning.sql)

  lab03_A   partial covering index and before/after plan
  lab03_B   expression, GIN, and BRIN indexes
  lab03_C   index statistics and autovacuum evidence
  lab03_D   monthly range partitions and pruning
  lab03_E   materialized summary and dashboard snapshot
  lab03     whole file

Every section includes the common claim_perf workload setup. Use "all" to
complete the full evidence flow in one run.
EOF
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

suffix_from_database() {
  if [[ "$1" =~ ^claimsure_backup_([0-9]{1,2})$ ]]; then
    normalize_student_no "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "$1" =~ ^claimsure_([0-9]{1,2})$ ]]; then
    normalize_student_no "${BASH_REMATCH[1]}"
    return
  fi
  echo "Invalid database: $1. Expected claimsure_xx or claimsure_backup_xx (xx = assigned number 01-20)." >&2
  return 1
}

resolve_identity() {
  local requested_no user_no database_no

  requested_no="$(normalize_student_no "$STUDENT_NO")"
  user_no=""
  database_no=""

  if [[ -n "$USER_OVERRIDE" ]]; then
    user_no="$(suffix_from_user "$USER_OVERRIDE")"
  fi
  if [[ -n "$DATABASE_OVERRIDE" ]]; then
    database_no="$(suffix_from_database "$DATABASE_OVERRIDE")"
  fi

  if [[ "$STUDENT_EXPLICIT" -eq 0 && -n "$user_no" && -n "$database_no" && "$user_no" != "$database_no" ]]; then
    echo "Access mapping mismatch: $USER_OVERRIDE cannot use $DATABASE_OVERRIDE." >&2
    echo "Use student_xx with claimsure_xx or claimsure_backup_xx for the same xx." >&2
    return 1
  fi

  if [[ "$STUDENT_EXPLICIT" -eq 1 ]]; then
    :
  elif [[ -n "$user_no" ]]; then
    requested_no="$user_no"
  elif [[ -n "$database_no" ]]; then
    requested_no="$database_no"
  fi

  STUDENT_NO="$requested_no"
  SSH_LOGIN="student${STUDENT_NO}"
  DB_USER="student_${STUDENT_NO}"
  DB_NAME="claimsure_${STUDENT_NO}"
  DB_BACKUP="claimsure_backup_${STUDENT_NO}"

  if [[ "$USE_BACKUP" -eq 1 ]]; then
    DB_NAME="$DB_BACKUP"
  elif [[ -n "$DATABASE_OVERRIDE" && "$DATABASE_OVERRIDE" == claimsure_backup_* ]]; then
    DB_NAME="$DB_BACKUP"
  fi
}

normalize_lab() {
  local value
  value="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"

  case "$value" in
    ALL|03|LAB03)
      printf '%s\n' "ALL"
      ;;
    LAB03_[A-E])
      printf '%s\n' "${value#LAB03_}"
      ;;
    [A-E])
      printf '%s\n' "$value"
      ;;
    *)
      echo "Unknown Module 3 lab: $1" >&2
      echo "Use A-E, all, or --list." >&2
      return 1
      ;;
  esac
}

extract_lab_section() {
  local section="$1"
  local marker_file line_no rest label
  local first_marker=0 start=0 end=0 last_line

  marker_file="$(mktemp)"
  grep -n "\\\\echo '\\\\n-- Lab 3" "$SQL_SOURCE" >"$marker_file" || true

  while IFS=: read -r line_no rest; do
    label="${rest#*-- Lab 3}"
    label="${label%%:*}"
    if [[ "$first_marker" -eq 0 ]]; then
      first_marker="$line_no"
    fi
    if [[ "$start" -eq 0 && "$label" == "$section" ]]; then
      start="$line_no"
    elif [[ "$start" -ne 0 && "$end" -eq 0 ]]; then
      end=$((line_no - 1))
      break
    fi
  done <"$marker_file"
  rm -f "$marker_file"

  if [[ "$start" -eq 0 ]]; then
    echo "No Lab 3$section section in $(basename "$SQL_SOURCE")." >&2
    return 1
  fi

  last_line="$(wc -l <"$SQL_SOURCE" | tr -d ' ')"
  if [[ "$end" -eq 0 ]]; then
    end="$last_line"
  fi

  if [[ "$first_marker" -gt 1 ]]; then
    sed -n "1,$((first_marker - 1))p" "$SQL_SOURCE"
  fi
  sed -n "${start},${end}p" "$SQL_SOURCE"
}

build_payload() {
  if [[ "$LAB" == "ALL" ]]; then
    cp "$SQL_SOURCE" "$PAYLOAD_FILE"
  else
    extract_lab_section "$LAB" >"$PAYLOAD_FILE"
  fi
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
      --database)
        DATABASE_OVERRIDE="$2"
        shift 2
        ;;
      --backup)
        USE_BACKUP=1
        shift
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
        PSQL_EXTRA+=("$@")
        break
        ;;
      -*)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
      *)
        if [[ -z "$LAB" ]]; then
          LAB="$1"
        else
          PSQL_EXTRA+=("$1")
        fi
        shift
        ;;
    esac
  done
}

main() {
  local password_label
  local -a psql_command

  load_env
  parse_args "$@"

  if [[ "$LIST_ONLY" -eq 1 ]]; then
    list_m3
    exit 0
  fi
  if [[ -z "$LAB" ]]; then
    usage >&2
    exit 2
  fi
  if [[ ! -f "$SQL_SOURCE" ]]; then
    echo "Missing SQL file: $SQL_SOURCE" >&2
    exit 1
  fi

  LAB="$(normalize_lab "$LAB")"
  resolve_identity

  PAYLOAD_FILE="$(mktemp)"
  trap 'rm -f "$PAYLOAD_FILE"' EXIT
  build_payload

  echo "Lab:      ${LAB/ALL/all}"
  echo "Host:     ${DB_HOST}:${DB_PORT}"
  echo "SSH user: $SSH_LOGIN"
  echo "DB user:  $DB_USER"
  echo "Database: $DB_NAME"
  echo "Backup:   $DB_BACKUP"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo
    echo "----- SQL that would run -----"
    cat "$PAYLOAD_FILE"
    return 0
  fi

  psql_command=(
    psql -X
    -h "$DB_HOST"
    -p "$DB_PORT"
    -U "$DB_USER"
    -d "$DB_NAME"
    -v ON_ERROR_STOP=1
  )
  if [[ "$ASK_PASS" -eq 1 ]]; then
    psql_command+=(-W)
    password_label="interactive password prompt"
  elif [[ -n "${PGPASSWORD:-}" ]]; then
    password_label=".env (DB_PASSWORD)"
  else
    password_label=".pgpass or psql prompt"
  fi
  if (( ${#PSQL_EXTRA[@]} > 0 )); then
    psql_command+=("${PSQL_EXTRA[@]}")
  fi
  psql_command+=(-f "$PAYLOAD_FILE")

  echo "Password: $password_label"
  echo
  # .env also sets PGSERVICE for the SSH runner. That service file lives on
  # the lab server, not this laptop, so unset it before a direct psql connect.
  unset PGSERVICE PGSERVICEFILE
  PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}" "${psql_command[@]}"
}

main "$@"
