#!/usr/bin/env bash
# Module 6 reset: forward options to the measurement runner.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/run-lab06.sh" reset "$@"
