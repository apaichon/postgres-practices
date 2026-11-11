# ห้องแล็บ PostgreSQL — เวอร์ชันต่อเนื่องจากบท 1–2

คู่มือนี้ใช้คำอธิบายภาษาไทยและคำสั่งภาษาอังกฤษ สำหรับ Modules 1–7 และ 9–10 บน PostgreSQL 18 คู่มือแต่ละบทยังคงให้รัน SQL และเครื่องมือ PostgreSQL ด้วยตนเอง แล้วอ่านผลก่อนทำต่อ หากต้องการรันซ้ำหรือสาธิตแบบอัตโนมัติ มี [shell runner แยกต่างหาก](RUNNER.md) ให้เลือกทั้งบทหรือขั้นตอนย่อย โดยอ่านคำสั่งจากคู่มือชุดนี้

[สไลด์เวอร์ชันต่อเนื่อง](../slides/README.md) สำหรับบท 1–7, 9 และ 10

## เลือกบทเรียน

| บท | คู่มือ | สิ่งที่ได้ทดลอง |
| --- | --- | --- |
| 1 | [Basic SQL](module-01-basic-sql.md) | Schema, constraints, CRUD, transaction, JOIN, aggregate |
| 2 | [Advanced SQL](module-02-advanced-sql.md) | View, function, procedure, CTE, window, pivot; ต่อจากบท 1 |
| 3 | [Performance](module-03-performance-tuning.md) | EXPLAIN, index, maintenance, partition, materialized view |
| 4 | [Security](module-04-security.md) | Permission gates, role, sequence, RLS, audit, default privileges |
| 4 (Clone) | [Security — Clone schema และเก็บผลจริง](module-04-security-clone.md) | สำเนาตาราง/ข้อมูล, Login แยก, ทดสอบสิทธิ์และ RLS โดยไม่คืนผลด้วย ROLLBACK |
| 4 (Pure SQL ไทย) | [Security และ User Management ตามสไลด์ต้นทาง](module-04-security-user-management-th.md) | 0, 4A–4H, Owner delegation ให้ student_xx, Connections A/S/B/C/D, Row/Column/Audit และ recovery |
| 5 | [Architecture](module-05-architecture.md) | Backend, MVCC สอง session, tuple, WAL, file mapping |
| 6 | [Configuration](module-06-configuration.md) | อ่านค่าเดิม, memory, timeout, WAL, autovacuum, logging, decision |
| 7 | [Backup and recovery](module-07-backup-recovery.md) | Logical restore, cold copy, physical backup, PITR |
| 9 | [Monitoring](module-09-monitoring.md) | Workload, blocking, deadlock, statistics, Grafana evidence |
| 10 | [Modern features](module-10-modern-features.md) | JSONB, full-text, partition, optional vector, RLS access paths |
| Supabase | [Supabase Labs — SB0–SB10](module-10-supabase.md) | Project แยก, Table/RLS, Auth, curl GET/INSERT/UPDATE, ทดสอบข้าม Owner และคืนค่า |

Module 8 ไม่อยู่ในขอบเขตครั้งนี้ ทุกบทใช้เคลม กรมธรรม์ และลูกค้าจากบท 1–2 ต่อกัน

ดู [ผลการตรวจบน PostgreSQL 18 และขอบเขต optional services](VALIDATION.md) ก่อนเตรียมห้องเรียน

## เตรียมการเชื่อมต่อ

`xx` คือ **placeholder สำหรับหมายเลขนักเรียนสองหลักที่อาจารย์มอบหมาย (`01`–`20`)** ให้แทนทุกตำแหน่งก่อนรันคำสั่ง ใช้เลขเดียวกันตลอดทั้งบทและทุก Terminal:

| สิ่งที่แยกต่อคน | รูปแบบในคู่มือ |
| --- | --- |
| SSH account | `studentxx` (ชื่อบัญชี SSH ไม่มีขีดล่าง) |
| PostgreSQL login / database | `student_xx` / `claimsure_xx` |
| Roles บท Security / API | `cs_actor_xx`, `cs_reader_xx`, `cs_api_xx` |
| Backup / recovery / staging | `claimsure_backup_xx`, `claimsure_databasus_xx`, `m7_stage_xx` |
| Monitoring session tag | `module09_xx_holder`, `module09_xx_waiter`, `module09_xx_observer` |

ชื่อที่อยู่ใน SQL variables หรือ Bash variables จะประกอบจากหมายเลขหรือ login ของตน ตรวจ `\conninfo`, `current_database()` และ `session_user` ก่อนแก้ข้อมูลทุกครั้ง ถ้าชื่อไม่ตรงบัญชีที่ได้รับ ให้แก้ connection ก่อนดำเนินแล็บต่อ

