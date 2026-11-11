#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/classroom-labs.py" --root "${COURSE_STACK_ROOT:-/opt/setup-postgres-labs}" "$@"
