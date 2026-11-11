#!/usr/bin/env bash
# Instructor only: configure the existing Docker monitoring pipeline.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
M9_STACK_ROOT="${M9_STACK_ROOT:-/opt/setup-postgres-labs}"
[[ -r "$M9_STACK_ROOT/.env" ]] || { echo 'Instructor: monitoring stack .env is required (no credentials are bundled).' >&2; exit 1; }
set -a
source "$M9_STACK_ROOT/.env"
set +a
exec python3 "$SCRIPT_DIR/module09-stack.py" --root "$M9_STACK_ROOT" "$@"
