# Module 7: กู้ลูกค้า กรมธรรม์ และเคลมที่เรียนมาตลอดคอร์ส

[กลับสารบัญ](README.md)

ทำบท 6 จนคืนค่า shared แล้ว ปิดทุก transaction/workload ของบทอื่น ใช้ customer/policy/claim 100,006 เคลมชุดเดิม **ไม่สร้าง recovery_event** ลำดับ 7.1 → 7.2 → 7.3 → 7.4 → 7.5 ต้องทำใน Bash เดิมและอ่านผลแต่ละขั้น

Logical archive เก็บสามตารางพร้อม identity sequences และ indexes ส่วนการนำข้อมูลกลับ shared ใช้ **data-only + TRUNCATE สามตารางใน transaction เดียว** เพื่อเก็บ claim_detail_v, claim_tax, review_claim และรายงานบท 3 ไว้ คืนตามลำดับ customer → policy → claim เพื่อให้แถวที่ FK อ้างถึงมีอยู่ก่อน ไม่มี DROP SCHEMA/--clean บน shared วิธีนี้เป็นแบบฝึกกู้ข้อมูลบน DDL เดิม ไม่ใช่การกู้ทั้ง schema เมื่อ DDL สูญหาย

บล็อก TRUNCATE กระทบข้อมูลทั้งสามตารางในฐานข้อมูลฝึกที่ระบุ จึงต้องใช้ archive ที่เพิ่งสร้างจาก own DB ในบทนี้เท่านั้น ถ้ามี FK จากงานอื่นอ้างเข้ามาแล้วคำสั่งหยุด ให้ตรวจขอบเขตกับอาจารย์ ไม่เติม CASCADE หรือปิด constraints เพื่อให้ผ่าน

## ลำดับแล็บในบทนี้

เลข `7.x` คือชุดแล็บ และตัวอักษรท้ายเลขคือขั้นตอนย่อย เช่น `7.1a` → `7.1b` ให้ทำตามลำดับและอ่านผลก่อนข้ามไปขั้นถัดไป

| ชุดแล็บ | เนื้อหา | ขั้นตอน |
| --- | --- | --- |
| 7.1 | เตรียมบัญชี, workspace, private server และ baseline | 7.1a–7.1e |
| 7.2 | Logical backup และ restore | 7.2a–7.2i |
| 7.3 | Cold backup และ restore | 7.3a–7.3e |
| 7.4 | Point-in-time recovery (PITR) | 7.4a–7.4h |
| 7.5 | คืน baseline และปิด private servers | 7.5a |
| 7.6 | ทางเลือกและการตรวจปัญหา | 7.6a–7.6b |

## 7.1 — เตรียมสภาพแวดล้อมและข้อมูลตั้งต้น

### 7.1a — เตรียมบัญชีและ PostgreSQL 18

รันใน Bash ของนักเรียน ไม่ใช้ sudo เปลี่ยน STUDENT_NO เป็นของตัวเอง ตรวจ server/client major version ให้ตรงกัน

```bash
umask 077
STUDENT_NO=xx                      # CHANGE to your own 01–20
case "$STUDENT_NO" in
  0[1-9]|1[0-9]|20) ;;
  *) printf 'Replace xx with your assigned number (01-20).\n' >&2; exit 1 ;;
esac
PG_BIN="${PG_BIN:-/usr/lib/postgresql/18/bin}"
export PATH="$PG_BIN:$PATH"
postgres --version                 # must be PostgreSQL 18
pg_dump --version
read -r -s -p "DB password for student_$STUDENT_NO: " PGPASSWORD
printf '\n'
export PGPASSWORD
```

### 7.1b — กำหนด connection และ workspace

array เก็บ connection flags ไม่ใช่ runner จด LAB path ที่พิมพ์ไว้ ใช้ Bash terminal นี้ตลอดบท

```bash
MAIN="claimsure_$STUDENT_NO"; STAGE="m7_stage_$STUDENT_NO"
SHARED_HOST="${LAB_DB_HOST:-127.0.0.1}"
SHARED_PORT="${M7_DB_PORT:-5432}"
LAB="$(mktemp -d "$HOME/case-m7.XXXXXXXX")"
PRIMARY="$LAB/primary"; SOCKET="$LAB/sock"; WAL="$LAB/wal"
BACKUPS="$LAB/backups"; SOURCE_PORT=$((5900 + 10#$STUDENT_NO))
RECOVERY_PORT=$((6000 + 10#$STUDENT_NO))
mkdir -p "$SOCKET" "$WAL" "$BACKUPS" "$LAB/recovery"
SHARED=(-h "$SHARED_HOST" -p "$SHARED_PORT" -U "student_$STUDENT_NO")
PRIVATE=(-h "$SOCKET" -p "$SOURCE_PORT" -U labadmin)
CORE_TABLES=(--table=claimsure.customer --table=claimsure.policy --table=claimsure.claim
 --table=claimsure.customer_customer_id_seq --table=claimsure.policy_policy_id_seq
 --table=claimsure.claim_claim_id_seq)
RECOVERED=(-h "$SOCKET" -p "$RECOVERY_PORT" -U labadmin)
printf 'SAVE this workspace path: %s\n' "$LAB"
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" -c '\conninfo'
```

