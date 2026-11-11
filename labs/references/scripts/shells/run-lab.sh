#!/usr/bin/env bash
# Run a lab (or one sub-lab) from scripts/sql on a remote host over SSH.
#
#   ./scripts/shells/run-lab.sh lab01_A
#   ./scripts/shells/run-lab.sh lab07_D
#   ./scripts/shells/run-lab.sh lab07_B -v snapshot=before_backup
#   ./scripts/shells/run-lab.sh --list
#
# Target: your assigned SSH account; set --student or STUDENT_NO first
#   psql "service=claimsure" -v ON_ERROR_STOP=1 -f <sql>
# Lab 7D uses service=backup unless --service is set.
# Module 6 delegates to run-lab06-docker.sh in the repository; --local uses the classroom runner.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SQL_DIR="$REPO_ROOT/scripts/sql"

SSH_HOST="${SSH_HOST:-31.220.82.70}"
SSH_USER="${SSH_USER:-${USER:-}}"
SSH_PORT="${SSH_PORT:-22}"
SSH_IDENTITY="${SSH_IDENTITY:-}"
PGSERVICE="${PGSERVICE:-claimsure}"
PGSERVICE_BACKUP="${PGSERVICE_BACKUP:-backup}"

RUN_LOCAL=0
DRY_RUN=0
FORCE_TTY=0
LIST_ONLY=0
ASK_PASS=0
USE_SSHPASS=0
SERVICE_OVERRIDE=""
LAB_ID=""
PAYLOAD_FILE=""
PSQL_EXTRA=()
STUDENT_OVERRIDE=""
SQL_OVERRIDE=""
MODULE4_LOGIN=""

usage() {
  cat <<'EOF'
Usage: run-lab.sh [options] <lab_id> [-- psql-args...]

Run SQL from scripts/sql on the remote lab server:

  ssh <user>@<host>  then  psql "service=<name>" -v ON_ERROR_STOP=1 -f <sql>

Lab IDs
  Whole module     lab01   lab03   07
  Sub-lab          lab01_A   lab03_B   lab05_D.1   lab07-D
  Module 4 block   lab04_0   lab04_A.1   lab04_C.4 (one START/END block)
  Two-session      lab05_mvcc_a   lab05_mvcc_b
                   lab09_lock_a   lab09_lock_b

Options
  -l, --list          List modules and lettered sub-labs
      --host HOST     SSH host (default: 31.220.82.70 or SSH_HOST)
      --user USER     SSH user (SSH_USER or current OS account)
      --port PORT     SSH port (default: 22)
      --identity FILE SSH private key
      --service NAME  libpq service (default: claimsure; lab07_D uses backup)
      --student xx    Student number 01-20 (also maps SSH user and service)
      --sql-file FILE Personal Module 4 template with passwords filled in
      --local         Run locally (default when LAB_RUN_LOCAL=1)
      --ask-pass      Prompt once for the SSH password (requires sshpass)
      --tty           Copy SQL to the remote host and allocate a TTY
      --dry-run       Print target and SQL, do not execute
  -h, --help          Show this help

Examples
  ./scripts/shells/run-lab.sh lab01_A
  ./scripts/shells/run-lab.sh --ask-pass lab01_A
  SSHPASS='your-password' ./scripts/shells/run-lab.sh lab01_A
  ./scripts/shells/run-lab.sh lab07_B -v snapshot=before_backup
  ./scripts/shells/run-lab.sh --student xx --dry-run lab04_A.1

Copy .env.example to .env to change the default host, user, or service names.
Set LAB_RUN_LOCAL=1 in .env when running directly on the lab server.
The remote account must have matching entries in ~/.pg_service.conf.
Password login needs sshpass. Prefer an SSH key when you can.
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
  SSH_HOST="${SSH_HOST:-31.220.82.70}"
  SSH_PORT="${SSH_PORT:-22}"
  SSH_IDENTITY="${SSH_IDENTITY:-}"
  # Installed student copies execute here instead of opening another SSH session.
  RUN_LOCAL="${LAB_RUN_LOCAL:-$RUN_LOCAL}"
  apply_student_mapping
}

