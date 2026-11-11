#!/usr/bin/env bash
# Separate Docker environments; independent of the continuous SQL lab runner.
set -euo pipefail
LABS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  8|08) LAB_RUNNER="$LABS_DIR/module08-replication/lab.py" ;;
  10) LAB_RUNNER="$LABS_DIR/supabase/lab.py" ;;
  *)
    echo 'Usage: bash labs/docker-labs.sh {8|10} COMMAND [ARGS]'
    echo 'Common commands: init config pull up status stop down verify'
    echo 'Lab 8: psql [pg1|pg2|pg3]. Lab 10: seed api-demo verify psql wait.'
    echo 'Lab 10 optional Storage/Functions: seed --extended; verify --extended.'
    exit 2 ;;
esac
shift
exec python3 "$LAB_RUNNER" "$@"