### 7.1c — initdb และตั้ง private archive

แก้เฉพาะ config ใต้ PRIMARY ไม่มี TCP listener และ private socket อยู่ใน directory ของตัวเอง

```bash
initdb -D "$PRIMARY" -U labadmin --auth-local=trust --auth-host=reject \
  --encoding=UTF8 --locale=C
printf "\ninclude = 'manual-lab.conf'\n" >> "$PRIMARY/postgresql.conf"
cat > "$PRIMARY/manual-lab.conf" <<CONF
listen_addresses = ''
unix_socket_directories = '$SOCKET'
unix_socket_permissions = 0700
port = $SOURCE_PORT
timezone = 'Asia/Bangkok'
log_timezone = 'Asia/Bangkok'
shared_buffers = '32MB'
max_connections = 10
wal_level = replica
max_wal_senders = 4
archive_mode = on
archive_command = 'test ! -f $WAL/%f && cp %p $WAL/%f'
archive_timeout = '60s'
CONF
```

### 7.1d — เปิด source และตรวจ config

labadmin เป็น superuser เฉพาะ private instance ตรวจ config_file และ system_identifier ให้แน่ใจว่าคนละ server กับ shared

```bash
pg_ctl -D "$PRIMARY" -l "$LAB/primary.log" -w start
createdb "${PRIVATE[@]}" -T template0 "$STAGE"
psql -X -v ON_ERROR_STOP=1 "${PRIVATE[@]}" -d "$STAGE" <<'SQL'
SHOW config_file;
SELECT name,setting,context,sourcefile,pending_restart
FROM pg_settings WHERE name IN
 ('port','listen_addresses','wal_level','archive_mode','archive_command');
SELECT system_identifier FROM pg_control_system();
SQL
```

### 7.1e — ตรวจเคลมเดิมและบันทึก baseline

ต้องเห็น CLM-L1-002 ยอด 22000; ไม่มี CLM-L7-* และจำนวนรวม 100006 ถ้าไม่ตรงให้ตรวจบทก่อนหน้าแล้วบันทึกค่าจริงก่อนทดลอง:

```bash
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" <<'SQL'
SELECT current_database(),current_user;
SELECT count(*) AS claims,sum(estimated_amount) AS estimated_total FROM claimsure.claim;
SELECT claim_no,status,estimated_amount FROM claimsure.claim
WHERE claim_no LIKE 'CLM-L1-%' OR claim_no LIKE 'CLM-L7-%' ORDER BY claim_no;
SQL
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" -Atc \
 'SELECT count(*),sum(estimated_amount) FROM claimsure.claim;' > "$LAB/before-count-total.txt"
```
## 7.2 — Logical backup: ลบเคลมแล้วกู้ข้อมูล

### 7.2a — Logical archive ของตารางหลักจริง

```bash
pg_dump "${SHARED[@]}" -d "$MAIN" -Fc --no-owner --no-acl \
  "${CORE_TABLES[@]}" -f "$BACKUPS/a-logical.dump"
pg_restore --list "$BACKUPS/a-logical.dump"
```

ตรวจ TABLE DATA และ SEQUENCE SET ของ customer/policy/claim ส่วน schema/routines/report ไม่อยู่ใน archive ที่เลือกด้วย --table นี้ จึงสร้าง schema บน private ก่อน restore และใช้ DDL shared ที่มีอยู่ตอนคืนข้อมูล

ทำทีละขั้นใน Bash เดิมจาก 7.1a–7.2a อ่านผลก่อนรันบล็อกถัดไป ใช้ archive ที่สร้างใน 7.2a จากฐานข้อมูลของตัวเอง

### 7.2b — ตรวจข้อมูลก่อนลบ

ตรวจชื่อฐานข้อมูลและบัญชี ต้องพบ `CLM-L1-002` ยอด `22000` และจำนวนเคลมรวม `100006` ตาม baseline ใน 7.1e

```bash
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" \
 -c '\conninfo'
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" <<'SQL'
SELECT current_database(),current_user;
SELECT count(*) AS claims,sum(estimated_amount) AS estimated_total FROM claimsure.claim;
SELECT claim_no,status,estimated_amount FROM claimsure.claim
WHERE claim_no LIKE 'CLM-L1-%' OR claim_no LIKE 'CLM-L7-%' ORDER BY claim_no;
SQL
```

