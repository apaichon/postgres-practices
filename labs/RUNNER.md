# Shell runner สำหรับแล็บ ClaimSure เวอร์ชันต่อเนื่อง

Module 5 ของ continuous runner อ่าน [คู่มือเดิม](module-05-architecture-continuous.md) โดยเฉพาะ ส่วน [Module 5 ตามสไลด์ต้นฉบับไทย](module-05-architecture.md) ใช้ `make lab5` และฐาน `architecture_m5_xx` แยกต่างหาก

[กลับสารบัญคู่มือ](README.md)

ใช้ `run-labs.sh` เลือกทั้ง module หรือขั้นตอนย่อยในบท 1–7, 9 และ 10 ได้ คำสั่ง SQL/Bash อ่านจากคู่มือ Markdown ในโฟลเดอร์นี้ โดยมี Python standard library ควบคุม session A/B/C, งานที่รอ lock และขั้น expected error ให้ตามลำดับ ไม่เรียก runner ของเวอร์ชัน fixtures เดิม

ตัวอย่างทั้งหมดรันใน Bash ของบัญชี SSH นักเรียนบนเครื่อง Linux ต้องมี Python 3.9+, Bash และ PostgreSQL 18 client/server binaries บท 6–7 ใช้ `initdb`, `pg_ctl`, `pg_basebackup`, `pg_verifybackup` ด้วย ไม่รันด้วย root

[ผลทดสอบ runner บน PostgreSQL 18.6](runner/VALIDATION.md) รวมการรันต่อ, expected errors และ Ctrl+C ระหว่าง autovacuum lab

## เริ่มต้น

เข้าโฟลเดอร์คู่มือที่มีไฟล์นี้ แล้วกำหนดเลขนักเรียนและ connection:

```bash
export STUDENT_NO=xx
case "$STUDENT_NO" in
  0[1-9]|1[0-9]|20) ;;
  *) printf 'Replace xx with your assigned number (01-20).\n' >&2; exit 1 ;;
esac
export PGHOST=127.0.0.1
export PGPORT=5432
export PG_BIN=/usr/lib/postgresql/18/bin
read -r -s -p 'Student database password: ' PGPASSWORD
printf '\n'
export PGPASSWORD
```

Runner ใช้ `student_xx` / `claimsure_xx` ตาม `STUDENT_NO` และตรวจชื่อ login/database ก่อนทดลอง เปลี่ยนเป็นเลขของตนเอง `01`–`20` ห้ามชี้ไปฐานของเพื่อน หากไม่ตั้ง `PGPASSWORD` และมี interactive terminal ตัวรันจะถามรหัสผ่าน หรือใช้ `.pgpass` ได้

`run` และ `status` ต้องรับหมายเลขจริงผ่าน `STUDENT_NO` หรือ `--student` ไม่มีค่าเริ่มต้นเป็นนักเรียนคนใด ส่วน `list`, `show` และ `check` ใช้ตรวจเอกสารได้โดยไม่ต้องเชื่อมต่อฐานข้อมูล

ดูรายการโดยยังไม่เชื่อมฐานข้อมูล:

```bash
bash ./run-labs.sh list
bash ./run-labs.sh list 7
bash ./run-labs.sh show 7 7.4b
bash ./run-labs.sh check all
```

`show` แสดงบล็อกต้นทางในคู่มือ พร้อมชื่อ recipe ที่ควบคุมลำดับ บล็อกเปิด interactive psql, คำสั่ง conditional start และการเปลี่ยน session จะถูกจัดการโดย runner จึงไม่ใช่การวางทุกบล็อกที่แสดงพร้อมกัน `check` ตรวจว่า recipe ยังอ้างบล็อกในคู่มือได้และตรวจ Bash syntax โดยไม่เปิด connection

## เลือก module และ submodule

รันทั้งบท:

```bash
bash ./run-labs.sh run 1
bash ./run-labs.sh run 2
bash ./run-labs.sh run 3
```

