# Module 9: Monitoring — workload, blocking, deadlock บนสัญญาณที่ Grafana อ่าน

[กลับสารบัญ](README.md)

ต่อจากบท 7 ที่กู้ customer/policy/claim แล้ว บทนี้ไม่แก้เคลมจริง ไม่สร้าง monitor_queue ใน schema claimsure และไม่ ROLLBACK ยอดเงินของ CLM-L1 เพื่อเก็บข้อมูลไว้ให้บท 10 งานทดลองอยู่ที่ schema **lab_m9_shell** ซึ่งเป็น fixture ชุดเดียวกับ [Grafana lab ของห้องเรียน](references/cheat-sheets/module-09-grafana-lab.md)

Stack ของเครื่องนี้คือ PostgreSQL 18, postgres_exporter **v0.20.1**, Prometheus และ Grafana **11.5.2** นักเรียนใช้ฐาน **claimsure_xx** ของตนบนพอร์ต **5432** และรหัส Grafana ที่อาจารย์กำหนดให้บัญชีนั้น พอร์ตที่ใช้คือ Grafana **3000** และ Prometheus ที่ฟังเฉพาะ **127.0.0.1:9090** บนเครื่องเซิร์ฟเวอร์ พอร์ต 13000, 19090, 19187 และรหัส `admin / Grafana18` เป็นค่าจากสไลด์เก่า

Collector ที่ provision แล้วมองเห็นเฉพาะสามอย่างนี้

- เซสชันของ role ตนที่ `application_name` ขึ้นต้น `module09_xx_` เช่น `module09_xx_holder` เมื่อฐานคือ claimsure_xx
- ตาราง `lab_m9_shell.workload`, `queue`, `lock_demo`
- คำสั่งใน `pg_stat_statements` ที่มีข้อความ `lab_m9_shell`

ใช้สาม Terminal ของนักเรียนเดียวกัน A/B เป็นผู้ทำงาน C เป็นผู้สังเกต เชื่อมตรงฐานของตน ไม่ reset statistics ทั้งฐาน ไม่ terminate backend ของคนอื่น และไม่รัน `module09-workload.sh` พร้อมกับ pgbench ในบทนี้ เพราะจะเพิ่ม client ชุดที่สองบน role เดียวกัน

## ก่อนเริ่ม — อาจารย์เตรียม pipeline ครั้งเดียว

นักเรียนข้ามบล็อกนี้ อาจารย์ที่มี Docker และไฟล์ `.env` ของ stack เดิมรันบนเครื่องเซิร์ฟเวอร์ สคริปต์ไม่มีรหัสผ่าน ไม่ใช้ bootstrap ทั้งห้องเพราะสคริปต์นั้นจัดการรหัสบัญชีนักเรียนด้วย

```bash
cd /opt/setup-postgres-labs
./scripts/module09-stack.sh init-all --dry-run
./scripts/module09-stack.sh init-all
./scripts/module09-stack.sh check
```

สำเนาในรีโปอยู่ที่ `/opt/postgres-admin-labs/scripts/shells` ตัวแปร `M9_STACK_ROOT` เลือก root อื่นเมื่อ stack ไม่อยู่ที่ path นี้

`init-all` ซ่อม login อ่านอย่างเดียว `claim_monitor`, ให้ `pg_monitor` พร้อม CONNECT/statistics ครบ 20 ฐานหลัก, ตรวจหรือสร้าง extension `pg_stat_statements` ที่ preload ไว้แล้ว, ใส่ collector ของบท 9 และ provision แดชบอร์ด มันสตาร์ท Grafana/Prometheus ถ้าบริการหยุดอยู่ และสร้าง **เฉพาะ postgres-exporter** ใหม่เพื่อโหลด custom collector ไม่ restart PostgreSQL ไม่ลบ volume ของ Prometheus/Grafana ไม่สร้างบัญชีนักเรียนใหม่ และไม่เปลี่ยนรหัสนักเรียน ถ้า preload ยังไม่มี รายงานนั้นเป็นงานอาจารย์แยกต่างหาก