ถ้าข้อมูลไม่ตรง 7.1e หรือไม่ใช่ฐาน `claimsure_xx` ของตัวเอง ให้หยุดตรวจ ก่อนลบหรือกู้ข้อมูล

### 7.2c — ลบเคลมและ COMMIT

ลบเฉพาะ `CLM-L1-002` แล้วบันทึกการเปลี่ยนแปลง ต้องเห็น `DELETE 1` และ `COMMIT` หลังจากนี้ใช้ `ROLLBACK` เพื่อเอาแถวกลับไม่ได้

```bash
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" <<'SQL'
BEGIN;
DELETE FROM claimsure.claim WHERE claim_no='CLM-L1-002';
COMMIT;
SQL
```

### 7.2d — ตรวจผลหลังลบ ก่อน restore

เปิด connection ใหม่เพื่อยืนยันว่าการลบถูก COMMIT แล้ว ยังไม่รันคำสั่ง restore ในขั้นนี้

```bash
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" <<'SQL'
SELECT current_database(),current_user;
SELECT count(*) AS claims,sum(estimated_amount) AS estimated_total FROM claimsure.claim;
SELECT count(*) AS target_claims FROM claimsure.claim WHERE claim_no='CLM-L1-002';
SELECT claim_no,status,estimated_amount FROM claimsure.claim
WHERE claim_no LIKE 'CLM-L1-%' OR claim_no LIKE 'CLM-L7-%' ORDER BY claim_no;
SQL
```

ต้องเห็น `claims = 100005`, `target_claims = 0` และยอดรวมลดลง `22000` จาก 7.1e เคลม `CLM-L1-002` ต้องหายจากรายการ

### 7.2e — เตรียมไฟล์ข้อมูลจาก archive

สามคำสั่งต่อไปนี้ **เขียนไฟล์ SQL เท่านั้น ยังไม่เปลี่ยนข้อมูลในฐาน** ใช้ `--schema=claimsure` คู่กับชื่อตาราง และเลือก identity sequence ของแต่ละตารางด้วย รันทีละบล็อก ถ้าคำสั่งใด error ให้หยุดก่อน 7.2f

**ไฟล์ลูกค้า — customer**

```bash
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=customer --table=customer_customer_id_seq \
 --file="$LAB/a-logical-customer.sql" "$BACKUPS/a-logical.dump"
```

**ไฟล์กรมธรรม์ — policy**

```bash
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=policy --table=policy_policy_id_seq \
 --file="$LAB/a-logical-policy.sql" "$BACKUPS/a-logical.dump"
```

**ไฟล์เคลม — claim**

```bash
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=claim --table=claim_claim_id_seq \
 --file="$LAB/a-logical-claim.sql" "$BACKUPS/a-logical.dump"
```

### 7.2f — Restore ข้อมูลทั้งสามตาราง

ขั้นนี้แทนที่ข้อมูลทั้งสามตารางด้วยข้อมูลจาก 7.2a โดยเก็บ DDL, view และ routines เดิมไว้ หยุด workload อื่นก่อนรัน คืนลูกค้า → กรมธรรม์ → เคลม เพื่อให้แถวที่ foreign key อ้างถึงมีอยู่ก่อน

```bash
psql -X -1 -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" \
 -c 'TRUNCATE claimsure.claim, claimsure.policy, claimsure.customer;' \
 -f "$LAB/a-logical-customer.sql" \
 -f "$LAB/a-logical-policy.sql" \
 -f "$LAB/a-logical-claim.sql"
```

`-1` ครอบ `TRUNCATE` และไฟล์ทั้งสามใน transaction เดียว ถ้า SQL/FK error การเปลี่ยนข้อมูลตารางใน transaction นี้จะ rollback ให้แก้สาเหตุก่อนทำต่อ ไม่เติม `CASCADE` หรือปิด constraints

### 7.2g — ตรวจผลหลัง restore

เปิด connection ใหม่ ต้องได้จำนวนและยอดรวมเท่ากับ 7.1e พร้อมเคลมเดิมกลับมาครบ

```bash
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" <<'SQL'
SELECT current_database(),current_user;
SELECT count(*) AS claims,sum(estimated_amount) AS estimated_total FROM claimsure.claim;
SELECT count(*) AS target_claims FROM claimsure.claim WHERE claim_no='CLM-L1-002';
SELECT claim_no,status,estimated_amount FROM claimsure.claim
WHERE claim_no LIKE 'CLM-L1-%' OR claim_no LIKE 'CLM-L7-%' ORDER BY claim_no;
SQL
```

| ตรวจอะไร | ก่อนลบ | หลัง COMMIT ก่อน restore | หลัง restore |
| --- | --- | --- | --- |
| จำนวนเคลมรวม | 100006 | 100005 | 100006 |
| จำนวน `CLM-L1-002` | 1 | 0 | 1 |
| ยอด `CLM-L1-002` | 22000 | ไม่มีแถว | 22000 |
| ยอดรวมทุกเคลม | baseline จาก 7.1e | baseline − 22000 | เท่ากับ baseline |

