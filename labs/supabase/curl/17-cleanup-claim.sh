#!/usr/bin/env bash
# 17 — Admin deletes only this temporary claim
# EXPECT: HTTP 200, one deleted row
if ! declare -F supabase_run_case >/dev/null; then
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh" 17 "$@"
  supabase_run_case "$TARGET"
  exit
fi

HTTP_STATUS="$(curl "${CURL_FLAGS[@]}" \
  --request DELETE \
  "$SUPABASE_PUBLIC_URL/rest/v1/claimsure_claims?id=eq.$CLAIM_ID&adjuster_id=eq.$BKK_ID&claim_no=eq.$CLAIM_NO" \
  --header "@$ADMIN_HEADERS" \
  --header 'Prefer: return=representation' \
  --output "$RESPONSE" \
  --write-out '%{http_code}')" || die "API connection failed or timed out"
expect_status 200
expect_json --arg id "$CLAIM_ID" 'length==1 and .[0].id==$id'
