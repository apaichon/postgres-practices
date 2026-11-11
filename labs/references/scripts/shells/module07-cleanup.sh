#!/usr/bin/env bash
# Preview or clear only this student's Module 7 practice data and lab files.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/run-lab07.sh" cleanup "$@"