### 7.2h — เทียบจำนวนและยอดรวมกับไฟล์ baseline

บันทึกผลหลังกู้ แล้วเทียบกับไฟล์ที่เก็บใน 7.1e

```bash
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" -Atc \
 'SELECT count(*),sum(estimated_amount) FROM claimsure.claim;' > "$LAB/after-logical-count-total.txt"
diff -u "$LAB/before-count-total.txt" "$LAB/after-logical-count-total.txt"
```

`diff` ไม่แสดงข้อความและ exit code เป็น `0` หมายถึงจำนวนและยอดรวมตรงกัน หากมีความต่าง ให้ตรวจผลก่อนเริ่มส่วน 7.3 ทั้งนี้ count/sum ตรงกันยังไม่พิสูจน์ว่าทุกแถวเหมือนกัน จึงต้องตรวจรายการเคลมใน 7.2g ร่วมด้วย Sequence values มากับ archive; sequence changes ไม่ rollback แบบข้อมูลตาราง และช่องว่างเลข ID หลัง rollback เป็นเรื่องปกติ

### 7.2i — หลักฐาน RPO/RTO

จดเวลาเริ่ม/จบและตรวจจำนวน/ยอด/เคลมเดิม ไม่สรุปจาก exit code อย่างเดียว บอกว่าข้อมูลหลังเวลา dump ไม่อยู่ใน archive; บัญชี/roles ระดับ cluster ก็ไม่อยู่ใน table dump นี้

## 7.3 — Cold backup: หยุด server แล้วสำเนาทั้ง cluster

### 7.3a — ส่งสามตารางเข้า private staging

ใช้ Bash และตัวแปรจาก 7.1a–7.1d หาก logout/login ใหม่ ให้คืนตัวแปรให้ชี้ workspace เดิมก่อน ตรวจว่า private server ยังรันอยู่:

```bash
pg_ctl -D "$PRIMARY" status
```

ถ้าแสดง `no server running` ให้ start cluster เดิม แล้วจึงทำ 7.3a ต่อ ไม่ต้องรัน `initdb` ใหม่:

```bash
pg_ctl -D "$PRIMARY" -l "$LAB/primary.log" -w start
```

```bash
pg_dump "${SHARED[@]}" -d "$MAIN" -Fc --no-owner --no-acl \
  "${CORE_TABLES[@]}" -f "$BACKUPS/c-stage.dump"
psql -X -v ON_ERROR_STOP=1 "${PRIVATE[@]}" -d "$STAGE" -c 'CREATE SCHEMA claimsure;'
pg_restore "${PRIVATE[@]}" -d "$STAGE" --single-transaction --exit-on-error \
 --no-owner --no-acl "$BACKUPS/c-stage.dump"
psql -X -v ON_ERROR_STOP=1 "${PRIVATE[@]}" -d "$STAGE" <<'SQL'
SELECT current_database(),current_user;
SELECT count(*) AS claims,sum(estimated_amount) AS estimated_total FROM claimsure.claim;
SELECT claim_no,status,estimated_amount FROM claimsure.claim
WHERE claim_no LIKE 'CLM-L1-%' OR claim_no LIKE 'CLM-L7-%' ORDER BY claim_no;
SQL
```

### 7.3b — หยุด private source แล้ว copy ทั้ง cluster

cold copy ทำขณะ server หยุดเท่านั้น ห้ามใช้ cp ของ source ที่ยังเขียนข้อมูลโดยถือว่า consistent snapshot checksum ต้องผ่าน

```bash
C_BACKUP="$BACKUPS/c-snapshot"
mkdir "$C_BACKUP"
pg_ctl -D "$PRIMARY" -m fast -w stop
cp -a "$PRIMARY" "$C_BACKUP/data"
pg_ctl -D "$PRIMARY" -l "$LAB/primary.log" -w start
(cd "$C_BACKUP"; find data -type f -print0 | sort -z | \
  xargs -0 sha256sum > SHA256SUMS)
(cd "$C_BACKUP"; sha256sum -c SHA256SUMS)
```

### 7.3c — สร้างความเสียหายหลัง snapshot บน shared

ลบเคลมเดิมและเพิ่มเคลม CLM-L7-LOSS ยอด 999 อ้างกรมธรรม์เดิม:

```bash
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" <<'SQL'
BEGIN;
DELETE FROM claimsure.claim WHERE claim_no='CLM-L1-002';
INSERT INTO claimsure.claim(claim_no,policy_id,status,incident_at,estimated_amount)
SELECT 'CLM-L7-LOSS',policy_id,'NEW',incident_at,999
FROM claimsure.claim WHERE claim_no='CLM-L1-001';
COMMIT;
SQL
C_RECOVERY="$LAB/recovery/c"
(cd "$C_BACKUP"; sha256sum -c SHA256SUMS)
cp -a "$C_BACKUP/data" "$C_RECOVERY"
```
### 7.3d — ตั้ง recovery socket/port ก่อน start