| ไฟล์ | หน้าที่ |
| --- | --- |
| `/opt/setup-postgres-labs/config/prometheus.yml` | job `postgres`, 20 target, scrape ทุก 30 วินาที |
| `config/module09-exporter-queries.yaml` | เซสชันที่ติดแท็ก, capacity, ประมาณการตาราง, query ID |
| `config/module09-monitoring.override.yaml` | เพิ่มแฟล็กและ mount ของ collector บน exporter เดิม |
| `config/grafana/dashboards/claimsure-module09.json` | แดชบอร์ด UID คงที่ `claimsure-module09` |
| `module09-grafana-import.json` | ไฟล์นำเข้าทาง UI, UID ว่าง เพื่อสร้างสำเนาใหม่ |

แฟล็ก custom query ใช้ได้กับ exporter รุ่นที่ปักไว้ และถูก mark deprecated ที่ upstream ให้ทดสอบ collector นี้อีกครั้งก่อนอัปเกรด exporter Collector ปริยายยังเปิดอยู่ ไม่ใส่ค่าลูกค้าหรือข้อความ SQL เป็น Prometheus label

## เปิด Grafana ก่อนลงมือ

บนแล็ปท็อปเปิด `http://<SERVER_IP>:3000` แล้วล็อกอินด้วยรหัส Grafana ของตน

1. เปิด **Dashboards → ClaimSure → Module 9 - Student PostgreSQL Monitoring** หรือ URL `http://<SERVER_IP>:3000/d/claimsure-module09`
2. เลือก datasource **Prometheus** และ **Your student database = claimsure_xx** ของตน ตัวเลือกนี้เลือกชุดที่แดชบอร์ดกลางแสดง ทั้งห้องเห็นรายชื่อฐานเดียวกัน
3. ตั้งช่วงเวลา **Last 15 minutes** และ refresh **10 วินาที**
4. อ่านสามแผงสุขภาพ: **1. Exporter HTTP scrape UP = 1**, **2. PostgreSQL connection healthy = 1**, **3. Exporter scrape error = 0**

`up=1` หมายถึง Prometheus ดึง HTTP จาก exporter ได้ ยังไม่พิสูจน์ว่า login ฐานผ่าน อาการเดิมของเครื่องนี้คือไม่มี role `claim_monitor` จึงได้ `up=1` พร้อม `pg_up=0` แผงที่ 2 ต้องเป็น 1 ด้วย ถ้าทั้งสามค่าไม่ใช่ 1 / 1 / 0 ให้หยุดแล้วให้อาจารย์รัน `init-all` ด้านบน การนำเข้า JSON ไม่ได้ติดตั้ง collector

แดชบอร์ดนี้ใช้ datasource Prometheus เท่านั้น ไม่มี datasource PostgreSQL ชื่อ ClaimSure ไม่มี standby, Alertmanager, node_exporter หรือ exporter p99 ของแอปพลิเคชัน แผงเหล่านั้นไม่อยู่ในแล็บนี้

บัญชีนักเรียนที่เป็น Editor จะนำเข้าสำเนาของตนได้ บัญชี Viewer ใช้แดชบอร์ดที่ provision แล้ว หรือให้อาจารย์นำเข้าให้ สิทธิ์ในฐานข้อมูลไม่เปลี่ยนบทบาท Grafana บนแล็ปท็อป:

```bash
scp studentxx@SERVER_IP:scripts/module09-grafana-import.json .
```

เปลี่ยน `studentxx` และ `SERVER_IP` เป็นของตน สำเนาอีกที่อยู่ที่ `/opt/postgres-admin-labs/scripts/shells/module09-grafana-import.json`

1. **Dashboards → New → Import**
2. **Upload dashboard JSON file** แล้วเลือก `module09-grafana-import.json`
3. ตั้งชื่อเฉพาะ เช่น `Module 9 - Student xx` เลือกโฟลเดอร์ที่แก้ได้ ปล่อย UID ว่างเพื่อไม่เขียนทับแดชบอร์ด UID `claimsure-module09`
4. กด **Import** แล้วเลือก datasource **Prometheus** กับ `claimsure_xx` ของตน
5. ตรวจสามแผงสุขภาพอีกครั้ง ถ้าแผงขึ้น error ให้เปิดเมนูแผง → **Inspect → Query**

ไฟล์ JSON มีตัวแปร datasource/database และไม่มีรหัสผ่าน

