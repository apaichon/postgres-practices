#!/usr/bin/env bash
# Shared configuration, dependencies, assertions and cleanup for curl/*.sh.
set -eEuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CURL_DIR="$SCRIPT_DIR/curl"
ENV_FILE="$SCRIPT_DIR/.env"
REPORT="$SCRIPT_DIR/artifacts/api-results-shell.json"
STUDENT="${STUDENT_NO:-}"
TARGET=all
TIMEOUT=20
SHOW_BODY=0
LIST_ONLY=0
TARGET_SET=0
TMP=""
ACTIVE_ID=""
HTTP_STATUS=0
NAMES=(readAnonymous loginBkk loginCm readBkk readCm readOtherOwner
  invalidToken wrongPassword createClaim readCreatedClaim cmReadsBkkClaim
  updateOwnClaim rejectOwnerTransfer rejectOtherOwnerInsert cmUpdatesBkkClaim
  confirmClaimUnchanged cleanupClaim readServiceRole)
FILES=(01-anonymous.sh 02-login-bkk.sh 03-login-cm.sh
  04-read-bkk.sh 05-read-cm.sh 06-read-other-owner.sh
  07-invalid-token.sh 08-wrong-password.sh 09-create-claim.sh
  10-read-created-claim.sh 11-cm-read-bkk-claim.sh 12-update-own-claim.sh
  13-reject-owner-transfer.sh 14-reject-other-owner-insert.sh 15-cm-update-bkk-claim.sh
  16-confirm-claim-unchanged.sh 17-cleanup-claim.sh 18-read-service-role.sh)
DONE=()
BKK_TOKEN=""; BKK_ID=""; CM_TOKEN=""; CM_ID=""
CLAIM_ID=""; CLAIM_NO=""; CLAIM_STATUS=NEW

usage() {
  cat <<'EOF'
Usage: bash labs/supabase/run_api.sh [all|01..18|requestName] [options]
       bash labs/supabase/curl/NN-name.sh [options]

Run all cases, or one case with its required login/test-row setup.
Temporary rows are removed automatically after each invocation.

Examples (replace xx with your assigned number):
  bash labs/supabase/run_api.sh --list
  bash labs/supabase/run_api.sh all
  bash labs/supabase/run_api.sh 04
  bash labs/supabase/curl/04-read-bkk.sh
  bash labs/supabase/curl/12-update-own-claim.sh --student xx
  bash labs/supabase/run_api.sh updateOwnClaim --student xx
  bash labs/supabase/run_api.sh all --show-body

Options:
  --student xx   Assigned two-digit number (01–20).
                 Default: STUDENT_NO, then @studentNo in data-api.http.
  --env PATH     Private configuration (default: labs/supabase/.env).
  --report PATH  JSON summary without credentials.
  --timeout N    Seconds per HTTP call, 1–120 (default: 20).
  --show-body    Print JSON for data requests; Auth responses stay hidden.
  --list        List cases without reading credentials or calling APIs.
  -h, --help    Show this help.

Requires a running, seeded lab with four baseline claims; never seeds/resets it.
EOF
}

record() {
  local passed="$1" message="${2:-}"
  [[ -n "$ACTIVE_ID" ]] || return 0
  jq -cn --argjson number "$((10#$ACTIVE_ID))" \
    --arg name "${NAMES[$((10#$ACTIVE_ID-1))]}" \
    --argjson status "$((10#${HTTP_STATUS:-0}))" --argjson passed "$passed" \
    --arg error "$message" --argjson selected "$([[ "$TARGET" == all || "$TARGET" == "$ACTIVE_ID" ]] && echo true || echo false)" \
    '{number:$number,name:$name,status:$status,passed:$passed,selected:$selected}
      + (if $error=="" then {} else {error:$error} end)' >> "$TMP/results.jsonl"
}

die() {
  printf 'FAIL%s: %s\n' "${ACTIVE_ID:+ $ACTIVE_ID}" "$1" >&2
  if [[ -n "$TMP" && -n "$ACTIVE_ID" ]]; then record false "$1"; fi
  exit 1
}