auto.conf ของ target override path/port ที่ copy มา และปิด archive ของ recovery; cold snapshot ไม่ต้องใช้ recovery.signal

```bash
cat > "$C_RECOVERY/postgresql.auto.conf" <<CONF
listen_addresses = ''
unix_socket_directories = '$SOCKET'
unix_socket_permissions = 0700
port = $RECOVERY_PORT
archive_mode = off
archive_command = ''
archive_library = ''
CONF
pg_ctl -D "$C_RECOVERY" -l "$LAB/c-recovery.log" -w start
psql -X -v ON_ERROR_STOP=1 "${RECOVERED[@]}" -d "$STAGE" \
  -c "SELECT pg_is_in_recovery(); SELECT claim_no FROM claimsure.claim WHERE claim_no IN ('CLM-L1-002','CLM-L7-LOSS');"
```

### 7.3e — คืนข้อมูลจาก recovery กลับ shared

Private cold recovery ต้องมี CLM-L1-002 และไม่มี CLM-L7-LOSS จึง export/import:

```bash
pg_dump "${RECOVERED[@]}" -d "$STAGE" -Fc --no-owner --no-acl \
  "${CORE_TABLES[@]}" -f "$BACKUPS/c-recovered.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=customer --table=customer_customer_id_seq \
 --file="$LAB/c-recovered-customer.sql" "$BACKUPS/c-recovered.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=policy --table=policy_policy_id_seq \
 --file="$LAB/c-recovered-policy.sql" "$BACKUPS/c-recovered.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=claim --table=claim_claim_id_seq \
 --file="$LAB/c-recovered-claim.sql" "$BACKUPS/c-recovered.dump"
psql -X -1 -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" \
 -c 'TRUNCATE claimsure.claim, claimsure.policy, claimsure.customer;' \
 -f "$LAB/c-recovered-customer.sql" -f "$LAB/c-recovered-policy.sql" -f "$LAB/c-recovered-claim.sql"
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" <<'SQL'
SELECT current_database(),current_user;
SELECT count(*) AS claims,sum(estimated_amount) AS estimated_total FROM claimsure.claim;
SELECT claim_no,status,estimated_amount FROM claimsure.claim
WHERE claim_no LIKE 'CLM-L1-%' OR claim_no LIKE 'CLM-L7-%' ORDER BY claim_no;
SQL
pg_ctl -D "$C_RECOVERY" -m fast -w stop
```
## 7.4 — PITR: กู้ข้อมูลถึง restore point

### 7.4a — คืน baseline, sync staging แล้วทำ physical base

```bash
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=customer --table=customer_customer_id_seq \
 --file="$LAB/a-logical-customer.sql" "$BACKUPS/a-logical.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=policy --table=policy_policy_id_seq \
 --file="$LAB/a-logical-policy.sql" "$BACKUPS/a-logical.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=claim --table=claim_claim_id_seq \
 --file="$LAB/a-logical-claim.sql" "$BACKUPS/a-logical.dump"
psql -X -1 -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" \
 -c 'TRUNCATE claimsure.claim, claimsure.policy, claimsure.customer;' \
 -f "$LAB/a-logical-customer.sql" -f "$LAB/a-logical-policy.sql" -f "$LAB/a-logical-claim.sql"
pg_dump "${SHARED[@]}" -d "$MAIN" -Fc --no-owner --no-acl \
  "${CORE_TABLES[@]}" -f "$BACKUPS/d-base-stage.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=customer --table=customer_customer_id_seq \
 --file="$LAB/d-base-stage-customer.sql" "$BACKUPS/d-base-stage.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=policy --table=policy_policy_id_seq \
 --file="$LAB/d-base-stage-policy.sql" "$BACKUPS/d-base-stage.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=claim --table=claim_claim_id_seq \
 --file="$LAB/d-base-stage-claim.sql" "$BACKUPS/d-base-stage.dump"
psql -X -1 -v ON_ERROR_STOP=1 "${PRIVATE[@]}" -d "$STAGE" \
 -c 'TRUNCATE claimsure.claim, claimsure.policy, claimsure.customer;' \
 -f "$LAB/d-base-stage-customer.sql" -f "$LAB/d-base-stage-policy.sql" -f "$LAB/d-base-stage-claim.sql"
D_BASE="${BACKUPS:?Restore BACKUPS from 7.1b first}/d-base"
mkdir "$D_BASE"
pg_basebackup "${PRIVATE[@]}" -D "$D_BASE/data" -Fp -Xs -c fast -P
pg_verifybackup "$D_BASE/data"
```
### 7.4b — เพิ่มเคลมหลัง base ก่อน restore point

