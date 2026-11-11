#!/usr/bin/env bash
# 12 — BKK updates its own claim status
# EXPECT: HTTP 200, REVIEW
if ! declare -F supabase_run_case >/dev/null; then
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh" 12 "$@"
  supabase_run_case "$TARGET"
  exit
fi

printf '%s' '{"status":"REVIEW"}' > "$TMP/body.json"

HTTP_STATUS="$(curl "${CURL_FLAGS[@]}" \
  --request PATCH \
  "$SUPABASE_PUBLIC_URL/rest/v1/claimsure_claims?id=eq.$CLAIM_ID" \
  --header "@$BKK_HEADERS" \
  --header 'Content-Type: application/json' \
  --data-binary "@$TMP/body.json" \
  --header 'Prefer: return=representation' \
  --output "$RESPONSE" \
  --write-out '%{http_code}')" || die "API connection failed or timed out"
expect_status 200
expect_json --arg id "$CLAIM_ID" 'length==1 and .[0].id==$id and .[0].status=="REVIEW"'
CLAIM_STATUS=REVIEW
