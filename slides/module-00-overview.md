---
theme: default
title: "Course Overview — เตรียม Terminal และ SSH สำหรับแล็บ"
layout: default
class: continuous-deck
colorSchema: light
fonts:
  sans: Noto Sans Thai
  mono: JetBrains Mono
info: ClaimSure continuous case | Student lab prerequisites
transition: slide-left
mdc: true
lang: th
download: false
---

# ภาพรวมคอร์สและการเข้าแล็บ

## PostgreSQL 18 · ClaimSure · ฐานข้อมูลแยกต่อคน

<div class="cs-flow">
  <div><strong>Terminal</strong><small>เครื่องของนักเรียน</small></div>
  <span>→ SSH →</span>
  <div><strong>Linux / Bash</strong><small>บัญชี studentxx</small></div>
  <span>→ psql →</span>
  <div><strong>PostgreSQL</strong><small>ฐาน claimsure_xx</small></div>
</div>

- บท 1–2: สร้าง customer → policy → claim และ SQL ที่ใช้ต่อทั้งคอร์ส
- บท 3–7, 9–10: วัดผล ปรับสิทธิ์ ตั้งค่า กู้คืน และต่อยอดข้อมูลเดิม
- บท 8, Databasus และ Supabase: ใช้ environment ตามคู่มือเสริม

<p class="cs-takeaway">ก่อนบท 1: SSH ได้ · เข้า DB ของตนได้ · แยก Bash กับ SQL ได้</p>

<footer class="cs-footer"><span>ClaimSure · ภาพรวมและเตรียมแล็บ</span><span>1 / 10</span></footer>

<!--
Speaker notes:
ให้นักเรียนเปิดคู่มือ labs/README.md ควบคู่กับสไลด์ คอร์สหลักใช้ข้อมูลต่อเนื่องตามลำดับ 1 → 2 → 3 → 4 → 5 → 6 → 7 → 9 → 10 บทเสริมใช้ environment ของตนเอง ขั้นตอนต่อไปเป็นการเตรียม connection ไม่ใช่การติดตั้ง infrastructure ของห้องเรียน
Source: ../labs/README.md · เลือกบทเรียน / เส้นเรื่องและขอบเขตข้อมูล
-->

---
layout: default
class: continuous-deck
---

# สิ่งที่ต้องมีก่อนเริ่ม

- Windows: PowerShell หรือ Windows Terminal ที่เรียก `ssh` ได้
- macOS / Linux: Terminal ที่เรียก `ssh` ได้
- เปิดคู่มือแล็บและเตรียม Terminal 2 หน้าต่างสำหรับ Session A/B
- อาจารย์เตรียม Linux, PostgreSQL 18 และฐาน `claimsure_xx` ให้แต่ละคน

| ข้อมูลที่รับจากอาจารย์ | ตัวอย่างนักเรียน xx |
| --- | --- |
| Server address และ SSH port | `SERVER_IP` และ `SSH_PORT` — เปลี่ยนเป็นค่าจริง |
| SSH username / password หรือ key | `studentxx` / credential ของตน |
| Database login / password | `student_xx` / รหัสฐานข้อมูลของตน |
| Database และที่ตั้งคู่มือบน server | `claimsure_xx` / path ที่อาจารย์แจ้ง |

<footer class="cs-footer"><span>ClaimSure · Prerequisites</span><span>2 / 10</span></footer>

<!--
Speaker notes:
เช็ก ssh -V บนเครื่องนักเรียนก่อนเริ่ม หากคำสั่งไม่พบให้จัดเตรียม SSH client กับอาจารย์ รหัส SSH กับรหัส PostgreSQL เป็นคนละ credential แม้ห้องเรียนบางชุดอาจกำหนดค่าเดียวกัน xx คือ placeholder ให้แทนด้วยเลขสองหลักของตนก่อนรัน ไม่ต้องติดตั้ง PostgreSQL server หรือ Node.js บนเครื่องนักเรียนเพื่อทำ SQL ผ่าน SSH
Source: ../labs/README.md · เตรียมการเชื่อมต่อ; ../labs/references/scripts/shells/README.md · Configure your student account
-->

---
layout: default
class: continuous-deck
---

# 1 · SSH จากเครื่องของนักเรียน

รันใน Terminal / PowerShell บนเครื่องตนเอง เปลี่ยน server, port และเลขบัญชี:

```bash
ssh -p SSH_PORT studentxx@SERVER_IP
```

ครั้งแรกตรวจ host fingerprint กับอาจารย์ก่อนตอบ `yes` แล้วใส่รหัส SSH

เมื่อเข้า server แล้ว รันคำสั่งต่อไปนี้:

```bash
whoami
hostname
bash
```

