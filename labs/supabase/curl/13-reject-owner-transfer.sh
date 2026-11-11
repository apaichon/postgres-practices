#!/usr/bin/env bash
# 13 — Reject an owner transfer to CM
# EXPECT: HTTP 403, SQLSTATE 42501
if ! declare -F supabase_run_case >/dev/null; then
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh" 13 "$@"
  supabase_run_case "$TARGET"
  exit
fi

# Also register the proposed owner to clean up if the policy is broken.
printf '%s\t%s\t%s\n' "$CLAIM_ID" "$CLAIM_NO" "$CM_ID" >> "$TMP/rows.tsv"
jq -n --arg owner "$CM_ID" '{adjuster_id:$owner}' > "$TMP/body.json"

HTTP_STATUS="$(curl "${CURL_FLAGS[@]}" \
  --request PATCH \
  "$SUPABASE_PUBLIC_URL/rest/v1/claimsure_claims?id=eq.$CLAIM_ID" \
  --header "@$BKK_HEADERS" \
  --header 'Content-Type: application/json' \
  --data-binary "@$TMP/body.json" \
  --header 'Prefer: return=representation' \
  --output "$RESPONSE" \
  --write-out '%{http_code}')" || die "API connection failed or timed out"
expect_status 403
expect_json '.code=="42501"'
