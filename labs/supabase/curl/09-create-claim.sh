#!/usr/bin/env bash
# 09 — BKK creates a temporary claim
# EXPECT: HTTP 201, one NEW row
if ! declare -F supabase_run_case >/dev/null; then
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh" 09 "$@"
  supabase_run_case "$TARGET"
  exit
fi

CLAIM_ID="$(new_uuid)"
CLAIM_NO="CLM-REST_$STUDENT-$CLAIM_ID"
CLAIM_STATUS=NEW
# Register before POST so cleanup also works if the response is lost.
printf '%s\t%s\t%s\n' "$CLAIM_ID" "$CLAIM_NO" "$BKK_ID" >> "$TMP/rows.tsv"
jq -n --arg id "$CLAIM_ID" --arg claim "$CLAIM_NO" --arg owner "$BKK_ID" \
  '{id:$id,claim_no:$claim,branch:"BKK",adjuster_id:$owner,amount:1500,status:"NEW"}' \
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
expect_status 201
expect_json --arg id "$CLAIM_ID" --arg owner "$BKK_ID" \
  'length==1 and .[0].id==$id and .[0].adjuster_id==$owner and .[0].status=="NEW"'
