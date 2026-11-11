#!/usr/bin/env bash
# 18 — Admin reads all four seed claims
# EXPECT: HTTP 200, four baseline rows
if ! declare -F supabase_run_case >/dev/null; then
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh" 18 "$@"
  supabase_run_case "$TARGET"
  exit
fi

HTTP_STATUS="$(curl "${CURL_FLAGS[@]}" \
  --request GET \
  "$SUPABASE_PUBLIC_URL/rest/v1/claimsure_claims?select=claim_no,branch,amount,status&order=claim_no" \
  --header "@$ADMIN_HEADERS" \
  --output "$RESPONSE" \
  --write-out '%{http_code}')" || die "API connection failed or timed out"
expect_status 200
expect_json 'length==4 and ([.[].claim_no]|sort)==["CLM-BKK-001","CLM-BKK-002","CLM-CM-001","CLM-CM-002"]'