Prometheus ฟังที่ localhost **9090** ของเซิร์ฟเวอร์ exporter ไม่ได้เผยพอร์ตออกนอก Docker เทอร์มินัลที่ SSH อยู่บนเครื่องเซิร์ฟเวอร์เรียก `127.0.0.1:9090` ได้ตรง ๆ จะเปิด UI จากแล็ปท็อปให้ทำอุโมงค์แยกต่างหาก แล้วเปิด `http://127.0.0.1:9090/targets` งานคือ **postgres** และ instance เป็น `postgres:5432/claimsure_xx` ไม่ใช่ `job="postgres-exporter"` Grafana ไปถึง Prometheus ผ่านเครือข่าย Docker อยู่แล้ว จึงไม่ต้องมีอุโมงค์เพื่อดูแดชบอร์ด

```bash
ssh -L 9090:127.0.0.1:9090 studentxx@SERVER_IP
```

Scrape ทุก **30 วินาที** การกด refresh ทุก 10 วินาทีไม่ทำให้เก็บถี่ขึ้น แผงที่เป็น `rate()` ต้องมีตัวอย่างใหม่อย่างน้อยสองครั้ง จึงรอ **60–90 วินาที** หลังมีกิจกรรม

## 9A — Session A: ตรวจเคลมเดิม แล้วสร้าง fixture ที่ collector อ่าน

**Bash A** หลังตั้ง environment ตาม README ชื่อแอปต้องตรงกับเลขท้ายสองหลักของฐานข้อมูล เพราะ collector ใช้ `right(current_database(), 2)`

```bash
STUDENT_NO="${PGDATABASE##*_}"
case "$STUDENT_NO" in
  0[1-9]|1[0-9]|20) ;;
  *) printf 'Replace xx with your assigned number (01-20); expected claimsure_xx\n' >&2; exit 1 ;;
esac
export PGAPPNAME="module09_${STUDENT_NO}_holder"
psql -X -v ON_ERROR_STOP=1
```

**psql A** บล็อกนี้สร้างหรือเติม schema ที่มีเครื่องหมาย `module09-shell-v1` ซ้ำได้ ถ้า schema ชื่อนี้มีอยู่แล้วแต่ไม่มีเครื่องหมาย จะหยุดเพื่อไม่เขียนทับของคนอื่น แถว workload 20,000 แถวและคิว 1,000 แถวเป็นค่าเดียวกับ `module09-init-all.sh`

```sql
\pset pager off
\set VERBOSITY verbose
SELECT count(*) AS expected_100006 FROM claimsure.claim;
SELECT claim_no,status,estimated_amount FROM claimsure.claim
WHERE claim_no IN ('CLM-L1-001','CLM-L1-002') ORDER BY claim_no;
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $$
BEGIN
 IF current_setting('server_version_num')::int<180000 OR pg_is_in_recovery() THEN
  RAISE EXCEPTION 'Use a PostgreSQL 18+ primary';
 END IF;
 IF to_regnamespace('lab_m9_shell') IS NOT NULL AND to_regclass('lab_m9_shell.module_identity') IS NULL THEN
  RAISE EXCEPTION 'Existing lab_m9_shell has no Module 9 marker; preserving it';
 END IF;
 IF to_regnamespace('lab_m9_shell') IS NOT NULL THEN
  IF (SELECT nspowner FROM pg_namespace WHERE nspname='lab_m9_shell')<>(SELECT oid FROM pg_roles WHERE rolname=current_user) THEN
   RAISE EXCEPTION 'Module 9 schema belongs to another role';
  END IF;
  IF (SELECT identity FROM lab_m9_shell.module_identity WHERE id=1) IS DISTINCT FROM 'module09-shell-v1' THEN
   RAISE EXCEPTION 'Invalid Module 9 schema marker';
  END IF;
 END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS lab_m9_shell;
CREATE TABLE IF NOT EXISTS lab_m9_shell.module_identity(
 id int PRIMARY KEY CHECK(id=1), identity text NOT NULL CHECK(identity='module09-shell-v1')
);
INSERT INTO lab_m9_shell.module_identity VALUES (1,'module09-shell-v1') ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS lab_m9_shell.lock_demo(id int PRIMARY KEY,note text NOT NULL);
CREATE TABLE IF NOT EXISTS lab_m9_shell.workload(id int PRIMARY KEY,bucket int,amount numeric(12,2),payload text);
CREATE TABLE IF NOT EXISTS lab_m9_shell.queue(id int PRIMARY KEY,touches int NOT NULL DEFAULT 0);
TRUNCATE lab_m9_shell.lock_demo,lab_m9_shell.workload,lab_m9_shell.queue;
INSERT INTO lab_m9_shell.lock_demo VALUES(1,'ready'),(2,'ready');
INSERT INTO lab_m9_shell.workload
SELECT g,g%100,(g%50000)::numeric,repeat(md5(g::text),3) FROM generate_series(1,20000) g;
INSERT INTO lab_m9_shell.queue SELECT g,0 FROM generate_series(1,1000) g;
ANALYZE lab_m9_shell.workload;
ANALYZE lab_m9_shell.queue;
COMMIT;
SELECT current_database() AS database,current_user AS login,
       right(current_database(),2) AS student_no,
       (SELECT count(*) FROM lab_m9_shell.workload) AS workload_rows,
       (SELECT identity FROM lab_m9_shell.module_identity WHERE id=1) AS marker;
```

