# Supabase Labs — Table, Authentication, Data API และ RLS

[สารบัญแล็บ](README.md) · [การติดตั้งและดูแล stack](supabase/README.md) · [บทฝึก API ฉบับย่อ](../docs/tutorials/supabase-self-hosted/API-LAB.md)

ใบงานนี้ใช้ **Supabase self-hosted ของโปรเจกต์นี้** ให้ผู้เรียนทำทีละแล็บ บันทึก HTTP status และผล JSON แล้วอธิบายว่า Auth, grants และ RLS มีผลต่อ request อย่างไร ประมาณเวลา **60–90 นาทีหลังระบบพร้อม** ตามความคุ้นเคยกับ Terminal

ใช้ข้อมูลจำลองใน `public.claimsure_claims` ของ Supabase project ที่ได้รับมอบหมาย ฐานนี้แยกจาก `claimsure_xx` ของบท PostgreSQL ต่อเนื่อง และไม่ได้ sync ข้อมูลกับ `claimsure.claim` อัตโนมัติ

## ก่อนเริ่ม

- มี repository สำเนาของตน, Bash, Python 3.10+, `curl` และ Browser
- ถ้าติดตั้งเอง ต้องมี Docker Engine/Desktop และ Docker Compose v2; ถ้าเป็นเครื่องเรียน อาจารย์เตรียม stack และสิทธิ์ให้ก่อน
- ได้หมายเลขนักเรียนสองหลัก `01`–`20`, endpoint ของตน และ credentials ที่เกี่ยวข้อง
- ใช้ Terminal เดียวกันสำหรับตัวแปร Login/API ใน SB3–SB8
- รัน Bash จาก **root ของ repository `postgres-practices`**; SQL รันใน **SQL Editor ของ Supabase project ของตน**

`xx` คือ placeholder ให้แทนด้วยหมายเลขที่ได้รับก่อนใช้ชื่อที่แยกต่อคน เช่น `studentxx`, `postgres-practices-m10_xx` และ `adjuster.bkk_xx@claimsure.example.com`

ชื่อ `postgres`, `anon`, `authenticated`, `service_role` และ `public.claimsure_claims` เป็นชื่อระบบ/ตารางของชุดฝึกภายใน project ที่แยกไว้แล้ว ให้ใช้ตามคำสั่ง ส่วนชื่อที่แยกตามผู้เรียนต้องตรงกับ project และบัญชีของตน

| แล็บ | สิ่งที่ลงมือ | หลักฐานเมื่อจบ |
| --- | --- | --- |
| SB0 | เตรียม project และตรวจ connection | Project name, URL และหมายเลขของตน |
| SB1 | สร้าง Table และ Policies | RLS เปิด, มี SELECT/INSERT/UPDATE policies |
| SB2 | เตรียม Auth Users และ Claims | ผู้ใช้ 2 ราย, เคลม 4 แถว, Owner ตรง UUID |
| SB3 | เรียก API ก่อน Login | HTTP 200 และ `[]` |
| SB4 | Login เป็น BKK และ CM | แต่ละคนอ่านเคลมของตน 2 แถว |
| SB5 | ทดลองอ่านข้าม Owner | HTTP 200 และ `[]` |
| SB6 | INSERT/UPDATE ของตน | HTTP 201; status เปลี่ยนเป็น REVIEW |
| SB7 | ทดลองเขียนข้ามสิทธิ์ | HTTP 403 หรือแถวถูกกรอง ตามกรณี |
| SB8 | คืนข้อมูลและตรวจครบชุด | เหลือ 4 แถว; verify ผ่าน 15 กรณี |
| SB9 | Optional: Storage และ Function | verify แบบ extended ผ่าน 18 กรณี |
| SB10 | ส่งหลักฐานและปิดระบบ | รายงานไม่มี passwords/tokens |

## SB0 — เตรียม project และตรวจ endpoint

### SB0.1 หมายเลขนักเรียน

**Bash:** แทน `xx` ด้วยเลขของตนก่อนรัน

```bash
export STUDENT_NO=xx
case "$STUDENT_NO" in
  0[1-9]|1[0-9]|20) ;;
  *) printf 'Replace xx with your assigned number (01-20).\n' >&2; exit 1 ;;
esac
pwd
python3 --version
curl --version
```

