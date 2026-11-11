# Lab 10 — Supabase Data API และ Authentication

ใช้เป็น **Docker Lab 10** ของหลักสูตร ดู [คู่มือรวม Labs 8 / 10](../DOCKER-LABS.md)
สำหรับตัวรัน `bash labs/docker-labs.sh 10 COMMAND` และการตั้ง ports ให้แยกจาก stack เดิม

**แกนของ Lab:** สร้าง Table แล้วเรียก REST API ได้, Login ด้วย Supabase Auth และทดลองเปลี่ยนผู้เรียกเพื่อดูข้อมูลตาม Role/RLS ลดการเขียน CRUD routes และระบบ Login/token เอง โดยยังต้องออกแบบ Schema และ Policies ให้ถูกต้อง

สำหรับทำตามทีละขั้นและส่งหลักฐาน ใช้ **[ใบงาน Markdown Supabase Labs — SB0–SB10](../module-10-supabase.md)** ครอบคลุม prerequisites, คำสั่ง, expected results, การทดสอบข้าม Owner และการคืนข้อมูล

เริ่มที่ **[บทฝึก Data API + Auth ภาษาไทย](../../docs/tutorials/supabase-self-hosted/index.html)** หรือ [Markdown พร้อม curl](../../docs/tutorials/supabase-self-hosted/API-LAB.md) ผู้เรียนจะเห็น request, HTTP status และ JSON ที่ต่างกันตามผู้เรียก

Storage, Realtime, Edge Functions, Pooler และการดูแลระบบเป็นเนื้อหาเสริม ดู [คู่มือ Studio/Storage](../../docs/tutorials/supabase-self-hosted/README.md) และ [คู่มืออ้างอิงผู้ดูแล](../../docs/tutorials/supabase-self-hosted/user-guide.html) ส่วน Compose ยังคงใช้ชุด Upstream ที่ pin ไว้ใน [upstream.json](upstream.json)

## เริ่มใช้งาน

