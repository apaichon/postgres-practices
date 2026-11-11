# Workshop CLI Cheatsheet — SSH และ psql

[กลับสารบัญ Labs](../../README.md) · [Lab 4 ภาษาไทย](../../module-04-security-user-management-th.md)

แทน `xx` ด้วยเลขนักเรียนสองหลักที่ได้รับ (`01`–`20`), `SERVER_IP` และ `SSH_PORT` ด้วยค่าจากอาจารย์ก่อนรันทุกตัวอย่าง ชื่อ SSH คือ `studentxx` ส่วนชื่อ PostgreSQL คือ `student_xx` และฐานข้อมูลคือ `claimsure_xx` รหัสผ่าน SSH กับ PostgreSQL เป็นคนละ credential

## 1. SSH เข้าเครื่อง workshop จาก laptop

รันบน **Terminal ของ laptop**:

```bash
ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -p SSH_PORT studentxx@SERVER_IP
```

| Option | ใช้ทำอะไร |
| --- | --- |
| `-p SSH_PORT` | ระบุพอร์ต SSH ที่อาจารย์แจ้ง |
| `-o ServerAliveInterval=30` | เมื่อไม่ได้รับข้อมูล 30 วินาที ให้ส่งข้อความขอคำตอบผ่าน SSH |
| `-o ServerAliveCountMax=3` | ยุติ connection เมื่อไม่ได้รับคำตอบครบเกณฑ์; ค่านี้ประมาณ 90 วินาที |
| `-i ~/.ssh/workshop_key` | เพิ่มเมื่อต้องใช้ private key ตามที่อาจารย์กำหนด |

