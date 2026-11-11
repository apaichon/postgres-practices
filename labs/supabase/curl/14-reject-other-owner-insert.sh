#!/usr/bin/env bash
# 14 — Reject BKK inserting a claim owned by CM
# EXPECT: HTTP 403, SQLSTATE 42501
if ! declare -F supabase_run_case >/dev/null; then
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh" 14 "$@"
  supabase_run_case "$TARGET"
  exit
fi

reject_id="$(new_uuid)"
reject_claim="CLM-REST-REJECT_$STUDENT-$reject_id"
printf '%s\t%s\t%s\n' "$reject_id" "$reject_claim" "$CM_ID" >> "$TMP/rows.tsv"
jq -n --arg id "$reject_id" --arg claim "$reject_claim" --arg owner "$CM_ID" \
  '{id:$id,claim_no:$claim,branch:"CM",adjuster_id:$owner,amount:1,status:"NEW"}' \
  > "$TMP/body.json"

HTTP_STATUS="$(curl "${CURL_FLAGS[@]}" \
  --request POST \
  "$SUPABASE_PUBLIC_URL/rest/v1/claimsure_claims" \
  --header "@$BKK_HEADERS" \
  --header 'Content-Type: application/json' \
  --data-binary "@$TMP/body.json" \
  --header 'Prefer: return=representation' \
  --output "$RESPONSE" \
  --write-out '%{http_code}')" || die "API connection failed or timed out"
expect_status 403
expect_json '.code=="42501"'