ต้องได้ `workload_rows=20000` และ `marker=module09-shell-v1` ยอด CLM-L1-001 / CLM-L1-002 ยังเป็น 15000 / 22000

## 9B — Session C: อ่านเซสชันที่ติดแท็ก

**Bash C:**

```bash
STUDENT_NO="${PGDATABASE##*_}"
case "$STUDENT_NO" in
  0[1-9]|1[0-9]|20) ;;
  *) printf 'Replace xx with your assigned number (01-20); expected claimsure_xx\n' >&2; exit 1 ;;
esac
export PGAPPNAME="module09_${STUDENT_NO}_observer"
psql -X -v ON_ERROR_STOP=1
```

**psql C** รัน SELECT นี้ซ้ำระหว่างแต่ละการทดลอง หรือเติม `\watch 1` แล้วกด Ctrl+C เพื่อหยุด เซสชันผู้สังเกตนี้ถูกนับในแผง **Tagged Module 9 sessions** ด้วย เพราะชื่อขึ้นต้น `module09_xx_`

```sql
\pset pager off
SELECT pid,application_name,state,wait_event_type,wait_event,
       round(extract(epoch FROM clock_timestamp()-xact_start)::numeric,2) AS transaction_seconds,
       pg_blocking_pids(pid) AS blockers,left(query,100) AS query
FROM pg_stat_activity
WHERE datname=current_database() AND usename=current_user
  AND starts_with(application_name,'module09_'||right(current_database(),2)||'_')
  AND pid<>pg_backend_pid()
ORDER BY pid;
```

`state=active` ไม่ได้หมายความว่าใช้ CPU เสมอไป ถ้า `wait_event_type=Lock` แปลว่ากำลังรอ lock ส่วน `idle in transaction` คือ connection ที่ยังมี transaction ค้าง แผง **Oldest Module 9 transaction** และ **Module 9 sessions by state** อ่านค่าชุดนี้หลัง scrape ถัดไป

## 9C — Bash A: workload 120 วินาทีบนตารางแล็บ

ออก psql A ด้วย `\q` ก่อน ช่วง 120 วินาทีครอบคลุม scrape 30 วินาทีอย่างน้อยสองครั้ง จึงพอให้แผง `rate()` มีตัวอย่าง เปิดแดชบอร์ดค้างไว้ระหว่างคำสั่งนี้ทำงาน

```bash
STUDENT_NO="${PGDATABASE##*_}"
case "$STUDENT_NO" in
  0[1-9]|1[0-9]|20) ;;
  *) printf 'Replace xx with your assigned number (01-20); expected claimsure_xx\n' >&2; exit 1 ;;
esac
mkdir -p "$HOME/case-labs"
cat > "$HOME/case-labs/m9-workload.sql" <<'SQL'
\set bucket random(0, 99)
\set q random(1, 900)
BEGIN;
SELECT sum(amount) FROM lab_m9_shell.workload WHERE bucket=:bucket;
UPDATE lab_m9_shell.queue SET touches=touches+1 WHERE id BETWEEN :q AND (:q + 9);
COMMIT;
SQL
PGAPPNAME="module09_${STUDENT_NO}_workload" pgbench -n -c 2 -j 1 -T 120 -P 10 -f "$HOME/case-labs/m9-workload.sql"
```

นี่คือ native pgbench สอง client ตามค่าปริยายของ `module09-workload.sh` อ่านไฟล์ SQL ที่เพิ่งเขียน ไม่ใช่ shell runner ของบทนี้ ระหว่างรันให้ดู Session C และแผง **Tagged Module 9 sessions**, **Module 9 SQL calls per second**, **Database transactions per second** และ **Top lab SQL by recent execution time** เมื่อจบ pgbench พิมพ์จำนวน transaction กับ latency ของรอบนี้ ไม่ใช้ TPS ของเครื่องเรียนเป็นค่ารับประกัน production