### SB0.2 เลือกสภาพแวดล้อมของตน

ถ้าอาจารย์เปิด stack ให้แล้ว ให้ตรวจ project/endpoint และไป SB1 โดยไม่ init หรือเปลี่ยน `.env` ของชุดที่มีข้อมูลอยู่

ถ้าติดตั้งในสำเนา repository ของตนเป็นครั้งแรก:

```bash
bash labs/docker-labs.sh 10 init
```

ก่อน `up` ครั้งแรก แก้ **เฉพาะ `.env` ของสำเนาตน** ที่ `labs/supabase/.env`:

| ค่า | กำหนดให้ตรงกับชุดของตน |
| --- | --- |
| `COMPOSE_PROJECT_NAME` | `postgres-practices-m10_xx` โดยแทน xx แล้ว |
| `API_GW_HTTP_PORT` | API host port ที่อาจารย์จัดให้ หรือ port ว่างของเครื่องตน |
| `DB_SESSION_PORT` / `DB_TRANSACTION_PORT` | คนละ host port กับ stack อื่น |
| `SUPABASE_PUBLIC_URL` | `http://127.0.0.1:API_PORT` โดยแทน API_PORT แล้ว |
| `API_EXTERNAL_URL` | URL เดียวกันตามด้วย `/auth/v1` |
| `DEMO_BKK_EMAIL` | `adjuster.bkk_xx@claimsure.example.com` โดยแทน xx แล้ว |
| `DEMO_CM_EMAIL` | `adjuster.cm_xx@claimsure.example.com` โดยแทน xx แล้ว |

