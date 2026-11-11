# SQL ฉบับผู้สอน — PostgreSQL Admin Labs

ชุดนี้เป็นสำเนาพร้อมคำอธิบายของ SQL หลัก **Module 1–10** รวมไฟล์ Session A/B ของ **MVCC** และ **Blocking** ทั้งหมด **14 ไฟล์ / 502 SQL statements** แบ่ง Lab ย่อยตามต้นฉบับในแต่ละไฟล์

ทุก Statement มี Comment ภาษาไทยบอก **Lab, Login/Database, จุดประสงค์, เหตุผล และผลที่ให้ผู้เรียนสังเกต** ใช้ศัพท์เทคนิคภาษาอังกฤษ คำสั่ง SQL และ psql ของต้นฉบับคงเดิม ไฟล์นักเรียนใน `scripts/sql/` ไม่ถูกแก้ไข

## เลือกไฟล์ก่อนสอน

| Module | ไฟล์ผู้สอน | Login / Environment หลัก |
| --- | --- | --- |
| 1 Basic SQL | [01-basic-sql-teacher.sql](01-basic-sql-teacher.sql) | `student_xx` / `claimsure_xx`; มีสิทธิ์สร้าง Schema |
| 2 Advanced SQL | [02-advanced-sql-teacher.sql](02-advanced-sql-teacher.sql) | นักเรียนเดิม / ฐานเดียวกับ Module 1A–B |
| 3 Performance | [03-performance-tuning-teacher.sql](03-performance-tuning-teacher.sql) | นักเรียน / ฐานฝึก มีพื้นที่สำหรับ 2 ล้าน Claims |
| 4 Security | [04-security-user-management-teacher.sql](04-security-user-management-teacher.sql) | `postgres` เฉพาะ 0/4A จากนั้น `student_xx` และ Runtime Logins |
| 5 Architecture | [05-architecture-teacher.sql](05-architecture-teacher.sql) | `postgres` / Seeded Enterprise Primary; ต้องมี Fixture ตาม Header |
| 6 Configuration | [06-configuration-claim-teacher.sql](06-configuration-claim-teacher.sql) | `postgres` / `claimsure_m6` บน Dedicated Module 6 Instance |
| 7 Backup/Recovery | [07-backup-recovery-teacher.sql](07-backup-recovery-teacher.sql) | `postgres` / Enterprise Primary; Lab 7D ต่อฐาน Restore ที่แยกไว้ |
| 8 Replication | [08-replication-teacher.sql](08-replication-teacher.sql) | `postgres` / Primary, Standby หรือ Endpoint ตาม Lab |
| 9 Monitoring | [09-monitoring-teacher.sql](09-monitoring-teacher.sql) | `postgres` / ฐานฝึก; มีสิทธิ์อ่าน Monitoring Details |
| 10 Modern Features | [10-modern-features-supabase-teacher.sql](10-modern-features-supabase-teacher.sql) | ผู้สอน `postgres` บนฐานฝึกที่จัดแยก; RLS สลับ Effective Role |
| 5E MVCC A | [05-mvcc-session-a-teacher.sql](05-mvcc-session-a-teacher.sql) | Connection A / ฐานเดียวกับ B |
| 5E MVCC B | [05-mvcc-session-b-teacher.sql](05-mvcc-session-b-teacher.sql) | Connection B / ฐานเดียวกับ A |
| 9C Blocking A | [09-blocking-session-a-teacher.sql](09-blocking-session-a-teacher.sql) | Connection A / เตรียม `lab_m9.lock_demo` ก่อน |
| 9C Blocking B | [09-blocking-session-b-teacher.sql](09-blocking-session-b-teacher.sql) | Connection B / ฐานเดียวกับ A |

`xx` คือเลขนักเรียน เช่น `03` ตามชื่อที่จัดเตรียมจริง ไม่ใช่ข้อความที่ส่งให้ Server ตามตัวอักษร ใน Module 4 ต้องแทน `xx` ทุกแห่ง รวม Role, Schema, Database และ Marker ก่อนเริ่ม

## วิธีใช้ระหว่างสอน

1. เปิดไฟล์แล้วอ่าน Header: ตรวจ Database, Login, Fixture และ Session ที่ต้องใช้ก่อนรัน
2. ใช้สารบัญด้านล่างค้น Lab หรือค้น `[START 04-SQL032]` เพื่อไปยังคำอธิบายของคำสั่งนั้น `SOURCE` อ้างเลขบรรทัดของไฟล์นักเรียน
3. อธิบาย “ทำไปเพื่ออะไร” แล้วให้ผู้เรียนคาดผล จากนั้นรัน Statement และอ่านผลตาม Comment
4. ถ้ามี `BEGIN` ให้ทำต่อใน Connection เดิมจนถึง `COMMIT` หรือ `ROLLBACK` ของชุดนั้น Function/Procedure/DO ต้องเลือกครบทั้ง Definition รวม Dollar Quotes
5. ให้ผู้เรียนอธิบายหลักฐานที่ได้ เช่น Row Count, Role, Plan, Wait Event หรือ Counter Delta ก่อนเปลี่ยน Lab