ก่อนเริ่มบท 1 เปิด [สไลด์ภาพรวมและ prerequisite](../slides/module-00-overview.md)
ด้วย `make overview` จาก project root เพื่อดูวิธีเข้า SSH ด้วย `studentxx`,
ตั้งค่า connection ของตน และเลือกทำแล็บด้วยตนเองหรือ runner
ใช้ server address, SSH port, credentials และ path ของคู่มือที่อาจารย์แจ้ง

ใช้ Terminal ที่รองรับ Bash บนเครื่องเรียน Linux หลัง SSH เข้า **บัญชีของตัวเอง** แทน `xx` ด้วยหมายเลขสองหลักของตนที่อาจารย์มอบหมาย (`01`–`20`):

```bash
STUDENT_NO=xx
case "$STUDENT_NO" in
  0[1-9]|1[0-9]|20) ;;
  *) printf 'Replace xx with your assigned number (01-20).\n' >&2; exit 1 ;;
esac
export PGHOST=127.0.0.1
export PGPORT=5432
export PGUSER="student_$STUDENT_NO"
export PGDATABASE="claimsure_$STUDENT_NO"
export PGCONNECT_TIMEOUT=5
export PGAPPNAME="case-course-$STUDENT_NO"
umask 077
mkdir -p "$HOME/case-labs/evidence"
psql --version
```

พอร์ต 5432 คือการเชื่อมตรง PostgreSQL ของห้องเรียน ไม่ใช้ PgBouncer 6432 ในบทที่ทดลอง session/transaction หาก server อยู่คนละเครื่อง ให้เปลี่ยน `PGHOST` ตามที่อาจารย์ให้

ตั้งรหัสผ่านในหน่วยความจำของ Bash นี้ โดยไม่ใส่รหัสจริงใน command history:

```bash
read -r -s -p "Database password: " PGPASSWORD
printf '\n'
export PGPASSWORD
psql -X -v ON_ERROR_STOP=1
```

ใน psql:

```sql
\conninfo
\pset pager off
\timing on
\set VERBOSITY verbose
SET TIME ZONE 'Asia/Bangkok';
SELECT current_database(), session_user, current_user,
       current_setting('server_version') AS version,
       current_setting('server_version_num')::int >= 180000 AS pg18_or_newer;
```

ต้องได้ฐานข้อมูลและ login ของตัวเอง เช่น `claimsure_xx` / `student_xx` และตรวจว่าเครื่องเรียนเป็น PostgreSQL 18 ค่า `-X` ปิดการอ่าน psqlrc ส่วน `ON_ERROR_STOP` ช่วยหยุดเมื่อป้อนคำสั่งผ่านไฟล์/stdin; คู่มือจะปิดเฉพาะช่วงที่ตั้งใจทดลอง error

ใช้ `\q` กลับ Bash แล้วเปิด psql ใหม่ตามบทเรียน ไม่ต้องพิมพ์ SQL ลงใน Bash และไม่ต้องพิมพ์คำสั่ง Bash ลงใน psql

## รูปแบบการทำงาน

- บล็อก `bash`: วางใน Terminal ของนักเรียน
- บล็อก `sql`: วางใน psql เมื่อมี prompt ของฐานข้อมูล
- Session A/B/C: เปิดคนละ Terminal และทำตามลำดับที่กำหนด แต่ละ Terminal ต้องตั้ง PGHOST/PGPORT/PGUSER/PGDATABASE และอ่านรหัสผ่านตามส่วนเตรียมการเชื่อมต่ออีกครั้ง ใช้ connection ตรงฐานข้อมูลเดียวกัน
- บล็อกที่มี `<<'SQL'` จนถึง `SQL`: วางทั้งบล็อกใน Bash; เป็นการส่ง SQL ที่มองเห็นได้ให้ psql ไม่ใช่การเรียก shell script
- `\watch 5` ดูผลทุก 5 วินาที; กด Ctrl+C เพื่อหยุด watch และกลับ prompt
- อย่าวางทั้งบทพร้อมกัน ขั้นที่รอ lock ต้องมีอีก Terminal ปลด lock และขั้น expected error ต้องอ่าน SQLSTATE ก่อนทำต่อ

ถ้าระบบแสดง prompt ลงท้ายด้วย `!` หลัง error ใน transaction ให้ `ROLLBACK;` ก่อนเริ่ม transaction ใหม่ คำสั่ง SQL ต้องจบด้วย `;`; meta-command เช่น `\q` ไม่ต้องมี `;`

## เส้นเรื่องและขอบเขตข้อมูล

