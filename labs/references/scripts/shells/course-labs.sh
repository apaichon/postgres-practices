#!/usr/bin/env bash
# Unified student runner for modules 1-7 and 9.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${SCRIPT_DIR##*/}" == scripts && -r "$SCRIPT_DIR/../.env" ]]; then source "$SCRIPT_DIR/../.env"
elif [[ -r "$HOME/.env" ]]; then source "$HOME/.env"; fi
if [[ -n "${DB_PASSWORD:-}" ]]; then export PGPASSWORD="$DB_PASSWORD"; fi
if [[ -n "${STUDENT_NO:-}" ]]; then export STUDENT_NO; fi
if [[ -n "${LAB_DB_HOST:-}" ]]; then export LAB_DB_HOST; fi
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
export PG_BIN PATH="$PG_BIN:$PATH"
exec python3 "$SCRIPT_DIR/course-labs.py" "$@"