apply_student_mapping() {
  local raw number
  raw="${STUDENT_OVERRIDE:-${LAB_STUDENT_NO:-${STUDENT_NO:-${SSH_USER:-${USER:-}}}}}"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  raw="${raw#claimsure_backup_}"
  raw="${raw#claimsure_}"
  raw="${raw#student_}"
  raw="${raw#student-}"
  raw="${raw#student}"
  if [[ "$raw" =~ ^[0-9]{1,2}$ ]]; then
    number=$((10#$raw))
    if (( number >= 1 && number <= 20 )); then
      raw="$(printf '%02d' "$number")"
      STUDENT_SUFFIX="$raw"
      SSH_USER="student${raw}"
      PGSERVICE="claimsure_${raw}"
      PGSERVICE_BACKUP="claimsure_backup_${raw}"
      return 0
    fi
  fi
  STUDENT_SUFFIX=""
}

pad_module() {
  local n="$1"
  n="${n#0}"
  [[ -z "$n" ]] && n=0
  if [[ "${#n}" -eq 1 ]]; then
    printf '0%s' "$n"
  else
    printf '%s' "$n"
  fi
}

sql_file_for_module() {
  case "$1" in
    01) printf '%s\n' "01-basic-sql.sql" ;;
    02) printf '%s\n' "02-advanced-sql.sql" ;;
    03) printf '%s\n' "03-performance-tuning.sql" ;;
    04) printf '%s\n' "04-security-user-management.sql" ;;
    05) printf '%s\n' "05-architecture.sql" ;;
    06) printf '%s\n' "06-configuration-claim.sql" ;;
    07) printf '%s\n' "07-backup-recovery.sql" ;;
    08) printf '%s\n' "08-replication.sql" ;;
    09) printf '%s\n' "09-monitoring.sql" ;;
    10) printf '%s\n' "10-modern-features-supabase.sql" ;;
    *) return 1 ;;
  esac
}

label_matches() {
  local label="$1"
  local want="$2"
  local part
  local oldifs="$IFS"
  IFS='/'
  # shellcheck disable=SC2086
  set -- $label
  IFS="$oldifs"
  for part in "$@"; do
    [[ "$part" == "$want" ]] && return 0
  done
  return 1
}

session_sql_file() {
  local module="$1"
  local section="$2"
  case "${module}_${section}" in
    05_E_A|05_MVCC_A|05_SESSION_A) printf '%s\n' "05-mvcc-session-a.sql" ;;
    05_E_B|05_MVCC_B|05_SESSION_B) printf '%s\n' "05-mvcc-session-b.sql" ;;
    09_LOCK_A|09_BLOCK_A|09_SESSION_A) printf '%s\n' "09-blocking-session-a.sql" ;;
    09_LOCK_B|09_BLOCK_B|09_SESSION_B) printf '%s\n' "09-blocking-session-b.sql" ;;
    *) return 1 ;;
  esac
}

normalize_lab() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  raw="${raw#LAB}"
  raw="${raw#_}"
  raw="${raw#-}"

  MODULE=""
  SECTION=""

  if [[ "$raw" =~ ^([0-9]+)[_-](E_A|E_B|MVCC_A|MVCC_B|SESSION_A|SESSION_B|LOCK_A|LOCK_B|BLOCK_A|BLOCK_B)$ ]]; then
    MODULE="$(pad_module "${BASH_REMATCH[1]}")"
    SECTION="${BASH_REMATCH[2]}"
    return 0
  fi

  if [[ "$raw" =~ ^([0-9]+)$ ]]; then
    MODULE="$(pad_module "${BASH_REMATCH[1]}")"
    SECTION=""
    return 0
  fi

  if [[ "$raw" =~ ^([0-9]+)[_-](.+)$ ]]; then
    MODULE="$(pad_module "${BASH_REMATCH[1]}")"
    SECTION="${BASH_REMATCH[2]}"
    return 0
  fi

  if [[ "$raw" =~ ^([0-9]+)([A-Z](\.[0-9]+)?)$ ]]; then
    MODULE="$(pad_module "${BASH_REMATCH[1]}")"
    SECTION="${BASH_REMATCH[2]}"
    return 0
  fi

  echo "Unrecognized lab id: $1" >&2
  echo "Try: lab01_A   lab03_B   lab05_D.1   lab07_D   --list" >&2
  return 1
}

