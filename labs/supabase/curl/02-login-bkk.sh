#!/usr/bin/env bash
# 02 — Login BKK and keep its token privately
# EXPECT: HTTP 200; token/user ID are kept in memory
if ! declare -F supabase_run_case >/dev/null; then
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh" 02 "$@"
  supabase_run_case "$TARGET"
  exit
fi

# Build JSON from stdin so quoted passwords remain valid JSON.
printf '%s\0%s\0' "$DEMO_BKK_EMAIL" "$DEMO_PASSWORD" \
  | jq -Rs 'split("\u0000")|{email:.[0],password:.[1]}' > "$TMP/body.json"

HTTP_STATUS="$(curl "${CURL_FLAGS[@]}" \
  --request POST \
  "$SUPABASE_PUBLIC_URL/auth/v1/token?grant_type=password" \
  --header "@$ANON_HEADERS" \
  --header 'Content-Type: application/json' \
  --data-binary "@$TMP/body.json" \
  --output "$RESPONSE" \
  --write-out '%{http_code}')" || die "API connection failed or timed out"

expect_status 200
expect_json '(.access_token|type)=="string" and (.user.id|type)=="string"'
BKK_TOKEN="$(jq -er '.access_token' "$RESPONSE")"
BKK_ID="$(jq -er '.user.id' "$RESPONSE")"
[[ "$BKK_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || die "Invalid Auth user UUID"
save_auth_headers "$BKK_HEADERS" "$ANON_KEY" "$BKK_TOKEN"
