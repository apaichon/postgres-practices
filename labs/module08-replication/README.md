# Module 8 — isolated three-node PostgreSQL replication

Replace `xx` in `COMPOSE_PROJECT_NAME=postgres-practices-m8_xx` with your assigned two-digit number before starting your isolated stack.

ชุด Compose สำหรับทดลอง replication แบบแยกสาม nodes พร้อมไฟล์ config, init script และ status SQL ดูเอกสารประกอบและขอบเขตคู่มือที่ท้ายหน้านี้

Compose นี้เป็น Environment ใหม่สำหรับ Streaming replication แบบ 1 Primary + 2 Standbys
ใช้ PostgreSQL 18 image เดียวกันทั้งสาม Nodes และไม่มี Container name/Network/Volume แบบ Global
ตั้ง Project และ Ports ของตนใน `.env` ตามคู่มือ ก่อนเรียก `docker compose`

ลำดับหลัก: เปิด pg1 → Import ข้อมูลหลักจากบท 1–7 หรือเลือก Demo → Clone pg2 → เพิ่ม pg3 →
หยุด/คืน pg3 ให้ Catch up → หยุด Primary pg1 → Promote pg2 → เปลี่ยน pg3 ให้ Follow pg2 →
Rebuild pg1 จาก pg2 แล้วกลับมามี 3 Nodes

`node-entrypoint.sh` มีหน้าที่ Start/Clone/Rebuild เท่านั้น ไม่ Auto-promote, Auto-select Primary
หรือ Auto-delete Data โดย Rebuild เก็บ Data Directory เดิมไว้ใน Volume ของ Node นั้น
File lock ป้องกันการ Clone/Rebuild Volume ที่ Server ของ Lab ยังใช้งานอยู่

อย่าใช้ `docker compose up -d` ทุก Services ตั้งแต่แรก: pg2/pg3 ต้องมี Base backup ก่อน
หลัง Failover ให้เชื่อ Role จาก `pg_is_in_recovery()` ไม่เชื่อหมายเลข Node หรือ Port

Image เริ่มต้นถูก Pin เป็น Official `postgres:18-alpine` Digest ที่ตรวจด้วย PostgreSQL 18.6
ถ้าจะเปลี่ยน Image ให้ตั้ง `M8_IMAGE` เป็น PostgreSQL 18 Official Image เดียวกันทุก Node
แล้วทดสอบใหม่ใน Project/Volumes ใหม่ อย่าเปลี่ยน Major Version ของ Volume เดิม

## Docker quick start

From the repository root (Docker Compose v2 and Python 3.10+):

```bash
bash labs/docker-labs.sh 8 init
bash labs/docker-labs.sh 8 config
bash labs/docker-labs.sh 8 pull
bash labs/docker-labs.sh 8 up
bash labs/docker-labs.sh 8 verify
```

The helper creates `.env` with random secrets, starts pg1, creates slots
`m8_pg2` / `m8_pg3`, clones each empty standby with `pg_basebackup`, and waits
for all nodes to be healthy. `verify` proves replication using a temporary row
and checks that both standbys reject writes. It also works after rejoin when
pg2 is the primary. No classroom data is required for this check.

Default database: `claimsure_m8`; admin: `postgres`; password:
`M8_ADMIN_PASSWORD` in `.env`. Host ports: pg1 `55811`, pg2 `55812`, pg3 `55813`,
all on `127.0.0.1`. Choose unused ports and a unique project name in `.env`
before startup. Keep the same `.env` when resuming existing volumes.

## Manual exercise — bootstrap and inspect replication

For the rest of this walkthrough, run commands in **`labs/module08-replication`**.
Initialize `.env` first with `python3 lab.py init`. If using manual steps,
start from empty lab volumes and perform these in order instead of helper `up`:

```bash
cd labs/module08-replication
docker compose up -d pg1
# Wait until pg1 is healthy: docker compose ps
docker compose exec -T pg1 psql -X -U postgres -d claimsure_m8 -v ON_ERROR_STOP=1 <<'SQL'
SELECT pg_create_physical_replication_slot('m8_pg2');
SELECT pg_create_physical_replication_slot('m8_pg3');
SQL
docker compose run --rm --no-deps pg2 clone pg1
docker compose up -d pg2
docker compose run --rm --no-deps pg3 clone pg1
docker compose up -d pg3
python3 lab.py verify
```

If the helper already started the three nodes, skip manual bootstrap.
Inspect roles, WAL senders/receiver and slot retention on every node:

```bash
docker compose exec -T pg1 psql -X -U postgres -d claimsure_m8 -f /lab/sql/status.sql
docker compose exec -T pg2 psql -X -U postgres -d claimsure_m8 -f /lab/sql/status.sql
docker compose exec -T pg3 psql -X -U postgres -d claimsure_m8 -f /lab/sql/status.sql
```

pg1 must report `is_standby = f`; pg2 and pg3 report `t`. pg1 should have
two `streaming` senders. Replicas share pg1's system identifier and have a WAL
receiver pointing at pg1. This is asynchronous physical replication;
`synchronous_commit = on` alone does not configure a synchronous standby.

Create a small canary on the primary. Optionally import your own ClaimSure
dump into this isolated database before this step; classroom data is not
automatically copied into this stack.