want_token() {
  local module_num="$1"
  local section="$2"
  module_num="${module_num#0}"
  printf '%s%s\n' "$module_num" "$section"
}

extract_lab_section() {
  local sql_file="$1"
  local want="$2"
  local marker_file
  local line_no rest label
  local first_marker=0
  local start=0
  local end=0
  local last_line

  marker_file="$(mktemp)"
  grep -n "\\\\echo '\\\\n-- Lab " "$sql_file" >"$marker_file" || true

  if [[ ! -s "$marker_file" ]]; then
    cat "$sql_file"
    rm -f "$marker_file"
    return 0
  fi

  while IFS=: read -r line_no rest; do
    label="${rest#*-- Lab }"
    label="${label%%:*}"
    if [[ "$first_marker" -eq 0 ]]; then
      first_marker="$line_no"
    fi
    if [[ "$start" -eq 0 ]]; then
      if label_matches "$label" "$want"; then
        start="$line_no"
      fi
    elif [[ "$end" -eq 0 ]]; then
      end=$((line_no - 1))
      break
    fi
  done <"$marker_file"
  rm -f "$marker_file"

  if [[ "$start" -eq 0 ]]; then
    echo "No sub-lab '$want' in $(basename "$sql_file"). Use --list." >&2
    return 1
  fi

  last_line="$(wc -l <"$sql_file" | tr -d ' ')"
  if [[ "$end" -eq 0 ]]; then
    end="$last_line"
  fi

  if [[ "$first_marker" -gt 1 ]]; then
    sed -n "1,$((first_marker - 1))p" "$sql_file"
  fi
  sed -n "${start},${end}p" "$sql_file"
}

list_labs() {
  local module file path
  echo "Lab IDs (pass to run-lab.sh):"
  echo
  for module in 01 02 03 04 05 06 07 08 09 10; do
    file="$(sql_file_for_module "$module")"
    path="$SQL_DIR/$file"
    if [[ "$module" == "04" ]]; then
      echo "  Module 4: $file (one block at a time; postgres for 0/4A only)"
      awk '/^-- START / { id=$3; sub(/^4/, "", id); printf "    lab04_%s", id; next } /^-- LOGIN:/ { if (id != "") { printf "  %s\n", $0; id="" } }' "$path"
      continue
    fi
    printf '  lab%s\n' "$module"
    if [[ -f "$path" ]] && grep -q "\\\\echo '\\\\n-- Lab " "$path"; then
      grep "\\\\echo '\\\\n-- Lab " "$path" | while IFS= read -r line; do
        label="${line#*-- Lab }"
        label="${label%%:*}"
        oldifs="$IFS"
        IFS='/'
        # shellcheck disable=SC2086
        set -- $label
        IFS="$oldifs"
        for part in "$@"; do
          section="${part#"${part%%[!0-9]*}"}"
          printf '    lab%s_%s\n' "$module" "$section"
        done
      done
    else
      printf '    lab%s_A   (whole file)\n' "$module"
    fi
  done
  echo
  echo "  Two-session files:"
  echo "    lab05_mvcc_a    lab05_mvcc_b"
  echo "    lab09_lock_a    lab09_lock_b"
}