client สองตัวอาจชน lock กันสั้น ๆ ใช้ PID ใน Session C แยกเหตุนั้นออกจาก holder ของขั้น 9D แถวคิวถูก COMMIT จริงใน `lab_m9_shell` เท่านั้น temp bytes เป็นศูนย์ได้ถ้าไม่มี spill แผง **Database temp bytes per second** ที่เป็นศูนย์เป็นผลที่รับได้ แผงเวลาของ query ID คือวินาทีของการทำงานต่อวินาที ไม่ใช่ mean latency หรือ p99

**psql C:**

```sql
SELECT sum(touches) AS committed_queue_touches FROM lab_m9_shell.queue;
SELECT count(*) AS expected_100006 FROM claimsure.claim;
SELECT claim_no,estimated_amount FROM claimsure.claim
WHERE claim_no IN ('CLM-L1-001','CLM-L1-002') ORDER BY claim_no;
SELECT datname,numbackends,xact_commit,xact_rollback,deadlocks,temp_files,temp_bytes
FROM pg_stat_database WHERE datname=current_database();
SELECT relname,n_live_tup,n_dead_tup FROM pg_stat_user_tables
WHERE schemaname='lab_m9_shell' ORDER BY relname;
```

`committed_queue_touches` ต้องมากกว่า 0 ยอดสองเคลมยังเป็น 15000 / 22000 counter ของ `pg_stat_database` เป็นระดับฐานข้อมูล ให้จดก่อน/หลังเมื่ออ่านค่าเพิ่ม แผง **Lab estimated dead tuples** เป็นค่าประมาณ และ autovacuum ทำให้ลดลงได้ ไม่สั่ง `pg_stat_statements_reset` และไม่ล้าง statistics

## 9D — สร้าง blocking แล้วเทียบ PID กับแผง Grafana

เปิด psql A อีกครั้งด้วยชื่อ holder แล้วเปิด **Bash B** ถ้า workload ของ 9C จบแล้ว ภาพ blocking จะไม่ปนกับ client ของ pgbench

```bash
STUDENT_NO="${PGDATABASE##*_}"
case "$STUDENT_NO" in
  0[1-9]|1[0-9]|20) ;;
  *) printf 'Replace xx with your assigned number (01-20); expected claimsure_xx\n' >&2; exit 1 ;;
esac
export PGAPPNAME="module09_${STUDENT_NO}_holder"
psql -X -v ON_ERROR_STOP=1
```

```bash
STUDENT_NO="${PGDATABASE##*_}"
case "$STUDENT_NO" in
  0[1-9]|1[0-9]|20) ;;
  *) printf 'Replace xx with your assigned number (01-20); expected claimsure_xx\n' >&2; exit 1 ;;
esac
export PGAPPNAME="module09_${STUDENT_NO}_waiter"
psql -X -v ON_ERROR_STOP=1
```

**psql A** ถือแถวที่ 1 ของตารางแล็บค้างไว้

```sql
BEGIN;
UPDATE lab_m9_shell.lock_demo SET note='held by module 9' WHERE id=1;
```

**psql B** UPDATE จะค้าง ปล่อยค้างไว้ 60–90 วินาทีเพื่อให้ scrape สองรอบเห็นค่า แล้วค่อยไปอ่าน C `lock_timeout` 180 วินาทีกันคำสั่งนี้ถูกยกเลิกก่อนดูกราฟ

```sql
BEGIN;
SET LOCAL lock_timeout='180s';
UPDATE lab_m9_shell.lock_demo SET note='waiter completed' WHERE id=1;
```

**psql C:**

```sql
SELECT b.pid AS blocked_pid,h.pid AS blocker_pid,
       b.application_name AS blocked_application,
       h.application_name AS blocker_application,
       b.wait_event_type,b.wait_event
FROM pg_stat_activity b
CROSS JOIN LATERAL unnest(pg_blocking_pids(b.pid)) x(pid)
JOIN pg_stat_activity h ON h.pid=x.pid
WHERE b.datname=current_database() AND b.usename=current_user
  AND starts_with(b.application_name,'module09_'||right(current_database(),2)||'_');
```