ก่อนเริ่ม ตรวจตัวแปรและ physical base จาก 7.4a โดยใช้ workspace เดิม ถ้าเปิด Bash ใหม่ต้องคืนตัวแปรจาก 7.1a–7.1b ให้ครบโดยไม่สร้าง workspace ใหม่:

```bash
D_BASE="${BACKUPS:?Restore BACKUPS to the existing lab backups directory first}/d-base"
printf 'Physical base: %s\n' "$D_BASE"
test -f "$D_BASE/data/backup_manifest"
```

ถ้าไม่พบ `backup_manifest` ให้หยุดตรวจ path และผล 7.4a ก่อน ไม่สร้าง directory ว่างเพื่อข้ามขั้นตอน

แถวนี้ไม่มีใน physical base ต้องอาศัย WAL replay จึงจะกู้ได้:

```bash
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" <<'SQL'
INSERT INTO claimsure.claim(claim_no,policy_id,status,incident_at,estimated_amount)
SELECT 'CLM-L7-AFTER-BASE',policy_id,'NEW',incident_at,400
FROM claimsure.claim WHERE claim_no='CLM-L1-001';
SQL
pg_dump "${SHARED[@]}" -d "$MAIN" -Fc --no-owner --no-acl \
  "${CORE_TABLES[@]}" -f "$BACKUPS/d-point-stage.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=customer --table=customer_customer_id_seq \
 --file="$LAB/d-point-stage-customer.sql" "$BACKUPS/d-point-stage.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=policy --table=policy_policy_id_seq \
 --file="$LAB/d-point-stage-policy.sql" "$BACKUPS/d-point-stage.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=claim --table=claim_claim_id_seq \
 --file="$LAB/d-point-stage-claim.sql" "$BACKUPS/d-point-stage.dump"
psql -X -1 -v ON_ERROR_STOP=1 "${PRIVATE[@]}" -d "$STAGE" \
 -c 'TRUNCATE claimsure.claim, claimsure.policy, claimsure.customer;' \
 -f "$LAB/d-point-stage-customer.sql" -f "$LAB/d-point-stage-policy.sql" -f "$LAB/d-point-stage-claim.sql"
POINT="m7_${STUDENT_NO}_before_loss_$(date -u +%Y%m%dT%H%M%S)"
SEGMENT=$(psql -X -v ON_ERROR_STOP=1 "${PRIVATE[@]}" -d "$STAGE" -Atc \
 "SELECT pg_walfile_name(pg_create_restore_point('$POINT'));")
printf '%s\n' "${POINT:?Restore point was not created}" \
 > "${D_BASE:?Restore D_BASE from 7.4a first}/restore-point.name"
```

ถ้าคำสั่งบันทึกไฟล์เคยแจ้ง `-bash: /restore-point.name: Permission denied` แสดงว่า `$D_BASE` ว่างตอนรัน ให้คืน `BACKUPS` และ `D_BASE` จาก workspace เดิม ตรวจ `backup_manifest` แล้วรันเฉพาะคำสั่ง `printf` ด้านบนอีกครั้งโดยใช้ `$POINT` เดิม ไม่รัน `INSERT` ใน 7.4b ซ้ำ หาก `$POINT` หายด้วย ให้หยุดตรวจ restore point ที่สร้างไว้ก่อนทำ 7.4c ไม่ใช้ sudo หรือ chmod เพื่อเขียนที่ `/`

### 7.4c — switch WAL และตรวจไฟล์ archive จริง

SQL pg_switch_wal สำเร็จยังไม่พอ ต้อง test ไฟล์ SEGMENT ด้วย ถ้าเห็น STOP ให้หยุดแก้ก่อนบล็อกถัดไป

```bash
psql -X -v ON_ERROR_STOP=1 "${PRIVATE[@]}" -d "$STAGE" \
  -c 'SELECT pg_switch_wal();'
for attempt in {1..30}; do
  test -s "$WAL/$SEGMENT" && break
  sleep 1
done
test -s "$WAL/$SEGMENT" || { echo 'STOP: inspect primary.log'; false; }
TARGET_TIME=$(psql -X -v ON_ERROR_STOP=1 "${PRIVATE[@]}" -d "$STAGE" \
  -Atc 'SELECT clock_timestamp();')
printf '%s\n' "$TARGET_TIME" > "$D_BASE/restore-point.time"
ls -l "$WAL/$SEGMENT"
```

### 7.4d — บันทึกความเสียหายหลัง target ลง WAL

