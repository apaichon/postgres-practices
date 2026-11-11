#!/usr/bin/env bash
# CLI entry point; Python's standard library coordinates persistent psql sessions.
set -euo pipefail
RUNNER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null || { echo 'Python 3.9+ is required.' >&2; exit 1; }
exec python3 "$RUNNER_DIR/runner/main.py" "$@"