**อย่า Execute All ข้ามทุก Lab**: บางไฟล์ต้องสลับ Login/Session/Server และมี Expected Errors หรือขั้น Shell คั่นอยู่ เครื่องหมาย `[START ...]` / `[END ...]` ราย Statement ช่วยค้นคำอธิบาย ไม่ได้แปลว่า Statement นั้นเป็น Transaction แยกจากชุดก่อนหน้า

Module 4 เป็น Pure SQL ใช้ SQL Editor ได้ ส่วนไฟล์อื่นมีคำสั่งของ **psql Client** เช่น `\set`, `\if`, `\gset`, `\prompt` และ Variables รูปแบบ `:'snapshot'` จึงใช้ psql ได้ตรงตามต้นฉบับ หากใช้ DBeaver/pgAdmin ให้เลือก SQL เฉพาะ Branch ที่ต้องการ แทน Variables ด้วย Literal ที่ถูกต้อง และหยุด/สลับ Connection ด้วยตนเอง

ตัวอย่างเปิด Connection นักเรียนจาก Terminal แล้วเลือกรัน SQL เป็นช่วง ๆ:

```bash
psql -X -h HOST -p PORT -U student_xx -d claimsure_xx -W
```

ใช้ Host/Port/Password ที่ผู้สอนจัดให้ `-W` ขอ Password โดยไม่ใส่ไว้ใน Command Line ชื่อไฟล์/Make Target/Shell Path ใน Comment ต้นฉบับอาจเป็นของ Environment คนละชุด ให้ยึด Setup ที่ใช้งานจริงและคู่มือประจำ Lab

## จุดที่ผู้สอนต้องจัดลำดับเอง

### Module 4: ใช้ postgres ให้จบต้น Lab

| ช่วง | Login จริง | สิ่งที่ทำ |
| --- | --- | --- |
| 0, 4A | `postgres` | สร้าง 11 Roles, Password, Schema, CONNECT และ Membership; ส่งมอบ Owner ให้ Student |
| 4B | `student_xx` | `BEGIN` → `SET LOCAL ROLE claimsure_owner_xx` → สร้าง Tables/Seed → `COMMIT` |
| 4C–D | `student_xx`, `claim_app_xx` | Owner ให้ Grants/ตั้ง RLS; App Login จริงทดสอบ |
| 4E | `student_xx`, `internal_auditor_xx`, `manager_th_xx` | Column Grants และ Expected Permission Errors |
| 4F | `student_xx`, `claim_app_xx`, `internal_auditor_xx` | สร้าง Function/Trigger → App Commit → Auditor อ่าน Audit |
| 4G | `student_xx`, `claim_app_xx` | Owner ตั้ง Default Privileges แล้วสร้าง Object ใหม่; App อ่าน |
| 4H | `student_xx` | ตรวจ Effective Privileges, Membership และ Ownership |

`claimsure_owner_xx` เป็น **NOLOGIN**; Student ใช้ `SET LOCAL ROLE` ภายใน Transaction ได้หลัง 4A.4 ซึ่งให้ `SET TRUE, INHERIT FALSE` หาก `can_set_owner=false` ให้กลับไปตรวจ Grant ใน 4A.4 โดยผู้ดูแล ไม่เพิ่ม `SUPERUSER`/`CREATEROLE` ให้นักเรียน

Expected Errors คือ `04-SQL075`, `090`, `107`, `116`, `138` แต่ละครั้งต้องอ่าน Error แล้วรัน **Recovery block ถัดไปที่มี `ROLLBACK`** ก่อนเริ่มงานใหม่ App/Auditor/Manager ต้อง Login ด้วย User ของตนจริง การทดสอบเป็น `postgres` จะไม่พิสูจน์สิทธิ์ของ Runtime User

### Module 5: Fixture และสอง Sessions

ไฟล์หลักต้องมี Enterprise `insurance.claim` ซึ่งมี `tenant_id` และข้อมูล `CLM-1001`, มี `insurance.audit_event` และต้องมี `CLM-L1-005` สำหรับ Tuple/MVCC บางส่วน **Module 1 Fixture อย่างเดียวไม่ครบ** ตรวจ Schema/Data ก่อนเริ่มและอย่าข้าม Guard เมื่อ Environment ไม่ตรง

