#!/usr/bin/env bash
# Module 6: student measurements with automatic parameter rollback.
set -euo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${SCRIPT_DIR##*/}" == scripts && -r "$SCRIPT_DIR/../.env" ]]; then
  source "$SCRIPT_DIR/../.env"
elif [[ -r "$HOME/.env" ]]; then
  source "$HOME/.env"
fi
SID="${STUDENT_NO:-${USER:-}}"
ACTION='' DRY=0 DATABASE=main ROWS=100000 REPEAT=3 WAIT_SECONDS=75 WAL_ROWS=120000
usage() {
cat <<'HELP'
Usage: run-lab06.sh [options] A|B|C|D|E|F|G|all|baseline|setup|reset|doctor|manual
  A  PostgreSQL boot defaults, effective values, origins and scoped rollback
  B  Repeated report-sort measurements: original / 64kB / 4MB / 32MB
  C  Actual statement and row-lock timeouts, before/after with SQLSTATE evidence
  D  PRIVATE cluster: max_wal_size 64MB vs 256MB; real WAL/checkpoint deltas
  E  Own lab queue: original vs candidate autovacuum; restore exact table options
  F  PRIVATE logs: identical slow SQL, sort and lock wait before/after logging
  G  Results and keep/revert worksheet
  all       A through G, then reset (private server stopped; evidence retained)
  baseline  Read PostgreSQL boot/effective/RESET values and their source
  setup     Create only lab_m6_shell fixtures in your selected own database
  reset     Restore saved table/private configuration; stop private server
  doctor    Read-only connection and PostgreSQL 18 tool checks
  manual    Show copyable SQL and the configuration file/scope guide
Options:
  --student 1..20        default: student account / STUDENT_NO
  --database main|backup|OWN_DB  default: claimsure_xx on direct port 5432
  --rows 10000..200000   report/queue rows (default 100000)
  --repeat 1..5         repeats per memory value (default 3)
  --wait 0..180         maximum autovacuum observation seconds (default 75)
  --wal-rows 30000..200000  logged private WAL workload (default 120000)
  --dry-run            print the plan without changing databases or files
Reports: ~/labs/module06/RUN_ID/ (transcript, original/restored settings, metrics).
Private cluster: ~/m6, Unix socket only, port 5600+xx, labadmin without TCP login.
A/B/C/E run in your own shared DB. D/F use private native PostgreSQL, not Docker.
No shared ALTER SYSTEM, cluster restarts, role grants or insurance changes occur.
Session/role tests roll back; E restores exact prior options; D restores its
original postgresql.auto.conf, even on an ordinary command failure or interrupt.
Interrupted state can be recovered with reset. RESET is not the boot default.
HELP
}
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
while (( $# )); do
 case "$1" in
  --student|--database|--rows|--repeat|--wait|--wal-rows)
   (( $#>=2 )) || die "$1 needs a value"
   case "$1" in
    --student) SID="$2";; --database) DATABASE="$2";; --rows) ROWS="$2";;
    --repeat) REPEAT="$2";; --wait) WAIT_SECONDS="$2";; --wal-rows) WAL_ROWS="$2";;
   esac; shift 2;;
  --dry-run) DRY=1; shift;;
  --list|-h|--help) usage; exit 0;;
  --*) die "Unknown option $1";;
  *) [[ -z "$ACTION" ]] || die 'Choose one action'; ACTION="$1"; shift;;
 esac
