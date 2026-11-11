#!/usr/bin/env bash
# Dedicated PostgreSQL 18 instance; never uses the shared classroom SSH service.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAB_DIR="$REPO_ROOT/labs/module06"
cd "$LAB_DIR"

usage() {
  cat <<'USAGE'
Module 6 — six parameter groups on an isolated Docker Compose instance
First copy labs/module06/.env.example to labs/module06/.env and edit it.
  run-lab06-docker.sh up                    Start the dedicated instance
  run-lab06-docker.sh sql A|B|C|D|E|F|all    Run SQL experiments (no file changes)
  run-lab06-docker.sh set A|B|C|D|E|F baseline|candidate
                                    Copy ONE preset; does not activate it
  run-lab06-docker.sh reload                pg_reload_conf(), then inspect
  run-lab06-docker.sh restart               Restart this lab instance; disconnects clients
  run-lab06-docker.sh inspect               Effective/source/file errors/pending restart
  run-lab06-docker.sh psql                  Open postgres on claimsure_m6
  run-lab06-docker.sh logs                  Last 100 PostgreSQL log lines
  run-lab06-docker.sh stop                  Stop the instance; keep data and config
No command deletes the data volume. See labs/module06/README.md for rollback.
USAGE
}
dc() { docker compose -f "$LAB_DIR/compose.yaml" "$@"; }
db() { dc exec -T postgres psql -X -U postgres -d claimsure_m6 -v ON_ERROR_STOP=1 "$@"; }
wait_ready() {
  local attempt
  for attempt in {1..30}; do
    # Ignore the temporary initdb server: PID 1 becomes postgres only at final exec.
    if dc exec -T postgres sh -c 'test "$(cat /proc/1/comm)" = postgres' >/dev/null 2>&1 \
      && db -Atqc 'SELECT 1' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  dc logs --tail 30 postgres
  echo "PostgreSQL did not become ready." >&2
  return 1
}
inspect() { db -f /lab/sql/06-configuration-inspect.sql; }
action="${1:-help}"
case "$action" in help|-h|--help) usage; exit 0 ;; esac
if [[ ! -f .env ]]; then
  echo "Create labs/module06/.env from .env.example first. See labs/module06/README.md." >&2
  exit 2
fi
case "$action" in
  up) dc up -d postgres; wait_ready; inspect ;;
  sql)
    group="${2:-}"
    case "$group" in A|B|C|D|E|F|all) ;; *) usage >&2; exit 2 ;; esac
    db -v "m6_lab=$group" -f /lab/sql/06-configuration-claim.sql
    ;;
  set)
    group="${2:-}"; preset="${3:-}"
    case "$group" in
      A) file=10-connections.conf ;; B) file=20-memory.conf ;;
      C) file=30-wal.conf ;; D) file=40-planning.conf ;;
      E) file=50-parallel.conf ;; F) file=60-autovacuum.conf ;;
      *) usage >&2; exit 2 ;;
    esac
    case "$preset" in baseline|candidate) ;; *) usage >&2; exit 2 ;; esac
    cp "presets/$preset/$file" "config/conf.d/$file"
    echo "Edited host file: $LAB_DIR/config/conf.d/$file"
    echo "PostgreSQL reads: /etc/postgresql/module06/conf.d/$file"
    case "$group" in
      A|B|E) echo "RESTART REQUIRED. Run reload + inspect to see pending_restart, then restart." ;;
      *) echo "RELOAD REQUIRED. Run reload + inspect, then open a new session for the SQL comparison." ;;
    esac
    ;;
  reload) db -c 'SELECT pg_reload_conf();'; inspect ;;
  restart) dc restart postgres; wait_ready; inspect ;;
  inspect) inspect ;;
  psql) dc exec postgres psql -X -U postgres -d claimsure_m6 -v ON_ERROR_STOP=1 ;;
  logs) dc logs --tail 100 postgres ;;
  stop) dc stop postgres ;;
  *) usage >&2; exit 2 ;;
esac