เลือกเฉพาะขั้น หรือหลายขั้นใน connection เดียว:

```bash
bash ./run-labs.sh run 1 1A 1B
bash ./run-labs.sh run 2 2E 2F 2G
bash ./run-labs.sh run 5 5B 5C
bash ./run-labs.sh run 6 6D
bash ./run-labs.sh run 7 7.1
bash ./run-labs.sh run 7 7.2
bash ./run-labs.sh run 7 7.4b
```

ตัวอย่างข้างต้นเป็นทางเลือก ไม่รันซ้ำต่อกันโดยอัตโนมัติ ขั้นที่พึ่งข้อมูลจากขั้นก่อนต้องทำขั้นก่อนให้ครบ เช่น `7.4b` ต้องมี physical base จาก `7.4a` ใน state เดียวกัน Runner จะเรียงตามคู่มือแม้ระบุ selectors สลับกัน

เลขบท 7 ใช้ `7.1` เป็นกลุ่ม และ `7.1a` เป็นขั้นย่อย ส่วนบทอื่นใช้รหัสเดิมในคู่มือ เช่น `1A`, `6D.3`, `10F.1` กลุ่ม `6D` เลือก `6D.1`–`6D.4`

ให้หยุดรออ่านผลก่อนเริ่มแต่ละขั้น โดยยังคง SQL connections เดิม:

```bash
bash ./run-labs.sh run 5 --pause
bash ./run-labs.sh run 7 --pause
```

`5B` ค้าง transaction เพื่อให้ `5C` ตรวจ snapshot จึงต้องเลือกสองขั้นนี้ใน invocation เดียวกัน หรือรันทั้งบท 5 ไม่รัน `5C` แยกหลัง process เดิมจบไปแล้ว ส่วน 6C, 6F, 9D และ 9E ตัวรันเปิด connections เพิ่มและปลด lock ตามลำดับให้เอง

## รันต่อหลัง logout หรือหยุดระหว่างบท

สถานะเก็บใต้ `~/case-labs/continuous-runner/studentxx/moduleNN/` แยกจาก PostgreSQL workspace ใน `~/case-m6.*` / `~/case-m7.*` ไม่บันทึกรหัสผ่านลงไฟล์

```bash
bash ./run-labs.sh status 7
bash ./run-labs.sh run 7 --resume
```

`--resume` ข้ามขั้นที่สำเร็จแล้วและคืนค่าตัวแปร Bash เช่น `LAB`, `BACKUPS`, `D_BASE`, `POINT` จากไฟล์ state เดิม ไม่สร้าง workspace ใหม่แทนของเดิม การเริ่มแล็บใหม่ของ runner ไม่ import ความคืบหน้าจากแล็บ manual ที่ทำไว้ก่อนหน้า

ขั้นที่ใช้ private server จะตรวจ `pg_ctl status` และเปิด cluster เดิมหากหยุดอยู่ ก่อนเริ่ม SQL ที่ต้องใช้ server นั้น ไม่รัน `initdb` ใหม่เพื่อ resume

ถ้ามีขั้นที่จบไม่สมบูรณ์ ตัวรันจะหยุดพร้อมชื่อขั้นและ log ไม่ replay โดยอัตโนมัติ เพราะอาจมี `COMMIT` ไปแล้ว ตรวจข้อมูลและแก้เหตุให้เรียบร้อยก่อนเลือกทำซ้ำ:

```bash
bash ./run-labs.sh run 7 7.4b --retry-failed
```

ตัวอย่างนี้ใช้เฉพาะเมื่อยืนยันว่ารัน 7.4b ซ้ำได้แล้ว หาก INSERT สำเร็จก่อนเกิด error ที่เขียน `restore-point.name` ให้คืน path และบันทึก `$POINT` เดิมตามคู่มือ ไม่สั่ง INSERT ซ้ำ

