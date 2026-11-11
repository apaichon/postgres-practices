#!/usr/bin/env bash
# 15 — CM cannot select the BKK row for UPDATE
# EXPECT: HTTP 200, []
if ! declare -F supabase_run_case >/dev/null; then
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh" 15 "$@"
  supabase_run_case "$TARGET"
  exit
fi

printf '%s' '{"status":"APPROVED"}' > "$TMP/body.json"

HTTP_STATUS="$(curl "${CURL_FLAGS[@]}" \
  --request PATCH \
  "$SUPABASE_PUBLIC_URL/rest/v1/claimsure_claims?id=eq.$CLAIM_ID" \
  --header "@$CM_HEADERS" \
  --header 'Content-Type: application/json' \
  --data-binary "@$TMP/body.json" \
  --header 'Prefer: return=representation' \
  --output "$RESPONSE" \
  --write-out '%{http_code}')" || die "API connection failed or timed out"
expect_status 200
expect_json '.==[]'
