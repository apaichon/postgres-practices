#!/usr/bin/env bash
# Entry point; the readable curl commands live in curl/01-*.sh through 18-*.sh.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/curl/_common.sh" "$@"

printf 'Supabase API shell tests for student %s; credentials hidden\n' "$STUDENT"
if [[ "$TARGET" == all ]]; then
  for ((n=1;n<=18;n++)); do supabase_run_case "$(printf '%02d' "$n")"; done
else
  supabase_run_case "$TARGET"
fi
