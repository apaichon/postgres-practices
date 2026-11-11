#!/usr/bin/env bash
# Module 9 student launcher; no sudo or Docker required.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${SCRIPT_DIR##*/}" == scripts && -r "$SCRIPT_DIR/../.env" ]]; then
 source "$SCRIPT_DIR/../.env"
elif [[ -r "$HOME/.env" ]]; then source "$HOME/.env"; fi
if [[ -n "${DB_PASSWORD:-}" ]]; then export PGPASSWORD="$DB_PASSWORD"; fi
if [[ -n "${STUDENT_NO:-}" ]]; then export STUDENT_NO; fi
export PATH="${PG_BIN:-/usr/lib/postgresql/18/bin}:$PATH"
exec python3 "$SCRIPT_DIR/module09-lab.py" "$@"