นี่คือ **อีกเวอร์ชันที่ใช้ข้อมูลต่อเนื่อง** จากบท 1–2 เรียนตามลำดับ 1 → 2 → 3 → 4 → 5 → 6 → 7 → 9 → 10 เวอร์ชันเดิมยังอยู่ที่ command-line (ส่วนแยกในต้นฉบับ: `docs/labs/command-line/README.md`)

ใช้ schema **claimsure** ในฐานข้อมูล **claimsure_xx** ของตน เช่น claimsure_xx ตารางหลักคือ customer → policy → claim ส่วน claim_detail_v, claim_tax, claims_by_status และ review_claim มาจากบท 2

| บท | ต่อจากข้อมูลเดิมอย่างไร | สิ่งที่ส่งต่อ |
| --- | --- | --- |
| 1–2 | ลูกค้า 3 ราย กรมธรรม์ 3 ฉบับ เคลม CLM-L1-001 ถึง 006 พร้อม view/routines | 6 เคลม; CLM-L1-001 อยู่ REVIEW หลัง 1D |
| 3 | ขยายจากเคลม 6 แถวเป็น CLM-L3-* อีก 100,000 แถวใน claim จริง | 100,006 เคลม, description/metadata, indexes, รายงานจาก claim |
| 4 | ทดลอง role/RLS/column/audit บน claim และ policy จริง | คืนสิทธิ์และการทดลองก่อนบทถัดไป |
| 5 | UPDATE/DELETE เคลม CLM-L1-* หลาย session; WAL จากเคลม CLM-L5-* | คืน 6 เคลมและลบเฉพาะ CLM-L5-* |
| 6 | sort/timeout/autovacuum บน claim; private copy ของ customer/policy/claim สำหรับ WAL/logging | คืนข้อมูลและ options ของ shared; เก็บหลักฐาน private |
| 7 | backup ชุด customer/policy/claim เดิม; กู้ CLM-L1-002 และเคลมหลัง base | คืนข้อมูล 3 ตารางโดยเก็บ view/routines ไว้ |
| 9 | workload, blocking และ deadlock บน schema lab_m9_shell ให้ตรงสัญญาณ Grafana | COMMIT เฉพาะคิวแล็บ; เคลมจริงไม่ถูกแก้ |
| 10 | เติม JSONB/FTS, event partitions, vector และ customer-based RLS ให้เคลมเดิม | ข้อมูลต่อยอดพร้อมวิธีคืนเฉพาะส่วนเพิ่ม |

**เริ่มเวอร์ชันนี้จากบท 1–2 แล้วทำบท 3 เพียงครั้งแรก** หากทำเวอร์ชันเดิมแล้ว ให้ตรวจชื่อ/โครงสร้าง objects ก่อน โดยเฉพาะ monthly summaries; ไม่รันสองเวอร์ชันสลับในฐานข้อมูลเดียวกัน เวอร์ชันนี้ใช้ชื่อรายงานขึ้นต้น cs_ เพื่อลดการชนกัน แต่ใช้ customer/policy/claim ชุดเดียวกันโดยตั้งใจ

ถ้ามีข้อมูลอื่นอยู่ก่อน จำนวนรวมอาจไม่ใช่ตัวอย่าง ให้เก็บผลจริงและใช้รหัส CLM-L1-*/CLM-L3-* ตรวจขอบเขต ไม่ TRUNCATE หรือลบ schema เพื่อแก้ให้ตัวเลขตรง บท 7 มีขั้นคืนข้อมูลทั้ง 3 ตารางในฐานข้อมูลฝึก ต้องเก็บ archive ใหม่จากสถานะปัจจุบันก่อนทุกครั้ง และปิด sessions/workload ของบทอื่นก่อนเริ่ม

| งาน | ผู้รัน / ที่ตั้ง |
| --- | --- |
| SQL, index, เพิ่มคอลัมน์, backup ของ own DB | student_xx ที่เป็นเจ้าของ claimsure และตารางหลัก |
| NOLOGIN roles บท 4/10 | Instructor เตรียมตามขั้นที่ระบุ; ไม่มอบ SUPERUSER/CREATEROLE ให้นักเรียน |
| ALTER SYSTEM/CHECKPOINT และอ่าน private log | labadmin เฉพาะ private server บท 6 |
| initdb/pg_ctl/physical recovery | private servers ใต้ home บท 6/7; ไม่หยุด shared server |
| pgvector/pg_stat_statements/monitoring/Supabase | Optional; อาจารย์เตรียมบริการและสิทธิ์ก่อน |

บท 6/7 ต้องมี **server binaries PostgreSQL 18** ไม่ใช่เฉพาะ psql เช่น:

```bash
export PATH="/usr/lib/postgresql/18/bin:$PATH"
postgres --version
initdb --version
pg_ctl --version
pg_dump --version
pg_restore --version
pg_basebackup --version
pg_verifybackup --version
```

หากอาจารย์ติดตั้ง runtime ที่อื่น ให้ใช้ path นั้น ห้ามใช้ pg_dump รุ่นเก่ากว่า server ที่ dump และ physical backup/recovery ต้องใช้ major version เดียวกับต้นทาง

## บันทึกหลักฐานและจบงาน

แต่ละบทมี expected result และ reset ของตัวเอง ใน psql สามารถบันทึกผล query ช่วงหนึ่งได้:

```sql
\o ~/case-labs/evidence/my-observation.txt
SELECT current_database(), current_user, clock_timestamp();
\o
```

`\o` ตัวที่สองคืน output มาหน้าจอ ตั้งชื่อไฟล์ใหม่เมื่อทดลองรอบใหม่ บันทึก parameter, workload, ค่าเดิม, ค่าที่ทดลอง, ผลก่อน/หลัง และวิธีคืนค่า เวลาที่ต่างกันเล็กน้อยยังไม่พอพิสูจน์ความเร็ว

เมื่อจบทุก Terminal:

```bash
unset PGPASSWORD
```

## ที่มาของบทเรียน

ออกแบบจาก [SQL ต้นฉบับ](references/scripts/sql), [classroom fixtures](references/scripts/shells), [Module 7 native-command guide](references/scripts/shells/module07-manual-labs-c-d.md) และสไลด์ของแต่ละบท โดยขยายคำสั่งให้ทำเองโดยขยายเคส customer-policy-claim จากบท 1–2 ให้เป็นเส้นเรื่องเดียว

เอกสารหลัก: [psql](https://www.postgresql.org/docs/18/app-psql.html), [SQL tutorial](https://www.postgresql.org/docs/18/tutorial.html), [GRANT](https://www.postgresql.org/docs/18/sql-grant.html), [PITR](https://www.postgresql.org/docs/18/continuous-archiving.html)

## การจัดไฟล์ในสำเนานี้

คัดลอกจาก `postgres-admin-labs/docs/labs/command-line-continuous` พร้อม runner และไฟล์ประกอบ โดยเก็บไฟล์อ้างอิงเพิ่มเติมใน `references/`:

- `references/cheat-sheets/`: คู่มือ Grafana ที่บท 9 อ้างถึง
- `references/scripts/sql/`: SQL ต้นฉบับสำหรับอ้างอิง
- `references/scripts/shells/`: shell helpers และคู่มือเดิมสำหรับอ้างอิง

[สไลด์เวอร์ชันต่อเนื่อง](../slides/README.md) อยู่ที่ `../slides/` ส่วน infrastructure ของห้องเรียนเป็นส่วนแยกจากสำเนานี้ คำสั่ง `/opt/...` ในคู่มือยังหมายถึงการติดตั้งบน server ของห้องเรียน ใช้ [RUNNER.md](RUNNER.md) สำหรับตัวรันเวอร์ชัน continuous ส่วน scripts ใต้ `references/` เป็นไฟล์ต้นฉบับประกอบ ไม่ใช่ตัวรันหลักของชุดนี้

## แล็บเพิ่มเติม: Replication, Databasus และ Supabase

เริ่ม Docker Compose สำหรับ Lab 8 และ Lab 10 ด้วย [คู่มือ Docker Labs](DOCKER-LABS.md)
และตัวรัน `bash labs/docker-labs.sh {8|10} COMMAND`

| แล็บ | คู่มือและไฟล์ประกอบ |
| --- | --- |
| Replication / HA | [Native tutorial](module-08-replication.md), [Compose 3 nodes](module08-replication/README.md), [cheat sheet](references/cheat-sheets/module-08-replication-ha.md) |
| Databasus | [คู่มือหลัก](module-07-databasus.md), [student manual พร้อมภาพ](module-07-databasus-student-manual.md), [PDF](module-07-databasus-student-manual.pdf) |
| Supabase Data API / Authentication | [Stack และคำสั่ง](supabase/README.md), [Lab เรียก API ตาม Role/RLS พร้อม curl](../docs/tutorials/supabase-self-hosted/API-LAB.md), [HTML lesson](../docs/tutorials/supabase-self-hosted/index.html) |

แล็บเพิ่มเติมเหล่านี้ใช้ environment/instance ตามคู่มือของตน ไม่ถูกเพิ่มเข้า `run-labs.sh run all` ของชุด continuous โดยอัตโนมัติ