```bash
docker compose exec -T pg1 psql -X -U postgres -d claimsure_m8 -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS lab_m8.canary(id bigint PRIMARY KEY, note text NOT NULL);
INSERT INTO lab_m8.canary VALUES (1, 'before failover')
ON CONFLICT (id) DO UPDATE SET note = EXCLUDED.note;
SQL
python3 lab.py verify
docker compose exec -T pg2 psql -X -U postgres -d claimsure_m8 -c 'TABLE lab_m8.canary;'
```

## Pause a standby and observe catch-up

```bash
docker compose stop pg3
docker compose exec -T pg1 psql -X -U postgres -d claimsure_m8 \
  -c "UPDATE lab_m8.canary SET note = 'written while pg3 stopped' WHERE id = 1;"
docker compose exec -T pg1 psql -X -U postgres -d claimsure_m8 -f /lab/sql/status.sql
docker compose up -d pg3
python3 lab.py verify
docker compose exec -T pg3 psql -X -U postgres -d claimsure_m8 -c 'TABLE lab_m8.canary;'
```

While pg3 is stopped its slot is inactive and retains WAL. This lab caps slot
retention at 256 MB, so a long outage with many writes may invalidate the
slot; rebuild the stopped standby in that case. Slots do not replace backups.

## Manual failover — fence pg1, then promote pg2

Stop application writes first. Keep these commands in the same shell:

```bash
python3 lab.py verify
M8_TARGET_LSN=$(docker compose exec -T pg1 psql -XAt -U postgres -d claimsure_m8 \
  -c 'SELECT pg_current_wal_lsn();')
docker compose stop pg1
# pg1 must now be stopped. Do not restart it before rebuilding below.
docker compose exec -T pg2 psql -X -U postgres -d claimsure_m8 \
  -c "SELECT pg_last_wal_replay_lsn() >= '$M8_TARGET_LSN'::pg_lsn AS caught_up;"
```

Proceed only when `caught_up = t`; repeat the query if needed. In a real
unplanned outage, unavailable primary WAL can mean lost commits with async
replication. This controlled exercise waits for replay before promotion.

```bash
docker compose stop pg3
docker compose exec -T pg2 psql -X -U postgres -d claimsure_m8 -v ON_ERROR_STOP=1 \
  -c 'SELECT pg_promote(true, 60);'
docker compose exec -T pg2 psql -X -U postgres -d claimsure_m8 \
  -c 'SELECT pg_is_in_recovery();'
docker compose exec -T pg2 psql -X -U postgres -d claimsure_m8 \
  -c "UPDATE lab_m8.canary SET note = 'written on promoted pg2' WHERE id = 1;"
```

pg2 must now return `f`. Move the lab SQL client to port `55812` (or your
configured pg2 port). There is no automatic proxy or client routing in this
exercise. The startup helper refuses `up` after roles change so it cannot
bring back the old primary through the original bootstrap sequence.

## Rejoin pg3 and the former primary pg1

Both targets must remain stopped. Rebuild keeps the previous data directory
inside that node's volume and clones from the new primary:

```bash
docker compose exec -T pg2 psql -X -U postgres -d claimsure_m8 -v ON_ERROR_STOP=1 <<'SQL'
SELECT pg_create_physical_replication_slot('m8_pg3')
WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'm8_pg3');
SELECT pg_create_physical_replication_slot('m8_pg1')
WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'm8_pg1');
SQL
docker compose run --rm --no-deps -e M8_REBUILD_CONFIRM=pg3 pg3 rebuild pg2
docker compose up -d pg3
docker compose run --rm --no-deps -e M8_REBUILD_CONFIRM=pg1 pg1 rebuild pg2
docker compose up -d pg1
python3 lab.py verify
docker compose exec -T pg1 psql -X -U postgres -d claimsure_m8 -c 'TABLE lab_m8.canary;'
docker compose exec -T pg2 psql -X -U postgres -d claimsure_m8 -f /lab/sql/status.sql
```

Expected: pg2 primary, pg1/pg3 read-only standbys, both streaming from pg2,
and all nodes show `written on promoted pg2`. After this drill, resume with
`docker compose up -d pg2` followed by `docker compose up -d pg1 pg3`;
the helper's `up` remains limited to the original topology.

Stop with `python3 lab.py stop`, or remove containers/networks while keeping
volumes with `python3 lab.py down`. Do not run `down -v` unless intentionally
discarding all data, including preserved pre-rebuild directories.

References: [pg_basebackup](https://www.postgresql.org/docs/18/app-pgbasebackup.html),
[failover and fencing](https://www.postgresql.org/docs/18/warm-standby-failover.html).

## เอกสารประกอบในสำเนานี้

- [Native streaming-replication/HA tutorial](../module-08-replication.md): คู่มือ PostgreSQL instances แบบ native ของต้นฉบับ เป็นอีก environment จาก Compose 3 nodes นี้
- [Replication/HA cheat sheet](../references/cheat-sheets/module-08-replication-ha.md)
- [สไลด์ภาษาไทย](../../slides/module-08-replication-th.md) และ [English](../../slides/module-08-replication.md)

คู่มือ Docker 3 nodes อยู่ในหน้านี้ ส่วนคู่มือ native ใช้ environment และขั้นตอนแยกกัน