ต้องเห็น waiter รอ holder ชื่อแอปเป็น `module09_xx_waiter` และ `module09_xx_holder` ระหว่างที่ B ยังค้าง แผง **Blocked Module 9 clients** อย่างน้อย 1, **Oldest blocked query** และ **Oldest Module 9 transaction** เพิ่ม และมี **idle in transaction** ระหว่างที่ A ไม่ได้ส่งคำสั่งใหม่ บันทึกเวลาที่เห็นบนกราฟไว้กับผล SQL

จากนั้น **A** `ROLLBACK;` จะปล่อย lock **B** จึงจบ แล้ว B ต้อง `ROLLBACK;` ด้วย แถว `lock_demo` กลับเป็น `ready` หลัง scrape ถัดไปแผง blocked ลงสู่ 0 จุดเก่าบนกราฟยังอยู่ ถ้า B timeout ก่อนดูผล ให้ `ROLLBACK` ที่ B แล้วเริ่มขั้นนี้ใหม่

บทเรียนฝั่ง production คือระบุเจ้าของ lock และเก็บหลักฐานก่อนยกเลิกงาน การ ROLLBACK ในแล็บนี้ใช้กับเซสชันแล็บที่รู้ชื่อเท่านั้น

## 9E — สร้าง deadlock ด้วย lock คนละแถว

เริ่มเมื่อ A และ B จบ transaction จาก 9D แล้ว ขั้นนี้มี error ที่ตั้งใจไว้ จึงเปิด VERBOSITY และปิด ON_ERROR_STOP ชั่วคราวในทั้งสอง session

**psql A:**

```sql
\set VERBOSITY verbose
\set ON_ERROR_STOP off
BEGIN;
UPDATE lab_m9_shell.lock_demo SET note='held by module 9' WHERE id=1;
```

**psql B:**

```sql
\set VERBOSITY verbose
\set ON_ERROR_STOP off
BEGIN;
UPDATE lab_m9_shell.lock_demo SET note='held by module 9' WHERE id=2;
```

**A** ขอแถวที่ B ถือ จึงรอ

```sql
UPDATE lab_m9_shell.lock_demo SET note='opposite lock order' WHERE id=2;
```

**B** ขอแถวที่ A ถือ ทำให้เกิดวงจร

```sql
UPDATE lab_m9_shell.lock_demo SET note='opposite lock order' WHERE id=1;
```

หนึ่ง session จะถูกยกเลิกด้วย **40P01** อีกฝั่งได้ **00000** ไม่รับประกันว่าฝั่งไหนเป็น victim ฝั่งที่ UPDATE สำเร็จต้อง ROLLBACK เช่นกัน ทำบล็อกนี้ใน **ทั้ง A และ B** หลังเห็นผลของ UPDATE

```sql
\echo Last statement SQLSTATE: :SQLSTATE
ROLLBACK;
\set ON_ERROR_STOP on
```

**C** ตรวจหลังปล่อยทุก transaction

```sql
SELECT datname,deadlocks FROM pg_stat_database WHERE datname=current_database();
SELECT id,note FROM lab_m9_shell.lock_demo ORDER BY id;
SELECT claim_no,estimated_amount FROM claimsure.claim
WHERE claim_no IN ('CLM-L1-001','CLM-L1-002') ORDER BY claim_no;
```

สองแถว lock demo ยังเป็น `ready` และสองเคลมยังมียอดเดิม แผง **Database deadlocks in last 5 minutes** ใช้ `increase()` ซึ่งประมาณค่าและเป็นเศษส่วนได้ ให้ยืนยันเหตุการณ์จาก SQLSTATE กับ counter นี้ เหตุ deadlock เดิมในฐานเดียวกันอยู่ในตัวนับสะสมด้วย ให้อ่านเป็น delta ไม่ล้าง statistics เพื่อให้ได้ 0 ทางแก้ของแอปพลิเคชันคือ retry ทั้ง transaction ภายในขอบเขตที่กำหนด และล็อกแถวตามลำดับเดียวกันทุกครั้ง

## 9F — Optional: จับคู่ query ID กับแผง Top lab SQL

อาจารย์ต้องเตรียม `pg_stat_statements` ที่ preload และมี extension ในฐานนี้ก่อน ผ่าน `module09-stack.sh init-all` นักเรียนไม่ restart shared server เอง

```sql
SELECT extname,extversion FROM pg_extension WHERE extname='pg_stat_statements';
```

เมื่อ extension พร้อม จึงรัน