done
if [[ "$ACTION" == manual ]]; then cat "$SCRIPT_DIR/module06-configuration-lab.md"; exit 0; fi
SID="${SID#student_}"; SID="${SID#student}"
[[ "$SID" =~ ^[0-9]{1,2}$ ]] || die 'Use your student account or --student 1..20'
((10#$SID>=1 && 10#$SID<=20)) || die 'Student must be 1..20'
printf -v SID '%02d' "$((10#$SID))"
if [[ "${USER:-}" =~ ^student([0-9]{2})$ ]]; then [[ "$SID" == "${BASH_REMATCH[1]}" ]] || die 'Use your own student number'; fi
for number in "$ROWS" "$REPEAT" "$WAIT_SECONDS" "$WAL_ROWS"; do [[ "$number" =~ ^[0-9]{1,6}$ ]] || die 'Numeric options need unsigned decimal integers'; done
ROWS=$((10#$ROWS)); REPEAT=$((10#$REPEAT)); WAIT_SECONDS=$((10#$WAIT_SECONDS)); WAL_ROWS=$((10#$WAL_ROWS))
((ROWS>=10000 && ROWS<=200000 && REPEAT>=1 && REPEAT<=5 && WAIT_SECONDS<=180 && WAL_ROWS>=30000 && WAL_ROWS<=200000)) || die 'Numeric option outside the range in --help'
case "$DATABASE" in main) DATABASE="claimsure_$SID";; backup) DATABASE="claimsure_backup_$SID";; esac
case "$DATABASE" in "claimsure_$SID"|"claimsure_backup_$SID") ;; *) die 'Choose your own main or backup database';; esac
if [[ -z "$ACTION" ]]; then usage; read -r -p 'Lab/action: ' ACTION; fi
case "$ACTION" in a|b|c|d|e|f|g) ACTION="${ACTION^^}";; esac
case "$ACTION" in A|B|C|D|E|F|G|all|baseline|setup|reset|doctor) ;; *) die 'Unknown lab/action; use --help';; esac
if [[ -z "${PG_BIN:-}" ]]; then
 if [[ -x /usr/lib/postgresql/18/bin/initdb ]]; then PG_BIN=/usr/lib/postgresql/18/bin
 else PG_BIN=/usr/local/lib/claimsure-postgres18/usr/lib/postgresql/18/bin; fi