resolve_sql() {
  local session_file
  SQL_SOURCE=""
  EXTRACT_WANT=""
  USE_WHOLE_FILE=0

  if session_file="$(session_sql_file "$MODULE" "$SECTION")"; then
    SQL_SOURCE="$SQL_DIR/$session_file"
    USE_WHOLE_FILE=1
    return 0
  fi

  local module_file
  if ! module_file="$(sql_file_for_module "$MODULE")"; then
    echo "No SQL module for lab $MODULE" >&2
    return 1
  fi
  SQL_SOURCE="$SQL_DIR/$module_file"
  if [[ "$MODULE" == "04" ]]; then
    [[ -z "$SQL_OVERRIDE" ]] || SQL_SOURCE="$SQL_OVERRIDE"
    resolve_module4_block
    return
  elif [[ -n "$SQL_OVERRIDE" ]]; then
    echo "--sql-file is supported only for Module 4." >&2
    return 1
  fi
  if [[ ! -f "$SQL_SOURCE" ]]; then
    echo "Missing SQL file: $SQL_SOURCE" >&2
    return 1
  fi

  if [[ -z "$SECTION" ]]; then
    USE_WHOLE_FILE=1
    return 0
  fi

  if grep -q "\\\\echo '\\\\n-- Lab " "$SQL_SOURCE"; then
    EXTRACT_WANT="$(want_token "$MODULE" "$SECTION")"
    USE_WHOLE_FILE=0
  else
    if [[ "$SECTION" == "A" ]]; then
      USE_WHOLE_FILE=1
    else
      echo "Module $MODULE has no lettered sub-labs. Use lab${MODULE} or lab${MODULE}_A." >&2
      return 1
    fi
  fi
}

resolve_module4_block() {
  if [[ ! -f "$SQL_SOURCE" ]]; then
    echo "Missing SQL file: $SQL_SOURCE" >&2
    return 1
  fi
  if [[ -z "$SECTION" || ! "$SECTION" =~ ^(0|[A-H]\.[0-9]+)$ ]]; then
    echo "Module 4 uses multiple logins. Select one block, e.g. lab04_0, lab04_A.1 or lab04_C.4; use --list for the sequence." >&2
    return 1
  fi
  if [[ -z "${STUDENT_SUFFIX:-}" ]]; then
    echo "Module 4 needs a student number 01-20; pass --student xx." >&2
    return 1
  fi
  EXTRACT_WANT="$(want_token "$MODULE" "$SECTION")"
  [[ "$SECTION" != "0" ]] || EXTRACT_WANT=0
  MODULE4_LOGIN="$(extract_module4_block | sed -nE 's/^-- LOGIN: [ASBCD] = ([a-z_]+).*/\1/p')"
  if [[ -z "$MODULE4_LOGIN" ]]; then
    echo "No START/END block $EXTRACT_WANT with a LOGIN in $SQL_SOURCE." >&2
    return 1
  fi
  MODULE4_LOGIN="${MODULE4_LOGIN//xx/$STUDENT_SUFFIX}"
  USE_WHOLE_FILE=0
}

extract_module4_block() {
  awk -v want="$EXTRACT_WANT" '
    $0 ~ "^-- START " want " \\|" { active=1 }
    active { print }
    $0 == "-- END " want { active=0 }
  ' "$SQL_SOURCE"
}

