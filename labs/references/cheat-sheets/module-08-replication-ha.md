# Module 8 — Replication / HA command sheet

[คู่มือเต็ม 8A–8E](../../module-08-replication.md) · [Compose](../../module08-replication/compose.yaml)

รันจาก root ของ repository:

| หัวข้อ | คำสั่ง | หลักฐาน |
| --- | --- | --- |
| เตรียม | `make lab8-init` / `make lab8-config` | .env ส่วนตัวและพอร์ตว่าง |
| 8A | `make up` / `make sql-m8` / `make lab8-verify` | primary + replica + PgBouncer, streaming และ read-only |
| 8B | `make node-add` | replica2 และ replica2_slot, สอง physical senders |
| 8C | `make node-down NODE=replica2` / `make lab8-wal` | slot inactive และ retained WAL |
| 8C คืน node | `make node-up NODE=replica2` / `make lab8-verify` | replay/catch-up และ slot active |
| 8D | `make logical-up` / `make logical-verify` | อีก cluster รับสอง published tables และ row changes |
| 8E | `make pgbouncer` / `make pool-verify` | claim_app Login, transaction mode และ tenant RLS |
| ตรวจบริการ | `make node-status` | Container status ของ project นี้ |
| จบงาน | `make stop` / `make down` | หยุด services / ลบ containers แต่เก็บ volumes |

เปิด admin SQL ด้วย `make psql`, `make replica`, `make replica2` หรือ `make subscriber` ใช้ `\q` ออกจาก psql

Database `claimsure`; พอร์ต host primary 55811, replica 55812, replica2 55813, subscriber 55814, PgBouncer 55820 (ใช้ค่าจริงใน .env ถ้าเปลี่ยนแล้ว) ทุก PostgreSQL container ใช้ 5432

```sql
-- ใน make psql
SELECT application_name, state, write_lsn, flush_lsn, replay_lsn
FROM pg_stat_replication;
SELECT slot_name, slot_type, active, restart_lsn, wal_status
FROM pg_replication_slots ORDER BY slot_name;
```

```sql
-- ใน make pgbouncer: claim_app จริง
BEGIN;
SET LOCAL app.tenant_id = '1';
SELECT claim_no, tenant_id FROM insurance.claim ORDER BY claim_no;
COMMIT;
SELECT count(*) FROM insurance.claim; -- 0: context จบพร้อม transaction
```

Physical replication ส่งทั้ง cluster; logical subscription เลือก tables และไม่คัดลอก schema/roles/sequence state ให้เอง ส่วน failover ต้องครบ detect → fence → promote → route → verify → rejoin การหยุด replica2 ใน 8C ยังไม่ใช่ primary failover