<p class="cs-takeaway">whoami ต้องเป็นบัญชีของตน เช่น studentxx · จากนี้ใช้ Bash บน server</p>

<footer class="cs-footer"><span>ClaimSure · SSH login</span><span>3 / 10</span></footer>

<!--
Speaker notes:
SSH_PORT เป็น placeholder ที่ต้องแทนด้วยตัวเลขจากอาจารย์ เช่น 22 เมื่อห้องเรียนใช้ default port ไม่ใช่พอร์ต PostgreSQL 5432 หากใช้ SSH key ให้เพิ่ม -i ตามที่อาจารย์กำหนด ตอนพิมพ์ password จะไม่เห็นอักขระบนหน้าจอ เป็นพฤติกรรมปกติ หลังเข้าได้ hostname จะเป็นเครื่อง Linux ที่เรียน และ whoami ต้องตรงบัญชีที่ได้รับ
Source: ../labs/README.md · เตรียมการเชื่อมต่อ; ../labs/references/scripts/shells/README.md · Configure your student account
-->

---
layout: default
class: continuous-deck
---

# 2 · ตั้ง connection ของนักเรียนแต่ละคน

รันใน Bash หลัง SSH · แทน `xx` ด้วยเลขสองหลักที่อาจารย์มอบหมาย:

```bash
export STUDENT_NO=xx
export PGHOST=127.0.0.1 PGPORT=5432
export PGUSER="student_$STUDENT_NO"
export PGDATABASE="claimsure_$STUDENT_NO"
export PGCONNECT_TIMEOUT=5
export PGAPPNAME="case-course-$STUDENT_NO"
umask 077
mkdir -p "$HOME/case-labs/evidence"
psql --version
```

<p class="cs-takeaway">แทน xx ด้วยหมายเลขที่ได้รับ · student_xx / claimsure_xx ต้องเป็นของตน</p>

<footer class="cs-footer"><span>ClaimSure · คู่มือ README / เตรียมการเชื่อมต่อ</span><span>4 / 10</span></footer>

<!--
Speaker notes:
127.0.0.1 ในขั้นนี้หมายถึงเครื่อง Linux หลัง SSH ไม่ใช่ laptop นักเรียน หาก DB อยู่คนละเครื่องให้ใช้ PGHOST ที่อาจารย์ให้ พอร์ต 5432 เป็น connection ตรง PostgreSQL แล็บที่อาศัย session/transaction ค้างไม่ใช้ PgBouncer 6432 ต้องทำขั้นนี้และอ่านรหัสผ่านใหม่ในแต่ละ Terminal ตัวแปรที่ export ไม่ข้ามไปหน้าต่างอื่น
Source: ../labs/README.md · เตรียมการเชื่อมต่อ
-->

---
layout: default
class: continuous-deck
---

# 3 · เข้า psql และตรวจตัวตน

ใน Bash — ใส่ **รหัสฐานข้อมูล** เมื่อถูกถาม:

```bash
read -r -s -p "Database password: " PGPASSWORD
printf '\n'
export PGPASSWORD
psql -X -v ON_ERROR_STOP=1
```

ใน psql — ตรวจว่าชื่อฐานและผู้ใช้เป็นของตน:

```sql
\conninfo
SELECT current_database(), session_user, current_user,
       current_setting('server_version') AS version;
```

<p class="cs-takeaway">ตัวอย่าง: claimsure_xx · student_xx · PostgreSQL 18</p>

<footer class="cs-footer"><span>ClaimSure · ตรวจ connection ก่อนทำ SQL</span><span>5 / 10</span></footer>

<!--
Speaker notes:
read -s ไม่แสดงรหัสผ่านและไม่เขียนรหัสจริงเป็น literal ใน command history ค่า PGPASSWORD อยู่ใน environment ของ Bash นี้ ให้ตรวจทั้งฐาน login และ current_user หากชื่อไม่ตรงของตนให้หยุดและแก้ connection ก่อนทำ DDL/DML บนเครื่องห้องเรียนควรเป็น PostgreSQL 18 ตามคู่มือ psql --version ในหน้าก่อนเป็นรุ่น client ส่วน server_version ในหน้านี้เป็นรุ่น server
Source: ../labs/README.md · เตรียมการเชื่อมต่อ
-->

---
layout: default
class: continuous-deck
---

# 4 · ทำแล็บด้วยตนเองทีละขั้น

เปิดคู่มือ `labs/module-01-basic-sql.md` ควบคู่กับ Terminal

| อยู่ที่ไหน | คำสั่งที่ใช้ |
| --- | --- |
| Bash หลัง SSH · prompt มักลงท้าย `$` | บล็อก `bash` เช่น `psql`, `pg_dump`, `mkdir` |
| psql · prompt เช่น `claimsure_xx=>` | บล็อก `sql` และ meta-command เช่น `\conninfo` |

