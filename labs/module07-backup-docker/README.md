# Module 7 Docker Lab — PostgreSQL Backup, Restore และ PITR

Lab นี้รันบนเครื่องด้วย Docker Compose และใช้เครื่องมือ native ของ PostgreSQL 18 โดยตรง ผู้เรียนจะได้เห็นทั้งคำสั่ง ผล restore และไฟล์ backup จริงบน host ครบ 5 เรื่อง:

1. Logical backup/restore ด้วย `pg_dump` และ `pg_restore`
2. Global objects ด้วย `pg_dumpall --globals-only`
3. Weekly full physical backup ด้วย `pg_basebackup`
4. Daily physical incremental backup และการรวม chain ด้วย `pg_combinebackup`
5. Point-in-time recovery (PITR) ด้วย base backup + archived WAL + named restore point

> Daily incremental ใน Lab นี้หมายถึง **physical block-level incremental backup** ของ PostgreSQL 18 ไม่ใช่ logical dump เฉพาะแถวที่เปลี่ยน Incremental directory เปิดเป็น server โดยตรงไม่ได้ ต้องมี full backup และ incremental ทุกตัวใน chain แล้วรวมด้วย `pg_combinebackup` ก่อน restore

## ภาพรวม

| Service | หน้าที่ | Port บนเครื่อง | เริ่มเมื่อใด |
| --- | --- | ---: | --- |
| `primary` | ฐานต้นทาง `backup_lab`, WAL archive และ WAL summary | 55432 | `make up` |
| `logical-target` | เป้าหมายสำหรับ logical restore | 55433 | `make up` |
| `physical-restore` | เปิด synthetic full ที่รวม backup chain แล้ว | 55434 | `make physical-restore` |
| `pitr-restore` | เปิด cluster ที่ replay WAL ถึง restore point | 55435 | `make pitr` |

ข้อมูล source/target อยู่ใน Docker volumes แต่ไฟล์ที่ต้องใช้กู้คืนถูก bind mount ออกมาที่:

- `artifacts/logical/` — logical dump, archive listing และ checksum
- `artifacts/globals/` — global objects
- `artifacts/physical/` — weekly full, daily incremental และ combined restore
- `artifacts/pitr/` — PITR data directory และ expected result
- `archive/` — archived WAL ที่ PITR ใช้ replay

## เริ่มต้น

ต้องมี Docker และ Docker Compose:

```bash
cd labs/module07-backup-docker
cp .env.example .env
make up
make status
```

`make up` สร้างข้อมูลตัวอย่าง 3 แถวใน `claims.claim_event`:

| claim_no | event_type | amount |
| --- | --- | ---: |
| CLM-0001 | REGISTERED | 1000.00 |
| CLM-0002 | APPROVED | 2500.00 |
| CLM-0003 | PAID | 1800.00 |

หาก port ชนกับ service อื่น ให้แก้ `M7_*_PORT` ใน `.env` ก่อน `make up`

## Lab A — Logical backup, committed damage และ restore

### A1. สร้าง backup

```bash
make logical-backup
make files
```

ไฟล์สำคัญ:

| ไฟล์ | เนื้อหา |
| --- | --- |
| `artifacts/logical/backup_lab.dump` | Custom-format dump ของ database พร้อม schema/data/owner/ACL |
| `artifacts/logical/backup_lab.list` | สารบัญจาก `pg_restore --list` |
| `artifacts/logical/CHECKSUMS.sha256` | Checksum ของ logical dump และ global files |
| `artifacts/globals/globals.sql` | Global objects ต้นฉบับจาก source |
| `artifacts/globals/globals-for-restore.sql` | สำเนาสำหรับ bootstrap target ด้วยชื่อ admin ต่างจาก source |

Lab ตัด password hash ออกจาก global dump ด้วย `--no-role-passwords` จึงต้องกำหนด password ใหม่ให้ login roles หลัง restore ในระบบจริง

### A2. ทำข้อมูลเสียหายและ COMMIT

```bash
make logical-damage
```

คำสั่งนี้ลบ `CLM-0002` และเพิ่ม `CLM-BAD-LOGICAL` ใน source จริง การเปลี่ยนแปลงถูก commit แล้ว