```bash
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" <<'SQL'
BEGIN;
DELETE FROM claimsure.claim WHERE claim_no='CLM-L1-002';
INSERT INTO claimsure.claim(claim_no,policy_id,status,incident_at,estimated_amount)
SELECT 'CLM-L7-LOSS',policy_id,'NEW',incident_at,999
FROM claimsure.claim WHERE claim_no='CLM-L1-001';
COMMIT;
SQL
pg_dump "${SHARED[@]}" -d "$MAIN" -Fc --no-owner --no-acl \
  "${CORE_TABLES[@]}" -f "$BACKUPS/d-after-loss.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=customer --table=customer_customer_id_seq \
 --file="$LAB/d-after-loss-customer.sql" "$BACKUPS/d-after-loss.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=policy --table=policy_policy_id_seq \
 --file="$LAB/d-after-loss-policy.sql" "$BACKUPS/d-after-loss.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=claim --table=claim_claim_id_seq \
 --file="$LAB/d-after-loss-claim.sql" "$BACKUPS/d-after-loss.dump"
psql -X -1 -v ON_ERROR_STOP=1 "${PRIVATE[@]}" -d "$STAGE" \
 -c 'TRUNCATE claimsure.claim, claimsure.policy, claimsure.customer;' \
 -f "$LAB/d-after-loss-customer.sql" -f "$LAB/d-after-loss-policy.sql" -f "$LAB/d-after-loss-claim.sql"
SEGMENT=$(psql -X -v ON_ERROR_STOP=1 "${PRIVATE[@]}" -d "$STAGE" -Atc \
 'SELECT pg_walfile_name(pg_current_wal_insert_lsn());')
```
### 7.4e — ยืนยันว่า archive ไปไกลกว่า target

archive ต้องมี segment ที่ไปไกลกว่า target ดู pg_stat_archiver และรักษา base/WAL ให้ครบคู่กัน

```bash
psql -X -v ON_ERROR_STOP=1 "${PRIVATE[@]}" -d "$STAGE" \
  -c 'SELECT pg_switch_wal();'
for attempt in {1..30}; do
  test -s "$WAL/$SEGMENT" && break
  sleep 1
done
test -s "$WAL/$SEGMENT" || { echo 'STOP: archive incomplete'; false; }
psql -X -v ON_ERROR_STOP=1 "${PRIVATE[@]}" -d "$STAGE" \
  -c 'SELECT archived_count,last_archived_wal,failed_count,last_failed_wal FROM pg_stat_archiver;'
pg_verifybackup "$D_BASE/data"
D_RECOVERY="$LAB/recovery/d"
cp -a "$D_BASE/data" "$D_RECOVERY"
```

### 7.4f — เขียน target และ recovery.signal ก่อน start

แก้เฉพาะ D_RECOVERY สร้าง recovery.signal ก่อน start และเลือก target name ที่บันทึกไว้เพียงค่าเดียว

```bash
cat > "$D_RECOVERY/postgresql.auto.conf" <<CONF
listen_addresses = ''
unix_socket_directories = '$SOCKET'
unix_socket_permissions = 0700
port = $RECOVERY_PORT
archive_mode = off
archive_command = ''
archive_library = ''
hot_standby = on
restore_command = 'cp $WAL/%f %p'
recovery_target_name = '$POINT'
recovery_target_timeline = 'current'
recovery_target_action = 'pause'
CONF
touch "$D_RECOVERY/recovery.signal"
pg_ctl -D "$D_RECOVERY" -l "$LAB/d-recovery.log" -w start
```

### 7.4g — รอ replay paused และตรวจ เคลมก่อนความเสียหาย

connect ได้อย่างเดียวไม่พอ ต้อง in recovery=true, paused และ CLM-L1-002 และ CLM-L7-AFTER-BASE โดยไม่มี CLM-L7-LOSS จึงไปขั้น import

```bash
PAUSED=f
for attempt in {1..30}; do
  PAUSED=$(psql -X -v ON_ERROR_STOP=1 "${RECOVERED[@]}" -d "$STAGE" -Atc \
    "SELECT pg_get_wal_replay_pause_state()='paused';")
  test "$PAUSED" = t && break
  sleep 1
done
test "$PAUSED" = t || { echo 'STOP: inspect d-recovery.log'; false; }
psql -X -v ON_ERROR_STOP=1 "${RECOVERED[@]}" -d "$STAGE" -c \
 'SELECT pg_is_in_recovery(),pg_get_wal_replay_pause_state(),pg_last_xact_replay_timestamp();'
psql -X -v ON_ERROR_STOP=1 "${RECOVERED[@]}" -d "$STAGE" \
 -c "SELECT claim_no,estimated_amount FROM claimsure.claim WHERE claim_no IN ('CLM-L1-002','CLM-L7-AFTER-BASE','CLM-L7-LOSS') ORDER BY claim_no;"
```

### 7.4h — Import recovered data กลับตารางเดิมบน shared

