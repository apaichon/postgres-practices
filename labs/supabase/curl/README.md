# Supabase — curl แยกไฟล์ทีละ API

แต่ละไฟล์มีคำสั่ง `curl` ของ API นั้นโดยตรง อ่าน Method, URL, Headers, JSON body และผลที่คาดไว้ได้ในไฟล์เดียว เลข 01–18 ตรงกับ [data-api.http](../data-api.http)

## วิธีรัน

เตรียม stack และ Demo baseline สี่แถวตาม [คู่มือ Supabase Lab](../README.md#เริ่มใช้งาน) ก่อน ต้องมี **Bash 3.2+, curl, jq และ uuidgen หรือ openssl** ส่วนไฟล์ทดสอบเหล่านี้ไม่เรียก Python

รันจาก root ของ repository:

```bash
# อ่านเคลมของ BKK — Login ให้อัตโนมัติ
bash labs/supabase/curl/04-read-bkk.sh

# แก้สถานะ — Login และสร้างแถวทดลองให้ก่อน PATCH
bash labs/supabase/curl/12-update-own-claim.sh

# ทดสอบการเพิ่มเคลมให้คนอื่น ซึ่งต้องถูก RLS ปฏิเสธ
bash labs/supabase/curl/14-reject-other-owner-insert.sh

# รันทั้ง 18 ไฟล์ตามลำดับ
bash labs/supabase/run_api.sh all
```

อ่าน URL, API Keys และ Demo credentials จาก `labs/supabase/.env` หมายเลขนักเรียนใช้ `--student xx` โดยแทน `xx` เป็นเลขจริงของตน หรืออ่านจาก `STUDENT_NO` แล้วจึง `@studentNo` ในไฟล์ HTTP หากยังเป็น `xx` สคริปต์จะหยุดให้ตั้งค่าก่อนเรียก API

```bash
# แทน xx ด้วยหมายเลขที่ได้รับ
bash labs/supabase/curl/04-read-bkk.sh --student xx
# ดู options โดยไม่เรียก API
bash labs/supabase/curl/04-read-bkk.sh --help
# ดูชื่อ request ทั้งหมด
bash labs/supabase/run_api.sh --list
```

ทุกไฟล์รับ `--env PATH`, `--report PATH` และ `--timeout N` ได้เหมือน [run_api.sh](../run_api.sh) เมื่อเรียกไฟล์เดี่ยวจะแสดง JSON ของ Data API และผล `PASS`; ขั้นเตรียมแสดง `SETUP PASS` ส่วน Auth response จะซ่อน token ไว้ รายงานเริ่มต้นอยู่ที่ `labs/supabase/artifacts/api-results-shell.json` และเขียนใหม่ทุกครั้ง

## รายการ API

ทุกเส้นทาง Data API ด้านล่างใช้ `/rest/v1/claimsure_claims` ส่วน Login ใช้ `/auth/v1/token?grant_type=password`

| ไฟล์ | Method / ผู้เรียก | สิ่งที่ทดลอง | ผลที่คาด |
| --- | --- | --- | --- |
| [01-anonymous.sh](01-anonymous.sh) | GET / anon | อ่านก่อน Login | 200, `[]` |
| [02-login-bkk.sh](02-login-bkk.sh) | POST / anon | Login BKK | 200, เก็บ token/UUID |
| [03-login-cm.sh](03-login-cm.sh) | POST / anon | Login CM | 200, เก็บ token/UUID |
| [04-read-bkk.sh](04-read-bkk.sh) | GET / BKK | อ่านเคลมของตน | 200, BKK สองแถว |
| [05-read-cm.sh](05-read-cm.sh) | GET / CM | อ่านเคลมของตน | 200, CM สองแถว |
| [06-read-other-owner.sh](06-read-other-owner.sh) | GET / BKK | กรองหาเคลม CM | 200, `[]` |
| [07-invalid-token.sh](07-invalid-token.sh) | GET / token ผิด | ทดสอบ token ไม่ถูกต้อง | 401 |
| [08-wrong-password.sh](08-wrong-password.sh) | POST / anon | Login ด้วย password ผิด | 400 หรือ 401 |
| [09-create-claim.sh](09-create-claim.sh) | POST / BKK | เพิ่มเคลมของตน | 201, `NEW` |
| [10-read-created-claim.sh](10-read-created-claim.sh) | GET / BKK | อ่านแถวทดลอง | 200, หนึ่งแถว |
| [11-cm-read-bkk-claim.sh](11-cm-read-bkk-claim.sh) | GET / CM | อ่านแถวทดลองของ BKK | 200, `[]` |
| [12-update-own-claim.sh](12-update-own-claim.sh) | PATCH / BKK | แก้สถานะของตน | 200, `REVIEW` |
| [13-reject-owner-transfer.sh](13-reject-owner-transfer.sh) | PATCH / BKK | เปลี่ยน Owner เป็น CM | 403, `42501` |
| [14-reject-other-owner-insert.sh](14-reject-other-owner-insert.sh) | POST / BKK | เพิ่มแถวให้ CM | 403, `42501` |
| [15-cm-update-bkk-claim.sh](15-cm-update-bkk-claim.sh) | PATCH / CM | แก้เคลมของ BKK | 200, `[]` |
| [16-confirm-claim-unchanged.sh](16-confirm-claim-unchanged.sh) | GET / BKK | ยืนยันผลหลังทดสอบเขียนข้าม Owner | 200, ยังเป็น `REVIEW` และ Owner เดิม |
| [17-cleanup-claim.sh](17-cleanup-claim.sh) | DELETE / service_role | ลบแถวทดลองตาม ID/Owner/claim_no | 200, หนึ่งแถวที่ลบ |
| [18-read-service-role.sh](18-read-service-role.sh) | GET / service_role | อ่าน Demo baseline ทั้งหมด | 200, สี่แถว |

## อ่านโค้ดจากตรงไหน

เริ่มที่ [04-read-bkk.sh](04-read-bkk.sh) เพื่อดู GET หรือ [12-update-own-claim.sh](12-update-own-claim.sh) เพื่อดู PATCH โค้ดต้นไฟล์โหลดตัวช่วยและเตรียม dependencies จากนั้นเป็น JSON body (ถ้ามี), คำสั่ง `curl` และการตรวจ HTTP status/JSON ตามลำดับ

ตัวแปรที่ใช้ร่วมกันมาจาก [_common.sh](_common.sh):

| ตัวแปร/ตัวช่วย | หน้าที่ |
| --- | --- |
| `SUPABASE_PUBLIC_URL` | URL ของ API Gateway จาก `.env` |
| `ANON_HEADERS`, `BKK_HEADERS`, `CM_HEADERS`, `ADMIN_HEADERS` | ไฟล์ headers ของผู้เรียกแต่ละแบบ มี `apikey` และ `Authorization: Bearer …` |
| `BKK_ID`, `CM_ID` | UUID ของผู้ใช้จาก Login response |
| `CLAIM_ID`, `CLAIM_NO` | แถวชั่วคราวของรอบทดลองนี้ ชื่อมีหมายเลขนักเรียนและ UUID |
| `CURL_FLAGS` | ตั้ง timeout และการแสดง error ของ curl |
| `TMP`, `RESPONSE` | โฟลเดอร์ชั่วคราวสำหรับ headers/body และไฟล์ JSON response |
| `expect_status`, `expect_json` | ตรวจผลที่คาดไว้ ถ้าไม่ตรงจะหยุดและคืน exit code ที่ไม่ใช่ 0 |

`--header "@$BKK_HEADERS"` ให้ curl อ่าน headers จากไฟล์ส่วนตัว ส่วน `--data-binary "@$TMP/body.json"` ส่ง JSON ที่เตรียมไว้ จึงไม่ต้องคัดลอก credentials/token ลงโค้ด ไฟล์ชั่วคราวถูกลบเมื่อจบ

ตัวช่วยกลางยังจัดการอ่าน config, Login ที่จำเป็น, สร้างแถวทดลอง, รายงาน และ cleanup ส่วน [run_api.sh](../run_api.sh) ใช้ไฟล์ย่อยชุดนี้โดยตรง จึงแก้คำสั่ง API ที่ไฟล์เดียวได้

แต่ละการเรียกเป็นรอบทดลองอิสระ ไม่ต้องรัน 02/09 ค้างไว้ก่อนเรียก 12 เมื่อจบหรือเกิดข้อผิดพลาดจะพยายามลบเฉพาะแถวชั่วคราวของรอบนั้นและเทียบข้อมูลเดิมทั้งสี่แถว หาก cleanup ไม่สำเร็จจะรายงาน `FAIL` รวมถึงกรณีเรียก 09 เดี่ยว แถวที่เพิ่มจะถูกลบก่อนโปรแกรมจบ จึงไม่ส่งต่อ UUID ข้ามการเรียกแต่ละครั้ง