หากตั้งใจทำขั้นที่เคยสำเร็จแล้วซ้ำ ใช้ `--replay` หลังตรวจผลข้างเคียง:

```bash
bash ./run-labs.sh run 2 2E --replay
```

Runner เก็บ connection binding ของ host/port/student ไว้กับ state หากเปลี่ยนเครื่องเป้าหมายต้องใช้ state directory คนละชุด:

```bash
bash ./run-labs.sh run 1 --student xx --state-dir "$HOME/case-labs/continuous-runner-round2"
```

## Instructor และ optional services

บท 4 และ 10 ต้องมี NOLOGIN roles ที่อาจารย์เตรียม นักเรียนไม่ต้องได้ SUPERUSER/CREATEROLE

ถ้าอาจารย์เตรียม roles ด้วยวิธี manual แล้ว นักเรียนรันตามปกติ:

```bash
bash ./run-labs.sh run 4
bash ./run-labs.sh run 10
```

อาจารย์สามารถเลือกเฉพาะการเตรียม/ลบ role โดยใช้ student connection สำหรับการตรวจเป้าหมาย และใช้ credential อีกชุดสำหรับ admin session รหัสทั้งสองอยู่ใน environment ของ process นี้เท่านั้น:

```bash
export INSTRUCTOR_USER=postgres
read -r -s -p 'Instructor database password: ' INSTRUCTOR_PASSWORD
printf '\n'
export INSTRUCTOR_PASSWORD
bash ./run-labs.sh run 4 4.0 --instructor
bash ./run-labs.sh run 10 10F.0 --instructor
```

เมื่อจบแล็บและคืน grants/policies แล้ว:

```bash
bash ./run-labs.sh run 4 4Z --instructor
bash ./run-labs.sh run 10 10Z --instructor
unset INSTRUCTOR_PASSWORD
```

หรือให้อาจารย์รันทั้งบทพร้อมเตรียม roles → ทดลองด้วย student → ลบ roles:

```bash
bash ./run-labs.sh run 4 --instructor
bash ./run-labs.sh run 10 --instructor
```

`--instructor` ไม่เปลี่ยน student SQL ให้ทำงานด้วย superuser หาก roles เดิมมีอยู่แล้ว คำสั่ง CREATE ROLE จะ error ให้ตรวจว่าใครเตรียมไว้ก่อน ไม่ลบ role ของงานอื่นเพื่อให้ผ่าน

Optional steps ไม่รวมในค่าปริยาย:

| ขั้น | บริการ/สิ่งที่ต้องเตรียม | วิธีเลือก |
| --- | --- | --- |
| 9F | pg_stat_statements ที่ติดตั้ง/preload แล้ว | `run 9 9F`; ไม่มี extension จะแจ้งข้าม |
| 9G | Prometheus ที่ 127.0.0.1:9090 บนเครื่องเซิร์ฟเวอร์, job `postgres`, instance `postgres:5432/claimsure_xx` | `run 9 9G` |
| 10E | pgvector ที่อาจารย์ติดตั้ง | `run 10 10E`; ไม่มี extension จะแจ้งข้าม |
| 10G | project Supabase ฝึก, UUID และ authenticated token | `run 10 10G` โดยระบุชัดเจนเท่านั้น |
| 7.6 | เนื้อหาเสริม ไม่มีคำสั่งทดลองสำเร็จรูป | `show 7 7.6` |
| 1Z/2Z | 1Z คืนหกเคลมด้วย INSERT 1B; 2Z ถอด objects บท 2 ที่บทถัดไปต้องใช้ | เลือก explicit เมื่อไม่ใช้บทต่อไปแล้ว; ถ้ามี dependency จะหยุดตาม PostgreSQL ไม่เติม CASCADE |

