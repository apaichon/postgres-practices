#!/usr/bin/env bash
# 10 — BKK reads the temporary claim
# EXPECT: HTTP 200, one row
if ! declare -F supabase_run_case >/dev/null; then
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh" 10 "$@"
  supabase_run_case "$TARGET"
  exit
fi

HTTP_STATUS="$(curl "${CURL_FLAGS[@]}" \
  --request GET \
  "$SUPABASE_PUBLIC_URL/rest/v1/claimsure_claims?select=claim_no,branch,amount,status&order=claim_no&id=eq.$CLAIM_ID" \
  --header "@$BKK_HEADERS" \
  --output "$RESPONSE" \
  --write-out '%{http_code}')" || die "API connection failed or timed out"
expect_status 200
expect_json --arg claim "$CLAIM_NO" --arg status "$CLAIM_STATUS" \
  'length==1 and .[0].claim_no==$claim and .[0].status==$status'