build_module4_payload() {
  local dest="$1" block
  block="$(extract_module4_block)"
  if [[ "$DRY_RUN" -eq 0 && "$block" == *change_me_* ]]; then
    echo "Set real passwords in a personal copy, then pass --sql-file FILE for 4A.3. Preview with --dry-run." >&2
    return 1
  fi
  {
    # Refuse an incorrect service identity instead of testing permissions as postgres.
    printf '\\set ON_ERROR_STOP on\n'
    printf "SELECT session_user = '%s' AND current_user = '%s' AND current_database() = 'claimsure_%s' AS correct_connection \\gset\n" "$MODULE4_LOGIN" "$MODULE4_LOGIN" "$STUDENT_SUFFIX"
    printf '\\if :correct_connection\n\\else\n\\echo Wrong Module 4 login or database.\nSELECT 1 / 0 AS module4_wrong_connection;\n\\endif\n'
    if [[ "$block" == *'| EXPECTED ERROR:'* ]]; then
      printf '\\set ON_ERROR_STOP off\n'
      printf '%s\n' "${block//xx/$STUDENT_SUFFIX}"
      # The last statement must fail with the documented permission SQLSTATE.
      # Capture it before rollback, then fail the runner if denial was not observed.
      printf '\\set module4_sqlstate :SQLSTATE\nROLLBACK;\n\\set ON_ERROR_STOP on\n'
      printf "SELECT :'module4_sqlstate' = '42501' AS expected_denial \\gset\n"
      printf '\\if :expected_denial\n\\echo Expected permission denial verified; transaction rolled back.\n\\else\n\\echo Expected SQLSTATE 42501; received :module4_sqlstate\nSELECT 1 / 0 AS module4_missing_expected_denial;\n\\endif\n'
    else
      printf '%s\n' "${block//xx/$STUDENT_SUFFIX}"
    fi
  } >"$dest"
}

choose_service() {
  if [[ -n "$SERVICE_OVERRIDE" ]]; then
    printf '%s\n' "$SERVICE_OVERRIDE"
    return
  fi
  if [[ "$MODULE" == "07" && "$SECTION" == "D" ]]; then
    printf '%s\n' "$PGSERVICE_BACKUP"
    return
  fi
  printf '%s\n' "$PGSERVICE"
}

sql_needs_tty() {
  grep -q $'\\prompt ' "$1"
}

build_sql_payload() {
  local dest="$1"
  if [[ "$MODULE" == "04" ]]; then
    build_module4_payload "$dest"
    return
  fi
  if [[ "$USE_WHOLE_FILE" -eq 1 ]]; then
    cat "$SQL_SOURCE" >"$dest"
  else
    extract_lab_section "$SQL_SOURCE" "$EXTRACT_WANT" >"$dest"
  fi
}