Keepalive ช่วยกรณีเครือข่ายตัด connection ที่ว่าง และตรวจจับ connection ที่ไม่ตอบสนอง แต่ไม่ได้เชื่อมต่อใหม่หรือเก็บ process ให้เอง ดู [OpenSSH: ServerAliveInterval / ServerAliveCountMax](https://man.openbsd.org/ssh_config#ServerAliveInterval)

### ตั้งชื่อย่อไว้ใช้ซ้ำ

เพิ่มบล็อกนี้ใน `~/.ssh/config` **บน laptop** โดยแทน placeholders ก่อนบันทึก ถ้ามีไฟล์อยู่แล้วให้เพิ่มบล็อกใหม่โดยเก็บ config เดิมไว้:

```sshconfig
Host pg-workshop
    HostName SERVER_IP
    User studentxx
    Port SSH_PORT
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

จากนั้นใช้:

```bash
chmod 600 ~/.ssh/config
ssh pg-workshop
```

| คำสั่ง / ปุ่ม | ความหมาย |
| --- | --- |
| `ssh -V` | ดูรุ่น SSH client |
| `ssh -G pg-workshop` | ดู config ที่จะใช้ โดยยังไม่เชื่อมต่อ |
| `ssh -v pg-workshop` | แสดงขั้นตอนเชื่อมต่อเมื่อจำเป็นต้องตรวจปัญหา |
| `whoami` / `hostname` | หลัง SSH ตรวจบัญชี Linux และเครื่องที่กำลังใช้งาน |
| `exit` | ออกจาก shell ปัจจุบัน; เมื่ออยู่ SSH จะกลับ laptop |

## 2. เข้า psql หลัง SSH

รันใน **shell บนเครื่อง workshop** แต่ละ Terminal ต้องตั้งค่าชุดนี้เอง:

```bash
export STUDENT_NO=xx
export PGHOST=127.0.0.1 PGPORT=5432
export PGDATABASE="claimsure_$STUDENT_NO"
export PGUSER="student_$STUDENT_NO"
export PGCONNECT_TIMEOUT=5
export PGAPPNAME="workshop-$STUDENT_NO"
unset PGPASSWORD

psql --version
psql -X -W
```

`127.0.0.1` ในส่วนนี้คือเครื่อง workshop หลัง SSH ถ้า PostgreSQL อยู่เครื่องอื่นให้ใช้ `PGHOST` ที่อาจารย์แจ้ง ใช้พอร์ตตรง **5432** สำหรับแล็บ session/transaction ตามคู่มือ; ห้องเรียนที่มี PgBouncer 6432 ให้ตรวจโหมดกับอาจารย์ก่อน

`-X` ไม่อ่าน psqlrc, `-W` ถามรหัสผ่านผ่าน prompt และ `PGCONNECT_TIMEOUT=5` จำกัดเวลารอเชื่อมต่อ ตาม [psql options](https://www.postgresql.org/docs/18/app-psql.html) และ [connection environment variables](https://www.postgresql.org/docs/18/libpq-envars.html)

แบบระบุทุกค่าในคำสั่งเดียว ใช้ได้หลังแทน `xx` แล้ว:

```bash
psql -X -W -h 127.0.0.1 -p 5432 -U student_xx -d claimsure_xx
```

## 3. Login ด้วยบัญชีอื่น — Lab 4 ภาษาไทย

Instructor ต้องทำ **0/4A** และตั้งรหัสผ่านของ B/C/D ก่อนเปิด connections เหล่านี้ อ้างอิง [คู่มือ Lab 4](../../module-04-security-user-management-th.md) ทุกหน้าต่าง SSH ใช้บัญชี Linux ของตัวเองได้ ส่วน `-U` เลือกบัญชี PostgreSQL

หลังตั้ง environment ตามข้อ 2 ให้เปิดคนละ Terminal แล้วเลือกคำสั่งตามหน้าที่:

| Connection | PostgreSQL Login | หน้าที่ |
| --- | --- | --- |
| A | `postgres` | Instructor เตรียม Lab เท่านั้น |
| S | `student_xx` | นักเรียนจัดการ Lab ผ่าน Owner role |
| B | `claim_app_xx` | App อ่าน/เขียนและทดสอบ tenant RLS |
| C | `internal_auditor_xx` | Auditor อ่านคอลัมน์ที่อนุญาตและ audit |
| D | `manager_th_xx` | Manager เปลี่ยนสถานะเคลม |

```bash
# A — Instructor ใช้ credential ที่อาจารย์จัดให้
PGAPPNAME="m4-$STUDENT_NO-A" psql -X -W -U postgres

# S — Student
PGAPPNAME="m4-$STUDENT_NO-S" psql -X -W -U "student_$STUDENT_NO"

# B — App
PGAPPNAME="m4-$STUDENT_NO-B" psql -X -W -U "claim_app_$STUDENT_NO"

# C — Auditor
PGAPPNAME="m4-$STUDENT_NO-C" psql -X -W -U "internal_auditor_$STUDENT_NO"

# D — Manager
PGAPPNAME="m4-$STUDENT_NO-D" psql -X -W -U "manager_th_$STUDENT_NO"
```

**เลือกเพียงหนึ่งคำสั่งต่อ Terminal** แล้วคง connection เดิมไว้ตามขั้นของ Lab ค่า `PGHOST`, `PGPORT`, `PGDATABASE` มาจากข้อ 2 และ `-U` ทับค่า `PGUSER` สำหรับคำสั่งนั้น

Roles ที่ขึ้นต้น `role_` เช่น `role_claimsure_read_xx` เป็น **NOLOGIN** จึงใช้ `psql -U` เข้าโดยตรงไม่ได้ สำหรับบัญชีเพิ่มเติม เช่น `adjuster_bkk_xx`, `claim_monitor_xx`, `claim_dba_xx` ต้องมีรหัสผ่าน, CONNECT และ HBA ที่เหมาะสมก่อน; การสร้าง role อย่างเดียวยังไม่ทำให้เชื่อมต่อได้

### เปลี่ยน Login ภายใน psql

ใช้เมื่อต้องการปิด connection เดิมแล้วเปิดใหม่ แทน `xx` ก่อนรัน **ไม่ใช้สลับ A/S/B/C/D ระหว่างขั้นที่ต้องเก็บ transaction เดิม**:

```sql
\connect claimsure_xx claim_app_xx 127.0.0.1 5432
\conninfo
SELECT current_database(), session_user, current_user;
```

เมื่อเปิด psql ด้วย `-W` จะถามรหัสผ่านสำหรับ connection ใหม่ด้วย ถ้า reconnect ล้มเหลวใน interactive mode connection เดิมอาจยังอยู่ ให้ตรวจตัวตนทุกครั้ง ตาม [psql: connect](https://www.postgresql.org/docs/18/app-psql.html#APP-PSQL-META-COMMAND-CONNECT)

## 4. ตรวจตัวตนและตั้งหน้าจอเมื่อเข้า psql

วางใน **psql**:

```sql
\conninfo
\pset pager off
\timing on
\set VERBOSITY verbose

SELECT current_database() AS database,
       session_user AS login,
       current_user AS active_role,
       current_setting('application_name') AS application,
       pg_backend_pid() AS pid;
```

`session_user` ใช้ดู Login ที่เชื่อมเข้ามา ส่วน `current_user` ใช้ดู role ที่กำลังทำงาน หลัง Login ใหม่โดยยังไม่ SET ROLE ทั้งสองควรตรงกับบัญชีที่เลือก ก่อนแก้ข้อมูลให้ตรวจชื่อฐานและผู้ใช้ของตน

### ใช้ Owner role เฉพาะ transaction ของ Connection S

ตัวอย่างนี้ใช้หลัง Instructor มอบสิทธิ์ตาม 4A.4 และแทน `xx` แล้ว:

```sql
BEGIN;
SET LOCAL ROLE role_claimsure_owner_xx;
SELECT session_user, current_user;
COMMIT;
SELECT session_user, current_user;
```

ภายใน transaction `session_user` ยังเป็น `student_xx` แต่ `current_user` เป็น Owner หลัง `COMMIT` จะกลับเป็น `student_xx` ถ้าใช้ `SET ROLE` แบบ session ให้ใช้ `RESET ROLE;` เพื่อกลับ ดู [PostgreSQL: SET ROLE](https://www.postgresql.org/docs/18/sql-set-role.html)

## 5. คำสั่ง psql ที่หยิบใช้บ่อย

Meta-command ที่ขึ้นต้น `\` ไม่ใส่ `;` ส่วน SQL ให้จบด้วย `;`

| คำสั่งใน psql | ใช้ทำอะไร |
| --- | --- |
| `\?` / `\h SELECT` | ดูความช่วยเหลือ psql / SQL |
| `\conninfo` | ดู connection ปัจจุบัน |
| `\l` / `\dn` | รายชื่อ databases / schemas |
| `\dt claimsure.*` | ดูตารางของบทเรียนต่อเนื่อง |
| `\dt lab_m4_xx.*` | ดูตารางของ Lab 4 ภาษาไทย |
| `\d+ lab_m4_xx.claim_secure` | ดูโครงสร้าง, policies และรายละเอียดตาราง |
| `\du` | ดู roles และ attributes |
| `\dp lab_m4_xx.*` | ดู object privileges |
| `\ddp` | ดู default privileges |
| `\x auto` | แสดงผลแนวตั้งเมื่อตารางกว้าง |
| `\timing on` | แสดงเวลา query |
| `\p` / `\r` | ดู / ล้าง SQL ที่ยังค้างใน query buffer |
| `\errverbose` | ดูรายละเอียด error ล่าสุด |
| `\q` | ออกจาก psql กลับ shell |

### ดูข้อมูลตาม tenant ใน Connection B

รันหลังทำ **4D.1** เสร็จใน [Lab 4](../../module-04-security-user-management-th.md):

```sql
BEGIN;
SET LOCAL app.tenant_id = '101';
SELECT claim_id, tenant_id, claim_no, status
FROM lab_m4_xx.claim_secure
ORDER BY claim_id;
COMMIT;
```

App ควรเห็นเฉพาะ tenant 101; ตอนเพิ่ง seed มี 2 แถว จำนวนอาจเปลี่ยนถ้ามีการเพิ่มข้อมูล Context นี้อยู่เฉพาะ transaction และเป็นกลไกสาธิต RLS ใน SQL Lab; บัญชี SQL ตั้งค่าเองได้

## 6. เมื่อ query รอหรือเกิด error

| อาการ / งาน | วิธีทำ |
| --- | --- |
| Query รอนาน | กด `Ctrl+C` เพื่อขอยกเลิก query ปัจจุบัน |
| Prompt ค้าง `claimsure_xx->` | SQL ยังไม่จบ; ใช้ `\p` ดู buffer หรือ `\r` ล้าง แล้วป้อนใหม่ |
| Prompt `claimsure_xx=!>` / SQLSTATE `25P02` | Transaction failed; ในขั้น expected error ของ Lab ใช้ `ROLLBACK;` ใน connection เดิม แล้วทำ recovery ตามคู่มือ |
| SQLSTATE `42501` | ตรวจ Login, grants, RLS และผลที่ Lab คาดไว้; บางขั้นตั้งใจให้ถูกปฏิเสธ |
| `password authentication failed` | ตรวจชื่อ `-U` และรหัสของ Login นั้น |
| `Peer authentication failed` | ตรวจว่าระบุ `-h 127.0.0.1` เพื่อใช้ TCP ตามคู่มือ |
| `connection refused` | ตรวจ host/port และสถานะบริการกับอาจารย์ |
| อ่านแล้วไม่เห็นแถวใน Lab 4 | ตรวจ role และ tenant context ใน transaction ตามขั้น |

ดูเวลาทุก 5 วินาทีใน psql แล้วกด `Ctrl+C` เพื่อหยุด:

```sql
SELECT clock_timestamp(), session_user, current_user;
\watch 5
```

## 7. รันไฟล์และบันทึกผล

รันจาก **shell** โดยใช้ environment ในข้อ 2 เฉพาะไฟล์ที่คู่มืออนุญาตให้รันครบ:

```bash
psql -X -W -v ON_ERROR_STOP=1 -f /path/to/approved-lab.sql
```

**Lab 4 ภาษาไทยให้เลือก START–END ทีละ block ใน interactive session** เพราะมี expected errors และ recovery ใน connection เดิม ไม่ใช้คำสั่งข้างบนรันทั้งไฟล์ Lab 4

บันทึก query results ระหว่าง interactive session เริ่มจาก shell:

```bash
mkdir -p "$HOME/case-labs/evidence"
psql -X -W
```

จากนั้นใน psql:

```sql
\o ~/case-labs/evidence/workshop-observation.txt
SELECT current_database(), session_user, current_user, clock_timestamp();
\o
```

`\o` ที่ไม่มีชื่อไฟล์คืนผลมาหน้าจอ ไฟล์นี้เป็น query output ไม่ใช่ transcript ครบทุกข้อความ และการเปิดชื่อเดิมจะเขียนทับ ให้ตั้งชื่อใหม่เมื่อต้องการเก็บผลหลายรอบ

## 8. คำสั่ง shell และจบ session

| คำสั่ง | ใช้ทำอะไร |
| --- | --- |
| `pwd` / `ls -lah` | ดู path ปัจจุบัน / รายการไฟล์ |
| `cd /path/to/postgres-practices/labs` | ไปโฟลเดอร์ Lab ที่อาจารย์แจ้ง |
| `less module-04-security-user-management-th.md` | อ่านคู่มือใน Terminal; กด `q` ออก |
| `tail -n 50 /path/to/log.txt` | ดู 50 บรรทัดท้ายของ log |

จบใน psql ด้วย `\q` แล้วกลับ shell:

```bash
unset PGPASSWORD
exit
```

ถ้าตั้ง SSH alias ตามข้อ 1 แล้ว ดาวน์โหลดหลักฐานจาก **Terminal บน laptop** ได้ด้วย:

```bash
scp pg-workshop:case-labs/evidence/workshop-observation.txt .
```

ถ้าใช้ `scp` แบบระบุพอร์ตเอง ให้ใช้ `-P SSH_PORT` ตัวใหญ่ ส่วน `ssh` ใช้ `-p SSH_PORT` ตัวเล็ก
