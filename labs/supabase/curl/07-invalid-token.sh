#!/usr/bin/env bash
# 07 — Invalid bearer token
# EXPECT: HTTP 401
if ! declare -F supabase_run_case >/dev/null; then
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh" 07 "$@"
  supabase_run_case "$TARGET"
  exit
fi

HTTP_STATUS="$(curl "${CURL_FLAGS[@]}" \
  --request GET \
  "$SUPABASE_PUBLIC_URL/rest/v1/claimsure_claims?select=claim_no,branch,amount,status&order=claim_no" \
  --header "@$INVALID_HEADERS" \
  --output "$RESPONSE" \
  --write-out '%{http_code}')" || die "API connection failed or timed out"
expect_status 401