`--optional` เพิ่ม optional steps ในเครื่อง เช่น vector/monitoring แต่ไม่รวม `10G`, `1Z`, `2Z` สำหรับ `10G` ต้องตั้ง `SUPABASE_DB_URL`, `REAL_USER_ID`, `SUPABASE_URL`, `SUPABASE_PUBLIC_KEY`, `SUPABASE_ACCESS_TOKEN` ก่อนรัน ไม่มีการบันทึก credentials ลง runner state จะสร้าง/import/test RLS API ของตารางฝึก `public.course_claim` แล้ว DROP ตารางฝึกนี้เมื่อทดสอบสำเร็จ หากทดสอบไม่จบให้ตรวจและลบเฉพาะตารางฝึกตามคู่มือ

## รันชุดหลักครบทุกบท

ต้องเริ่มจากฐานฝึกของตนที่พร้อมทำบท 1 และทำตามลำดับ โดยไม่เปิด workload ของบทอื่นค้างไว้:

```bash
bash ./run-labs.sh run all --instructor --pause
```

คำสั่งนี้รวมบท 1–7, 9, 10 รวมการทดลองลบ/restore ในบท 7 และการคืนข้อมูลท้ายบท ใช้ instructor credentials ตามข้างต้นสำหรับ roles เท่านั้น ไม่รัน Module 8 หรือ Supabase project โดยปริยาย

หาก roles เตรียมไว้แล้วทั้งบท 4/10 ให้รัน `run all` โดยไม่ใส่ `--instructor` และให้อาจารย์ลบ roles ภายหลัง การรันซ้ำทั้งคอร์สต้องตรวจ DDL/data ที่มีอยู่ก่อน ไม่ลบ schema เพียงเพื่อให้การทดสอบผ่าน

## หลักฐานและพฤติกรรมเมื่อเกิด error

- Log ของแต่ละ invocation อยู่ใน state directory พร้อม session labels A/B/C/P/Q; ไม่ใช้ `set -x` และไม่บันทึก passwords
- `progress.json` เก็บเฉพาะขั้นที่สำเร็จ; `inflight.json` ระบุขั้นที่หยุดกลางทาง
- การปิด/ขัดจังหวะ runner ปิด SQL connections เพื่อ rollback transaction ที่ยังไม่ commit; ข้อมูลที่ COMMIT แล้วไม่ย้อนกลับเอง
- Snapshot ของหกเคลมในบท 10, สองเคลมในบท 5 และ rows/options ใน 6E เก็บเป็นไฟล์ local ของนักเรียนเพื่อช่วยคืนค่าหาก connection หลุด
- 5A ใช้ TEMP table สำหรับ snapshot แทนตารางช่วยถาวร และมี CSV สำรองใน state เพื่อให้ 5E คืนข้อมูลได้เมื่อเปิด connection ใหม่
- Private clusters เก็บหลักฐานไว้ใน workspace เดิม ไม่ถูกลบอัตโนมัติ หากหยุดกลางบท 6–7 ให้ตรวจสถานะ server ก่อนทำต่อ
- 6B รัน original/64kB/4MB/32MB อย่างละสามครั้ง; 6D.4 โหลดซ้ำด้วย 256MB จริง; 6E แทน `\watch` ด้วยการรอสูงสุด 90 วินาทีแล้วคืนค่า หากไม่เห็น autovacuum จะแจ้งผลที่วัดได้ ปรับเวลารอด้วย `--autovacuum-wait`
- 4B–4E, 6C และ 9E ตรวจ SQLSTATE ที่คาดไว้ด้วย ไม่ถือว่า error ทุกชนิดเป็นผลสำเร็จ

เมื่อเลิกใช้:

```bash
unset PGPASSWORD INSTRUCTOR_PASSWORD
```

อ้างอิงพฤติกรรมเครื่องมือ: [psql](https://www.postgresql.org/docs/18/app-psql.html), [PostgreSQL locking](https://www.postgresql.org/docs/18/explicit-locking.html), [Python subprocess](https://docs.python.org/3/library/subprocess.html)
