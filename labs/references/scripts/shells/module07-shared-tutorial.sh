#!/usr/bin/env bash
# Guided shared-server practice: changes only the Module 7 practice schema.
set -euo pipefail
umask 077
DRY_ARGS=()
RESTORE_DB=backup
while (( $# )); do
  case "$1" in
    --dry-run) DRY_ARGS=(--dry-run); shift ;;
    --database)
      (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || { echo '--database needs a target database name' >&2; exit 2; }
      RESTORE_DB="$2"; shift 2 ;;
    --database=*) RESTORE_DB="${1#*=}"; [[ -n "$RESTORE_DB" ]] || exit 2; shift ;;
    -h|--help)
      echo 'Usage: module07-shared-tutorial.sh [--dry-run] [--database main|backup|DATABASE]'
      echo 'Resets only the own main practice table, saves a backup, commits damage,'
      echo 'and restores the practice schema into the selected own database (default: backup).'
      exit 0 ;;
    *) echo 'Unknown option. Use --help.' >&2; exit 2 ;;
  esac
done
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
LAB7_DUMP="$HOME/backups/module07/shared-$(date -u +%Y%m%dT%H%M%SZ)-$$.dump"

# Validate the target before resetting or changing any data.
./run-lab07.sh --dry-run practice-restore "$LAB7_DUMP" --database "$RESTORE_DB" >/dev/null
./run-lab07.sh "${DRY_ARGS[@]}" seed main --reset-practice
./run-lab07.sh "${DRY_ARGS[@]}" practice-backup "$LAB7_DUMP"
./run-lab07.sh "${DRY_ARGS[@]}" damage
./run-lab07.sh "${DRY_ARGS[@]}" inspect main
./run-lab07.sh "${DRY_ARGS[@]}" practice-restore "$LAB7_DUMP" --database "$RESTORE_DB"
./run-lab07.sh "${DRY_ARGS[@]}" inspect "$RESTORE_DB"

if (( ${#DRY_ARGS[@]} )); then
  printf '\nPreview complete; no data or files changed. Archive would be: %s\n' "$LAB7_DUMP"
else
  printf '\nSaved backup: %s\n' "$LAB7_DUMP"
fi
