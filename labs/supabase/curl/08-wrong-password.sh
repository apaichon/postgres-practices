#!/usr/bin/env bash
# 08 — Wrong password
# EXPECT: HTTP 400 or 401
if ! declare -F supabase_run_case >/dev/null; then
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh" 08 "$@"
  supabase_run_case "$TARGET"
  exit
fi

printf '%s\0%s\0' "$DEMO_BKK_EMAIL" 'intentionally-wrong-workshop-password' \
  | jq -Rs 'split("\u0000")|{email:.[0],password:.[1]}' > "$TMP/body.json"

HTTP_STATUS="$(curl "${CURL_FLAGS[@]}" \
  --request POST \
  "$SUPABASE_PUBLIC_URL/auth/v1/token?grant_type=password" \
  --header "@$ANON_HEADERS" \
  --header 'Content-Type: application/json' \
  --data-binary "@$TMP/body.json" \
  --output "$RESPONSE" \
  --write-out '%{http_code}')" || die "API connection failed or timed out"
expect_status 400 401
