#!/usr/bin/env bash
# Lab D: replay staging WAL to a target, then import recovered shared practice data.
set -euo pipefail
umask 077
DRY_ARGS=()
RESTORE_DB=main
while (( $# )); do
  case "$1" in
    --dry-run) DRY_ARGS=(--dry-run); shift ;;
    --database)
      (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || { echo '--database needs a target database name' >&2; exit 2; }
      RESTORE_DB="$2"; shift 2 ;;
    --database=*) RESTORE_DB="${1#*=}"; [[ -n "$RESTORE_DB" ]] || exit 2; shift ;;
    -h|--help)
      echo 'Usage: module07-claimsure-pitr-tutorial.sh [--dry-run] [--database main|backup|DATABASE]'
      echo 'Resets only the own main practice table, captures a private staging base and recovery point,'
      echo 'commits damage, then logically imports recovered rows into the selected own DB (default: main).'
      exit 0 ;;
    *) echo 'Unknown option. Use --help.' >&2; exit 2 ;;
  esac
done
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
LAB7_DUMP="$HOME/backups/module07/pitr-target-validation.dump"

# Validate the target before resetting or changing any data.
./run-lab07.sh --dry-run practice-restore "$LAB7_DUMP" --database "$RESTORE_DB" >/dev/null
./run-lab07.sh "${DRY_ARGS[@]}" seed main --reset-practice
./run-lab07.sh "${DRY_ARGS[@]}" claimsure-pitr-backup
./run-lab07.sh "${DRY_ARGS[@]}" claimsure-pitr-event
./run-lab07.sh "${DRY_ARGS[@]}" claimsure-pitr-mark
./run-lab07.sh "${DRY_ARGS[@]}" damage
./run-lab07.sh "${DRY_ARGS[@]}" inspect main
./run-lab07.sh "${DRY_ARGS[@]}" claimsure-pitr-restore --database "$RESTORE_DB"
./run-lab07.sh "${DRY_ARGS[@]}" inspect "$RESTORE_DB"

if (( ${#DRY_ARGS[@]} )); then
  printf '\nLab D preview complete; no data or files changed.\n'
else
  printf '\nLab D complete. Inspect the selected database on the shared port 5432.\n'
fi