ตัว helper จะใช้ Email ใน `.env` ทั้งตอนสร้าง Auth Users และเพิ่ม Claims ส่วน Passwords/Keys ใช้ค่าที่ `init` สร้างไว้ เก็บ `.env` คู่กับข้อมูลของ project นี้ ดู [การแยก ports และ stacks](DOCKER-LABS.md#existing-stacks-and-multiple-students)

```bash
bash labs/docker-labs.sh 10 config
bash labs/docker-labs.sh 10 pull
bash labs/docker-labs.sh 10 up
bash labs/docker-labs.sh 10 status
```

ถ้า Docker อยู่บน server ให้เข้า SSH ด้วย `studentxx` ของตน และใช้ SSH tunnel ตาม [คู่มือติดตั้ง](supabase/README.md#เมื่อใช้-server-ที่อื่น) โดยเลือก ports ที่ตรงกับชุดของตน

### SB0.3 แยก credentials

| งาน | Credential |
| --- | --- |
| เปิด Studio | `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` |
| ต่อ SQL ผ่าน pooler | `postgres.claimsure` / `POSTGRES_PASSWORD` เมื่อ `POOLER_TENANT_ID=claimsure` |
| Login แอปเป็น BKK/CM | Email ใน `.env` / `DEMO_PASSWORD` |
| เรียก Data API เป็นผู้ใช้ | `ANON_KEY` ใน header apikey + user access token ใน Bearer |

เปิด Studio ตาม `SUPABASE_PUBLIC_URL` ของตน และตรวจว่าเป็น project ที่ได้รับมอบหมาย Studio SQL Editor เป็น Admin; การเห็นข้อมูลที่นี่ไม่พิสูจน์สิทธิ์ของแอป

**Checkpoint:** จด project name และ URL โดยไม่แนบ `.env`, passwords หรือ API keys

## SB1 — สร้าง Table และเปิด RLS

**Concept:** Table กำหนดข้อมูลและ constraints, grants กำหนด operations และ RLS กำหนดแถวที่ผู้เรียกเข้าถึงได้

เปิด **SQL Editor** ใน Studio ของ project ตน คัดลอกและรัน [01-claims-schema.sql](supabase/sql/01-claims-schema.sql) **ทั้งไฟล์** ไฟล์นี้สร้าง Table, index, grants และ policies และยังไม่สร้าง Auth Users หรือ Claims

โครงสร้างหลัก:

| Column | หน้าที่ |
| --- | --- |
| `id` | UUID primary key |
| `claim_no` | เลขเคลมที่ไม่ซ้ำ |
| `branch` | BKK หรือ CM |
| `adjuster_id` | UUID อ้าง `auth.users(id)` เป็น Owner |
| `amount` | จำนวนเงินตั้งแต่ 0 ขึ้นไป |
| `status` | NEW, REVIEW หรือ APPROVED |

อ่าน policy สำคัญจากไฟล์เต็ม:

```sql
CREATE POLICY claims_read_own ON public.claimsure_claims
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = adjuster_id);

CREATE POLICY claims_insert_own ON public.claimsure_claims
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = adjuster_id);

CREATE POLICY claims_update_own ON public.claimsure_claims
  FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = adjuster_id)
  WITH CHECK ((SELECT auth.uid()) = adjuster_id);
```

บล็อกข้างบนใช้ประกอบคำอธิบาย ไม่ต้องรันซ้ำหลังไฟล์เต็ม เพราะ policies ถูกสร้างแล้ว `USING` เลือกแถวเดิมที่เข้าถึงได้ ส่วน `WITH CHECK` ตรวจแถวที่จะเพิ่มหรือค่าหลัง UPDATE

**SQL Editor:**

```sql
SELECT current_database(), session_user, current_user;
SELECT relrowsecurity FROM pg_class
WHERE oid='public.claimsure_claims'::regclass;
SELECT policyname,cmd,roles,qual,with_check
FROM pg_policies
WHERE schemaname='public' AND tablename='claimsure_claims'
ORDER BY policyname;
```

**Expected:** RLS เป็น `true` และมี policies สามตัวตามด้านบน ยังไม่มี DELETE policy/grant สำหรับ `authenticated`

**คำถาม:** ทำไม `GRANT SELECT` อย่างเดียวจึงยังไม่ทำให้ผู้ใช้เห็นทุกแถวเมื่อเปิด RLS?

## SB2 — สร้าง Auth Users และข้อมูลตั้งต้น

**Bash:** รันครั้งเดียวเพื่อเตรียม baseline ของแล็บ

```bash
bash labs/docker-labs.sh 10 seed
```

`seed` รัน schema แบบทำซ้ำได้ สร้างหรือปรับ **Demo Users สองรายตาม Email ใน `.env`** ให้ยืนยัน Email แล้ว ตั้ง Password เป็น `DEMO_PASSWORD` และเพิ่ม/คืนค่าเคลมสี่แถว ใช้ซ้ำเมื่อตั้งใจคืน baseline เท่านั้น

เปิด **Authentication → Users** ตรวจสอง Demo Users และ UUID แล้วเปิด **Table Editor → public.claimsure_claims** ตรวจ Owner

**SQL Editor:**

```sql
SELECT c.claim_no,c.branch,u.email,c.adjuster_id,c.amount,c.status
FROM public.claimsure_claims c
JOIN auth.users u ON u.id=c.adjuster_id
ORDER BY c.claim_no;
```

| Claim | Branch | Amount | Status | Owner |
| --- | --- | ---: | --- | --- |
| CLM-BKK-001 | BKK | 12500.00 | NEW | BKK user ของ project ตน |
| CLM-BKK-002 | BKK | 28000.00 | REVIEW | BKK user ของ project ตน |
| CLM-CM-001 | CM | 8900.00 | NEW | CM user ของ project ตน |
| CLM-CM-002 | CM | 16500.00 | APPROVED | CM user ของ project ตน |

BKK/CM เป็น Auth Users คนละ UUID แต่ใช้ database role เดียวกันคือ `authenticated` Policy จำกัดตาม Owner ไม่ได้ให้สมาชิกสาขาเดียวกันอ่านข้อมูลของกันและกันโดยอัตโนมัติ

**Checkpoint:** มี 4 Claims และ Owner ตรง Auth UUID เก็บเฉพาะผล query ที่จำเป็น ไม่จับภาพหน้าที่มี secrets

## SB3 — เรียก Data API ก่อน Login

ใช้ **Bash Terminal เดียวกัน** ตั้งแต่ตรงนี้ถึง SB8 คำสั่งอ่าน config จาก `.env` ของสำเนาตนโดยไม่พิมพ์ Keys

```bash
SUPABASE_URL=$(python3 -c 'from labs.supabase.lab import config; print(config()["SUPABASE_PUBLIC_URL"].rstrip("/"))')
ANON_KEY=$(python3 -c 'from labs.supabase.lab import config; print(config()["ANON_KEY"])')
CLAIMS_URL="$SUPABASE_URL/rest/v1/claimsure_claims?select=claim_no,branch,amount,status&order=claim_no"

curl --silent --show-error "$CLAIMS_URL" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  --write-out '\nHTTP %{http_code}\n'
```

**Expected:** HTTP `200` และ `[]` เพราะชุดนี้ให้ `anon` SELECT ได้ แต่ไม่มี RLS policy ที่อนุญาตให้อ่านแถวใด `[]` จึงต่างจาก HTTP `401` ที่ token ไม่ผ่านการตรวจ

**คำถาม:** ทำไม Table Editor เห็น 4 แถว แต่ request นี้เห็น 0 แถว?

## SB4 — Login แล้วอ่านข้อมูลของตน

### SB4.1 เตรียม Login payload

**Bash:** ฟังก์ชันนี้ส่ง JSON ให้ curl โดยอ่าน Demo Email/Password จาก config ของ project ตน

```bash
auth_payload() {
  python3 - "$1" <<'PY'
import json, sys
from labs.supabase.lab import config
values = config()
print(json.dumps({"email": values["DEMO_" + sys.argv[1] + "_EMAIL"],
                  "password": values["DEMO_PASSWORD"]}))
PY
}
```

### SB4.2 Login เป็น BKK

```bash
BKK_LOGIN=$(auth_payload BKK | curl --silent --show-error --fail-with-body \
  "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H 'Content-Type: application/json' \
  --data-binary @-)
BKK_TOKEN=$(printf '%s' "$BKK_LOGIN" | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
BKK_ID=$(printf '%s' "$BKK_LOGIN" | python3 -c 'import json,sys; print(json.load(sys.stdin)["user"]["id"])')

curl --silent --show-error "$CLAIMS_URL" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $BKK_TOKEN" \
  --write-out '\nHTTP %{http_code}\n'
```

**Expected:** HTTP `200` และ **CLM-BKK-001 / CLM-BKK-002** เท่านั้น ถ้า Login error ให้ตรวจ credentials ก่อนทำต่อ ตัวแปร Login มี tokens จึงไม่ใช้ `echo` หรือแนบค่าเหล่านี้ในรายงาน

### SB4.3 Login เป็น CM

```bash
CM_LOGIN=$(auth_payload CM | curl --silent --show-error --fail-with-body \
  "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H 'Content-Type: application/json' \
  --data-binary @-)
CM_TOKEN=$(printf '%s' "$CM_LOGIN" | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
CM_ID=$(printf '%s' "$CM_LOGIN" | python3 -c 'import json,sys; print(json.load(sys.stdin)["user"]["id"])')

curl --silent --show-error "$CLAIMS_URL" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $CM_TOKEN" \
  --write-out '\nHTTP %{http_code}\n'
```

**Expected:** HTTP `200` และ **CLM-CM-001 / CLM-CM-002** เท่านั้น URL และ apikey เหมือน BKK แต่ Bearer Token ระบุผู้ใช้ต่างกัน

## SB5 — ทดลองอ่านข้าม Owner

**Bash:** BKK ขอเฉพาะสาขา CM

```bash
curl --silent --show-error "$CLAIMS_URL&branch=eq.CM" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $BKK_TOKEN" \
  --write-out '\nHTTP %{http_code}\n'
```

**Expected:** HTTP `200`, `[]` Query string เปลี่ยนเงื่อนไขค้นหาได้ แต่ไม่ขยายสิทธิ์จาก RLS

ทดลอง token ที่ไม่ถูกต้อง:

```bash
curl --silent --show-error "$CLAIMS_URL" \
  -H "apikey: $ANON_KEY" -H 'Authorization: Bearer invalid-token' \
  --write-out '\nHTTP %{http_code}\n'
```

**Expected:** HTTP `401` จดความต่างระหว่าง **token ไม่ผ่านการตรวจ** กับ **token ถูกต้องแต่ไม่มีแถวที่มองเห็นได้**

## SB6 — เพิ่มและแก้ไขเคลมของตน

### SB6.1 สร้างแถวฝึกที่ระบุได้แน่นอน

**Bash:** ใช้หมายเลขจาก SB0 และ UUID ใหม่เพื่อแยกแถวฝึกของรอบนี้

```bash
: "${STUDENT_NO:?Set STUDENT_NO to your assigned number first}"
LAB_CLAIM_ID=$(python3 -c 'import uuid; print(uuid.uuid4())')
LAB_CLAIM_NO="CLM-SB_${STUDENT_NO}-${LAB_CLAIM_ID}"
OWN_BODY=$(python3 - "$LAB_CLAIM_ID" "$LAB_CLAIM_NO" "$BKK_ID" <<'PY'
import json, sys
print(json.dumps({"id": sys.argv[1], "claim_no": sys.argv[2],
                  "branch": "BKK", "adjuster_id": sys.argv[3],
                  "amount": 2500, "status": "NEW"}))
PY
)

printf '%s' "$OWN_BODY" | curl --silent --show-error \
  "$SUPABASE_URL/rest/v1/claimsure_claims" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $BKK_TOKEN" \
  -H 'Content-Type: application/json' -H 'Prefer: return=representation' \
  --data-binary @- --write-out '\nHTTP %{http_code}\n'
```

**Expected:** HTTP `201` และแถวใหม่ที่ Owner เป็น `BKK_ID` คงตัวแปรของแถวนี้ไว้จนคืนค่าใน SB8 หากจะเริ่ม SB6 ใหม่ ให้คืนแถวรอบเดิมก่อน

### SB6.2 อ่านแถวเดียวกันด้วยผู้ใช้สองคน

```bash
curl --silent --show-error "$CLAIMS_URL&id=eq.$LAB_CLAIM_ID" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $BKK_TOKEN" \
  --write-out '\nHTTP %{http_code}\n'

curl --silent --show-error "$CLAIMS_URL&id=eq.$LAB_CLAIM_ID" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $CM_TOKEN" \
  --write-out '\nHTTP %{http_code}\n'
```

**Expected:** BKK ได้ 1 แถว, CM ได้ `[]` ทั้งคู่เป็น HTTP `200`

### SB6.3 เปลี่ยน status

```bash
curl --silent --show-error --request PATCH \
  "$SUPABASE_URL/rest/v1/claimsure_claims?id=eq.$LAB_CLAIM_ID" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $BKK_TOKEN" \
  -H 'Content-Type: application/json' -H 'Prefer: return=representation' \
  --data '{"status":"REVIEW"}' --write-out '\nHTTP %{http_code}\n'
```

**Expected:** HTTP `200` และแถวใหม่มี `status=REVIEW` เคลมตั้งต้นทั้งสี่รายการไม่เปลี่ยน

## SB7 — ทดลองเขียนข้ามสิทธิ์

### SB7.1 BKK เพิ่มเคลมให้ CM

```bash
REJECT_BODY=$(python3 - "$CM_ID" <<'PY'
import json, sys, uuid
print(json.dumps({"claim_no": "CLM-REJECT-" + uuid.uuid4().hex,
                  "branch": "CM", "adjuster_id": sys.argv[1], "amount": 100}))
PY
)
printf '%s' "$REJECT_BODY" | curl --silent --show-error \
  "$SUPABASE_URL/rest/v1/claimsure_claims" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $BKK_TOKEN" \
  -H 'Content-Type: application/json' --data-binary @- \
  --write-out '\nHTTP %{http_code}\n'
```

**Expected:** HTTP `403` จาก INSERT `WITH CHECK` และไม่เพิ่มแถว

### SB7.2 BKK โอน Owner ของแถวตนให้ CM

```bash
TRANSFER_BODY=$(python3 - "$CM_ID" <<'PY'
import json, sys
print(json.dumps({"adjuster_id": sys.argv[1]}))
PY
)
printf '%s' "$TRANSFER_BODY" | curl --silent --show-error --request PATCH \
  "$SUPABASE_URL/rest/v1/claimsure_claims?id=eq.$LAB_CLAIM_ID" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $BKK_TOKEN" \
  -H 'Content-Type: application/json' --data-binary @- \
  --write-out '\nHTTP %{http_code}\n'
```

**Expected:** HTTP `403` จาก UPDATE `WITH CHECK` Owner ยังเป็น BKK

### SB7.3 CM พยายามแก้แถวของ BKK

```bash
curl --silent --show-error --request PATCH \
  "$SUPABASE_URL/rest/v1/claimsure_claims?id=eq.$LAB_CLAIM_ID" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $CM_TOKEN" \
  -H 'Content-Type: application/json' -H 'Prefer: return=representation' \
  --data '{"status":"APPROVED"}' --write-out '\nHTTP %{http_code}\n'
```

**Expected สำหรับชุดนี้:** HTTP `200`, `[]` เพราะ `USING` กรองไม่ให้ CM เลือกแถวนั้น การเขียนข้ามสิทธิ์จึงไม่ได้ตอบ `403` ทุกกรณี ใช้ BKK อ่านแถวตาม SB6.2 อีกครั้ง ต้องยังเป็น REVIEW

**คำถาม:** SB7.2 และ SB7.3 ถูกจำกัดคนละจุดอย่างไร?

## SB8 — คืนแถวฝึก แล้วตรวจครบชุด

### SB8.1 ระบุแถวที่จะคืนค่า

**Bash:** พิมพ์เฉพาะ IDs ของแถวฝึก ไม่พิมพ์ tokens

```bash
printf 'Lab claim UUID: %s\nBKK owner UUID: %s\nClaim number: %s\n' \
  "$LAB_CLAIM_ID" "$BKK_ID" "$LAB_CLAIM_NO"
```

**SQL Editor ของ project ตน:** แทน `LAB_CLAIM_ID_FROM_SB6` และ `BKK_ID_FROM_SB4` ด้วย UUID จากผลข้างบน และแทน `xx` ด้วยหมายเลขตน

```sql
DO $cleanup$
DECLARE
  removed_rows integer;
BEGIN
  DELETE FROM public.claimsure_claims
  WHERE id='LAB_CLAIM_ID_FROM_SB6'::uuid
    AND adjuster_id='BKK_ID_FROM_SB4'::uuid
    AND starts_with(claim_no,'CLM-SB_xx-');
  GET DIAGNOSTICS removed_rows = ROW_COUNT;
  IF removed_rows <> 1 THEN
    RAISE EXCEPTION 'Expected one lab row; removed %. Check UUIDs and student number.',
      removed_rows;
  END IF;
END;
$cleanup$;

SELECT claim_no,branch,amount,status
FROM public.claimsure_claims ORDER BY claim_no;
```

รันทั้งบล็อกในครั้งเดียว บล็อก DO ตรวจว่าลบ **เฉพาะ 1 แถวของรอบนี้** หากจำนวนไม่ตรงจะยกเลิกการลบและแจ้งให้ตรวจ UUIDs/หมายเลขใหม่ `authenticated` ในชุดนี้ไม่ได้รับ DELETE; การคืนแถวจึงทำผ่าน SQL Editor Admin ของ project ฝึก

ต้องกลับมาเป็นเคลมตั้งต้นสี่รายการตาม SB2 หากแถวฝึกเคย INSERT ไม่สำเร็จ จะไม่มีแถวให้ลบ ให้ตรวจ baseline แล้วบันทึกเหตุผล ไม่ใช้ TRUNCATE เพื่อให้จำนวนตรง

### SB8.2 ตรวจ Auth / API / RLS

หลังคืนแถวฝึกแล้ว **Bash**:

```bash
bash labs/docker-labs.sh 10 verify
```

**Expected:** `PASS: 15 Auth / Data API / RLS checks.` ตัวทดสอบสร้างแถวชั่วคราวอีกแถวเพื่อทดสอบ แล้วลบเฉพาะแถวของตัวเอง ผลอยู่ที่ [verification.json](../docs/tutorials/supabase-self-hosted/verification.json) โดยไม่เก็บ passwords หรือ tokens

ถ้าต้องการให้แสดง HTTP/JSON ของแต่ละกรณี ใช้:

```bash
bash labs/docker-labs.sh 10 api-demo
```

ชุดทดสอบเปรียบเทียบ `service_role` ด้วย ซึ่งข้าม RLS ได้ ผลจาก service key จึงไม่ใช่หลักฐานว่าผู้ใช้ทั่วไปมีสิทธิ์เห็นทุกแถว

## SB9 — Optional: Private Storage และ Edge Function

ทำหลัง SB8 และเมื่ออาจารย์เลือกหัวข้อนี้ `seed --extended` จะเตรียม Demo baseline ซ้ำพร้อม Private Bucket/ไฟล์ตัวอย่าง

```bash
bash labs/docker-labs.sh 10 seed --extended
bash labs/docker-labs.sh 10 verify --extended
```

**Expected:** `PASS: 18 extended checks.` เพิ่มการตรวจจากบทหลักสามกรณี:

1. Admin อ่าน `claim-documents/example-claim.txt` ได้
2. Anonymous ดาวน์โหลดไฟล์ private ไม่ได้
3. Function `claimsure-health` รับ JWT ที่ชุดฝึกยอมรับแล้วตอบ `edge_runtime=ready`

Policies ของ Table `claimsure_claims` ไม่ได้ให้สิทธิ์ Storage โดยอัตโนมัติ และ Function ตัวอย่างใช้ตรวจ runtime/JWT ไม่ได้พิสูจน์สิทธิ์รายผู้ใช้ของทุก Function อ่านวิธีใช้ Studio/Storage เพิ่มใน [คู่มือประกอบ](../docs/tutorials/supabase-self-hosted/README.md)

## SB10 — หลักฐานส่งงานและจบแล็บ

| หัวข้อ | สิ่งที่ส่ง |
| --- | --- |
| Environment | หมายเลข, project name และ URL ของตน |
| Schema | RLS=true และชื่อ policies สามตัว |
| Auth / SELECT | anon 0 แถว, BKK 2 แถว, CM 2 แถว ก่อน INSERT |
| INSERT / UPDATE | แถวฝึกของตน HTTP 201 และ REVIEW หลัง PATCH |
| Cross-owner | ผล SB5 และ SB7 พร้อม HTTP status/จำนวนแถว |
| คืนค่า | เคลมตั้งต้น 4 แถว และผล verify 15 กรณี |
| คำอธิบาย | แยก apikey / user JWT / database role / Owner และ USING / WITH CHECK |

เก็บเฉพาะผล JSON/SQL ที่จำเป็น ไม่แนบ `.env`, Login Responses, passwords, Keys, access tokens หรือ refresh tokens

**Bash:** เมื่อเก็บหลักฐานและคืนข้อมูลแล้ว

```bash
unset SUPABASE_URL ANON_KEY CLAIMS_URL BKK_LOGIN BKK_TOKEN BKK_ID
unset CM_LOGIN CM_TOKEN CM_ID LAB_CLAIM_ID LAB_CLAIM_NO OWN_BODY
unset REJECT_BODY TRANSFER_BODY
unset -f auth_payload
bash labs/docker-labs.sh 10 stop
```

`stop` เก็บ `.env` และ volumes ไว้ ครั้งถัดไปใช้ `up` ด้วย project เดิม ไม่ต้อง `seed` ทุกครั้ง

## ตรวจปัญหา

| อาการ | ตรวจอะไร |
| --- | --- |
| Port ชน | Host ports ของ project ตนก่อน `up`; API URL กับ auth URL ต้องตรงกัน |
| Studio ถามรหัสไม่ผ่าน | Dashboard Basic Auth; แยกจาก Demo User password |
| Login ไม่สำเร็จ | `seed` สำเร็จหรือไม่, Email ใน `.env`, `DEMO_PASSWORD` และ Confirmed User |
| API 401 | apikey, User JWT, expiry และ project URL ของ token ต้องเป็นชุดเดียวกัน |
| API 200 แต่ `[]` | Caller/Owner และ policies; เทียบกับ expected ของขั้นนั้น |
| API 403 เมื่อเขียน | grants, `adjuster_id` และ WITH CHECK |
| API 404/PGRST205 | schema/table มีจริงหรือไม่; SB1 ต้องรันทั้งไฟล์ซึ่งแจ้ง reload schema |
| verify ไม่ผ่านจำนวนแถว | คืนแถว SB6 ของตนก่อนตรวจ แล้วดูว่ามีแถวจากรอบก่อนค้างหรือไม่ |

เอกสารอ้างอิง: [Supabase Data API](https://supabase.com/docs/guides/api), [Password Auth](https://supabase.com/docs/guides/auth/passwords), [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security) และ [source ของตัวทดสอบในโปรเจกต์](supabase/lab.py)