fi
runtime_root="${PG_BIN%/usr/lib/postgresql/18/bin}"
if [[ -f "$runtime_root/.module07-runtime" ]]; then
 for library_dir in "$runtime_root"/usr/lib/*-linux-gnu; do
  if [[ -d "$library_dir" ]]; then export LD_LIBRARY_PATH="$library_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"; fi
 done
fi
export PATH="$PG_BIN:$PATH"
if [[ -n "${DB_PASSWORD:-}" ]]; then export PGPASSWORD="$DB_PASSWORD"; fi
export PGAPPNAME="module06_$SID"
WORK="${M6_WORKDIR:-$HOME/m6}"
[[ "$WORK" =~ ^/[a-zA-Z0-9_./-]+$ && "$WORK" != "$HOME" && "$WORK" != / ]] || die 'Choose a dedicated absolute M6_WORKDIR without spaces/quotes'
[[ ! -L "$WORK" ]] || die 'Private workspace cannot be a symlink'
WORK="$(realpath -m -- "$WORK")"
[[ "$WORK" == "$HOME/"* ]] || die 'Private workspace must be under your home'
PRIMARY="$WORK/primary" SOCKET="$WORK/sock" PRIVATE_PORT=$((5600+10#$SID)) PRIVATE_DB="m6_$SID"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"
REPORT_ROOT="${M6_REPORT_DIR:-$HOME/labs/module06}"
REPORT="$REPORT_ROOT/$STAMP"
READY_SHARED=0 READY_PRIVATE=0 E_DIRTY=0 LOCKER_PID=''
show() { printf '+ '; printf '%q ' "$@"; printf '\n'; }
run() { show "$@"; "$@" 9>&-; }
need() { command -v "$1" >/dev/null || die "Missing $1. Instructor: install the PostgreSQL 18 lab runtime."; }
shared_conn() { CONN=(psql -X --no-password -v ON_ERROR_STOP=1 -P pager=off -h "${LAB_DB_HOST:-127.0.0.1}" -p "${M6_DB_PORT:-5432}" -U "student_$SID" -d "$DATABASE"); }
private_conn() { CONN=(psql -X --no-password -v ON_ERROR_STOP=1 -P pager=off -h "$SOCKET" -p "$PRIVATE_PORT" -U labadmin -d "$PRIVATE_DB"); }
query() { "${CONN[@]}" -Atc "$1" 9>&-; }
sqlfile() { local name="$1"; shift; run "${CONN[@]}" -v "rows=$ROWS" -v "repeat=$REPEAT" -v "wal_rows=$WAL_ROWS" -v "run_id=$STAMP" "$@" -f "$SCRIPT_DIR/module06-$name.sql"; }
csv() { local name="$1"; shift; show "${CONN[@]}" --csv "$@"; printf 'Save: %s/%s.csv\n' "$REPORT" "$name"; "${CONN[@]}" --csv "$@" > "$REPORT/$name.csv" 9>&-; }
snapshot() { csv "$1" -f "$SCRIPT_DIR/module06-baseline.sql"; }
setup_shared() { shared_conn; if (( ! READY_SHARED )); then sqlfile setup; READY_SHARED=1; fi; }
owned_work() { [[ -d "$WORK" && -O "$WORK" && ! -L "$WORK/.module06" && -f "$WORK/.module06" && "$(cat "$WORK/.module06")" == "$UID:$SID" ]] || die 'Module 6 workspace is not owned/marked for this student'; }
private_running() { pg_ctl -D "$PRIMARY" status >/dev/null 2>&1; }
restore_private() {
 [[ -f "$WORK/original.auto.conf" ]] || return 0
 owned_work
 [[ -d "$PRIMARY" && ! -L "$PRIMARY" && -f "$PRIMARY/PG_VERSION" ]] || die 'Invalid private cluster; saved configuration retained'
 run cp -- "$WORK/original.auto.conf" "$PRIMARY/postgresql.auto.conf.module06-tmp"
 run mv -- "$PRIMARY/postgresql.auto.conf.module06-tmp" "$PRIMARY/postgresql.auto.conf"
 if private_running; then
  run pg_ctl -D "$PRIMARY" reload
  private_conn
  local original now restored=0
  original="$(cat "$WORK/original.max_wal_size")"
  for ((try=0;try<30;try++)); do
   now="$(query 'SHOW max_wal_size;')"
   if [[ "$now" == "$original" ]]; then restored=1; break; fi
   sleep .2
  done
  (( restored )) || die 'Private max_wal_size has not reloaded; saved config retained for reset'
 fi
 run rm -- "$WORK/original.auto.conf" "$WORK/original.max_wal_size"
 printf 'Private postgresql.auto.conf restored byte-for-byte.\n'
}
start_private() {
 need initdb; need pg_ctl; need createdb
 if [[ ! -e "$WORK/.module06" ]]; then die 'Missing Module 6 workspace marker'; fi
 owned_work
 if [[ ! -f "$PRIMARY/PG_VERSION" ]]; then
  [[ ! -e "$PRIMARY" && ! -L "$PRIMARY" ]] || die 'Private primary exists but is incomplete; preserving it'
  run mkdir -p -- "$SOCKET"
  run chmod 700 "$SOCKET"
  run initdb -D "$PRIMARY" -U labadmin --auth-local=trust --auth-host=reject --encoding=UTF8 --no-locale
  cat >> "$PRIMARY/postgresql.conf" <<CFG
listen_addresses = ''
unix_socket_directories = '$SOCKET'
port = $PRIVATE_PORT
shared_buffers = '32MB'
max_connections = 10
max_wal_size = '64MB'
min_wal_size = '32MB'
checkpoint_timeout = '30min'
log_line_prefix = '%m [%p] %a %u@%d '
CFG
 fi
 [[ "$(cat "$PRIMARY/PG_VERSION")" == 18 && ! -L "$PRIMARY" ]] || die 'Private cluster must be PostgreSQL 18'
 if ! private_running; then run pg_ctl -D "$PRIMARY" -l "$WORK/server.log" -w -t 30 start; fi
 restore_private
 CONN=(psql -X --no-password -v ON_ERROR_STOP=1 -h "$SOCKET" -p "$PRIVATE_PORT" -U labadmin -d postgres)
 if [[ "$(query "SELECT 1 FROM pg_database WHERE datname='$PRIVATE_DB'")" != 1 ]]; then run createdb --no-password -h "$SOCKET" -p "$PRIVATE_PORT" -U labadmin "$PRIVATE_DB"; fi
 private_conn
 if (( ! READY_PRIVATE )); then sqlfile setup; READY_PRIVATE=1; fi
 printf 'PRIVATE lab server: database=%s socket=%s port=%s. Shared server is unchanged.\n' "$PRIVATE_DB" "$SOCKET" "$PRIVATE_PORT"
}
start_locker() {
 local seconds="$1"
 local app="module06_${SID}_locker"
 show env "PGAPPNAME=$app" "${CONN[@]}" -c "BEGIN; SELECT * FROM lab_m6_shell.capacity_probe WHERE id=1 FOR UPDATE; SELECT pg_sleep($seconds); COMMIT;"
 PGAPPNAME="$app" "${CONN[@]}" -c "BEGIN; SELECT * FROM lab_m6_shell.capacity_probe WHERE id=1 FOR UPDATE; SELECT pg_sleep($seconds); COMMIT;" > "$REPORT/locker.log" 2>&1 9>&- &
 LOCKER_PID=$!
 local ready=0
 for ((attempt=0;attempt<100;attempt++)); do
  if [[ "$(query "SELECT count(*) FROM pg_stat_activity WHERE application_name='$app' AND usename=current_user AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
  kill -0 "$LOCKER_PID" 2>/dev/null || break
  sleep .03
 done
 (( ready )) || die 'Row-lock holder did not become ready; see locker.log'
}
finish_locker() { if [[ -n "$LOCKER_PID" ]]; then wait "$LOCKER_PID"; LOCKER_PID=''; fi; }
restore_queue() { shared_conn; sqlfile reset; E_DIRTY=0; }
queue_metric() {
 run "${CONN[@]}" -v "rid=$STAMP" -v "phase=$1" -c "SELECT pg_stat_clear_snapshot(); INSERT INTO lab_m6_shell.metrics(run_id,lab,phase,iteration,metric,value,unit,details) SELECT '$STAMP','E','$1',1,k,v,u,jsonb_build_object('last_autovacuum',last_autovacuum,'reloptions',(SELECT reloptions FROM pg_class WHERE oid=relid)) FROM pg_stat_user_tables CROSS JOIN LATERAL (VALUES ('dead_tuples',n_dead_tup::numeric,'rows'),('autovacuum_count',autovacuum_count::numeric,'count'),('table_bytes',pg_total_relation_size(relid)::numeric,'bytes')) m(k,v,u) WHERE relid='lab_m6_shell.queue'::regclass;"
}
run_lab() {
 local lab="$1"
 printf '\n========== Lab 6%s ==========\n' "$lab"
 shared_conn; snapshot "$lab-shared-original"
 case "$lab" in
 A) sqlfile A;;
 B) setup_shared; sqlfile B;;
 C)
  setup_shared; csv C-capacity-before -f "$SCRIPT_DIR/module06-capacity.sql"
  for phase in before after; do
   local value expected=0
   value="$(query 'SHOW statement_timeout;')"
   if [[ "$phase" == after ]]; then value=200ms; expected=1; fi
   sqlfile timeout -v "phase=${phase}_statement" -v timeout_name=statement_timeout -v "timeout_value=$value" -v statement_test=1 -v "expect_cancel=$expected" -v expected_state=57014
   value="$(query 'SHOW lock_timeout;')"
   if [[ "$phase" == after ]]; then value=200ms; fi
   start_locker 1.5
   sqlfile timeout -v "phase=${phase}_lock" -v timeout_name=lock_timeout -v "timeout_value=$value" -v statement_test=0 -v "expect_cancel=$expected" -v expected_state=55P03
   finish_locker
  done
  run "${CONN[@]}" -c "BEGIN; SET LOCAL idle_in_transaction_session_timeout='2min'; SHOW idle_in_transaction_session_timeout; ROLLBACK; SHOW idle_in_transaction_session_timeout;"
  csv C-capacity-after -f "$SCRIPT_DIR/module06-capacity.sql"
  ;;
 D)
  start_private; snapshot D-private-original
  run cp -- "$PRIMARY/postgresql.auto.conf" "$WORK/original.auto.conf"
  query 'SHOW max_wal_size;' > "$WORK/original.max_wal_size"
  for phase in before after; do
   local wal_size=64MB; [[ "$phase" != after ]] || wal_size=256MB
   run "${CONN[@]}" -c "ALTER SYSTEM SET max_wal_size='$wal_size';"
   run pg_ctl -D "$PRIMARY" reload
   local applied=0
   for ((attempt=0;attempt<30;attempt++)); do
    if [[ "$(query 'SHOW max_wal_size;')" == "$wal_size" ]]; then applied=1; break; fi
    sleep .2
   done
   (( applied )) || die 'Private WAL setting did not reload'
   sqlfile D -v "phase=$phase"
  done
  csv D-results -c "SELECT phase,metric,value,unit,details FROM lab_m6_shell.metrics WHERE run_id='$STAMP' AND lab='D' ORDER BY measured_at"
  restore_private; private_conn; snapshot D-private-restored
  ;;
 E)
  setup_shared; E_DIRTY=1; sqlfile E
  sleep 1
  queue_metric before
  local original_count target_count count dead observed=0
  original_count="$(query "SELECT autovacuum_count FROM pg_stat_user_tables WHERE relid='lab_m6_shell.queue'::regclass")"
  # 500 + (2500 / row_count) * row_count = a 3000-row teaching trigger.
  sqlfile E-candidate
  for ((elapsed=0;elapsed<=WAIT_SECONDS;elapsed+=5)); do
   count="$(query "SELECT autovacuum_count FROM pg_stat_user_tables WHERE relid='lab_m6_shell.queue'::regclass")"
   dead="$(query "SELECT n_dead_tup FROM pg_stat_user_tables WHERE relid='lab_m6_shell.queue'::regclass")"
   printf 'Autovacuum observation: elapsed=%ss dead_tuples=%s autovacuum_count=%s\n' "$elapsed" "$dead" "$count"
   if (( count>original_count && dead==0 )); then observed=1; break; fi
   (( elapsed+5<=WAIT_SECONDS )) || break
   sleep 5
  done
  queue_metric after
  if (( ! observed )); then printf 'No completed candidate autovacuum observed in this window. Extend --wait; do not claim a vacuum improvement.\n'; fi
  restore_queue
  ;;
 F)
  start_private; snapshot F-private-original
  for phase in before after; do
   local offset candidate=0 app="module06_${SID}_F_$phase"
   offset="$(stat -c %s "$WORK/server.log")"
   [[ "$phase" != after ]] || candidate=1
   start_locker 3
   PGAPPNAME="$app" sqlfile F -v "candidate=$candidate"
   finish_locker
   tail -c "+$((offset+1))" "$WORK/server.log" > "$REPORT/F-$phase-server.log"
   python3 - "$REPORT/F-$phase-server.log" "$app" "$REPORT/F-$phase-counts.csv" <<'PY'
import csv,re,sys
from pathlib import Path
lines=[line for line in Path(sys.argv[1]).read_text().splitlines() if sys.argv[2] in line]
with open(sys.argv[3],'w') as f:
 w=csv.writer(f); w.writerow(['metric','count'])
 for metric,pattern in [('slow_statements',r'duration:'),('temp_files',r'temporary file:'),('lock_waits',r'still waiting for')]:
  count=sum(bool(re.search(pattern,line)) for line in lines)
  w.writerow([metric,count]); print(f'{metric}: {count}')
PY
  done
  private_conn; snapshot F-private-restored
  printf 'Compare F-before-counts.csv / F-after-counts.csv with the captured server logs.\n'
  ;;
 G)
  setup_shared; sqlfile summary; csv G-shared-summary -f "$SCRIPT_DIR/module06-summary.sql"
  if [[ -f "$PRIMARY/PG_VERSION" ]] && private_running; then private_conn; sqlfile summary; csv G-private-summary -f "$SCRIPT_DIR/module06-summary.sql"; fi
  cat > "$REPORT/decision.md" <<'DECISION'
# Module 6 decision record
- Symptom and observation interval:
- Parameter, current value and source:
- PostgreSQL boot default / session RESET value:
- Test value, scope and activation method:
- Comparable before/after measurements and repeated-run medians:
- Memory/disk/concurrency/latency guardrails:
- Keep, revise or revert; owner and reason:
- Reset command: ./run-lab06.sh reset
DECISION
  ;;
 esac
 shared_conn; snapshot "$lab-shared-restored"
 if cmp -s "$REPORT/$lab-shared-original.csv" "$REPORT/$lab-shared-restored.csv"; then
  printf 'RESTORED: shared effective settings match the original capture.\n'
 else
  printf 'Shared settings differ from the capture; inspect CSVs for external changes before continuing.\n'
 fi
 if [[ "$lab" == B || "$lab" == C || "$lab" == E ]]; then
  csv "$lab-results" -c "SELECT * FROM lab_m6_shell.metrics WHERE run_id='$STAMP' ORDER BY measured_at"
 fi
}
reset_all() {
 shared_conn; sqlfile reset
 if [[ -f "$PRIMARY/PG_VERSION" ]]; then
  need pg_ctl; owned_work; restore_private
  if private_running; then run pg_ctl -D "$PRIMARY" -m fast -w -t 30 stop; fi
 fi
 printf 'Original configuration restored; private server stopped. Fixtures and reports retained.\n'
}
finish() {
 local status=$?
 trap - EXIT INT TERM
 set +e
 if [[ -n "$LOCKER_PID" ]]; then wait "$LOCKER_PID"; fi
 if (( E_DIRTY )); then shared_conn; "${CONN[@]}" -f "$SCRIPT_DIR/module06-reset.sql" || printf 'Queue restore is pending. Run reset after reconnecting.\n' >&2; fi
 if [[ -f "$WORK/original.auto.conf" ]]; then restore_private || printf 'Private config restore is pending. Run reset.\n' >&2; fi
 exit "$status"
}
shared_conn
if (( DRY )); then
 printf 'PREVIEW | student=%s | shared database=%s | port=%s | action=%s\n' "$SID" "$DATABASE" "${M6_DB_PORT:-5432}" "$ACTION"
 printf 'Reports would be saved to %s\n' "$REPORT"
 printf 'A/B/C/E: own shared database. D/F: private Unix socket %s, port %s.\n' "$SOCKET" "$PRIVATE_PORT"
 printf 'Each lab captures originals, measures before/after and restores changed parameters.\n'
 if [[ "$ACTION" == all ]]; then printf 'Order: A B C D E F G reset\n'; fi
 show "${CONN[@]}" -f "$SCRIPT_DIR/module06-baseline.sql"
 printf 'No files or databases changed. See manual for exact SQL and setting locations.\n'
 exit 0
fi
need psql
if [[ "$ACTION" == doctor ]]; then
 run "${CONN[@]}" -c "SELECT current_database(),current_user,current_setting('port') AS port,version();"
 for tool in initdb pg_ctl createdb; do need "$tool"; run "$tool" --version; done
 need python3; need flock; printf 'Module 6 tools and shared connection ready.\n'; exit 0
fi
if [[ ! -e "$WORK" ]]; then
 run mkdir -m 700 -p -- "$WORK"
 printf '%s:%s\n' "$UID" "$SID" > "$WORK/.module06"
fi
owned_work
exec 9>"$WORK/.lock"; flock -n 9 || die 'Another Module 6 action is running'
mkdir -p -- "$REPORT_ROOT"
mkdir -m 700 -- "$REPORT"
exec > >(tee "$REPORT/transcript.log") 2>&1
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'Student %s | action %s | database %s:%s | report %s\n' "$SID" "$ACTION" "$DATABASE" "${M6_DB_PORT:-5432}" "$REPORT"
case "$ACTION" in
 baseline) sqlfile baseline; snapshot baseline;;
 setup) setup_shared;;
 reset) reset_all;;
 all) for lab in A B C D E F G; do run_lab "$lab"; done; reset_all;;
 *) run_lab "$ACTION";;
esac
printf '\nEvidence saved to %s\n' "$REPORT"