ตั้งค่าการแสดงผลใน psql ก่อนเริ่มหัวข้อ **1A** ในคู่มือ:

```sql
\pset pager off
\timing on
\set VERBOSITY verbose
SET TIME ZONE 'Asia/Bangkok';
```

<p class="cs-takeaway">รันทีละบล็อก → อ่าน expected result → ทำขั้นถัดไป · SQL จบด้วย ;</p>

<footer class="cs-footer"><span>ClaimSure · คู่มือ README / รูปแบบการทำงาน</span><span>6 / 10</span></footer>

<!--
Speaker notes:
ให้เปิดคู่มือจากเครื่องนักเรียนเพื่ออ่านลำดับ แต่รันคำสั่งใน SSH Terminal บน server การเปิด psql ตามหน้า 5 และตั้งค่าหน้านี้เป็นการพร้อมเริ่ม 1A ไม่ได้สร้างตารางล่วงหน้า บล็อก Bash ที่มี heredoc ตั้งแต่ <<'SQL' จนถึง SQL ให้วางทั้งบล็อกใน Bash ตามคู่มือ ไม่วางทั้งบทพร้อมกัน โดยเฉพาะบทที่มี lock หรือ expected errors
Source: ../labs/README.md · รูปแบบการทำงาน; ../labs/module-01-basic-sql.md · 1A
-->

---
layout: default
class: continuous-deck
---

# ทางเลือก · ใช้ shell runner บน server

ออกจาก psql ด้วย `\q` แล้วเข้าโฟลเดอร์ `labs` ที่อาจารย์เตรียม:

```bash
cd /path/to/postgres-practices/labs
export PG_BIN=/usr/lib/postgresql/18/bin
bash ./run-labs.sh list 1
bash ./run-labs.sh show 1 1A
bash ./run-labs.sh check 1
```

เมื่อจะเลือกทำแล็บด้วย runner เริ่มบท 1 พร้อมหยุดอ่านผลแต่ละขั้น:

```bash
bash ./run-labs.sh run 1 --pause
```

<p class="cs-takeaway">ใช้ connection จากหน้า 4–5 · runner ต้องมี Python 3.9+ และ Bash</p>

<footer class="cs-footer"><span>ClaimSure · คู่มือ RUNNER / เริ่มต้น</span><span>7 / 10</span></footer>

<!--
Speaker notes:
/path/to/postgres-practices/labs เป็น placeholder ไม่ใช่ path ติดตั้งที่รับรอง ให้ใช้ตำแหน่งที่อาจารย์แจ้งและต้องมี run-labs.sh ในโฟลเดอร์นั้น หาก PostgreSQL binaries อยู่ที่อื่นให้เปลี่ยน PG_BIN ตามจริง ตัวแปร STUDENT_NO และ PGPASSWORD ต้องยังอยู่ใน Bash นี้ list/show/check ไม่เชื่อมฐานข้อมูล ส่วน run แก้ข้อมูลตามบทจริง นักเรียนเลือกทำ manual หรือ runner สำหรับการเริ่มแล็บรอบนี้ ไม่ทำ manual ไปแล้วแล้วสั่ง runner ซ้ำโดยไม่ตรวจสถานะ ข้อมูลที่ commit แล้วไม่ย้อนกลับอัตโนมัติ Runner นี้คือ labs/run-labs.sh ของชุด continuous ไม่ใช่ scripts ใต้ references
Source: ../labs/RUNNER.md · เริ่มต้น / เลือก module และ submodule
-->

---
layout: default
class: continuous-deck
---

# Session A/B · เปิดสอง Terminal ของคนเดียวกัน

| Terminal A | Terminal B |
| --- | --- |
| SSH ด้วย `studentxx` | SSH ด้วย `studentxx` อีกครั้ง |
| ตั้ง environment และอ่านรหัสตามหน้า 4–5 | ตั้ง environment และอ่านรหัสตามหน้า 4–5 |
| เข้า `claimsure_xx` เป็น `student_xx` | เข้า `claimsure_xx` เป็น `student_xx` |
| ทำขั้น A ตามคู่มือ ค้าง transaction เมื่อระบุ | ทำขั้น B เมื่อคู่มือให้เริ่ม แล้วสังเกต lock |

ตรวจใน psql ทั้งสองหน้าต่าง:

```sql
SELECT current_database(), current_user, pg_backend_pid();
```

<p class="cs-takeaway">ฐานและผู้ใช้ต้องตรงกัน · PID ต้องต่างกัน · ทำตามลำดับ A/B ในคู่มือ</p>

<footer class="cs-footer"><span>ClaimSure · หลาย connection / บท 5, 6 และ 9</span><span>8 / 10</span></footer>