ต้อง in recovery=true, paused และตรวจ CLM-L1-002/CLM-L7-AFTER-BASE มีทั้งคู่ ส่วน CLM-L7-LOSS ไม่มี จึงทำต่อ:

```bash
pg_dump "${RECOVERED[@]}" -d "$STAGE" -Fc --no-owner --no-acl \
  "${CORE_TABLES[@]}" -f "$BACKUPS/d-recovered.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=customer --table=customer_customer_id_seq \
 --file="$LAB/d-recovered-customer.sql" "$BACKUPS/d-recovered.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=policy --table=policy_policy_id_seq \
 --file="$LAB/d-recovered-policy.sql" "$BACKUPS/d-recovered.dump"
pg_restore --data-only --no-owner --no-acl --schema=claimsure \
 --table=claim --table=claim_claim_id_seq \
 --file="$LAB/d-recovered-claim.sql" "$BACKUPS/d-recovered.dump"
psql -X -1 -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" \
 -c 'TRUNCATE claimsure.claim, claimsure.policy, claimsure.customer;' \
 -f "$LAB/d-recovered-customer.sql" -f "$LAB/d-recovered-policy.sql" -f "$LAB/d-recovered-claim.sql"
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" <<'SQL'
SELECT current_database(),current_user;
SELECT count(*) AS claims,sum(estimated_amount) AS estimated_total FROM claimsure.claim;
SELECT claim_no,status,estimated_amount FROM claimsure.claim
WHERE claim_no LIKE 'CLM-L1-%' OR claim_no LIKE 'CLM-L7-%' ORDER BY claim_no;
SQL
```

ต้องมี 100007 เคลม ยอดรวมเท่ากับ baseline +400 แถวหลัง base กู้กลับมาด้วย WAL ไม่ได้เพียง copy base กลับ

## 7.5 — ตรวจผลและคืนข้อมูลสำหรับบทถัดไป

### 7.5a — เก็บหลักฐาน แล้วคืนเคลมชุดเดิมให้บท 9

หลังบันทึกผล recovery แล้ว ลบเฉพาะเคลมสาธิตหลัง base และ refresh ผลสรุป:

```bash
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" <<'SQL'
DELETE FROM claimsure.claim WHERE claim_no='CLM-L7-AFTER-BASE';
REFRESH MATERIALIZED VIEW claimsure.cs_monthly_claim_summary;
SELECT count(*) AS expected_6 FROM claimsure.claim_detail_v WHERE claim_no LIKE 'CLM-L1-%';
SELECT claimsure.claim_tax(15000,NULL) AS expected_1050;
SQL
psql -X -v ON_ERROR_STOP=1 "${SHARED[@]}" -d "$MAIN" -Atc \
 'SELECT count(*),sum(estimated_amount) FROM claimsure.claim;' > "$LAB/after-count-total.txt"
cmp "$LAB/before-count-total.txt" "$LAB/after-count-total.txt"
pg_ctl -D "$D_RECOVERY" -m fast -w stop
pg_ctl -D "$PRIMARY" -m fast -w stop
printf 'Retained evidence: %s\n' "$LAB"
```

cmp ต้องไม่ต่าง จำนวนรวมกลับ 100006 และ routines/view เดิมยังใช้ได้ ไม่ลบ customer/policy/claim หรือ private archives ที่ยังต้องใช้ หากจบ Bash นี้ค่อย unset PGPASSWORD; หากทำบท 9 ต่อใช้ environment README ที่อ่านรหัสผ่านใหม่ได้

## 7.6 — ทางเลือกและการตรวจปัญหา

ส่วนนี้เป็นข้อมูลเสริม ใช้เมื่อต้องการทดลองเพิ่มหรือตรวจข้อผิดพลาด

### 7.6a — ใช้ timestamp แทน named restore point

TARGET_TIME บันทึกหลัง named point และก่อนความเสียหาย หากทดลอง timestamp ให้ copy base ต้นฉบับไป target directory ใหม่ ใช้ recovery_target_time แทน recovery_target_name เพียงค่าเดียว และตรวจ paused/สองเคลม/ไม่มี LOSS ใหม่อีกครั้ง Flow หลักนี้ใช้ named target

### 7.6b — ตรวจ archive, replay และ foreign key

หาก archive ไม่ครบให้ตรวจ primary.log, pg_stat_archiver และไฟล์ SEGMENT; ถ้า paused ไม่ถึงให้ตรวจ target name และ base-before-target; ถ้า restore ผิด FK ให้ตรวจว่ากำลังกู้สามตารางชุดเดียวกันบน DDL เดิม ไม่ข้าม error หรือเพิ่ม CASCADE

อ้างอิง: [pg_dump](https://www.postgresql.org/docs/18/app-pgdump.html), [pg_restore](https://www.postgresql.org/docs/18/app-pgrestore.html), [PITR](https://www.postgresql.org/docs/18/continuous-archiving.html)
