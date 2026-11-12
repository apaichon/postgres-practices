#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB="$SCRIPT_DIR/lab.sh"
TODAY="$(date +%Y%m%d)"
RUN_ID="$(date +%Y%m%dT%H%M%S)"
WEEKDAY="$(date +%u)"
FULL_STATE="$SCRIPT_DIR/../artifacts/physical/latest"

bash "$LAB" up >/dev/null

if [[ "$WEEKDAY" == "7" || ! -f "$FULL_STATE" ]]; then
  printf 'Weekly full backup for %s\n' "$TODAY"
  bash "$LAB" logical-backup
  bash "$LAB" physical-full
else
  printf 'Daily incremental backup for %s\n' "$TODAY"
  bash "$LAB" globals
  bash "$LAB" physical-incremental "daily-$RUN_ID"
fi

bash "$LAB" files