```sql
SELECT queryid,calls,round(total_exec_time::numeric,2) AS total_ms,
       round(mean_exec_time::numeric,2) AS mean_ms,rows,temp_blks_written,
       left(query,120) AS query
FROM pg_stat_statements
WHERE dbid=(SELECT oid FROM pg_database WHERE datname=current_database())
  AND userid=(SELECT oid FROM pg_roles WHERE rolname=current_user)
  AND query LIKE '%lab_m9_shell%' AND query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC LIMIT 10;
```

นำ `queryid` ไปเทียบแผง **Top lab SQL by recent execution time** ข้อความ SQL อยู่ในผลนี้ ส่วน Prometheus เก็บเฉพาะ query ID ถ้า extension ยังไม่พร้อม ให้ข้าม 9F พร้อมระบุเหตุผล ไม่สั่ง `pg_stat_statements_reset` เพราะเป็นหลักฐานร่วม และ `mean_ms` ไม่ใช่ percentile

## 9G — Optional: ตรวจ pipeline Prometheus

รันบนเทอร์มินัลที่ SSH อยู่ที่เครื่องเซิร์ฟเวอร์ หลังอาจารย์ทำ `init-all` แล้ว สี่คำถามนี้คือชุดใน Grafana Explore ใช้ `$PGDATABASE` ที่ตั้งเป็น `claimsure_xx` โดยแทน xx ด้วยหมายเลขของตนแล้ว สามผลแรกต้องเป็น **1, 1, 0** คำถามที่สี่เป็นเกจตอนนั้น หลัง 9D จบแล้วค่า blocked เป็น 0 ได้ ถ้าต้องการเห็นค่าอย่างน้อย 1 ให้รันคำถามนี้ระหว่างที่ B ยังรออยู่

```bash
: "${PGDATABASE:?}"
curl -fsSG 'http://127.0.0.1:9090/api/v1/query' \
  --data-urlencode "query=up{job=\"postgres\",instance=\"postgres:5432/${PGDATABASE}\"}"
curl -fsSG 'http://127.0.0.1:9090/api/v1/query' \
  --data-urlencode "query=pg_up{job=\"postgres\",instance=\"postgres:5432/${PGDATABASE}\"}"
curl -fsSG 'http://127.0.0.1:9090/api/v1/query' \
  --data-urlencode "query=pg_exporter_last_scrape_error{job=\"postgres\",instance=\"postgres:5432/${PGDATABASE}\"}"
curl -fsSG 'http://127.0.0.1:9090/api/v1/query' \
  --data-urlencode "query=claimsure_m9_activity_blocked{job=\"postgres\",datname=\"${PGDATABASE}\"}"
```

| แผง | สิ่งที่อ่านได้ |
| --- | --- |
| 1–3 สุขภาพ HTTP / DB / scrape error | 1 / 1 / 0 ไล่ชั้นที่ล้มเหลวก่อน |
| Tagged Module 9 sessions, sessions by state, Blocked Module 9 clients | เฉพาะชื่อ `module09_xx_` |
| Student role sessions / role limit | limit จริงของ role และนับ client อื่นของ role เดียวกัน |
| Oldest blocked query, Oldest Module 9 transaction | เกจที่โตระหว่างถือ lock |
| Module 9 SQL calls per second, Top lab SQL | ต้องมีตัวอย่างของ `rate()` ไม่ใช่ p99 ของผู้ใช้ |
| Database transactions per second, Database deadlocks in last 5 minutes | ทั้งฐาน รวมงานอื่นใน claimsure_xx |
| Lab estimated dead tuples | ค่าประมาณของสามตารางแล็บ |
| Database cache hit fraction (recent) | ว่างได้เมื่ออัตราอ่านและ hit เป็นศูนย์ ทั้งคู่ ไม่ใช่แคชของ OS |
| Database temp bytes per second | ศูนย์เป็นผลปกติเมื่อไม่มี spill |
| Database size, Student database client backends | รวมมากกว่าเซสชันที่ติดแท็ก |
| Cluster WAL archive failures / 5m | ตัวนับร่วมของคลัสเตอร์ ไม่เอาไปบวกซ้ำข้าม 20 target |
| Student role connection limit | ค่า limit ของ role ตน |

แผง replica lag หรือ CPU ต้องมี collector ของ replica หรือเครื่อง ซึ่ง stack นี้ไม่ได้ติดตั้ง ช่องว่างจาก target ที่ไม่มีไม่ใช่ศูนย์ที่สุขภาพดี แดชบอร์ดนี้ไม่ได้ตั้งเส้นทางเตือนของ Alertmanager ข้อเสนอ alert ต้องมีเจ้าของ หน้าต่างสังเกต และคำค้นหลักฐานชุดแรก