while (( $# )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --list) LIST_ONLY=1; shift ;;
    --show-body) SHOW_BODY=1; shift ;;
    --student|--env|--report|--timeout)
      (( $# >= 2 )) || die "$1 needs a value"
      case "$1" in
        --student) STUDENT="$2" ;; --env) ENV_FILE="$2" ;;
        --report) REPORT="$2" ;; --timeout) TIMEOUT="$2" ;;
      esac
      shift 2 ;;
    -*) die "Unknown option; use --help" ;;
    *) (( TARGET_SET == 0 )) || die "Choose one case or all per invocation"
      TARGET="$1"; TARGET_SET=1; shift ;;
  esac
done

if (( LIST_ONLY )); then
  for ((i=0;i<${#NAMES[@]};i++)); do printf '%02d %s\n' "$((i+1))" "${NAMES[$i]}"; done
  exit 0
fi

if [[ "$TARGET" != all ]]; then
  if [[ "$TARGET" =~ ^[0-9]{1,2}$ ]]; then
    number=$((10#$TARGET))
    (( number >= 1 && number <= 18 )) || die "Case must be 01–18"
    TARGET="$(printf '%02d' "$number")"
  else
    found=0
    for ((i=0;i<${#NAMES[@]};i++)); do
      if [[ "$TARGET" == "${NAMES[$i]}" ]]; then
        TARGET="$(printf '%02d' "$((i+1))")"; found=1; break
      fi
    done
    (( found )) || die "Unknown case; use --list"
  fi
  SHOW_BODY=1
fi

for tool in curl jq cmp mktemp; do command -v "$tool" >/dev/null || die "Missing dependency: $tool"; done
if ! command -v uuidgen >/dev/null && ! command -v openssl >/dev/null; then
  die "UUID generation needs uuidgen or openssl"
fi
if [[ -z "$STUDENT" ]]; then
  STUDENT="$(sed -n 's/^@studentNo[[:space:]]*=[[:space:]]*//p' "$SCRIPT_DIR/data-api.http" | head -n 1)"
fi
[[ "$STUDENT" =~ ^(0[1-9]|1[0-9]|20)$ ]] || die "Set --student or STUDENT_NO to your assigned number; xx is a placeholder"
[[ "$TIMEOUT" =~ ^[0-9]{1,3}$ ]] || die "--timeout must be 1–120"
(( 10#$TIMEOUT >= 1 && 10#$TIMEOUT <= 120 )) || die "--timeout must be 1–120"
TIMEOUT=$((10#$TIMEOUT))

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

load_env() {
  local line key value
  [[ -f "$ENV_FILE" ]] || die "Missing .env; prepare your own Supabase lab first"
  # Assign only known configuration keys. Never execute/source the file.
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -n "$line" && "$line" != \#* ]] || continue
    [[ "$line" == *=* ]] || die "Invalid .env assignment"
    key="$(trim "${line%%=*}")"; value="$(trim "${line#*=}")"
    case "$value" in
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
      \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    case "$key" in
      SUPABASE_PUBLIC_URL|ANON_KEY|SERVICE_ROLE_KEY|DEMO_BKK_EMAIL|DEMO_CM_EMAIL|DEMO_PASSWORD)
        printf -v "$key" '%s' "$value" ;;
    esac
  done < "$ENV_FILE"
  for key in SUPABASE_PUBLIC_URL ANON_KEY SERVICE_ROLE_KEY DEMO_BKK_EMAIL DEMO_CM_EMAIL DEMO_PASSWORD; do
    [[ -n "${!key:-}" ]] || die "Missing .env key: $key"
  done
  SUPABASE_PUBLIC_URL="${SUPABASE_PUBLIC_URL%/}"
  case "$SUPABASE_PUBLIC_URL" in http://*|https://*) ;; *) die "Invalid SUPABASE_PUBLIC_URL" ;; esac
}

new_uuid() {
  if command -v uuidgen >/dev/null; then uuidgen | tr '[:upper:]' '[:lower:]'
  else
    local hex variant
    hex="$(openssl rand -hex 16)"; variant="$(printf '%x' "$(( (16#${hex:16:1} & 3) | 8 ))")"
    printf '%s-%s-4%s-%s%s-%s\n' "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" "$variant" "${hex:17:3}" "${hex:20:12}"
  fi
}

save_auth_headers() {
  # Files stay in the private temporary directory and are removed on exit.
  printf 'apikey: %s\nAuthorization: Bearer %s\n' "$2" "$3" > "$1"
}

request() {
  local method="$1" path="$2" caller="$3" body="${4:-}" representation="${5:-}"
  local key token
  key="$ANON_KEY"
  case "$caller" in
    anon) token="$ANON_KEY" ;; bkk) token="$BKK_TOKEN" ;; cm) token="$CM_TOKEN" ;;
    invalid) token=invalid-token ;; admin) key="$SERVICE_ROLE_KEY"; token="$SERVICE_ROLE_KEY" ;;
    *) return 1 ;;
  esac
  {
    printf 'apikey: %s\nAuthorization: Bearer %s\n' "$key" "$token"
    [[ -z "$body" ]] || printf 'Content-Type: application/json\n'
    [[ -z "$representation" ]] || printf 'Prefer: return=representation\n'
  } > "$TMP/headers"
  # Private header/body files keep credentials out of curl's process arguments.
  if [[ -n "$body" ]]; then
    HTTP_STATUS="$(curl --silent --show-error --connect-timeout 5 --max-time "$TIMEOUT" \
      --request "$method" --header "@$TMP/headers" --data-binary "@$body" \
      --output "$TMP/response.json" --write-out '%{http_code}' "$SUPABASE_PUBLIC_URL$path")" || return 1
  else
    HTTP_STATUS="$(curl --silent --show-error --connect-timeout 5 --max-time "$TIMEOUT" \
      --request "$method" --header "@$TMP/headers" \
      --output "$TMP/response.json" --write-out '%{http_code}' "$SUPABASE_PUBLIC_URL$path")" || return 1
  fi
}

expect_status() {
  case " $* " in *" $HTTP_STATUS "*) ;; *) die "HTTP $HTTP_STATUS; expected $*" ;; esac
}

expect_json() {
  jq -e "$@" "$TMP/response.json" >/dev/null 2>&1 || die "Response JSON did not match the expected result"
}

snapshot() {
  local output="$1"
  request GET '/rest/v1/claimsure_claims?select=*&order=claim_no' admin || return 1
  [[ "$HTTP_STATUS" == 200 ]] || return 1
  jq -e 'type=="array"' "$TMP/response.json" >/dev/null 2>&1 || return 1
  jq -Sc 'sort_by(.claim_no)' "$TMP/response.json" > "$output"
}

cleanup() {
  local code=$? cleanup_state=not-needed cleanup_failed=0 id claim owner path total selected
  trap - EXIT INT TERM ERR
  set +e
  ACTIVE_ID=""
  if [[ -s "$TMP/rows.tsv" ]]; then
    cleanup_state=passed
    while IFS=$'\t' read -r id claim owner; do
      path="/rest/v1/claimsure_claims?id=eq.$id&claim_no=eq.$claim&adjuster_id=eq.$owner"
      if ! request DELETE "$path" admin; then cleanup_failed=1
      elif [[ "$HTTP_STATUS" != 200 && "$HTTP_STATUS" != 204 ]]; then cleanup_failed=1
      fi
    done < "$TMP/rows.tsv"
  fi
  if [[ -f "$TMP/baseline.json" ]]; then
    if ! snapshot "$TMP/after.json" || ! cmp -s "$TMP/baseline.json" "$TMP/after.json"; then cleanup_failed=1; fi
  fi
  if (( cleanup_failed )); then
    code=1; cleanup_state=failed
    printf 'FAIL: cleanup/baseline check failed; inspect your lab before retrying\n' >&2
  elif [[ "$cleanup_state" == passed ]]; then
    printf 'CLEANUP: temporary rows removed; original four claims unchanged\n'
  fi
  if ! mkdir -p "$(dirname -- "$REPORT")" || ! jq -s \
    --arg started_at "$STARTED_AT" --arg target "$TARGET" --arg student "$STUDENT" \
    --arg cleanup "$cleanup_state" --argjson exit_code "$code" \
    '{started_at:$started_at,student:$student,target:$target,passed:($exit_code==0),
      cleanup:$cleanup,requests:.}' "$TMP/results.jsonl" > "$REPORT"; then
    code=1; printf 'FAIL: cannot write report\n' >&2
  else printf 'Report: %s\n' "$REPORT"; fi
  if (( code == 0 )); then
    total="$(jq -s 'length' "$TMP/results.jsonl")"
    selected="$(jq -s '[.[]|select(.selected)]|length' "$TMP/results.jsonl")"
    printf 'PASS: %s selected case(s), %s request check(s) including setup\n' "$selected" "$total"
  fi
  rm -rf -- "$TMP"
  exit "$code"
}

load_env
umask 077
TMP="$(mktemp -d "${TMPDIR:-/tmp}/supabase-api.XXXXXXXX")"
: > "$TMP/results.jsonl"; : > "$TMP/rows.tsv"
RESPONSE="$TMP/response.json"
CURL_FLAGS=(--silent --show-error --connect-timeout 5 --max-time "$TIMEOUT")
ANON_HEADERS="$TMP/anon.headers"; BKK_HEADERS="$TMP/bkk.headers"
CM_HEADERS="$TMP/cm.headers"; ADMIN_HEADERS="$TMP/admin.headers"
INVALID_HEADERS="$TMP/invalid.headers"
save_auth_headers "$ANON_HEADERS" "$ANON_KEY" "$ANON_KEY"
save_auth_headers "$ADMIN_HEADERS" "$SERVICE_ROLE_KEY" "$SERVICE_ROLE_KEY"
save_auth_headers "$INVALID_HEADERS" "$ANON_KEY" invalid-token

STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'die "Command failed while testing API; see the report"' ERR

snapshot "$TMP/baseline.json" || die "Cannot read the lab baseline with service role"
jq -e 'length==4 and ([.[].claim_no]|sort)==["CLM-BKK-001","CLM-BKK-002","CLM-CM-001","CLM-CM-002"]' \
  "$TMP/baseline.json" >/dev/null || die "Expected four seed claims; finish prior cleanup first. No reset performed"

supabase_run_case() {
  local id="$1" index=$((10#$1-1)) label name
  [[ "${DONE[$index]:-0}" == 0 ]] || return 0
  case "$id" in
    04|06|09) supabase_run_case 02 ;;
    05) supabase_run_case 03 ;;
    10|12|17) supabase_run_case 09 ;;
    11|13|15) supabase_run_case 09; supabase_run_case 03 ;;
    14) supabase_run_case 02; supabase_run_case 03 ;;
    16) supabase_run_case 12; supabase_run_case 13; supabase_run_case 15 ;;
  esac
  ACTIVE_ID="$id"; HTTP_STATUS=0; name="${NAMES[$index]}"
  source "$CURL_DIR/${FILES[$index]}"
  DONE[$index]=1
  label=PASS; [[ "$TARGET" == all || "$TARGET" == "$id" ]] || label='SETUP PASS'
  printf '%s %s %s: HTTP %s\n' "$label" "$id" "$name" "$HTTP_STATUS"
  record true
  if (( SHOW_BODY )) && [[ "$TARGET" == all || "$TARGET" == "$id" ]]; then
    case "$id" in 02|03|08) printf 'Auth response hidden\n' ;; *) jq . "$TMP/response.json" ;; esac
  fi
  ACTIVE_ID=""
}