prepare_ssh_password() {
  if [[ "$RUN_LOCAL" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  if [[ "$ASK_PASS" -eq 1 ]]; then
    if [[ ! -t 0 ]]; then
      echo "--ask-pass needs an interactive terminal." >&2
      return 1
    fi
    printf 'SSH password for %s@%s: ' "$SSH_USER" "$SSH_HOST" >&2
    IFS= read -r -s SSHPASS
    printf '\n' >&2
    if [[ -z "${SSHPASS}" ]]; then
      echo "SSH password was empty." >&2
      return 1
    fi
    export SSHPASS
  fi
  if [[ -n "${SSHPASS:-}" ]]; then
    if command -v sshpass >/dev/null 2>&1; then
      USE_SSHPASS=1
    elif [[ "$ASK_PASS" -eq 1 ]]; then
      echo "sshpass is not installed; cannot use --ask-pass." >&2
      echo "Use an SSH key instead, or run the SQL after you ssh in." >&2
      return 1
    else
      echo "SSHPASS is set but sshpass is missing. Using SSH key or an interactive prompt." >&2
      USE_SSHPASS=0
    fi
  fi
}

ssh_base() {
  SSH_CMD=(ssh -p "$SSH_PORT")
  SCP_CMD=(scp -P "$SSH_PORT")
  if [[ "$USE_SSHPASS" -eq 1 ]]; then
    SSH_CMD=(sshpass -e ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -p "$SSH_PORT")
    SCP_CMD=(sshpass -e scp -o PreferredAuthentications=password -o PubkeyAuthentication=no -P "$SSH_PORT")
  fi
  if [[ -n "$SSH_IDENTITY" ]]; then
    SSH_CMD+=(-i "$SSH_IDENTITY")
    SCP_CMD+=(-i "$SSH_IDENTITY")
  fi
  SSH_TARGET="${SSH_USER}@${SSH_HOST}"
}

quote_remote() {
  local arg quoted=""
  for arg in "$@"; do
    quoted+=" $(printf '%q' "$arg")"
  done
  printf '%s' "$quoted"
}

run_remote() {
  local sql_file="$1"
  local service="$2"
  local remote_psql
  local conninfo="service=${service}"
  if [[ "$MODULE" == "04" ]]; then
    conninfo+=" user=$MODULE4_LOGIN dbname=claimsure_$STUDENT_SUFFIX"
  fi
  remote_psql="psql $(printf '%q' "$conninfo") -v ON_ERROR_STOP=1"
  remote_psql+="$(quote_remote "${PSQL_EXTRA[@]+"${PSQL_EXTRA[@]}"}")"

  if [[ "$FORCE_TTY" -eq 1 ]] || sql_needs_tty "$sql_file"; then
    local remote_dir remote_sql
    remote_dir="/tmp/postgres-admin-labs"
    remote_sql="${remote_dir}/${LAB_ID}.sql"
    "${SSH_CMD[@]}" "$SSH_TARGET" "mkdir -p $(printf '%q' "$remote_dir")"
    "${SCP_CMD[@]}" "$sql_file" "${SSH_TARGET}:${remote_sql}"
    "${SSH_CMD[@]}" -t "$SSH_TARGET" "${remote_psql} -f $(printf '%q' "$remote_sql")"
  else
    "${SSH_CMD[@]}" "$SSH_TARGET" "${remote_psql} -f -" <"$sql_file"
  fi
}

run_local() {
  local sql_file="$1"
  local service="$2"
  local conninfo="service=${service}"
  if [[ "$MODULE" == "04" ]]; then
    conninfo+=" user=$MODULE4_LOGIN dbname=claimsure_$STUDENT_SUFFIX"
  fi
  psql "$conninfo" -v ON_ERROR_STOP=1 "${PSQL_EXTRA[@]+"${PSQL_EXTRA[@]}"}" -f "$sql_file"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -l|--list)
        LIST_ONLY=1
        shift
        ;;
      --host)
        SSH_HOST="$2"
        shift 2
        ;;
      --user)
        SSH_USER="$2"
        shift 2
        ;;
      --port)
        SSH_PORT="$2"
        shift 2
        ;;
      --identity)
        SSH_IDENTITY="$2"
        shift 2
        ;;
      --service)
        SERVICE_OVERRIDE="$2"
        shift 2
        ;;
      --student)
        STUDENT_OVERRIDE="$2"
        if [[ ! "$STUDENT_OVERRIDE" =~ ^0?[1-9]$|^1[0-9]$|^20$ ]]; then
          echo "--student must be 01-20." >&2
          exit 2
        fi
        shift 2
        ;;
      --sql-file)
        SQL_OVERRIDE="$2"
        shift 2
        ;;
      --local)
        RUN_LOCAL=1
        shift
        ;;
      --ask-pass)
        ASK_PASS=1
        shift
        ;;
      --tty)
        FORCE_TTY=1
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
        if [[ -n "$LAB_ID" ]]; then
          PSQL_EXTRA+=("$1")
          shift
          continue
        fi
        echo "Unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
      *)
        if [[ -z "$LAB_ID" ]]; then
          LAB_ID="$1"
        else
          PSQL_EXTRA+=("$1")
        fi
        shift
        ;;
    esac
  done
}

