#!/usr/bin/env bash
# Module 7: guided PostgreSQL 18 backup and recovery; no sudo or Docker needed.
set -euo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Student installations keep credentials one directory above scripts/.
if [[ "${SCRIPT_DIR##*/}" == scripts && -r "$SCRIPT_DIR/../.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/../.env"
fi
DRY=0
SID="${STUDENT_NO:-${USER:-}}"
usage() {
  cat <<'HELP'
Usage: run-lab07.sh [--student 1..20] [--dry-run] [action [parameters...]]
No action opens the guided menu. Missing parameters are prompted interactively.

Actions and parameter order:
  seed              [database] [--reset-practice]
  practice-backup   [file]  # claimsure_xx practice schema on port 5432
  practice-restore  [file] [TARGET_DB]  # or: [file] --database TARGET_DB
  logical-backup    [database] [database|schema|table|definitions|data] [object|-] [file]
  logical-restore   [file] [target_database] [all|schema|table] [object|-]
  doctor            # check private-lab tools without creating a cluster
  sandbox-init
  sandbox-start
  physical-backup   [destination_directory]
  snapshot-backup   [destination_directory]
  claimsure-snapshot-backup [auto|NEW_directory]
  claimsure-snapshot-restore [latest|directory] [--database main|backup|DATABASE]
  claimsure-pitr-backup [auto|NEW_directory]
  claimsure-pitr-event  # commit row 4 after the base, before the target
  claimsure-pitr-mark [unique_name] [latest|base_directory]
  claimsure-pitr-restore [latest|base_directory] [--database main|backup|DATABASE]
                        [--at-name NAME | --at-time saved|TIMESTAMP]
  physical-restore  [backup_directory] [auto|NEW_target_directory]
  snapshot-restore  [backup_directory] [auto|NEW_target_directory]
  mark              [restore_point_name]
  damage            [main|sandbox]  # default: claimsure_xx on port 5432
  pitr-restore      [base_backup_directory] [name|time] [target_value] [auto|NEW_target_directory]
  inspect           [database]
  inspect-recovery  # claimsure_backup_xx on port 5432
  inspect-sandbox-recovery  # private physical/snapshot/PITR copy
  stop
  cleanup [--yes|--dry-run] [--data-only|--files-only]
                    # default: preview; --yes clears only Module 7 artifacts

Database shortcuts (no shell variables required):
  main     claimsure_xx
  backup   claimsure_backup_xx
  sandbox  m7_xx (private source)
  restore  m7_restore_xx (private logical restore target)
Full database names remain supported.

Logical source databases: claimsure_xx, claimsure_backup_xx, m7_xx (private).
Generic logical restore target: claimsure_backup_xx or m7_restore_xx (private).
Practice restore target: main/claimsure_xx or backup/claimsure_backup_xx.
The practice target defaults to backup; the menu prompts for a target.
Physical, raw snapshot and PITR actions operate only on your private sandbox.
claimsure-snapshot-* and claimsure-pitr-* stage shared practice data privately, then import
the recovered practice schema into your own selected database on port 5432.
Cluster restore target auto (or omitted on the CLI) creates a unique new directory.
Existing explicit recovery directories are never overwritten.
Backup destinations must be new. Generic logical-restore never cleans objects.
practice-restore replaces only lab_m7_practice in the selected own main/backup database.
seed main --reset-practice resets only the practice table in your main database.
A table-only archive needs its schema and dependent objects already in the target.
Use .pgpass or DB_PASSWORD/PGPASSWORD for the shared server, never CLI passwords.

Configuration:
  PG_BIN        PostgreSQL 18 bin directory (auto-detect host tools or lab bundle)
  M7_WORKDIR    private sandbox (default ~/m7; absolute path without spaces/quotes)
  M7_BACKUP_DIR backup directory (default ~/backups/module07)
  LAB_DB_HOST   shared server (default 127.0.0.1)
  M7_DB_PORT    direct shared PostgreSQL port (default 5432; bypasses PgBouncer)

Examples:
  ./run-lab07.sh --student xx
  ./run-lab07.sh seed main --reset-practice
  ./run-lab07.sh damage
  ./run-lab07.sh inspect main
  ./run-lab07.sh inspect-recovery
  ./run-lab07.sh practice-restore ~/backups/module07/practice.dump --database main
  ./run-lab07.sh physical-backup "$HOME/backups/module07/base"
  ./run-lab07.sh snapshot-restore "$HOME/backups/module07/snapshot" auto
  ./run-lab07.sh --student xx --dry-run physical-backup /tmp/example-base
  ./run-lab07.sh --student xx logical-backup claimsure_xx schema insurance ~/backups/insurance.dump
  ./run-lab07.sh --student xx logical-restore ~/backups/insurance.dump claimsure_backup_xx all -
Read module07-backup-recovery.txt for the complete lab and prerequisites.
Read module07-manual-labs-c-d.md for Labs C/D with native commands, without wrappers.
HELP
}
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
while (( $# )); do
  case "$1" in
    --student) (( $# >= 2 )) || die '--student needs a number'; SID="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) die "Unknown option: $1" ;;
    *) break ;;
  esac
done
SID="${SID#student_}"; SID="${SID#student}"
if [[ ! "$SID" =~ ^[0-9]{1,2}$ ]]; then
  if (( DRY )); then die 'Supply --student 1..20'; fi
  read -r -p 'Student number (1..20): ' SID
fi
[[ "$SID" =~ ^[0-9]{1,2}$ ]] || die 'Student number must be 1..20'
(( 10#$SID >= 1 && 10#$SID <= 20 )) || die 'Student number must be 1..20'
printf -v SID '%02d' "$((10#$SID))"
if [[ "${USER:-}" =~ ^student([0-9]{2})$ ]]; then
  [[ "$SID" == "${BASH_REMATCH[1]}" ]] || die 'Use your own student number'
fi
# The classroom primary may run in Docker. Private clusters use these native
# tools independently; the optional bundle never installs a host system service.
BUNDLED_RUNTIME=/usr/local/lib/claimsure-postgres18
if [[ -z "${PG_BIN:-}" ]]; then
  if [[ -x /usr/lib/postgresql/18/bin/initdb ]]; then
    PG_BIN=/usr/lib/postgresql/18/bin
  elif [[ -x "$BUNDLED_RUNTIME/usr/lib/postgresql/18/bin/initdb" ]]; then
    PG_BIN="$BUNDLED_RUNTIME/usr/lib/postgresql/18/bin"
  else
    PG_BIN=/usr/lib/postgresql/18/bin
  fi
fi
if [[ "$PG_BIN" == */usr/lib/postgresql/18/bin ]]; then
  runtime_root="${PG_BIN%/usr/lib/postgresql/18/bin}"
  if [[ -f "$runtime_root/.module07-runtime" ]]; then
    for library_dir in "$runtime_root"/usr/lib/*-linux-gnu; do
      if [[ -d "$library_dir" ]]; then
        export LD_LIBRARY_PATH="$library_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      fi
    done
  fi
fi
export PATH="$PG_BIN:$PATH"
if [[ -n "${DB_PASSWORD:-}" ]]; then export PGPASSWORD="$DB_PASSWORD"; fi
WORK="${M7_WORKDIR:-$HOME/m7}"
[[ "$WORK" =~ ^/[a-zA-Z0-9_./-]+$ ]] || die 'M7_WORKDIR must be absolute, without spaces or quotes'
WORK="$(realpath -m -- "$WORK")"
[[ "$WORK" != / && "$WORK" != "$HOME" ]] || die 'Choose a dedicated M7_WORKDIR'
PRIMARY="$WORK/primary"
SOCKET="$WORK/sock"
SOURCE_PORT=$((5700 + 10#$SID))
RECOVERY_PORT=$((5800 + 10#$SID))
LOCAL_DB="m7_$SID"
BACKUPS="${M7_BACKUP_DIR:-$HOME/backups/module07}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"
RESTART_PRIMARY=0
WORK_LOCKED=0
show() { printf '+ '; printf '%q ' "$@"; printf '\n'; }
run() { show "$@"; if (( ! DRY )); then "$@" 9>&-; fi; }
need() { (( DRY )) || command -v "$1" >/dev/null || die "Missing $1. Instructor: run scripts/setup-module07-runtime.sh, then install-module07.py (see lab)."; }
# Capture SQL results while leaving the displayed command outside the result.
query() {
  show "${CONN[@]}" -Atc "$1" >&2
  if (( ! DRY )); then "${CONN[@]}" -Atc "$1"; fi
}
ask() {
  local variable="$1" label="$2" default="$3" supplied="${4:-}" answer
  if [[ -n "$supplied" ]]; then printf -v "$variable" '%s' "$supplied"; return; fi
  if (( DRY )); then printf -v "$variable" '%s' "$default"; return; fi
  read -r -p "$label [$default]: " answer || die "Missing input: $label"
  printf -v "$variable" '%s' "${answer:-$default}"
}
format() { printf '\nCommand format: %s\n' "$1"; }
write_file() {
  printf '+ write %s:\n%s\n' "$1" "$2"
  if (( ! DRY )); then printf '%s\n' "$2" > "$1"; fi
}
owned_workspace() {
  (( DRY )) && return
  [[ -d "$WORK" && ! -L "$WORK" && -O "$WORK" && -f "$WORK/.module07" ]] || die 'Run sandbox-init first'
  [[ "$(cat "$WORK/.module07")" == "$UID:$SID" ]] || die 'Sandbox belongs to another student'
}
lock_workspace() {
  owned_workspace
  (( WORK_LOCKED )) && return
  if (( ! DRY )); then
    exec 9>"$WORK/.lock"
    flock -n 9 || die 'Another Module 7 action is running in this sandbox'
    WORK_LOCKED=1
  fi
}
private_conn() {
  local db="${1:-$LOCAL_DB}" port="${2:-$SOURCE_PORT}"
  CONN=(psql -X --no-password -v ON_ERROR_STOP=1 -P pager=off -h "$SOCKET" -p "$port" -U labadmin -d "$db")
}
database_name() {
  case "$1" in
    main) printf 'claimsure_%s\n' "$SID" ;;
    backup) printf 'claimsure_backup_%s\n' "$SID" ;;
    sandbox) printf 'm7_%s\n' "$SID" ;;
    restore) printf 'm7_restore_%s\n' "$SID" ;;
    m7_|m7_restore_|claimsure_|claimsure_backup_)
      die "Incomplete database name '$1': a shell variable may be unset. Use main, backup, sandbox or restore; for example: ./run-lab07.sh inspect sandbox" ;;
    *) printf '%s\n' "$1" ;;
  esac
}
connect_db() {
  local db="$1"
  case "$db" in
    "claimsure_$SID"|"claimsure_backup_$SID")
      CONN=(psql -X --no-password -v ON_ERROR_STOP=1 -P pager=off
        -h "${LAB_DB_HOST:-127.0.0.1}" -p "${M7_DB_PORT:-5432}" -U "student_$SID" -d "$db") ;;
    "$LOCAL_DB"|"m7_restore_$SID") owned_workspace; private_conn "$db" ;;
    *) die "Choose claimsure_$SID, claimsure_backup_$SID, $LOCAL_DB or m7_restore_$SID" ;;
  esac
}
logical_flags() {
  case "$1" in
    claimsure*) DB_FLAGS=(-h "${LAB_DB_HOST:-127.0.0.1}" -p "${M7_DB_PORT:-5432}" -U "student_$SID" -d "$1") ;;
    *) DB_FLAGS=(-h "$SOCKET" -p "$SOURCE_PORT" -U labadmin -d "$1") ;;
  esac
}
start_primary() { run pg_ctl -D "$PRIMARY" -l "$WORK/primary.log" -w -t 30 start; }
cleanup() {
  local result=$?
  if (( RESTART_PRIMARY && ! DRY )); then
    printf 'Restarting the private primary after snapshot...\n' >&2
    pg_ctl -D "$PRIMARY" -l "$WORK/primary.log" -w -t 30 start 9>&- || result=1
  fi
  return "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
seed() {
  local db reset="${2:-}"
  local reset_args=()
  case "$reset" in
    '') ;;
    --reset-practice) reset_args=(-v reset_practice=1) ;;
    *) die 'Usage: seed [database] [--reset-practice]' ;;
  esac
  ask db 'Database to prepare' "claimsure_$SID" "${1:-}"
  db="$(database_name "$db")"
  connect_db "$db"; need psql
  [[ -r "$SCRIPT_DIR/module07-practice.sql" ]] || die 'Missing module07-practice.sql alongside the script'
  run "${CONN[@]}" "${reset_args[@]}" -f "$SCRIPT_DIR/module07-practice.sql"
}
sandbox_init() {
  (( EUID != 0 )) || die 'Run as a student, not root'
  for tool in initdb pg_ctl psql createdb; do need "$tool"; done
  if (( ! DRY )); then [[ ! -e "$WORK" ]] || die "$WORK already exists; use sandbox-start"; fi
  if (( ! DRY )); then
    [[ "$(initdb --version)" == *" 18."* ]] || die 'Use PostgreSQL 18 server binaries via PG_BIN'
  fi
  format 'initdb -D DATA -U USER --auth-local=trust --auth-host=reject; pg_ctl -D DATA start'
  run mkdir -p -- "$WORK" "$SOCKET" "$WORK/wal" "$WORK/recovery"
  run chmod 700 "$WORK" "$SOCKET"
  write_file "$WORK/.module07" "$UID:$SID"
  lock_workspace
  run initdb -D "$PRIMARY" -U labadmin --auth-local=trust --auth-host=reject --encoding=UTF8 --locale=C
  write_file "$PRIMARY/postgresql.auto.conf" "listen_addresses = ''
unix_socket_directories = '$SOCKET'
unix_socket_permissions = 0700
port = $SOURCE_PORT
shared_buffers = '32MB'
max_connections = 10
wal_level = replica
max_wal_senders = 4
max_replication_slots = 4
archive_mode = on
archive_command = 'test ! -f $WORK/wal/%f && cp %p $WORK/wal/%f'
archive_timeout = '60s'
logging_collector = off"
  start_primary
  run createdb --no-password -h "$SOCKET" -p "$SOURCE_PORT" -U labadmin "$LOCAL_DB"
  run createdb --no-password -h "$SOCKET" -p "$SOURCE_PORT" -U labadmin "m7_restore_$SID"
  seed "$LOCAL_DB"
  printf '\nPrivate database: %s; Unix socket: %s; source port: %s\n' "$LOCAL_DB" "$SOCKET" "$SOURCE_PORT"
}
logical_backup() {
  local db scope object dest temp
  ask db 'Database to back up' "claimsure_$SID" "${1:-}"
  ask scope 'Scope: database/schema/table/definitions/data' schema "${2:-}"
  object="${3:-}"
  case "$scope" in
    schema) ask object 'Schema name (one literal name)' insurance "$object" ;;
    table) ask object 'Table name (schema.table)' lab_m7_practice.claim_event "$object" ;;
    database|definitions|data) object=- ;;
    *) die 'Invalid backup scope' ;;
  esac
  ask dest 'NEW destination dump file' "$BACKUPS/${db}-${scope}-${STAMP}.dump" "${4:-}"
  db="$(database_name "$db")"
  connect_db "$db"; logical_flags "$db"; need pg_dump; need pg_restore
  local args=(--format=custom --no-owner --no-acl)
  case "$scope" in
    schema) [[ "$object" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die 'Use a simple schema name'; args+=(--strict-names "--schema=\"$object\"") ;;
    table) [[ "$object" =~ ^[a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die 'Use schema.table'; args+=(--strict-names "--table=\"${object%%.*}\".\"${object#*.}\"") ;;
    definitions) args+=(--schema-only) ;;
    data) args+=(--data-only) ;;
  esac
  [[ ! -e "$dest" && ! -L "$dest" && ! -e "$dest.sha256" && ! -L "$dest.sha256" ]] || die 'Destination or checksum already exists'
  format 'pg_dump -h HOST -p PORT -U USER -d DATABASE -Fc [--schema=SCHEMA | --table=SCHEMA.TABLE] -f FILE'
  run mkdir -p -- "$(dirname -- "$dest")"
  temp="$dest.partial-$$"
  # noclobber prevents replacing even a pre-existing empty partial file.
  if (( ! DRY )); then (set -C; : > "$temp") || die 'Partial file already exists'; fi
  if run pg_dump "${DB_FLAGS[@]}" "${args[@]}" --file="$temp" && run pg_restore --list "$temp"; then
    # A hard link publishes atomically and refuses to overwrite an existing file.
    run ln -T -- "$temp" "$dest"
    run rm -- "$temp"
    if (( ! DRY )); then (cd -- "$(dirname -- "$dest")"; sha256sum -- "$(basename -- "$dest")") > "$dest.sha256"; fi
    printf 'Backup destination: %s\nChecksum: %s.sha256\n' "$dest" "$dest"
  else
    printf 'Backup failed; incomplete file retained at %s\n' "$temp" >&2
    return 1
  fi
}
logical_restore() {
  local file target scope object schema replace_practice="${5:-0}"
  ask file 'Archive file to restore' "$BACKUPS/practice.dump" "${1:-}"
  ask target 'Target database' "claimsure_backup_$SID" "${2:-}"
  target="$(database_name "$target")"
  if [[ "$replace_practice" == 1 ]]; then
    case "$target" in
      "claimsure_$SID"|"claimsure_backup_$SID") ;;
      *) die "Practice restore target must be claimsure_$SID (main) or claimsure_backup_$SID (backup)" ;;
    esac
  else
    case "$target" in "claimsure_backup_$SID"|"m7_restore_$SID") ;; *) die 'Restore only to your backup database or private m7_restore_xx';; esac
  fi
  ask scope 'Selection: all/schema/table' all "${3:-}"
  object="${4:-}"
  local args=()
  case "$scope" in
    all) ;;
    schema) ask object 'Schema to select' lab_m7_practice "$object"; [[ "$object" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die 'Use a simple schema name'; args+=(--schema="$object") ;;
    table) ask object 'Table to select (schema.table)' lab_m7_practice.claim_event "$object"
      [[ "$object" =~ ^[a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die 'Use schema.table'
      schema="${object%%.*}"
      args+=(--schema="$schema" --table="${object#*.}") ;;
    *) die 'Invalid restore selection' ;;
  esac
  if [[ "$replace_practice" == 1 ]]; then
    [[ "$scope" == schema && "$object" == lab_m7_practice ]] || die 'Practice replacement is restricted to lab_m7_practice'
    args+=(--clean --if-exists)
  fi
  connect_db "$target"; logical_flags "$target"; need pg_restore
  if (( ! DRY )); then
    [[ -f "$file" && -f "$file.sha256" ]] || die 'Archive and its .sha256 file are required'
    (cd -- "$(dirname -- "$file")"; run sha256sum -c -- "$(basename -- "$file").sha256")
  fi
  format 'pg_restore -h HOST -p PORT -U USER -d TARGET --single-transaction --no-owner --no-acl ARCHIVE'
  run pg_restore --list "$file"
  if [[ "$replace_practice" == 1 ]]; then
    if (( ! DRY )); then
      local inventory
      inventory="$(pg_restore --list "$file")"
      grep -Eq ' SCHEMA - lab_m7_practice ' <<< "$inventory" || die 'Archive does not contain the complete lab_m7_practice schema'
      grep -Eq ' TABLE DATA lab_m7_practice claim_event ' <<< "$inventory" || die 'Archive does not contain practice table data'
    fi
    printf 'Replacing only lab_m7_practice in %s on shared port %s, in one transaction.\n' "$target" "${M7_DB_PORT:-5432}"
  else
    printf 'Target must have no conflicting objects. Existing objects cause a transactional rollback.\n'
  fi
  if [[ "$replace_practice" == 1 ]]; then
    run "${CONN[@]}" -c 'CREATE SCHEMA IF NOT EXISTS lab_m7_practice;'
  fi
  run pg_restore "${DB_FLAGS[@]}" --exit-on-error --single-transaction --no-owner --no-acl "${args[@]}" "$file"
  run "${CONN[@]}" -c 'ANALYZE;'
  if (( DRY )); then
    printf 'Restore preview complete. Target database: %s\n' "$target"
  else
    printf 'Restore completed in %s.\n' "$target"
    if [[ "$replace_practice" == 1 ]]; then
      run "${CONN[@]}" -c "SELECT current_database() AS restored_database, current_user AS login, current_setting('port') AS server_port; SELECT event_id, description, amount FROM lab_m7_practice.claim_event ORDER BY event_id;"
    fi
  fi
}
parse_shared_restore() {
  local restore_action="$1" source_default="$2" target_default="$3"
  shift 3
  local file='' target='' interactive=0
  if (( $# == 0 )); then interactive=1; fi
  while (( $# )); do
    case "$1" in
      --database)
        (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || die '--database needs a target database name'
        [[ -z "$target" ]] || die 'Specify the target database only once'
        target="$2"; shift 2 ;;
      --database=*)
        [[ -z "$target" ]] || die 'Specify the target database only once'
        target="${1#*=}"
        [[ -n "$target" ]] || die '--database needs a target database name'
        shift ;;
      -h|--help)
        printf 'Usage: %s [SOURCE] [TARGET_DB] or [SOURCE] --database TARGET_DB\n' "$restore_action"
        echo "Targets: main/claimsure_$SID or backup/claimsure_backup_$SID (default: $target_default)"
        exit 0 ;;
      --*) die "Unknown $restore_action option: $1" ;;
      *)
        if [[ -z "$file" ]]; then file="$1"
        elif [[ -z "$target" ]]; then target="$1"
        else die "Usage: $restore_action [SOURCE] [TARGET_DB] or [SOURCE] --database TARGET_DB"
        fi
        shift ;;
    esac
  done
  ask file 'Saved archive or backup directory' "$source_default" "$file"
  if (( interactive )); then
    ask target 'Restore target: main, backup or your full database name' "$target_default" "$target"
  fi
  RESTORE_SOURCE="$file"
  RESTORE_DATABASE="$(database_name "${target:-$target_default}")"
  case "$RESTORE_DATABASE" in
    "claimsure_$SID"|"claimsure_backup_$SID") ;;
    *) die "Restore target must be claimsure_$SID (main) or claimsure_backup_$SID (backup)" ;;
  esac
}
practice_restore() {
  parse_shared_restore practice-restore "$BACKUPS/practice.dump" backup "$@"
  logical_restore "$RESTORE_SOURCE" "$RESTORE_DATABASE" schema lab_m7_practice 1
}
new_destination() {
  [[ ! -e "$1" && ! -L "$1" ]] || die "Destination must be new: $1"
  if (( ! DRY )); then
    local parent
    parent="$(dirname -- "$(realpath -m -- "$1")")"
    while [[ ! -e "$parent" && "$parent" != / ]]; do parent="$(dirname -- "$parent")"; done
    [[ -d "$parent" && -w "$parent" ]] || die "Cannot write destination '$1'. Use a path under your home, e.g. $HOME/backups/module07/base. If you used \$M7_BACKUP_DIR, export it in this terminal first."
  fi
  # A destination inside the live cluster, archive or sandbox is never a backup.
  local path; path="$(realpath -m -- "$1")"
  [[ "$path" != "$WORK" && "$path" != "$WORK/"* ]] || die 'Save backups outside M7_WORKDIR'
}
private_scope() {
  printf '\nPRIVATE CLUSTER LAB | source=%s, socket port=%s | recovery=%s, socket port=%s\n' "$LOCAL_DB" "$SOURCE_PORT" "$LOCAL_DB" "$RECOVERY_PORT"
  printf 'Shared database claimsure_%s is on port %s. Restore its practice data with practice-restore FILE --database main.\n\n' "$SID" "${M7_DB_PORT:-5432}"
}
backup_cluster() {
  private_scope
  local kind="$1" dest
  ask dest 'NEW backup directory (outside sandbox)' "$BACKUPS/$kind-$STAMP" "${2:-}"
  lock_workspace; new_destination "$dest"
  need pg_ctl
  if (( ! DRY )); then
    pg_ctl -D "$PRIMARY" status >/dev/null || die 'Start the sandbox first'
    [[ -z "$(find "$PRIMARY/pg_tblspc" -type l -print -quit)" ]] || die 'External tablespaces are unsupported in this lab'
  fi
  run mkdir -p -- "$dest"
  if [[ "$kind" == physical ]]; then
    need pg_basebackup; need pg_verifybackup
    format 'pg_basebackup -h SOCKET -p PORT -U USER -D DEST/data -Fp -Xs -c fast -P; pg_verifybackup DEST/data'
    run pg_basebackup --no-password -h "$SOCKET" -p "$SOURCE_PORT" -U labadmin -D "$dest/data" -Fp -Xs -c fast -P
    run pg_verifybackup "$dest/data"
  else
    format 'pg_ctl -D DATA -m fast -w stop; cp -a DATA DEST/data; pg_ctl -D DATA start'
    printf 'Snapshot lab: a complete stopped-cluster copy. A live storage snapshot requires provider support.\n'
    run pg_ctl -D "$PRIMARY" -m fast -w stop
    RESTART_PRIMARY=1
    run cp -a -- "$PRIMARY" "$dest/data"
    start_primary
    RESTART_PRIMARY=0
  fi
  printf '+ (cd %q && find data -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)\n' "$dest"
  if (( ! DRY )); then (cd -- "$dest"; find data -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS); fi
  write_file "$dest/.module07-kind" "$kind:$SID"
  printf 'Backup directory: %s\n' "$dest"
}
restore_cluster() {
  private_scope
  local kind="$1" backup target type=name value=before_loss config
  local view_db="${RECOVERY_VIEW_DB:-$LOCAL_DB}"
  case "$view_db" in "$LOCAL_DB"|"m7_stage_$SID") ;; *) die 'Invalid private recovery view database';; esac
  local default_backup="$BACKUPS/base"
  [[ "$kind" != snapshot ]] || default_backup="$BACKUPS/snapshot"
  [[ "$kind" != pitr ]] || default_backup="$BACKUPS/pitr-base"
  ask backup 'Backup directory (contains data/)' "$default_backup" "${2:-}"
  if [[ "$kind" == pitr ]]; then
    ask type 'PITR target type: name/time' name "${3:-}"
    ask value 'Restore point name or timestamp with timezone' before_loss "${4:-}"
    case "$type" in
      name) [[ "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,62}$ ]] || die 'Use a simple restore point name (max 63 characters)' ;;
      time) [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[T\ ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}(:[0-9]{2})?)$ ]] || die 'Use YYYY-MM-DD HH:MM:SS+00 with an explicit timezone' ;;
      *) die 'Target type must be name or time' ;;
    esac
    if (( $# == 1 )); then
      ask target 'Recovery directory (auto creates a fresh directory)' auto
    else
      target="${5:-auto}"
    fi
  else
    if (( $# == 1 )); then
      ask target 'Recovery directory (auto creates a fresh directory)' auto
    else
      target="${3:-auto}"
    fi
  fi
  lock_workspace; need pg_ctl; need psql
  if [[ "$target" == auto ]]; then
    target="$WORK/recovery/$kind-$STAMP"
    printf 'Automatic NEW recovery directory: %s\n' "$target"
  fi
  target="$(realpath -m -- "$target")"
  [[ "$target" == "$WORK/recovery/"* && "$target" != "$WORK/recovery" ]] || die "Target must be under $WORK/recovery/"
  if [[ -e "$target" || -L "$target" ]]; then
    local retry="$kind-restore BACKUP auto"
    [[ "$kind" != pitr ]] || retry='pitr-restore BACKUP TYPE VALUE auto'
    die "Recovery target already exists: $target. Existing files were preserved. Choose a new directory or run ./run-lab07.sh $retry."
  fi
  if (( ! DRY )); then
    [[ ! -e "$SOCKET/.s.PGSQL.$RECOVERY_PORT" ]] || die 'Recovery instance already running. Run ./run-lab07.sh stop, then ./run-lab07.sh sandbox-start, then retry the restore with auto.'
    [[ -f "$backup/.module07-kind" ]] || die "Backup '$backup' does not contain .module07-kind. Select the directory printed by the backup command, e.g. $default_backup. If you used \$M7_BACKUP_DIR, set it in this terminal or use \$HOME/backups/module07 directly."
    local expected="$kind"; [[ "$kind" == pitr ]] && expected=physical
    [[ "$(cat "$backup/.module07-kind")" == "$expected:$SID" ]] || die 'Backup method or student number does not match'
    [[ "$(cat "$backup/data/PG_VERSION")" == 18 ]] || die 'This lab requires PostgreSQL 18 data'
    [[ -z "$(find "$backup/data" -type l -print -quit)" ]] || die 'External symlinks are unsupported'
    (cd -- "$backup"; run sha256sum --quiet -c SHA256SUMS)
  fi
  if [[ "$kind" != snapshot ]]; then need pg_verifybackup; run pg_verifybackup "$backup/data"; fi
  format 'cp -a BACKUP/data NEW_TARGET; configure recovery; pg_ctl -D NEW_TARGET -l LOG start'
  run mkdir -p -- "$(dirname -- "$target")"
  run cp -a -- "$backup/data" "$target"
  config="listen_addresses = ''
unix_socket_directories = '$SOCKET'
unix_socket_permissions = 0700
port = $RECOVERY_PORT
archive_mode = off
archive_command = ''
archive_library = ''
shared_buffers = '32MB'
max_connections = 10
hot_standby = on"
  if [[ "$kind" == pitr ]]; then
    config+="
restore_command = 'cp $WORK/wal/%f %p'
recovery_target_$type = '$value'
recovery_target_timeline = 'current'
recovery_target_action = 'pause'"
    run touch "$target/recovery.signal"
  fi
  write_file "$target/postgresql.auto.conf" "$config"
  # Record before startup so a failed recovery can still be stopped.
  write_file "$WORK/active-recovery" "$target"
  write_file "$WORK/active-recovery-db" "$view_db"
  run pg_ctl -D "$target" -l "$target.log" -w -t 30 start
  private_conn "$view_db" "$RECOVERY_PORT"
  if [[ "$kind" == pitr && "$DRY" == 0 ]]; then
    local paused=0
    for ((attempt=0; attempt<30; attempt++)); do
      if [[ "$("${CONN[@]}" -Atc "SELECT pg_get_wal_replay_pause_state() = 'paused'" 2>/dev/null || true)" == t ]]; then paused=1; break; fi
      pg_ctl -D "$target" status >/dev/null 2>&1 || break
      sleep 1
    done
    (( paused )) || die "PITR did not reach the target. Read $target.log; verify base-before-target ordering and complete archived WAL."
    run "${CONN[@]}" -c 'SELECT pg_is_in_recovery(), pg_get_wal_replay_pause_state(), pg_last_xact_replay_timestamp();'
  fi
  printf '\nRECOVERED COPY | database=%s | socket port=%s | directory=%s\n' "$view_db" "$RECOVERY_PORT" "$target"
  run "${CONN[@]}" -c 'SELECT event_id, description, amount FROM lab_m7_practice.claim_event ORDER BY event_id;'
  printf 'Recovery socket: %s, port: %s.\n' "$SOCKET" "$RECOVERY_PORT"
  if [[ "$kind" == pitr ]]; then printf 'PITR remains paused and read-only for inspection.\n'; fi
}
mark() {
  local point segment
  ask point 'New restore point name (use a unique name)' before_loss "${1:-}"
  [[ "$point" =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,62}$ ]] || die 'Use a simple name (max 63 characters)'
  lock_workspace; private_conn; need psql
  format "SELECT pg_create_restore_point('NAME'); SELECT pg_switch_wal();"
  segment="$(query "SELECT pg_walfile_name(pg_create_restore_point('$point'));")"
  run "${CONN[@]}" -c 'SELECT clock_timestamp() AS time_after_restore_point, pg_switch_wal();'
  if (( ! DRY )); then
    local archived=0
    for ((attempt=0; attempt<30; attempt++)); do
      if [[ -f "$WORK/wal/$segment" ]]; then archived=1; break; fi
      sleep 1
    done
    (( archived )) || die 'WAL did not archive within 30 seconds; inspect primary.log'
  fi
  printf 'Restore point: %s; archived WAL segment: %s\n' "$point" "$segment"
}
stop_recovery() {
  local target
  lock_workspace; need pg_ctl
  if [[ -f "$WORK/active-recovery" ]]; then
    target="$(cat "$WORK/active-recovery")"
    [[ "$target" == "$WORK/recovery/"* ]] || die 'Invalid recovery tracking file'
    if (( DRY )) || pg_ctl -D "$target" status >/dev/null 2>&1; then run pg_ctl -D "$target" -m fast -w stop; fi
  fi
}
stop_clusters() {
  stop_recovery
  if (( DRY )) || pg_ctl -D "$PRIMARY" status >/dev/null 2>&1; then run pg_ctl -D "$PRIMARY" -m fast -w stop; fi
  printf 'Private clusters stopped; backups and recovery files retained.\n'
}
# Lab C: physical snapshot of a private staging copy, then logical import to 5432.
ensure_staging_source() {
  need pg_ctl; need createdb; need psql
  if (( ! DRY )) && [[ ! -e "$WORK" ]]; then
    sandbox_init
  fi
  lock_workspace
  if (( DRY )) || ! pg_ctl -D "$PRIMARY" status >/dev/null 2>&1; then start_primary; fi
  private_conn postgres
  local exists
  exists="$(query "SELECT 1 FROM pg_database WHERE datname='m7_stage_$SID';")"
  if [[ "$exists" != 1 ]]; then
    run createdb --no-password -h "$SOCKET" -p "$SOURCE_PORT" -U labadmin -T template0 "m7_stage_$SID"
  fi
}
claimsure_snapshot_backup() {
  local dest="${1:-auto}" stage_archive
  [[ "$dest" != auto ]] || dest="$BACKUPS/claimsure-snapshot-$STAMP"
  dest="$(realpath -m -- "$dest")"
  new_destination "$dest"
  stage_archive="$BACKUPS/claimsure-stage-$SID-$STAMP.dump"
  stage_shared_practice "$stage_archive"
  printf '\nLAB C STEP 3: stop, copy and restart the private staging cluster.\n'
  backup_cluster snapshot "$dest"
  write_file "$dest/.claimsure-snapshot" "claimsure_$SID|m7_stage_$SID|lab_m7_practice"
  run mv -- "$stage_archive" "$stage_archive.sha256" "$dest/"
  write_file "$WORK/claimsure-snapshot.latest" "$dest"
  printf '\nCaptured practice data from claimsure_%s. Snapshot: %s\n' "$SID" "$dest"
  printf 'After damage, run: ./run-lab07.sh claimsure-snapshot-restore --database main\n'
}
claimsure_snapshot_restore() {
  local backup export_file partial
  # Default to the last completed capture; do not require shell variables.
  if (( $# == 0 )) || [[ "$1" == --* && "$1" != --help ]]; then
    parse_shared_restore claimsure-snapshot-restore latest main latest "$@"
  else
    parse_shared_restore claimsure-snapshot-restore latest main "$@"
  fi
  backup="$RESTORE_SOURCE"
  lock_workspace
  if [[ "$backup" == latest ]]; then
    if (( DRY )); then backup="$BACKUPS/claimsure-snapshot-LATEST"
    else
      [[ -f "$WORK/claimsure-snapshot.latest" ]] || die 'Run claimsure-snapshot-backup first'
      backup="$(cat "$WORK/claimsure-snapshot.latest")"
    fi
  fi
  if (( ! DRY )); then
    [[ -f "$backup/.claimsure-snapshot" ]] || die 'This is not a snapshot staged from claimsure. Run claimsure-snapshot-backup first; a raw private snapshot is a different exercise.'
    [[ "$(cat "$backup/.claimsure-snapshot")" == "claimsure_$SID|m7_stage_$SID|lab_m7_practice" ]] || die 'Staged snapshot belongs to a different source/student'
  fi
  stop_recovery
  printf '\nLAB C STEP 1: recover the private staging snapshot into a fresh directory.\n'
  local RECOVERY_VIEW_DB="m7_stage_$SID"
  restore_cluster snapshot "$backup" auto
  import_recovered_practice "$RESTORE_DATABASE"
}
# Shared-to-private synchronization is explicit: this is a staged PITR lesson,
# not continuous WAL capture from the live Docker cluster.
stage_shared_practice() {
  local archive="$1"
  ensure_staging_source
  printf '\nExport shared claimsure_%s:%s practice data into private m7_stage_%s.\n' "$SID" "${M7_DB_PORT:-5432}" "$SID"
  logical_backup "claimsure_$SID" schema lab_m7_practice "$archive"
  private_conn "m7_stage_$SID"
  run "${CONN[@]}" -c 'CREATE SCHEMA IF NOT EXISTS lab_m7_practice;'
  run pg_restore --no-password -h "$SOCKET" -p "$SOURCE_PORT" -U labadmin -d "m7_stage_$SID" \
    --single-transaction --exit-on-error --no-owner --no-acl --schema=lab_m7_practice --clean --if-exists "$archive"
}
import_recovered_practice() {
  local target_db="$1" export_file partial
  printf '\nExport only the recovered staging practice schema.\n'
  export_file="$BACKUPS/claimsure-recovered-$SID-$STAMP.dump"
  partial="$export_file.partial"
  run mkdir -p -- "$BACKUPS"
  if (( ! DRY )); then (set -C; : > "$partial") || die 'Recovery export partial file already exists'; fi
  run pg_dump --no-password -h "$SOCKET" -p "$RECOVERY_PORT" -U labadmin -d "m7_stage_$SID" \
    --format=custom --no-owner --no-acl --schema=lab_m7_practice --file="$partial"
  run pg_restore --list "$partial"
  run ln -T -- "$partial" "$export_file"
  run rm -- "$partial"
  if (( ! DRY )); then (cd -- "$BACKUPS"; sha256sum -- "$(basename -- "$export_file")") > "$export_file.sha256"; fi
  printf '\nLogical import into %s on shared port %s.\n' "$target_db" "${M7_DB_PORT:-5432}"
  logical_restore "$export_file" "$target_db" schema lab_m7_practice 1
  printf '\nRecovery is observable in your normal GUI connection to %s on port %s.\n' "$target_db" "${M7_DB_PORT:-5432}"
  printf 'Recovered logical archive: %s\n' "$export_file"
}
# Lab D: real base backup + archived staging WAL, then scoped shared import.
resolve_claimsure_pitr_base() {
  PITR_BASE="${1:-latest}"
  lock_workspace
  if [[ "$PITR_BASE" == latest ]]; then
    if (( DRY )); then PITR_BASE="$BACKUPS/claimsure-pitr-LATEST"
    else
      [[ -f "$WORK/claimsure-pitr.latest" ]] || die 'Run claimsure-pitr-backup first'
      PITR_BASE="$(cat "$WORK/claimsure-pitr.latest")"
    fi
  fi
  PITR_BASE="$(realpath -m -- "$PITR_BASE")"
  if (( ! DRY )); then
    [[ -f "$PITR_BASE/.claimsure-pitr" ]] || die 'Not a claimsure staged PITR base; run claimsure-pitr-backup first'
    [[ "$(cat "$PITR_BASE/.claimsure-pitr")" == "claimsure_$SID|m7_stage_$SID|lab_m7_practice" ]] || die 'PITR base belongs to a different source/student'
    [[ "$(cat "$PITR_BASE/.module07-kind")" == "physical:$SID" ]] || die 'Not a physical Module 7 base'
  fi
}
claimsure_pitr_backup() {
  local dest="${1:-auto}" archive="$BACKUPS/claimsure-pitr-stage-$SID-$STAMP.dump"
  [[ "$dest" != auto ]] || dest="$BACKUPS/claimsure-pitr-$STAMP"
  dest="$(realpath -m -- "$dest")"
  new_destination "$dest"
  stage_shared_practice "$archive"
  backup_cluster physical "$dest"
  write_file "$dest/.claimsure-pitr" "claimsure_$SID|m7_stage_$SID|lab_m7_practice"
  run mv -- "$archive" "$archive.sha256" "$dest/"
  write_file "$WORK/claimsure-pitr.latest" "$dest"
  printf '\nBase completed. Next: claimsure-pitr-event, claimsure-pitr-mark, damage, claimsure-pitr-restore.\n'
}
claimsure_pitr_event() {
  resolve_claimsure_pitr_base latest
  connect_db "claimsure_$SID"; need psql
  printf '\nCommit a change AFTER the base and BEFORE the target on shared port %s.\n' "${M7_DB_PORT:-5432}"
  run "${CONN[@]}" -c "BEGIN; SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='15s'; INSERT INTO lab_m7_practice.claim_event VALUES (4, 'AFTER_BASE_BEFORE_POINT', 400.00) ON CONFLICT (event_id) DO UPDATE SET description=EXCLUDED.description, amount=EXCLUDED.amount; COMMIT; SELECT * FROM lab_m7_practice.claim_event ORDER BY event_id;"
}
claimsure_pitr_mark() {
  local point="${1:-claimsure_${SID}_before_loss_${STAMP//-/_}}" timestamp
  [[ "$point" =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,62}$ ]] || die 'Use a simple unique point name (max 63 characters)'
  resolve_claimsure_pitr_base "${2:-latest}"
  if (( ! DRY )); then
    [[ ! -f "$PITR_BASE/.claimsure-pitr-target" ]] || die 'This base already has a target. Create a new base for a new lesson.'
  fi
  stage_shared_practice "$BACKUPS/claimsure-pitr-before-point-$SID-$STAMP.dump"
  mark "$point"
  private_conn "m7_stage_$SID"
  timestamp="$(query 'SELECT clock_timestamp();')"
  if (( DRY )); then timestamp='YYYY-MM-DD HH:MM:SS+00'; fi
  write_file "$PITR_BASE/.claimsure-pitr-target" "$point"
  write_file "$PITR_BASE/.claimsure-pitr-target-time" "$timestamp"
  printf '\nTarget saved. Commit damage on main, then run claimsure-pitr-restore --database main.\n'
}
claimsure_pitr_restore() {
  local type=name value='' option='' target_args=()
  while (( $# )); do
    case "$1" in
      --at-name|--at-time)
        [[ -z "$option" ]] || die 'Choose only one PITR target'
        (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || die "$1 needs a target value"
        option="$1"; value="$2"; [[ "$option" != --at-time ]] || type=time
        shift 2 ;;
      *) target_args+=("$1"); shift ;;
    esac
  done
  if (( ${#target_args[@]} == 0 )) || [[ "${target_args[0]}" == --* && "${target_args[0]}" != --help ]]; then
    target_args=(latest "${target_args[@]}")
  fi
  parse_shared_restore claimsure-pitr-restore latest main "${target_args[@]}"
  resolve_claimsure_pitr_base "$RESTORE_SOURCE"
  if [[ -z "$value" || "$value" == saved && "$type" == time ]]; then
    local suffix=target
    [[ "$type" != time ]] || suffix=target-time
    if (( DRY )); then
      if [[ "$type" == name ]]; then value=claimsure_before_loss; else value='2026-11-08 10:15:30+00'; fi
    else
      [[ -f "$PITR_BASE/.claimsure-pitr-$suffix" ]] || die 'No saved target. Run claimsure-pitr-mark AFTER the base and BEFORE damage.'
      value="$(cat "$PITR_BASE/.claimsure-pitr-$suffix")"
    fi
  fi
  case "$type" in
    name) [[ "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,62}$ ]] || die 'Invalid restore point name' ;;
    time) [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[T\ ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}(:[0-9]{2})?)$ ]] || die 'Use a timestamp with explicit timezone' ;;
  esac
  printf '\nCapture the current shared state AFTER the selected target into staging WAL.\n'
  stage_shared_practice "$BACKUPS/claimsure-pitr-after-loss-$SID-$STAMP.dump"
  mark "claimsure_${SID}_after_loss_${STAMP//-/_}"
  stop_recovery
  local RECOVERY_VIEW_DB="m7_stage_$SID"
  restore_cluster pitr "$PITR_BASE" "$type" "$value" auto
  # restore_cluster returns only after replay has PAUSED at the requested target.
  import_recovered_practice "$RESTORE_DATABASE"
}
cleanup_module07() {
  local apply=0 data=1 files=1 selection='' clusters='' cluster
  while (( $# )); do
    case "$1" in
      --yes) apply=1 ;;
      --dry-run) DRY=1 ;;
      --data-only|--files-only)
        [[ -z "$selection" ]] || die 'Choose only one cleanup scope'
        selection="$1"
        if [[ "$1" == --data-only ]]; then files=0; else data=0; fi ;;
      -h|--help)
        cat <<'HELP'
Usage: module07-cleanup.sh [--yes|--dry-run] [--data-only|--files-only]
Default: preview both scopes, with no changes. Add --yes to perform cleanup.
Data: remove lab_m7_practice.claim_event and its otherwise empty schema from
      your own claimsure_xx and claimsure_backup_xx databases on port 5432.
Files: stop your Module 7 private clusters, then remove the marked ~/m7 sandbox
       and ~/backups/module07, including WAL, backups and recovery copies.
--data-only leaves all files/private clusters; --files-only leaves shared data.
Insurance schemas, shared databases, credentials and scripts are preserved.
Custom backup destinations outside ~/backups/module07 are not removed.
HELP
        return ;;
      *) die "Unknown cleanup option: $1. Use cleanup --help" ;;
    esac
    shift
  done
  (( apply )) || DRY=1
  need python3
  printf '\nModule 7 cleanup | student=%s | shared port=%s | preview=%s\n' "$SID" "${M7_DB_PORT:-5432}" "$DRY"
  if (( files )); then
    # Preflight is read-only, including during previews; validate before SQL.
    python3 "$SCRIPT_DIR/module07-cleanup-files.py" validate "$WORK" "$BACKUPS" "$SID"
    if [[ -e "$WORK" ]]; then lock_workspace; fi
    clusters="$(python3 "$SCRIPT_DIR/module07-cleanup-files.py" clusters "$WORK" "$BACKUPS" "$SID")"
    if [[ -n "$clusters" ]]; then
      need pg_ctl
      while IFS= read -r cluster; do
        if (( DRY )) || pg_ctl -D "$cluster" status >/dev/null 2>&1; then
          run pg_ctl -D "$cluster" -m fast -w -t 30 stop
        elif [[ -f "$cluster/postmaster.pid" ]]; then
          die "Cluster has a stale or unrecognized PID file: $cluster. Files were preserved."
        fi
      done <<< "$clusters"
    fi
  fi
  if (( data )); then
    need psql
    local db cleanup_sql="BEGIN; SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='15s'; DROP TABLE IF EXISTS lab_m7_practice.claim_event; DROP SCHEMA IF EXISTS lab_m7_practice; COMMIT;"
    for db in "claimsure_$SID" "claimsure_backup_$SID"; do
      connect_db "$db"
      printf '\nClear only the Module 7 practice table/schema in %s.\n' "$db"
      # No CASCADE: dependent objects elsewhere cause a rollback in this DB.
      run "${CONN[@]}" -c "$cleanup_sql"
    done
  fi
  if (( files )); then
    run python3 "$SCRIPT_DIR/module07-cleanup-files.py" remove "$WORK" "$BACKUPS" "$SID"
  fi
  if (( DRY )); then
    printf '\nPreview complete; nothing changed. Add --yes to perform this cleanup.\n'
  else
    printf '\nModule 7 cleanup complete. Restart a lesson with seed main --reset-practice.\n'
  fi
}
action="${1:-}"
if (( $# )); then shift; fi
if [[ -z "$action" ]]; then
  cat <<'MENU'
Module 7: Backup and Recovery
  1  Prepare practice rows in a student database
  2  Logical backup (database / schema / table / definitions / data)
  3  Logical restore (all / selected schema / selected table)
  4  Create private sandbox for physical / snapshot / PITR labs
  5  Start existing sandbox
  6  PRIVATE cluster physical base backup
  7  PRIVATE cluster physical restore to a new directory
  8  PRIVATE snapshot backup (stop, copy complete cluster, restart)
  9  PRIVATE snapshot restore to a new directory
 10  Create and archive a named restore point
 11  Commit practice data loss in your claimsure_xx database (port 5432)
 12  PRIVATE cluster PITR restore by name or time
 13  Inspect source practice rows
 14  Inspect claimsure_backup_xx on port 5432
 15  Stop private clusters
 16  Check private-lab tools (doctor)
 17  Inspect private physical/snapshot/PITR recovery
 18  Back up the shared practice schema
 19  Restore practice schema (choose own main or backup database)
 20  Lab C: capture shared practice data into a staging snapshot
 21  Lab C: recover staged snapshot into shared database on 5432
 22  Lab D: capture shared practice into a staging PITR base
 23  Lab D: commit row 4 after the base on shared port 5432
 24  Lab D: save a recovery point before damage
 25  Lab D: recover PITR into selected shared database on 5432
 26  Preview Module 7 data and backup-file cleanup
  0  Exit
MENU
  ask choice 'Select action' 0
  case "$choice" in
    1) action=seed;; 2) action=logical-backup;; 3) action=logical-restore;;
    4) action=sandbox-init;; 5) action=sandbox-start;; 6) action=physical-backup;;
    7) action=physical-restore;; 8) action=snapshot-backup;; 9) action=snapshot-restore;;
    10) action=mark;; 11) action=damage;; 12) action=pitr-restore;;
    13) action=inspect;; 14) action=inspect-recovery;; 15) action=stop;; 16) action=doctor;; 17) action=inspect-sandbox-recovery;;
    18) action=practice-backup;; 19) action=practice-restore;;
    20) action=claimsure-snapshot-backup;; 21) action=claimsure-snapshot-restore;;
    22) action=claimsure-pitr-backup;; 23) action=claimsure-pitr-event;;
    24) action=claimsure-pitr-mark;; 25) action=claimsure-pitr-restore;; 26) action=cleanup;; 0) exit 0;;
    *) die 'Invalid menu selection';;
  esac
fi
if [[ "$action" != cleanup ]]; then
  printf '\nStudent %s | action %s | dry-run=%s\n' "$SID" "$action" "$DRY"
fi
case "$action" in
  doctor)
    for tool in initdb postgres pg_ctl psql createdb pg_dump pg_restore pg_basebackup pg_verifybackup; do
      need "$tool"
      run "$tool" --version
    done
    printf 'Database shortcuts: main=%s, backup=%s, sandbox=%s, restore=%s\n' "claimsure_$SID" "claimsure_backup_$SID" "$LOCAL_DB" "m7_restore_$SID"
    printf 'Default backup directory: %s\n' "$BACKUPS"
    printf 'Private-cluster tools ready. Shared Docker PostgreSQL is a separate server.\n' ;;
  cleanup) cleanup_module07 "$@" ;;
  seed) seed "$@" ;;
  practice-backup)
    ask file 'NEW practice archive file' "$BACKUPS/practice.dump" "${1:-}"
    logical_backup "claimsure_$SID" schema lab_m7_practice "$file" ;;
  practice-restore) practice_restore "$@" ;;
  claimsure-pitr-backup) claimsure_pitr_backup "$@" ;;
  claimsure-pitr-event) claimsure_pitr_event "$@" ;;
  claimsure-pitr-mark) claimsure_pitr_mark "$@" ;;
  claimsure-pitr-restore) claimsure_pitr_restore "$@" ;;
  claimsure-snapshot-backup) claimsure_snapshot_backup "$@" ;;
  claimsure-snapshot-restore) claimsure_snapshot_restore "$@" ;;
  logical-backup) logical_backup "$@" ;;
  logical-restore) logical_restore "$@" ;;
  sandbox-init) sandbox_init ;;
  sandbox-start)
    lock_workspace; need pg_ctl
    if (( ! DRY )) && pg_ctl -D "$PRIMARY" status >/dev/null 2>&1; then
      printf 'Private source is already running: %s\n' "$PRIMARY"
    else
      start_primary
    fi ;;
  physical-backup) backup_cluster physical "$@" ;;
  snapshot-backup) backup_cluster snapshot "$@" ;;
  physical-restore) restore_cluster physical "$@" ;;
  snapshot-restore) restore_cluster snapshot "$@" ;;
  pitr-restore) restore_cluster pitr "$@" ;;
  mark) mark "$@" ;;
  damage)
    db="$(database_name "${1:-main}")"
    case "$db" in
      "claimsure_$SID") connect_db "$db"; printf 'LIVE SHARED SOURCE | database=%s | user=student_%s | port=%s\n' "$db" "$SID" "${M7_DB_PORT:-5432}" ;;
      "$LOCAL_DB") lock_workspace; private_conn; printf 'PRIVATE SOURCE | database=%s | socket port=%s\n' "$db" "$SOURCE_PORT" ;;
      *) die 'damage accepts only your main database or your private sandbox' ;;
    esac
    need psql
    run "${CONN[@]}" -c "BEGIN; SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='15s'; DELETE FROM lab_m7_practice.claim_event WHERE event_id=2; INSERT INTO lab_m7_practice.claim_event VALUES (3, 'AFTER_LOSS', 999.00) ON CONFLICT DO NOTHING; COMMIT;"
    if (( DRY )); then printf '\nPreview: read the SOURCE after committing:\n'; else printf '\nCommit completed. Reading the same SOURCE in a new connection:\n'; fi
    run "${CONN[@]}" -c "SELECT current_database() AS database, current_user AS login, current_setting('port') AS server_port; SELECT event_id, description, amount FROM lab_m7_practice.claim_event ORDER BY event_id;"
    if [[ "$db" == "claimsure_$SID" ]]; then
      printf 'Inspect this change with inspect main. Restore the pre-damage logical archive using practice-restore, then inspect-recovery.\n'
    else
      printf 'Inspect this private source with inspect sandbox; inspect the private restored base with inspect-sandbox-recovery.\n'
    fi ;;

  inspect)
    ask db 'Database to inspect (main/backup/sandbox/restore)' "claimsure_$SID" "${1:-}"
    db="$(database_name "$db")"; connect_db "$db"; need psql
    case "$db" in
      "$LOCAL_DB") printf '\nLIVE SOURCE | database=%s | socket port=%s\n' "$db" "$SOURCE_PORT" ;;
      "claimsure_$SID") printf '\nSHARED SOURCE DATABASE | %s\n' "$db" ;;
      *) printf '\nLOGICAL RESTORE TARGET | %s\n' "$db" ;;
    esac
    run "${CONN[@]}" -c 'SELECT event_id, description, amount FROM lab_m7_practice.claim_event ORDER BY event_id;' ;;
  inspect-recovery)
    connect_db "claimsure_backup_$SID"; need psql
    printf '\nSHARED BACKUP DATABASE | database=claimsure_backup_%s | user=student_%s | port=%s\n' "$SID" "$SID" "${M7_DB_PORT:-5432}"
    run "${CONN[@]}" -c "SELECT current_database() AS database, current_user AS login, current_setting('port') AS server_port; SELECT event_id, description, amount FROM lab_m7_practice.claim_event ORDER BY event_id;" ;;
  inspect-sandbox-recovery)
    owned_workspace
    if (( ! DRY )) && [[ ! -S "$SOCKET/.s.PGSQL.$RECOVERY_PORT" ]]; then
      die 'No recovery server is running. Complete physical-restore, snapshot-restore or pitr-restore successfully before inspect-sandbox-recovery. A failed restore does not start a server.'
    fi
    db="$LOCAL_DB"
    if [[ -f "$WORK/active-recovery-db" ]]; then db="$(cat "$WORK/active-recovery-db")"; fi
    case "$db" in "$LOCAL_DB"|"m7_stage_$SID") ;; *) die 'Invalid private recovery database marker';; esac
    private_conn "$db" "$RECOVERY_PORT"; need psql
    printf '\nRECOVERED COPY | database=%s | socket port=%s\n' "$db" "$RECOVERY_PORT"
    run "${CONN[@]}" -c 'SELECT event_id, description, amount FROM lab_m7_practice.claim_event ORDER BY event_id;' ;;
  stop) stop_clusters ;;
  *) die "Unknown action $action; use --help" ;;
esac