### A3. Restore ไปยัง target แยก

```bash
make logical-restore
```

ตรวจผล:

- source port 55432 ยังเป็นข้อมูลหลังความเสียหาย
- logical target port 55433 เป็น snapshot ตอนสร้าง `backup_lab.dump`
- roles `claims_app` และ `claims_readonly` ถูกสร้างจาก global backup

ตัวอย่างเชื่อมต่อจาก host:

```bash
PGPASSWORD=postgres-lab psql -h 127.0.0.1 -p 55433 -U restore_admin -d backup_lab
```

## Lab B — Weekly full + Daily incremental + Physical restore

### B1. Weekly full

```bash
make physical-full
```

ผลลัพธ์อยู่ที่ `artifacts/physical/weekly-full/` และมี `backup_manifest` สำหรับ verify และเป็น reference ของ incremental ตัวแรก

### B2. จำลองข้อมูลที่เปลี่ยนในแต่ละวัน

```bash
bash scripts/lab.sh change day-01
bash scripts/lab.sh physical-incremental daily-01

bash scripts/lab.sh change day-02
bash scripts/lab.sh physical-incremental daily-02
```

ไฟล์ `artifacts/physical/chain.txt` ต้องเรียงดังนี้:

```text
weekly-full
daily-01
daily-02
```

ห้ามลบ backup กลาง chain เพราะ incremental ตัวถัดไปอ้างถึง manifest ของตัวก่อนหน้า

### B3. รวม chain และเปิด restored server

```bash
make physical-restore
```

Runner ทำ 3 ขั้น:

1. `pg_combinebackup` รวม full → daily-01 → daily-02 เป็น synthetic full
2. `pg_verifybackup` ตรวจ `artifacts/physical/restore/`
3. เปิด directory นั้นเป็น `physical-restore` บน port 55434 แล้วนับแถว

## Lab C — PITR ถึงจุดก่อนความผิดพลาด

```bash
make pitr
```

Lab นี้ทำงานแบบ self-contained:

1. สร้างแถว `PITR-BASE-*` แล้วทำ full base backup
2. เพิ่ม `PITR-GOOD-*`
3. สร้าง named restore point ด้วย `pg_create_restore_point()`
4. หลัง restore point ลบ `PITR-BASE-*` และเพิ่ม `PITR-BAD-*`
5. บังคับ switch WAL และรอจน WAL file ปรากฏใน `archive/`
6. คัดลอก base backup, สร้าง `recovery.signal` และ replay ถึง named restore point

ผลที่ผ่านต้องเป็น:

```text
deleted_row_recovered       = true
before_target_present       = true
after_target_mistake_absent = true
```

ไฟล์ `artifacts/pitr/expected.txt` บันทึกชื่อ restore point และ claim ของรอบล่าสุด ส่วน recovered server เปิดที่ port 55435

## คำสั่ง PostgreSQL จริงที่ Runner ใช้

### Logical database

```bash
pg_dump -U postgres -d backup_lab \
  --create --format=custom \
  --file=/artifacts/logical/backup_lab.dump

pg_restore --list /artifacts/logical/backup_lab.dump
pg_restore -U restore_admin --exit-on-error --create \
  --dbname=restore_admin /artifacts/logical/backup_lab.dump
```

### Global objects

```bash
pg_dumpall -U postgres --globals-only --no-role-passwords \
  --file=/artifacts/globals/globals.sql

psql -U restore_admin -d restore_admin \
  -f /artifacts/globals/globals-for-restore.sql
```

`pg_dump` ต่อ database ไม่เก็บ roles/tablespaces จึงต้องมี global backup แยกสำหรับ logical disaster recovery ส่วน physical backup เก็บทั้ง cluster อยู่แล้ว แต่การ export globals แยกยังช่วย audit และ rebuild บน cluster ใหม่

### Physical full

```bash
pg_basebackup -U postgres \
  --pgdata=/artifacts/physical/weekly-full \
  --format=plain --wal-method=stream --checkpoint=fast \
  --manifest-checksums=SHA256 --progress

pg_verifybackup /artifacts/physical/weekly-full
```

### Physical incremental