| ลำดับ MVCC 5E | ทำอะไร | สิ่งที่อธิบาย |
| --- | --- | --- |
| 1 — A | เปิด A รันไฟล์ Session A จนถึง `\prompt` | A อยู่ใน REPEATABLE READ และมี Snapshot แล้ว |
| 2 — B | เปิด B บน Database เดียวกัน รัน Session B จน Commit | Plain SELECT ของ A ไม่ขวาง UPDATE นี้ |
| 3 — A | กลับ A กด Enter แล้วอ่านก่อน COMMIT | A ยังเห็น Values ตาม Snapshot เดิม แม้ B Commit แล้ว |
| 4 — A | COMMIT แล้วอ่านอีกครั้ง | Snapshot ใหม่เห็น Version ของ B; ใช้ Timestamp/ctid ประกอบ หาก Status เดิมเป็น REVIEW อยู่แล้ว |

### Module 6: SQL → File → Activate → วัดผล

ใช้ Dedicated Module 6 Guide (ส่วนแยกในต้นฉบับ: `labs/module06/README.md`) ไม่เปลี่ยน Shared Classroom Instance ไฟล์หลักบน Host คือ `labs/module06/config/postgresql.conf` ซึ่ง Include `conf.d` และถูก Mount ที่ `/etc/postgresql/module06/postgresql.conf`

| Lab | ไฟล์บน Host ใต้ `labs/module06/config/conf.d/` | Baseline → Candidate | Activate |
| --- | --- | --- | --- |
| 6A Connections | `10-connections.conf` | `max_connections`: 40 → 60 | Restart |
| 6B Memory | `20-memory.conf` | `shared_buffers`: 128MB → 192MB | Restart; `work_mem` ทดลองด้วย SET LOCAL |
| 6C WAL/Checkpoints | `30-wal.conf` | `max_wal_size`: 1GB → 2GB | Reload |
| 6D Planner/Storage | `40-planning.conf` | `random_page_cost`: 4 → 1.1 | Reload แล้วเปิด Session ใหม่ |
| 6E Parallelism | `50-parallel.conf` | `max_worker_processes`: 4 → 8 | Restart |
| 6F Autovacuum | `60-autovacuum.conf` | `autovacuum_vacuum_cost_limit`: 200 → 400 | Reload; Table Options มีผลโดยไม่ต้อง Reload |

ในแต่ละกลุ่ม เก็บ Baseline → เปลี่ยนไฟล์หนึ่งกลุ่ม → Reload/Restart ตามตาราง → ตรวจ `pg_settings` และ `pending_restart` → วัด Workload เดิม → เก็บหลักฐาน → คืน Baseline ตามคู่มือ Candidate เป็นค่าฝึกสอน ไม่ใช่คำแนะนำใช้กับ Production ทุกเครื่อง

`pg_reload_conf()=true` ยืนยันแค่ส่งสัญญาณสำเร็จ ต้องตรวจค่าจริง, `pg_file_settings.error` และ Source ด้วย หลัง Restart ต้อง Reconnect; เวลา `pg_postmaster_start_time()` ควรเปลี่ยน ใน 6C ให้ใช้ Connection เดิมตั้งแต่เก็บ TEMP Baseline จนอ่าน Delta ส่วน 6F ให้ Commit แล้ว Poll เป็น Statement ใหม่ทุก 10–60 วินาที ค่อยทำ Cleanup 6F.3 หลังสังเกตครบ

### Module 7: แยก SQL Validation ออกจาก Backup/Restore

| ลำดับ | ที่รัน | สิ่งที่ต้องทำ |
| --- | --- | --- |
| Setup → 7A/B | SQL บน Source Primary | สร้าง `lab_m7`, ตั้ง RPO/RTO, Capture `snapshot=before_backup` |
| 7C → Backup | SQL + Terminal | ตรวจ Scope แล้วทำ Backup ด้วยขั้น Shell ที่ตรง Environment; ให้รวม Baseline `lab_m7` |
| Restore | Terminal / Recovery Tool | Restore ไป Database/Instance แยกตามคู่มือ ตรวจ Target ก่อนสั่ง |
| 7D | SQL บน `claimsure_restore` | ตั้ง `snapshot=after_restore` แล้ว Capture/เทียบ Counts/Routines กับ Baseline |
| 7E | SQL + Terminal | ตรวจ Physical/WAL Readiness; สร้างและ Verify Base Backup ใน Shell |
| 7F | SQL บน Primary + Recovery Instance | สร้าง Named Restore Point แล้วฝึก PITR ด้วย Base Backup และ WAL Chain ที่ครบ |
| 7G | SQL | บันทึก Evidence และ RPO/RTO ที่วัดจริงหลัง Restore Drill |

Guard เดิมของ 7D เช็กเพียงชื่อฐานว่าไม่ใช่ `claimsure` จึงไม่ป้องกันการเลือก `claimsure_xx` ผิด ต้องยืนยัน **isolated Target ด้วยตนเอง** และห้ามใช้ชื่อ Snapshot `before_backup` เป็นผลหลัง Restore ไม่เช่นนั้นอาจเทียบ Baseline กับตัวเอง