main() {
  load_env
  parse_args "$@"
  apply_student_mapping

  if [[ "$LIST_ONLY" -eq 1 ]]; then
    list_labs
    exit 0
  fi

  if [[ -z "$LAB_ID" ]]; then
    usage >&2
    exit 2
  fi

  if [[ -z "${STUDENT_SUFFIX:-}" ]]; then
    echo "Set --student or STUDENT_NO to your assigned number (01-20); xx is a placeholder." >&2
    exit 2
  fi

  normalize_lab "$LAB_ID"
  if [[ "$MODULE" == "06" && "$RUN_LOCAL" -eq 1 ]]; then
    case "${SECTION:-all}" in A|B|C|D|E|F|G|all) ;; *)
      echo "Classroom Module 6 uses labs A–G. See scripts/shells/module06-configuration-lab.md." >&2
      exit 2 ;;
    esac
    if [[ -n "$SERVICE_OVERRIDE" || -n "$SQL_OVERRIDE" || ${#PSQL_EXTRA[@]} -gt 0 ]]; then
      echo "Use run-lab06.sh directly for classroom Module 6 options." >&2
      exit 2
    fi
    echo "Module 6: classroom measurements for student_$STUDENT_SUFFIX."
    if [[ "$DRY_RUN" -eq 1 ]]; then
      exec "$SCRIPT_DIR/run-lab06.sh" --student "$STUDENT_SUFFIX" --dry-run "${SECTION:-all}"
    fi
    exec "$SCRIPT_DIR/run-lab06.sh" --student "$STUDENT_SUFFIX" "${SECTION:-all}"
  fi
  if [[ "$MODULE" == "06" ]]; then
    case "${SECTION:-all}" in A|B|C|D|E|F|all) ;; *)
      echo "Module 6 uses labs A–F. See labs/module06/README.md." >&2; exit 2 ;;
    esac
    if [[ -n "$SERVICE_OVERRIDE" || -n "$SQL_OVERRIDE" || ${#PSQL_EXTRA[@]} -gt 0 ]]; then
      echo "Module 6 now uses its dedicated Docker instance; use run-lab06-docker.sh. See labs/module06/README.md." >&2
      exit 2
    fi
    echo "Module 6: dedicated local Docker instance, postgres / claimsure_m6."
    echo "SQL track only; complete file activation exercises in labs/module06/README.md."
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "Would run: $REPO_ROOT/scripts/shells/run-lab06-docker.sh sql ${SECTION:-all}"
      return 0
    fi
    exec "$REPO_ROOT/scripts/shells/run-lab06-docker.sh" sql "${SECTION:-all}"
  fi
  resolve_sql
  SERVICE_NAME="$(choose_service)"

  PAYLOAD_FILE="$(mktemp)"
  trap 'rm -f "$PAYLOAD_FILE"' EXIT
  build_sql_payload "$PAYLOAD_FILE"

  echo "Lab:     $LAB_ID"
  echo "SQL:     ${SQL_SOURCE#$REPO_ROOT/}"
  if [[ "$USE_WHOLE_FILE" -eq 0 ]]; then
    echo "Section: Lab $EXTRACT_WANT"
  fi
  echo "Service: $SERVICE_NAME"
  if [[ "$MODULE" == "04" ]]; then
    echo "DB user: $MODULE4_LOGIN"
    echo "DB name: claimsure_$STUDENT_SUFFIX"
  fi
  if [[ "$RUN_LOCAL" -eq 1 ]]; then
    echo "Target:  local psql"
  else
    echo "Target:  ${SSH_USER}@${SSH_HOST}:${SSH_PORT}"
    if [[ "$ASK_PASS" -eq 1 || -n "${SSHPASS:-}" ]]; then
      echo "Auth:    SSH password (once, via sshpass)"
    elif [[ -n "$SSH_IDENTITY" ]]; then
      echo "Auth:    SSH key $SSH_IDENTITY"
    fi
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo
    echo "----- SQL that would run -----"
    cat "$PAYLOAD_FILE"
    return 0
  fi

  echo
  if [[ "$RUN_LOCAL" -eq 1 ]]; then
    run_local "$PAYLOAD_FILE" "$SERVICE_NAME"
  else
    prepare_ssh_password
    ssh_base
    run_remote "$PAYLOAD_FILE" "$SERVICE_NAME"
  fi
}

main "$@"