```bash
pg_basebackup -U postgres \
  --pgdata=/artifacts/physical/daily-01 \
  --format=plain --wal-method=stream --checkpoint=fast \
  --incremental=/artifacts/physical/weekly-full/backup_manifest \
  --manifest-checksums=SHA256 --progress
```

Source เปิด `summarize_wal=on` เพื่อสร้าง WAL summaries ที่ server ใช้หาว่า block ใดเปลี่ยนจาก reference backup

### Combine incremental chain

```bash
pg_combinebackup \
  --output=/artifacts/physical/restore \
  /artifacts/physical/weekly-full \
  /artifacts/physical/daily-01 \
  /artifacts/physical/daily-02

pg_verifybackup /artifacts/physical/restore
```

### PITR

ค่าที่ Runner เพิ่มใน `postgresql.auto.conf` ของ recovery copy:

```conf
restore_command = 'cp /archive/%f %p'
recovery_target_name = 'm7_before_mistake_<timestamp>'
recovery_target_action = 'promote'
recovery_target_timeline = 'current'
```

จากนั้นสร้างสัญญาณและเปิด PostgreSQL:

```bash
touch /artifacts/pitr/data/recovery.signal
docker compose --profile restore up -d pitr-restore
```

## ตัวอย่างนโยบายสำรองข้อมูล

`scripts/scheduled-backup.sh` แสดงนโยบายง่าย ๆ:

| เวลา | Backup | Artefact |
| --- | --- | --- |
| ทุกวันอาทิตย์ | Logical full + globals + physical full | `backup_lab.dump`, `globals.sql`, `weekly-full/` |
| จันทร์–เสาร์ | Globals + physical incremental | `globals.sql`, `daily-<timestamp>/` |
| ต่อเนื่อง | WAL archiving | `archive/<WAL segment>` |

รันด้วยตนเอง:

```bash
bash scripts/scheduled-backup.sh
```

ตัวอย่าง cron เวลา 02:00 ตาม timezone ของเครื่อง:

```cron
0 2 * * * cd /absolute/path/to/labs/module07-backup-docker && bash scripts/scheduled-backup.sh >> artifacts/schedule.log 2>&1
```

ถ้ายังไม่มี weekly full สคริปต์จะ bootstrap ด้วย full ก่อน แม้วันนั้นไม่ใช่อาทิตย์ สคริปต์ schedule **ไม่สร้างหรือแก้ข้อมูล application**; ใน Lab ใช้คำสั่ง `change` แยกเพื่อจำลอง workload เท่านั้น

ระบบจริงควรกำหนด retention ให้สอดคล้องกับ RPO/RTO เช่น เก็บ weekly full 4 ชุด พร้อม incremental และ WAL ทุกไฟล์ที่ยังจำเป็นต่อ recovery window, copy ไป storage คนละ failure domain, เข้ารหัส, monitor failure และทำ restore drill สม่ำเสมอ Lab นี้ไม่ลบ backup เก่าอัตโนมัติเพื่อให้เห็น chain ครบ

## ดูไฟล์และสถานะ

```bash
make files
make status
docker compose ps
```

## หยุดและล้าง Lab

```bash
make stop   # หยุด แต่เก็บ containers/volumes/files
make down   # ลบ containers แต่เก็บ volumes/files
make clean  # ลบเฉพาะ containers, volumes, artefacts และ WAL ของ Lab นี้
```

`make clean` เป็น destructive cleanup และส่ง `--yes` ให้ runner ไว้แล้ว หากเรียก runner โดยตรงต้องใช้:

```bash
bash scripts/lab.sh clean --yes
```

## อ้างอิง

- [PostgreSQL 18 — SQL Dump](https://www.postgresql.org/docs/18/backup-dump.html)
- [PostgreSQL 18 — pg_dumpall](https://www.postgresql.org/docs/18/app-pg-dumpall.html)
- [PostgreSQL 18 — pg_basebackup](https://www.postgresql.org/docs/18/app-pgbasebackup.html)
- [PostgreSQL 18 — pg_combinebackup](https://www.postgresql.org/docs/18/app-pgcombinebackup.html)
- [PostgreSQL 18 — Continuous Archiving and PITR](https://www.postgresql.org/docs/18/continuous-archiving.html)