ถ้า Import ไม่ขึ้น ให้ตรวจบทบาท Grafana แล้วใช้แดชบอร์ดที่ provision ไว้ แผง `rate()` ว่าง ให้ตรวจ 1/1/0, datasource, ฐาน, ช่วงเวลา แล้วรอ 60–90 วินาทีหลังมี workload เมตริก `claimsure_m9_*` หายไปเมื่อ exporter ยังไม่ได้โหลดไฟล์ collector การถือ lock ที่สั้นกว่าหนึ่งรอบ scrape จะไม่ขึ้นแผง blocked ถ้าชน connection limit ของ role ให้ปิดเซสชันเก่าของตน อย่าเปลี่ยน limit ของเซิร์ฟเวอร์ร่วม

## คืนค่า

ให้ pgbench จบเองหรือ Ctrl+C และ ROLLBACK ใน A/B ก่อน **psql C**

```sql
SELECT pid,application_name,state,pg_blocking_pids(pid)
FROM pg_stat_activity
WHERE datname=current_database() AND usename=current_user
  AND starts_with(application_name,'module09_'||right(current_database(),2)||'_');
SELECT count(*) AS expected_100006 FROM claimsure.claim;
SELECT claim_no,estimated_amount FROM claimsure.claim
WHERE claim_no IN ('CLM-L1-001','CLM-L1-002') ORDER BY claim_no;
SELECT id,note FROM lab_m9_shell.lock_demo ORDER BY id;
```

ต้องไม่เหลือแถวที่ `pg_blocking_pids` ไม่ว่าง เคลมทั้งฐานยังครบ และสองแถว lock demo เป็น `ready` จากนั้น `\q` ทุก session แล้วลบเฉพาะไฟล์ SQL ของ pgbench เมื่อไม่ใช้แล้ว

```bash
rm -i "$HOME/case-labs/m9-workload.sql"
```

ปล่อย schema `lab_m9_shell` ไว้ได้ บท 10 ไม่ได้ใช้ตารางนี้ ประวัติ deadlock ใน Grafana และตัวนับ statistics ยังอยู่ได้ตามปกติ ไม่ล้าง monitoring history, dashboard หรือ `pg_stat_statements` เพื่อรีเซ็ตบทเรียน

เมื่อสังเกตกราฟจบแล้วและต้องการถอด fixture ของตน มีสคริปต์ห้องเรียนที่หยุดเฉพาะเซสชันป้าย `module09_xx_` แล้วลบเฉพาะตารางที่มีเครื่องหมายใน transaction เดียว โดยไม่ CASCADE และไม่แตะข้อมูลประกันหรือแล็บอื่น รันด้วยบัญชี SSH ของตนโดยไม่มี sudo

```bash
cd "$HOME/scripts"
./module09-reset-all.sh --dry-run
./module09-reset-all.sh
```

อาจารย์ที่จะถอด fixture บทนี้ครบ 20 ฐาน ใช้คำสั่งที่มีชื่อ reset โดยตรง มันเก็บ role monitor, คอนฟิก, บริการ และประวัติการวัดไว้

```bash
cd /opt/setup-postgres-labs
./scripts/module09-stack.sh reset-all --dry-run
./scripts/module09-stack.sh reset-all --yes
```

ทางสคริปต์ทั้งชุดของห้องเรียน คือ `./run-lab09.sh doctor`, `./module09-workload.sh`, `./module09-blocking.sh`, `./module09-deadlock.sh` และ `./module09-observe.sh` ตาม [cheat sheet](references/cheat-sheets/module-09-grafana-lab.md) บทนี้พิมพ์คำสั่งชุดเดียวกันให้เห็นทีละขั้น อย่ารันสคริปต์นั้นคู่กับ pgbench ของ 9C

ที่มา: [Grafana lab ของห้องเรียน](references/cheat-sheets/module-09-grafana-lab.md), [สำเนาสคริปต์](references/scripts/shells/module09-grafana-lab.md), [pgbench](https://www.postgresql.org/docs/18/pgbench.html), [Monitoring](https://www.postgresql.org/docs/18/monitoring.html), [pg_stat_statements](https://www.postgresql.org/docs/18/pgstatstatements.html)