`\echo` ที่แสดง `pg_dump`, `pg_restore`, `pg_basebackup` หรือ INSERT ตัวอย่างเป็นเพียงข้อความ ยังไม่ได้ทำงาน Backup/Restore หรือบันทึก PASS ให้เอง SQL นี้ไม่แทนการ Restore Test

**หมายเลข 7E มีสอง Track:** ใน SQL ต้นฉบับนี้หมายถึง Physical Backup/WAL Readiness ส่วน **Databasus** ใช้ Module 7E Databasus Student Manual (ส่วนแยกในต้นฉบับ: `docs/labs/module-07-databasus-student-manual.md`) ซึ่งมี UI/Helper/Shell Flow และ Retention แบบ GFS/Time/Count แยกต่างหาก ชุด Teacher SQL นี้ไม่สร้างคำสั่งแทน Helper ที่ไม่มี Source ใน Repository

### Module 8–10: Server Side และ Context

- **Module 8:** Setup/Publication ทำบน Primary; อย่ารันทั้งไฟล์บน Standby ตั้งต้นด้วย DDL/DML อ่าน 8A/B แยกสองฝั่ง และต่อแต่ละ Endpoint เพื่อทดสอบ 8E ส่วน Publication ยังไม่ตั้ง Subscriber ให้เอง
- **Module 9:** Setup `lab_m9.lock_demo` ก่อนเปิด A/B ให้ A หยุดที่ Prompt แล้ว B ทดลอง UPDATE ซึ่งตั้งใจ Timeout หลัง 2 วินาที ใช้ Observer Session C อ่าน 9C **ระหว่างที่ B รอ** Query ใน B ก่อน UPDATE อาจยังไม่เห็น Blocked PID เมื่อ B จบให้ A กด Enter เพื่อ Commit และคืน Lock
- **Module 10:** ต้องมีสิทธิ์สร้าง Role สำหรับ Setup ส่วน RLS ทดสอบหลัง `SET ROLE lab_m10_authenticated` Custom `request.jwt.claim.sub` เป็น Context จำลอง ไม่ตรวจ JWT Signature และยังคงอยู่หลัง `RESET ROLE`; ให้ `RESET request.jwt.claim.sub;` หรือจบ Connection หลังสาธิต

## สารบัญ Lab และจุดค้น SQL

`SQL001–025` หมายถึงค้น `[START <Module>-SQL001]` เป็นต้นในไฟล์นั้น ตัวเลขระบุ Statement ภายในไฟล์ ไม่ใช่เลข Lab ใหม่ แต่ละแถวเรียงตามตำแหน่งในต้นฉบับ

### 01-basic-sql.sql — 25 Statements

