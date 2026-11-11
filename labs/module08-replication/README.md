# Lab 8 — Primary, Replica และ PgBouncer

ชุดนี้ใช้ลำดับ **8A–8E** ของสไลด์ต้นฉบับ `module-08-replication.md`

อ่าน [คู่มือ Lab 8 ฉบับเต็ม](../module-08-replication.md) ซึ่งรวม prerequisites, commands, SQL, expected results และ stop/resume ไว้ในที่เดียว

รันจาก **root ของ repository**:

```bash
make lab8-init
make lab8-config
make up
make sql-m8
make lab8-verify
make node-add
make node-down NODE=replica2
make lab8-wal
make node-up NODE=replica2
make logical-up
make logical-verify
make pool-verify
```

เริ่ม primary + replica + PgBouncer ก่อน เพิ่ม replica2 ด้วย profile `ha-lab` และ subscriber ด้วย `logical-lab` ข้อมูลอยู่ใน named volumes ของ project นี้ ไม่มี global container names

Database `claimsure`, Admin `postgres` / `M8_ADMIN_PASSWORD`, App `claim_app` / `M8_APP_PASSWORD` ใน `.env` Host ports: Primary `55811`, Replica `55812`, Replica2 `55813`, Subscriber `55814`, Pooler `55820`; เปลี่ยนเป็นพอร์ตว่างของตนก่อนเริ่ม

`make psql`, `make replica`, `make replica2`, `make subscriber` เปิด admin SQL ตาม Node ส่วน `make pgbouncer` ใช้ claim_app จริง

`make stop` / `make down` หยุดเฉพาะ project นี้และเก็บข้อมูลเดิม ไม่มีการลบ volumes อัตโนมัติ ดู [ที่มาของสไลด์และ adaptations](upstream.json)