รันใน Terminal จาก **root ของ repository** ต้องมี Docker Engine/Desktop, Compose v2 และ Python 3.10+ คู่มือทางการระบุขั้นต่ำสำหรับชุดเต็มที่ RAM 4 GB, CPU 2 cores, SSD 40 GB; ควรจัดงบเพิ่มให้ Containers อื่นบนเครื่องด้วย ดู [System requirements](https://supabase.com/docs/guides/self-hosting/docker#system-requirements)

```bash
python3 labs/supabase/lab.py init
python3 labs/supabase/lab.py config
python3 labs/supabase/lab.py pull
python3 labs/supabase/lab.py up
```

`init` สร้าง `labs/supabase/.env` สิทธิ์ `0600` และไม่เขียนทับไฟล์ที่มีอยู่แล้ว Passwords, Encryption Keys และ JWT Keys ถูกสร้างใหม่แต่ละชุด ไม่ต้องนำ Secrets จาก `.env` ของ ClaimSure เดิมมาใช้ `ANON_KEY` และ `SERVICE_ROLE_KEY` เป็น HS256 JWT ที่ลงชื่อด้วย `JWT_SECRET` ชุดเดียวกัน และหมดอายุใน 365 วัน

เปิด **http://127.0.0.1:18000** เบราว์เซอร์จะถาม Basic Auth ใช้ `DASHBOARD_USERNAME` และ `DASHBOARD_PASSWORD` จาก `.env` หน้านี้คือ Studio ของ **หนึ่ง Project** ไม่ใช่ Supabase Cloud ที่สร้างหลาย Projects ได้ Password นี้แยกจาก `POSTGRES_PASSWORD` และ Password ของ Auth Users

| ใช้ทำอะไร | Endpoint เริ่มต้น | User / Credential |
| --- | --- | --- |
| Studio + API Gateway | `http://127.0.0.1:18000` | Studio ใช้ Dashboard Basic Auth; Data API ใช้ API Key + User JWT |
| PostgreSQL ผ่าน Session Pooler | `127.0.0.1:15480` | `postgres.claimsure` + `POSTGRES_PASSWORD` |
| PostgreSQL ผ่าน Transaction Pooler | `127.0.0.1:16543` | `postgres.claimsure` + `POSTGRES_PASSWORD` |
| SQL ภายใน Container โดยตรง | `python3 labs/supabase/lab.py psql` | `postgres` / Database `postgres` |

`claimsure` ใน Pooler Username มาจาก `POOLER_TENANT_ID` ไม่ใช่ชื่อ Schema หรือ Auth User ส่วน `POSTGRES_PORT=5432` เป็น Port ภายใน Network และไม่ควรเปลี่ยนเพื่อแก้ Host Port ชนกัน ให้แก้ `DB_SESSION_PORT` / `DB_TRANSACTION_PORT` แทน

ถ้า Port 18000 ถูกใช้แล้ว แก้ `API_GW_HTTP_PORT`, `SUPABASE_PUBLIC_URL`, `API_EXTERNAL_URL` ให้ตรงกัน **ก่อนเริ่มครั้งแรก** ค่าที่เปลี่ยนใน `.env` มีผลเมื่อ `up` สร้าง Containers ใหม่; `docker compose restart` อย่างเดียวไม่โหลด Environment ใหม่

## เตรียมข้อมูลและทดสอบ

```bash
python3 labs/supabase/lab.py seed
python3 labs/supabase/lab.py api-demo
python3 labs/supabase/lab.py verify
```

`seed` รัน SQL ตามลำดับ สร้าง/ปรับ Password ของ **เฉพาะ Demo Users สองรายใน `.env`** แล้วเพิ่ม Claims จำลอง 4 รายการพร้อม Grants/RLS ไม่มีอีเมลหรือ SMS ถูกส่งออก Public Signup และ Phone Signup ปิดไว้ใน Lab นี้

`api-demo` แสดง HTTP requests/status และ JSON ที่อ่านได้จริง พร้อมซ่อน Passwords/Tokens ส่วน `verify` ตรวจ 15 กรณี Auth / Data API / RLS โดยไม่แสดงรายละเอียดทุก request และลบแถวชั่วคราวของการตรวจ ผลลัพธ์อยู่ที่ `docs/tutorials/supabase-self-hosted/verification.json` โดยไม่มี Passwords หรือ Tokens

| ผู้เรียก | Role | ผล GET จาก endpoint เดียวกัน |
| --- | --- | --- |
| ไม่ Login | `anon` | `[]` |
| BKK Login | `authenticated` | เคลมของ BKK สองแถว |
| CM Login | `authenticated` | เคลมของ CM สองแถว |
| Backend/ผู้สอน | `service_role` | สี่แถว; Key นี้ห้ามใส่ Frontend |

BKK/CM เป็นผู้ใช้ต่างคนใน Role เดียวกัน RLS ใช้ `auth.uid() = adjuster_id` กำหนดแถวที่เห็น ไม่ใช่การสร้าง Role แยกตามสาขา ตัวทดสอบยังตรวจ Password ผิด, Token ไม่ถูกต้อง, การอ่านข้าม Owner, INSERT/UPDATE ของตน และการเขียนข้าม Owner

### หัวข้อเสริม — Storage และ Edge Functions

บทหลักใช้ `seed` / `api-demo` / `verify` ได้โดยไม่ต้องเตรียม Bucket หากเลือกทำ Storage/Functions หรือจับภาพหน้าจอส่วน Storage ให้เพิ่ม:

```bash
python3 labs/supabase/lab.py seed --extended
python3 labs/supabase/lab.py verify --extended
```

แบบ `--extended` เตรียม Private Bucket/ไฟล์ และตรวจเพิ่มสามกรณี รวมเป็น 18 กรณี

## จับภาพ Tutorial ด้วย Playwright

ต้องมี Node.js 22+:

```bash
npm ci --prefix labs/supabase
python3 labs/supabase/lab.py seed --extended
npx --prefix labs/supabase playwright install chromium
npm run capture --prefix labs/supabase
```

Capture Script อ่าน Dashboard Credentials จาก `.env`, เปิด Studio จริง, ตรวจหน้าที่ต้องการ แล้วบันทึก PNG ลง `docs/tutorials/supabase-self-hosted/images/` และ Capture Manifest ไม่สร้างภาพจำลอง ไม่บันทึก HAR, Cookies, Local Storage, API Keys หรือ Auth Tokens หน้าที่แสดง API Keys ไม่อยู่ในรายการ Capture

ถ้ามี Google Chrome อยู่แล้ว สามารถใช้ `PLAYWRIGHT_CHANNEL=chrome npm run capture --prefix labs/supabase` หรือกำหนด `PLAYWRIGHT_EXECUTABLE_PATH` เป็น Absolute Path ของ Browser ในเครื่องได้

## สร้างคู่มือใช้งานใหม่จาก Source

แก้ `docs/tutorials/supabase-self-hosted/USER-GUIDE.md` แล้วสร้าง HTML ได้ด้วย:

```bash
npm ci --prefix labs/supabase
npm run guide --prefix labs/supabase
```

การสร้าง PDF ต้องมี Playwright Browser ตามด้านบน และ Python Packages `reportlab` / `pypdf` สำหรับจัด Header/Footer โดย Chromium จัดข้อความไทย:

```bash
python3 -m pip install reportlab pypdf
npm run guide:pdf --prefix labs/supabase
```

PDF อยู่ที่ `output/pdf/supabase-self-hosted-user-guide-th.pdf` ส่วน `npm run capture:guide --prefix labs/supabase` ใช้จับภาพฟอร์ม Create new user ที่ว่างสำหรับคู่มือ โดยไม่สร้าง User ใหม่ ใช้ข้อมูล Demo ที่มีอยู่แล้ว

## หยุด เปิดใหม่ และเก็บข้อมูล

```bash
python3 labs/supabase/lab.py status
python3 labs/supabase/lab.py stop
# เปิดใหม่ โดยใช้ข้อมูลเดิม
python3 labs/supabase/lab.py up
# ถอด Containers / Network; Named Volumes ยังอยู่
python3 labs/supabase/lab.py down
```

ข้อมูลอยู่ใน Named Volumes ของ Compose Project: `db-data`, `db-config`, `storage-data`, `deno-cache` ส่วน Functions และ Snippets อยู่ใต้ `labs/supabase/volumes/` **อย่าลบ `.env` แล้ว init ใหม่กับ Volume เดิม** เพราะ Passwords/Encryption Keys จะไม่ตรงกับข้อมูลที่มีอยู่

หากแก้ `.env` เพื่อใช้ Project Name ใหม่ ต้องเก็บไฟล์เดิมไว้ส่วนตัว และใช้ Directory แยกสำหรับอีก Instance เพราะ Functions/Snippets เป็น Bind Mount การเปลี่ยน PostgreSQL Password หลัง Initialize ต้องเปลี่ยน Role Passwords ใน Database ตามแนวทาง Upstream ด้วย ไม่ใช่เปลี่ยน Environment อย่างเดียว

## เมื่อใช้ Server ที่อื่น

ค่าตั้งต้นผูก Host Ports กับ `127.0.0.1` ถ้า Docker อยู่บน Server ให้เปิด SSH Tunnel จากเครื่องที่ใช้ Browser:

```bash
ssh -L 18000:127.0.0.1:18000 your-user@your-server
```

จากนั้นเปิด URL เดิม สำหรับ Public Deployment ให้ตั้ง DNS, Reverse Proxy + HTTPS, URL/Redirect ให้ตรง, SMTP จริง, Backup ของ PostgreSQL + Storage + Secrets และตรวจสิทธิ์แต่ละ Service ตาม [คู่มือ Self-hosting ทางการ](https://supabase.com/docs/guides/self-hosting/docker) ชุดนี้ยังไม่มี Public TLS, Production HA, SMTP Delivery หรือ Backup Scheduler

## ตรวจปัญหา

รันคำสั่งต่อไปนี้จาก `labs/supabase` (ไม่ใช่ใน `psql`):

```bash
docker compose --env-file .env -f compose.yaml ps
docker compose --env-file .env -f compose.yaml logs --tail=80 db
docker compose --env-file .env -f compose.yaml logs --tail=80 auth rest meta
docker compose --env-file .env -f compose.yaml logs --tail=80 api-gw studio
```

- **Port is already allocated:** เปลี่ยน Host Ports ตามตารางด้านบน แล้ว `up` ใหม่
- **401 ที่ Studio:** ตรวจ Dashboard Basic Auth; เปิด Incognito เพื่อเลิกใช้ Credentials ที่ Browser จำไว้
- **401 จาก Data API:** ตรวจ `apikey`, Bearer Token, JWT Expiry และการลงชื่อให้ตรงกัน
- **API ได้ `[]` แต่ SQL Editor ได้ 4 แถว:** เป็นผลที่ตั้งใจเมื่อ Request ไม่มีสิทธิ์ตาม RLS; SQL Editor ใช้ Admin
- **Auth Sign-in ไม่ผ่าน:** ต้องรัน `seed` ก่อน หรือสร้าง Confirmed Users ใน Tutorial; ใช้ `DEMO_PASSWORD` ไม่ใช่ Dashboard Password
- **Service ไม่ Healthy:** ตรวจ RAM/Disk และ Logs เฉพาะ Service; อย่าใช้ `down -v` เพื่อแก้แบบเดาเพราะจะลบข้อมูล
- **Playwright ไม่พบ Browser:** ติดตั้ง Chromium ตามคำสั่งด้านบน หรือเลือก Channel/Executable ที่มีอยู่
- **`/functions/v1/hello` ตอบ `INVALID_API_KEY`:** ตัวอย่าง `hello` ของ Upstream รุ่นนี้ใช้ `@supabase/server` ที่รับ Opaque API Keys รุ่นใหม่ ชุด Lab ใช้ HS256 Keys จึงให้ตัวอย่าง `claimsure-health` แยกไว้และเปิด JWT Verification ตามปกติ หากจะใช้ตัวอย่าง `hello` เดิม ให้ย้ายทั้งชุดไปใช้ [New Auth/API Keys](https://supabase.com/docs/guides/self-hosting/self-hosted-auth-keys) ตามคู่มือ Upstream

ไฟล์ Upstream คง License เดิมใน [LICENSE.supabase](LICENSE.supabase) การแก้ Gateway/Service Versions ควรยกทั้งชุดที่ผ่านการทดสอบเข้าด้วยกัน ไม่อัปเกรด Images ทีละตัวโดยไม่ตรวจ Compatibility

## สำเนาใน postgres-practices

คำสั่งที่ระบุ root ของ repository ในคู่มือนี้หมายถึง `postgres-practices` สำเนามี `.env.example` และ configuration/SQL/functions แต่ไม่มี `.env` จริง, database/storage runtime หรือ SQL snippets ส่วนตัว

หากมี stack ต้นฉบับทำงานอยู่บนเครื่องเดียวกัน ให้ใช้ `COMPOSE_PROJECT_NAME` และ host ports คนละชุดใน `.env` ของสำเนาก่อน `up` เพื่อให้เป็น environment แยกกัน ดูขั้นเปลี่ยน ports/URLs ด้านบน การคัดลอกไฟล์ครั้งนี้ไม่ได้เปิดหรือแก้บริการใด