เปิด [01-basic-sql-teacher.sql](01-basic-sql-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น | `01-SQL001–SQL002` | student_xx  /  claimsure_xx (ฐานฝึกของตน) |
| 1A | create schema and related tables | `01-SQL003–SQL007` | student_xx  /  claimsure_xx (ฐานฝึกของตน) |
| 1B | insert repeatable seed data | `01-SQL008–SQL010` | student_xx  /  claimsure_xx (ฐานฝึกของตน) |
| 1C | select the sample claim rows | `01-SQL011` | student_xx  /  claimsure_xx (ฐานฝึกของตน) |
| 1D | update one claim in a transaction | `01-SQL012–SQL015` | student_xx  /  claimsure_xx (ฐานฝึกของตน) |
| 1E | delete one claim and roll back the transaction | `01-SQL016–SQL018` | student_xx  /  claimsure_xx (ฐานฝึกของตน) |
| 1F | join related data and compare set operations | `01-SQL019–SQL022` | student_xx  /  claimsure_xx (ฐานฝึกของตน) |
| 1G | aggregate results and verify row counts | `01-SQL023–SQL025` | student_xx  /  claimsure_xx (ฐานฝึกของตน) |

### 02-advanced-sql.sql — 18 Statements

เปิด [02-advanced-sql-teacher.sql](02-advanced-sql-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น | `02-SQL001–SQL002` | student_xx  /  claimsure_xx ฐานเดียวกับ Module 1 |
| 2A | View contract for claim details | `02-SQL003–SQL004` | student_xx  /  claimsure_xx ฐานเดียวกับ Module 1 |
| 2B | SQL function for a shorter claim-tax calculation | `02-SQL005–SQL007` | student_xx  /  claimsure_xx ฐานเดียวกับ Module 1 |
| 2C | PL/pgSQL row-set function filtered by status | `02-SQL008–SQL009` | student_xx  /  claimsure_xx ฐานเดียวกับ Module 1 |
| 2D | Procedure for controlled claim review | `02-SQL010–SQL014` | student_xx  /  claimsure_xx ฐานเดียวกับ Module 1 |
| 2E | CTE pipeline for ranked customer tax totals | `02-SQL015` | student_xx  /  claimsure_xx ฐานเดียวกับ Module 1 |
| 2F | Window functions for sequence and running total | `02-SQL016` | student_xx  /  claimsure_xx ฐานเดียวกับ Module 1 |
| 2G | Conditional-aggregation pivot by customer and status | `02-SQL017` | student_xx  /  claimsure_xx ฐานเดียวกับ Module 1 |
| 2H | Catalog validation for functions and procedures | `02-SQL018` | student_xx  /  claimsure_xx ฐานเดียวกับ Module 1 |

### 03-performance-tuning.sql — 43 Statements

เปิด [03-performance-tuning-teacher.sql](03-performance-tuning-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น | `03-SQL001–SQL010` | student_xx  /  claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows |
| 3A | baseline plan for the slow claim search | `03-SQL011–SQL015` | student_xx  /  claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows |
| 3B | match index type to access pattern | `03-SQL016–SQL020` | student_xx  /  claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows |
| 3C | index and autovacuum maintenance evidence | `03-SQL021–SQL026` | student_xx  /  claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows |
| 3D | monthly range partition table | `03-SQL027–SQL035` | student_xx  /  claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows |
| 3E | materialized report and denormalized snapshot | `03-SQL036–SQL043` | student_xx  /  claimsure_xx ฐานฝึกของตนที่มีพื้นที่สำหรับ 2 ล้าน Rows |

### 04-security-user-management.sql — 154 Statements

เปิด [04-security-user-management-teacher.sql](04-security-user-management-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| 0 | ตรวจ Connection ก่อนสร้างสิ่งใด | `04-SQL001` | A = postgres (SUPERUSER)  /  DATABASE: claimsure_xx |
| 4A.1 | สร้าง Owner, Group และ Login | `04-SQL002–SQL025` | A = postgres (SUPERUSER)  /  claimsure_xx |
| 4A.2 | ตรวจ Role ที่เพิ่งสร้าง | `04-SQL026` | A = postgres (SUPERUSER)  /  claimsure_xx |
| 4A.3 | ตั้ง Password สำหรับ Connection B/C/D | `04-SQL027–SQL029` | A = postgres (SUPERUSER)  /  claimsure_xx |
| 4A.4 | เตรียม Schema และส่งมอบ Lab ให้ student_xx เป็นครั้งสุดท้าย | `04-SQL030–SQL039` | A = postgres (SUPERUSER); นี่คือขั้นสุดท้ายที่ใช้ postgres  /  claimsure_xx |
| 4B.1 | เปิด Connection S ตรวจสิทธิ์ที่ได้รับ แล้วใช้ Owner | `04-SQL040–SQL045` | S = student_xx (ผู้ใช้ปกติ); เปิด Connection ใหม่ด้วย Login นักเรียนเดิม  /  claimsure_xx |
| 4B.2 | สร้าง Table ทั้งสามในนาม Owner | `04-SQL046–SQL053` | S = student_xx (ผู้ดูแล Lab ของตน)  /  claimsure_xx |
| 4B.3 | เพิ่มข้อมูลตั้งต้น | `04-SQL054–SQL059` | S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner  /  claimsure_xx |
| 4C.1 | ตรวจ CONNECT ที่ postgres ให้ไว้แล้วใน 4A.4 | `04-SQL060` | S = student_xx (ผู้ดูแล Lab ของตน)  /  claimsure_xx |
| 4C.2 | ให้สิทธิ์ Object กับ Group | `04-SQL061–SQL067` | S = student_xx (ผู้ดูแล Lab ของตน); ภายในใช้ Owner  /  claimsure_xx |
| 4C.3 | ตรวจ Membership ที่ postgres เตรียมใน 4A.4 | `04-SQL068` | S = student_xx (ผู้ดูแล Lab ของตน)  /  claimsure_xx |
| 4C.4 | เปิด Connection B แล้วทดสอบอ่านและเพิ่มข้อมูล | `04-SQL069–SQL073` | B = claim_app_xx (ผู้ใช้ปกติ ไม่ใช่ SUPERUSER)  /  claimsure_xx |
| 4C.5 | EXPECTED ERROR: App สร้าง Table ไม่ได้ | `04-SQL074–SQL075` | B = claim_app_xx (ผู้ใช้ปกติ)  /  claimsure_xx |
| 4C.6 | RECOVERY หลัง Expected error ของ 4C.5 | `04-SQL076` | B = claim_app_xx (Connection เดิม)  /  claimsure_xx |
| 4D.1 | เปิด RLS และสร้าง Policy บนตารางเดิม | `04-SQL077–SQL082` | S = student_xx (ผู้ดูแล Lab ของตน); กลับมาที่ Connection S  /  claimsure_xx |
| 4D.2 | App อ่านและเพิ่มเฉพาะ Tenant ของตน | `04-SQL083–SQL087` | B = claim_app_xx (ผู้ใช้ปกติ)  /  claimsure_xx |
| 4D.3 | EXPECTED ERROR: App เพิ่มข้อมูลข้าม Tenant ไม่ได้ | `04-SQL088–SQL090` | B = claim_app_xx (ผู้ใช้ปกติ)  /  claimsure_xx |
| 4D.4 | RECOVERY หลัง Expected error ของ 4D.3 | `04-SQL091` | B = claim_app_xx (Connection เดิม)  /  claimsure_xx |
| 4D.5 | App ไม่มี Tenant context จึงเห็นศูนย์แถว | `04-SQL092–SQL095` | B = claim_app_xx (ผู้ใช้ปกติ)  /  claimsure_xx |
| 4E.1 | Owner ให้สิทธิ์ Column กับ Group ที่มีอยู่แล้ว | `04-SQL096–SQL103` | S = student_xx (ผู้ดูแล Lab ของตน)  /  claimsure_xx |
| 4E.2 | เปิด Connection C เป็น Auditor แล้วอ่านชื่อ | `04-SQL104–SQL105` | C = internal_auditor_xx (ผู้ใช้ปกติ)  /  claimsure_xx |
| 4E.3 | EXPECTED ERROR: Auditor อ่าน Contact fields ไม่ได้ | `04-SQL106–SQL107` | C = internal_auditor_xx (ผู้ใช้ปกติ)  /  claimsure_xx |
| 4E.4 | RECOVERY หลัง Expected error ของ 4E.3 | `04-SQL108` | C = internal_auditor_xx (Connection เดิม)  /  claimsure_xx |
| 4E.5 | เปิด Connection D เป็น Manager แล้วแก้ Status | `04-SQL109–SQL113` | D = manager_th_xx (ผู้ใช้ปกติ)  /  claimsure_xx |
| 4E.6 | EXPECTED ERROR: Manager แก้จำนวนเงินไม่ได้ | `04-SQL114–SQL116` | D = manager_th_xx (ผู้ใช้ปกติ)  /  claimsure_xx |
| 4E.7 | RECOVERY หลัง Expected error ของ 4E.6 | `04-SQL117` | D = manager_th_xx (Connection เดิม)  /  claimsure_xx |
| 4F.1 | Owner สร้าง Count function ก่อนให้ EXECUTE | `04-SQL118–SQL123` | S = student_xx (ผู้ดูแล Lab ของตน)  /  claimsure_xx |
| 4F.2 | Owner สร้าง Audit function และ Trigger | `04-SQL124–SQL131` | S = student_xx (ผู้ดูแล Lab ของตน)  /  claimsure_xx |
| 4F.3 | App เรียก Function และ UPDATE ให้เกิด Audit | `04-SQL132–SQL136` | B = claim_app_xx (ผู้ใช้ปกติ)  /  claimsure_xx |
| 4F.4 | EXPECTED ERROR: App ลบ Audit ไม่ได้ | `04-SQL137–SQL138` | B = claim_app_xx (ผู้ใช้ปกติ)  /  claimsure_xx |
| 4F.5 | RECOVERY หลัง Expected error ของ 4F.4 | `04-SQL139` | B = claim_app_xx (Connection เดิม)  /  claimsure_xx |
| 4F.6 | Auditor อ่านหลักฐานจาก App connection จริง | `04-SQL140` | C = internal_auditor_xx (ผู้ใช้ปกติ)  /  claimsure_xx |
| 4G.1 | ตั้ง Defaults แล้วสร้าง Table ในนาม Owner เดียวกัน | `04-SQL141–SQL147` | S = student_xx (ผู้ดูแล Lab ของตน)  /  claimsure_xx |
| 4G.2 | App อ่าน Table ใหม่ได้ผ่าน Write -> Read membership | `04-SQL148` | B = claim_app_xx (ผู้ใช้ปกติ)  /  claimsure_xx |
| 4H.1 | ตรวจสิทธิ์ของ App และ Owner membership | `04-SQL149–SQL152` | S = student_xx (ผู้ดูแล Lab ของตน)  /  claimsure_xx |
| 4H.2 | ตรวจ Membership และ Owner ของตาราง | `04-SQL153–SQL154` | S = student_xx (ผู้ดูแล Lab ของตน)  /  claimsure_xx |

### 05-architecture.sql — 65 Statements

เปิด [05-architecture-teacher.sql](05-architecture-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น | `05-SQL001` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 |
| 5A | Observe Connections (PDF pp. 105-106) | `05-SQL002–SQL003` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 |
| 5B | Background Process Evidence (PDF pp. 107-108) | `05-SQL004–SQL008` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 |
| 5C | Shared Memory in a Claim Update (PDF pp. 109-110) | `05-SQL009–SQL018` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 |
| 5D | Data Page and Tuple States (PDF pp. 111-112) | `05-SQL019` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 |
| 5D.1 | Page Lifecycle (PDF p. 113) | `05-SQL020–SQL026` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 |
| 5D.2 | INSERT New Live Tuple (PDF p. 114) | `05-SQL027–SQL029` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 |
| 5D.3 | UPDATE Old Tuple Plus New Tuple (PDF p. 115) | `05-SQL030–SQL033` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 |
| 5D.4 | DELETE and SELECT Visibility (PDF p. 116) | `05-SQL034–SQL041` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 |
| 5D.5 | Activity to Tuple-State Map (PDF p. 117) | `05-SQL042` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 |
| 5E | MVCC Lab Example (PDF p. 118) | `05-SQL043` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 |
| 5F | WAL Lab Example (PDF pp. 119-120) | `05-SQL044–SQL055` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 |
| 5G | Storage and PGDATA Lab Example (PDF p. 121) | `05-SQL056–SQL065` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005 |

### 06-configuration-claim.sql — 74 Statements

เปิด [06-configuration-claim-teacher.sql](06-configuration-claim-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น | `06-SQL001` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 0.1 | Verify the dedicated instance and create reusable generated data | `06-SQL002–SQL007` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6A.1 | Read connection capacity and file activation | `06-SQL008–SQL011` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6A.2 | Test a claim-intake statement budget and restore it | `06-SQL012–SQL020` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6B.1 | Inspect the cache allocation separately from the workspace | `06-SQL021–SQL022` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6B.2 | Compare three work_mem values with three repeated report sorts | `06-SQL023–SQL027` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6B.3 | Budget report memory and verify restoration | `06-SQL028–SQL029` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6C.1 | Snapshot checkpoints and the WAL insert position | `06-SQL030–SQL034` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6C.2 | Generate 5000 claim events and read counter deltas | `06-SQL035–SQL038` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6D.1 | Prepare the same index before either planner test | `06-SQL039–SQL042` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6D.2 | Test random_page_cost narrowly before adopting a file default | `06-SQL043–SQL047` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6E.1 | Read worker capacity and compare serial versus eligible parallel plans | `06-SQL048–SQL057` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6E.2 | Calculate a report process memory illustration | `06-SQL058` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6F.1 | Prepare a 20000-row review queue and baseline counters | `06-SQL059–SQL064` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6F.2 | Apply queue thresholds and generate 2000 obsolete tuple versions | `06-SQL065–SQL072` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |
| 6F.3 | Reset only the four lab table overrides | `06-SQL073–SQL074` | postgres  /  claimsure_m6  /  Dedicated PG18 cluster_name=claimsure-module06 |

### 07-backup-recovery.sql — 35 Statements

เปิด [07-backup-recovery-teacher.sql](07-backup-recovery-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น | `07-SQL001–SQL011` | postgres  /  claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore |
| 7A | ClaimSure recovery objectives and exposure | `07-SQL012–SQL014` | postgres  /  claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore |
| 7B | Capture a business validation baseline before backup | `07-SQL015–SQL018` | postgres  /  claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore |
| 7C | Logical backup scope and artifact checks | `07-SQL019–SQL021` | postgres  /  claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore |
| 7D | Post-restore validation and difference report | `07-SQL022–SQL025` | postgres  /  isolated claimsure_restore หลัง Restore; snapshot=after_restore |
| 7E | Physical backup and WAL archive readiness | `07-SQL026–SQL029` | postgres  /  claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore |
| 7F | Named restore point and recovery boundary | `07-SQL030–SQL033` | postgres  /  claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore |
| 7G | Recovery evidence and keep-or-fix decision | `07-SQL034–SQL035` | postgres  /  claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore |

### 08-replication.sql — 14 Statements

เปิด [08-replication-teacher.sql](08-replication-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น | `08-SQL001–SQL003` | postgres  /  claimsure  /  Primary |
| 8A/8B | primary or standby, senders and receiver | `08-SQL004–SQL006` | postgres  /  claimsure  /  เลือกอ่านบน Primary และ Standby แยกกัน |
| 8C | lag dimensions and replay delay | `08-SQL007–SQL009` | postgres  /  claimsure  /  Primary; postgres  /  claimsure  /  เลือกอ่านบน Primary และ Standby แยกกัน |
| 8D | logical publication on the primary | `08-SQL010–SQL013` | postgres  /  claimsure  /  Primary; postgres  /  Database ฝั่ง Subscriber ถ้ามี Subscription |
| 8E | routing evidence for direct/PgBouncer/HAProxy connections | `08-SQL014` | Role ของ Lab  /  claimsure  /  ต่อแต่ละ Direct/Pooler/HAProxy Endpoint แล้วรัน Query เดิม |

### 09-monitoring.sql — 14 Statements

เปิด [09-monitoring-teacher.sql](09-monitoring-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น | `09-SQL001–SQL003` | postgres  /  claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor |
| 9A | connection and workload snapshot | `09-SQL004–SQL005` | postgres  /  claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor |
| 9B | slow SQL and cache efficiency | `09-SQL006–SQL008` | postgres  /  claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor |
| 9C | blocker -> blocked relationship | `09-SQL009` | postgres  /  claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor |
| 9D | database, table, maintenance, WAL and replication health | `09-SQL010–SQL014` | postgres  /  claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor |

### 10-modern-features-supabase.sql — 37 Statements

เปิด [10-modern-features-supabase-teacher.sql](10-modern-features-supabase-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น | `10-SQL001–SQL003` | postgres  /  ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง |
| 10A | JSONB evolve-without-migration data | `10-SQL004–SQL009` | postgres  /  ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง |
| Full-text Search | Full-text search with a stored generated tsvector | `10-SQL010–SQL012` | postgres  /  ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง |
| Partitioning | Declarative partitioning and lifecycle operations | `10-SQL013–SQL018` | postgres  /  ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง |
| Vector Search | Vector similarity when pgvector is installed | `10-SQL019–SQL022` | postgres  /  ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง |
| JWT Context / RLS | Supabase-style JWT context + RLS readiness | `10-SQL023–SQL037` | postgres  /  ฐานฝึกที่แยกไว้ เช่น claimsure; RLS เปลี่ยน Effective Role ตามคำสั่ง; session_user=postgres, current_user=lab_m10_authenticated  /  ฐานฝึกเดียวกัน |

### 05-mvcc-session-a.sql — 7 Statements

เปิด [05-mvcc-session-a-teacher.sql](05-mvcc-session-a-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| 5E / MVCC Session A | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B | `05-SQL001–SQL007` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005  /  Session A |

### 05-mvcc-session-b.sql — 5 Statements

เปิด [05-mvcc-session-b-teacher.sql](05-mvcc-session-b-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| 5E / MVCC Session B | Snapshot เดิมของ A เทียบกับ Update ที่ Commit โดย B | `05-SQL001–SQL005` | postgres  /  claimsure บน Seeded Primary ที่มี Enterprise Fixture + CLM-L1-005  /  Session B |

### 09-blocking-session-a.sql — 5 Statements

เปิด [09-blocking-session-a-teacher.sql](09-blocking-session-a-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| 9C / Blocking Session A | A ถือ Row Lock; B รอจน Lock Timeout | `09-SQL001–SQL005` | postgres  /  claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor  /  Session A |

### 09-blocking-session-b.sql — 6 Statements

เปิด [09-blocking-session-b-teacher.sql](09-blocking-session-b-teacher.sql)

| Lab / ช่วง | จุดประสงค์ | SQL IDs | Login / Database |
| --- | --- | --- | --- |
| 9C / Blocking Session B | A ถือ Row Lock; B รอจน Lock Timeout | `09-SQL001–SQL006` | postgres  /  claimsure ฐานฝึก; Monitoring ทั้ง Cluster อาจต้อง pg_monitor  /  Session B |

## ขอบเขตและการตรวจไฟล์

ชุดนี้อ้าง SQL หลักปัจจุบัน 10 Modules และ 4 Session Files ไม่รวม Reset Scripts, Security Gates Walkthrough, Alternate Configuration Scripts หรือ Supabase Docker Setup ซึ่งมี Flow ของตนเอง

คำอธิบายถูกเพิ่มเป็น SQL Line Comments ขึ้นต้น `-- @teacher` เท่านั้น เมื่อตัดบรรทัดเหล่านั้นออกต้องได้ไฟล์ต้นฉบับตรงกันทุก Byte รวม psql Commands, Function Bodies และลำดับคำสั่ง จึงตรวจได้ว่าการเพิ่ม Teacher Notes ไม่เปลี่ยนพฤติกรรม SQL มี START/END ครบ 502 คู่ และระบุ Login ก่อนทุก Statement

การตรวจครั้งนี้เป็นการตรวจโครงสร้างและความตรงกันกับ Source ไม่ได้ Execute ทั้งชุดกับ Database จึงยังต้องเตรียม Fixture/Role/Server ตามแต่ละ Lab และเก็บผลวัดจริงก่อนนำไปสอน

อ้างอิงพฤติกรรม PostgreSQL ที่ใช้ประกอบคำอธิบาย: [EXPLAIN](https://www.postgresql.org/docs/18/sql-explain.html), [Monitoring Statistics](https://www.postgresql.org/docs/18/monitoring-stats.html) และ [PostgreSQL 17 Release Notes](https://www.postgresql.org/docs/17/release-17.html) สำหรับการเปลี่ยน VACUUM Memory เป็น TidStore