<!--
Speaker notes:
แทน xx ด้วยหมายเลขของตนในทั้ง Session A และ B แต่ละหน้าต่างเป็น SSH และ PostgreSQL connection คนละอัน ตัวแปรจาก A ไม่ส่งต่อ B บท 5 มีลำดับ transaction และ snapshot ที่ต้องค้างไว้ บท 6/9 มี waiter/blocker ห้ามวางทุกคำสั่งรวดเดียว หากเลือก runner มันจะควบคุมหลาย SQL connections ตาม recipe ให้เอง ไม่ต้องทำ manual สองหน้าต่างควบคู่
Source: ../labs/README.md · รูปแบบการทำงาน; ../labs/RUNNER.md · เลือก module และ submodule
-->

---
layout: default
class: continuous-deck
---

# คำสั่งช่วยระหว่างเรียนและเมื่อจบแล็บ

| เหตุการณ์ | ทำอย่างไร |
| --- | --- |
| ต้องการกลับจาก psql ไป Bash | `\q` |
| SQL ยังไม่ถูกส่ง · prompt ลงท้าย `->` | ตรวจว่าใส่ `;` ครบ หรือใช้ `\r` ล้าง input |
| Transaction error · prompt มี `!` | อ่าน error แล้ว `ROLLBACK;` ก่อนเริ่มใหม่ |
| กำลังรอ query / ใช้ `\watch` | Ctrl+C เพื่อยกเลิก แล้วตรวจ transaction |
| SSH หรือ DB เข้าไม่ได้ | ตรวจ host, port, username และ credential กับอาจารย์ |

จบตามขั้น reset ของบทก่อน แล้วออกจาก psql และ SSH:

```bash
unset PGPASSWORD
exit
```

<footer class="cs-footer"><span>ClaimSure · จบงานในทุก Terminal</span><span>9 / 10</span></footer>

<!--
Speaker notes:
คำสั่ง unset และ exit ต้องอยู่ใน Bash หลังใช้ \q แล้ว การใช้ bash ตามหน้า 3 อาจเพิ่ม shell หนึ่งชั้น ถ้า exit แล้วยังอยู่บน server ให้ exit อีกครั้งจนกลับเครื่องตนเอง ปิดทุก Terminal เมื่อจบงาน การออกจาก connection rollback เฉพาะ transaction ที่ยังไม่ commit ไม่ใช่การคืนข้อมูลที่ commit ไปแล้ว ให้ทำ reset และบันทึกหลักฐานตามบท อย่าสั่งลบ schema เพื่อให้จำนวนแถวตรงตัวอย่าง
Source: ../labs/README.md · รูปแบบการทำงาน / บันทึกหลักฐานและจบงาน
-->

---
layout: default
class: continuous-deck
---

# พร้อมเริ่มบท 1

- SSH เข้า Linux ด้วย `studentxx` ของตนได้
- `psql` เข้า `claimsure_xx` ด้วย `student_xx` ได้ และตรวจ server เป็น PostgreSQL 18
- เปิดคู่มือบท 1 และรู้ว่าบล็อกไหนรันใน Bash หรือ psql
- สร้างโฟลเดอร์ `~/case-labs/evidence` สำหรับเก็บผลแล้ว
- เลือกทำด้วยตนเอง หรือใช้ runner ที่หยุดอ่านผลทีละขั้น

## ก่อนบทที่ใช้เครื่องมือเพิ่มเติม

บท 6–7 ต้องมี PostgreSQL 18 **server binaries** เช่น `initdb` และ `pg_ctl`
ส่วน roles บท 4/10 และบริการเสริมให้อาจารย์เตรียมตามคู่มือ

<p class="cs-takeaway">เริ่ม 1A → อ่านผล → ทำต่อ 1B · ใช้ข้อมูลเดิมต่อถึงบทถัดไป</p>

<footer class="cs-footer"><span>ClaimSure · Next: Module 1 — Basic SQL</span><span>10 / 10</span></footer>

<!--
Speaker notes:
ให้ทุกคนยืนยัน current_database และ current_user ของตนก่อนเริ่มเขียนข้อมูล บท 1 สร้างข้อมูลตั้งต้น ส่วนบทถัดไปใช้ข้อมูลเดิมต่อกัน นักเรียนไม่ต้องมี SUPERUSER หรือ CREATEROLE บน shared server บท 6/7 ใช้ private servers ใต้ home และไม่หยุด shared PostgreSQL ดูเงื่อนไข pg_dump/physical recovery และ optional services ใน README ก่อนถึงบทนั้น
Source: ../labs/README.md · เส้นเรื่องและขอบเขตข้อมูล; ../labs/RUNNER.md · Instructor และ optional services
-->
