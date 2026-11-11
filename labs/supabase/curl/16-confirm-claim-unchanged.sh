#!/usr/bin/env bash
# 16 — BKK confirms its status and owner did not change
# EXPECT: HTTP 200, one REVIEW row still owned by BKK
if ! declare -F supabase_run_case >/dev/null; then
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh" 16 "$@"
  supabase_run_case "$TARGET"
  exit
fi

HTTP_STATUS="$(curl "${CURL_FLAGS[@]}" \
  --request GET \
  "$SUPABASE_PUBLIC_URL/rest/v1/claimsure_claims?id=eq.$CLAIM_ID&select=id,claim_no,adjuster_id,status" \
  --header "@$BKK_HEADERS" \
  --output "$RESPONSE" \
  --write-out '%{http_code}')" || die "API connection failed or timed out"
expect_status 200
expect_json --arg id "$CLAIM_ID" --arg owner "$BKK_ID" \
  'length==1 and .[0].id==$id and .[0].adjuster_id==$owner and .[0].status=="REVIEW"'
