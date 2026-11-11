# สไลด์ ClaimSure เวอร์ชันต่อเนื่อง

`xx` เป็น placeholder ให้แทนด้วยหมายเลขสองหลักที่ได้รับ (`01`–`20`) ก่อนรันทุกคำสั่ง เช่น `student_xx`, `claimsure_xx`, `cs_actor_xx` และ `module09_xx_holder` ใช้เลขของตนให้ตรงกันทุก Terminal ส่วน SSH account ใช้รูปแบบ `studentxx` ดู [การตั้งค่าและตรวจตัวตน](../labs/README.md#เตรียมการเชื่อมต่อ)

สไลด์ครบ **บท 1–10** โดยบท **1–7, 9 และ 10** ใช้ customer → policy → claim ชุดเดียวกันจาก [คู่มือบท 1](../labs/module-01-basic-sql.md) และ [บท 2](../labs/module-02-advanced-sql.md) คำอธิบายไทย คำสั่งอังกฤษ พร้อม Speaker Notes ในแต่ละหน้า บท 8 ใช้ native instances แยกและมีทั้งภาษาไทย/English

| บท | สไลด์ | Fundamentals | หน้ารวม | แล็บคำสั่งเต็ม |
| --- | --- | --- | --- | --- |
| 1 | [Basic SQL](module-01-basic-sql.md) | 9 หน้า | 35 | [คู่มือ 1](../labs/module-01-basic-sql.md) |
| 2 | [Advanced SQL](module-02-advanced-sql.md) | 13 หน้า | 34 | [คู่มือ 2](../labs/module-02-advanced-sql.md) |
| 3 | [Performance Tuning](module-03-performance-tuning.md) | 14 หน้า | 27 | [คู่มือ 3](../labs/module-03-performance-tuning.md) |
| 4 | [Security](module-04-security-user-management.md) | 13 หน้า | 29 | [คู่มือ 4](../labs/module-04-security.md) |
| 4 (Clone) | [Security Clone Schema](module-04-security-clone.md) | 11 หน้า | 34 | [คู่มือ 4 แบบ Clone](../labs/module-04-security-clone.md) |
| 4 (Pure SQL ไทย) | [Security และ User Management](module-04-security-user-management-th.md) | แทรกในเนื้อหา | 38 | [คู่มือตามสไลด์ไทย 4A–4H](../labs/module-04-security-user-management-th.md) |
| 5 | [Architecture](module-05-architecture.md) | 16 หน้า | 29 | [คู่มือ 5](../labs/module-05-architecture.md) |
| 6 | [Configuration](module-06-configuration-simple.md) | 11 หน้า | 34 | [คู่มือ 6](../labs/module-06-configuration.md) |
| 7 | [Backup & Recovery](module-07-backup-recovery.md) | 12 หน้า | 32 | [คู่มือ 7](../labs/module-07-backup-recovery.md) |
| 8 | [Replication & HA — native](module-08-replication-th.md) | 10 หน้า | 32 | [คู่มือ 8](../labs/module-08-replication.md) |
| 9 | [Monitoring](module-09-monitoring.md) | 10 หน้า | 31 | [คู่มือ 9](../labs/module-09-monitoring.md) |
| 10 | [Modern PostgreSQL](module-10-modern-features-supabase.md) | 13 หน้า | 34 | [คู่มือ 10](../labs/module-10-modern-features.md) |

ชุดหลักรวม **317 หน้า** มี Fundamentals **121 หน้า** (นับบท 8 ภาษาไทยหนึ่งชุด และไม่นับเวอร์ชัน 4 Clone / Pure SQL ไทย) ทุกบทจัด Fundamental และ infographic ไว้ก่อนแล็บที่ใช้แนวคิดนั้น พร้อม footer แสดงหัวข้อคู่มือและเลขหน้าสไลด์

## พื้นฐานก่อนเริ่มแล็บ

| บท | เนื้อหาพื้นฐาน |
| --- | --- |
| 1 | Relational model, กลุ่มคำสั่ง SQL, logical SELECT order, NULL, transaction/ACID |
| 2 | Reuse, cardinality, routine signatures, CTE/view/materialized view, window anatomy |
| 3 | Measurement loop, estimates/actuals, index access paths, statistics/maintenance, partitions/projections |
| 4 | Authentication/authorization/ownership, roles, grants/RLS, trusted context, invoker/definer/audit |
| 5 | Processes/memory/storage, tuples/keys, snapshots/isolation, WAL, rollback/vacuum/checkpoint |
| 6 | Setting scopes, activation contexts, memory budgets, WAL/checkpoints, autovacuum eligibility, measurement/logging |
| 7 | RPO/RTO, logical/physical backups, consistency, PITR chain, restore verification/dependencies |
| 8 | Physical streaming, slots/WAL retention, lag/commit modes, fencing/failover/rejoin, logical replication, pool context |
| 9 | Evidence sources, gauges/counters/rates, latency/throughput/concurrency, locks/deadlocks, correlation |
| 10 | Feature choice, JSON null/operators, FTS/vector retrieval, partition/derived data, API identity/RLS |

ทุกบทกระจาย Fundamental ไว้ก่อนแล็บที่เกี่ยวข้องตามตารางด้านล่าง หัวข้อและ footer ใช้รหัสจากคู่มือจริง: บท 6 ใช้ **6A–6G**, บท 7 ใช้ **7.1a–7.6b**, บท 8 ใช้ **Step 1–15**, บท 9 ใช้ **9A–9G / คืนค่า**, และบท 10 ใช้ **10A–10H** รวม **10F.0 / 10F.1** เลขหน้าสไลด์นับแยกตามลำดับนำเสนอ

สไลด์เวอร์ชันเดิมอยู่ในโครงการต้นฉบับ สำเนานี้รวมชุด continuous และ replication native พร้อมภาพปก โลโก้ components และธีมที่ใช้จริง

## เปิดสไลด์

### Module 4 ภาษาไทยจากต้นฉบับ Pure SQL

คัดลอก [สไลด์ภาษาไทย 38 หน้า](module-04-security-user-management-th.md) จาก
`setup-postgres-server/postgres-admin-labs/docs/slides/module-04-security-user-management-th.md`
โดยคงเนื้อหา/รูปแบบ ปรับ paths กับคำสั่งเปิดให้ใช้ใน repository นี้
และใช้ prefix `role_` สำหรับ NOLOGIN roles ตาม Source SQL ของ Lab
เขียน [คู่มือ Lab 0, 4A–4H](../labs/module-04-security-user-management-th.md)
พร้อม Source SQL ครบ 36 Blocks, Connections A/S/B/C/D และ expected error/recovery ห้าคู่ตามต้นฉบับ

```bash
# จาก project root
make slides MODULE=4:th PORT=3046
```

```bash
# จาก slides/
npm run slides:4:th -- --port 3046
npm run build:4:th
```

ใช้ `lab_m4_xx` และชื่อ roles ตามต้นฉบับ โดย postgres bootstrap 0/4A แล้ว
student_xx จัดการผ่าน Owner ใน 4B–4H ดู [ที่มาและ hashes](../labs/module04-security-th/upstream.json)
Static build อยู่ที่ `slides/dist/module04-th/` ส่วน `MODULE=4` และ `MODULE=4:clone` ยังคงเปิดชุดเดิม

CSS ประกอบของ Pure SQL อยู่ที่ `styles/module04-security-th.css` และโหลดผ่าน
`setup/main.ts` เพื่อให้เปิด URL ของสไลด์แต่ละหน้าโดยตรงได้ รูปแบบคำสั่งและ
Speaker Notes คงตามต้นฉบับ หน้าเนื้อหายาวสามารถเลื่อนแนวตั้งได้

### Module 4 เวอร์ชัน Clone schema

ชุด [Security Clone Schema](module-04-security-clone.md) มี **34 หน้า / 11 Fundamentals**
ใช้ `lab_m4_clone_xx`, Login จริงห้าบัญชี, RLS ตาม `session_user`, audit ที่เก็บผลจริง
และการตรวจต้นทางจาก snapshot ตาม [Lab เวอร์ชัน Clone](../labs/module-04-security-clone.md)
มีแผนภาพ SVG ที่แก้ไขได้และ Speaker Notes ทุกหน้า

จาก project root:

```bash
make slides MODULE=4:clone PORT=3044
```

หรือจาก `slides`:

```bash
npm run slides:4:clone -- --port 3044
npm run build:4:clone
```

Static build อยู่ที่ `slides/dist/module04-clone/` ชุดเดิมและคำสั่ง
`make slides MODULE=4` / `npm run slides:4` ยังคงใช้ไฟล์เดิม
ทั้งสองเวอร์ชันแยก deck และแยกคู่มือกัน

### ภาพรวมและ prerequisite ก่อนบท 1

เปิด [Course Overview — เตรียม Terminal และ SSH](module-00-overview.md) จำนวน **10 หน้า**
จาก project root:

```bash
make overview
# หรือ make slides MODULE=0
```

ครอบคลุมสิ่งที่ต้องรับจากอาจารย์, SSH ด้วย `studentxx`, ตั้งค่า PostgreSQL
ด้วย `student_xx` / `claimsure_xx`, ตรวจ connection, ทำแล็บด้วยตนเอง,
ตัวเลือก continuous runner และ Session A/B ของนักเรียนคนเดียวกัน
ใช้ภาษาไทยและ Speaker Notes ตามธีมเดิม โดยเลข server/port/path เป็น placeholder
ที่ต้องเปลี่ยนตามห้องเรียน ดู [คู่มือเตรียมแล็บ](../labs/README.md) และ
[คู่มือ runner](../labs/RUNNER.md) ประกอบ

จากโฟลเดอร์ `slides` ใช้ `npm run slides:0 -- --port 3030`
จำนวน 10 หน้านี้แยกจาก 317 หน้าของบท 1–10 ด้านบน

### เปิดแต่ละบท

ใช้ Node.js **22.12.0 ขึ้นไป** รันจากโฟลเดอร์ `slides` ในโครงการนี้ ติดตั้ง dependencies ตาม lockfile ครั้งแรก:

```bash
npm ci
```

เปิดบท 1:

```bash
npm run dev -- --port 3031
```

เลือกบทอื่นได้ด้วย scripts สำหรับบท 1–10:

```bash
npm run slides:2 -- --port 3032
npm run slides:7 -- --port 3037
npm run slides:10 -- --port 3040
```

หรือระบุไฟล์กับ Slidev โดยตรง:

```bash
npx slidev module-03-performance-tuning.md --port 3033
```

Build เป็นเว็บ static โดยเลือกไฟล์และ output directory:

```bash
npx slidev build module-07-backup-recovery.md --out dist/module07
```

`npm run build` build บท 1 เป็นค่าเริ่มต้น หากพอร์ตมี deck เปิดอยู่ให้เลือกพอร์ตใหม่

ใช้ P เพื่อเปิด Presenter Mode และอ่าน notes ตาม Slidev หน้าเนื้อหายาวเลื่อนแนวตั้งได้ คำสั่งในหน้าสไลด์บางหน้าเป็นส่วนของขั้นทดลอง ให้เปิดคู่มือที่อ้างใน footer เพื่อทำ BEGIN/ROLLBACK, expected errors และลำดับ A/B ให้ครบ ไม่วางคำสั่งทั้งบทพร้อมกัน

## ลำดับข้อมูล

1. บท 1–2: ลูกค้า 3 ราย กรมธรรม์ 3 ฉบับ เคลม CLM-L1-001 ถึง 006 พร้อม view/functions; หลัง 1D เคลม 001 อยู่ REVIEW
2. บท 3: ขยาย claim จริงอีก 100,000 แถวเป็น CLM-L3-* รวม 100,006 แถว เพิ่ม description/metadata และ indexes/report จากข้อมูลเดิม
3. บท 4–6: ใช้ claim จริงทดลองสิทธิ์, MVCC, timeout และ autovacuum แล้วคืนข้อมูล/options; งาน WAL/logging ใช้ private copy ของสามตารางเดิม
4. บท 7: กู้สามตารางตาม FK ด้วยลำดับ customer → policy → claim และรักษา DDL/view/routines เดิม ทดสอบแถวหลัง physical base เพื่อพิสูจน์ WAL replay
5. บท 8: replication native แยก instance และ lab_repl.canary; ใช้ Step 1–15
6. บท 9: workload/blocking/deadlock ใน lab_m9_shell พร้อม tagged sessions; รักษา claim เดิมและไม่ล้าง monitoring history
7. บท 10: เพิ่ม JSONB/FTS/events/vector และ customer-based RLS ให้เคสเดิม

ใช้ schema `claimsure` ในฐานข้อมูล `claimsure_xx` ของนักเรียน ไม่ใช้ insurance ของ runner; บท 9 ใช้ fixture lab_m9_shell ตามคู่มือปัจจุบัน บท 6–7 ต้องมี PostgreSQL 18 server binaries ส่วน pgvector, pg_stat_statements, Grafana และ Supabase จริงเป็น optional ตามคู่มือ

ตัวเลขเวลา, WAL volume, checkpoint counts และ log counts ต้องวัดใหม่กับ workload นี้ ไม่คัดผลจาก wal_probe หรือคิวในเวอร์ชันเดิมมาอ้าง การทดลอง logging/context simulation ไม่แทนการ verify token ของบริการจริง

## ไฟล์ประกอบ

- `style.css`: ธีมร่วมของชุดต่อเนื่อง
- `components/CaseCover.vue`: อ้างภาพปกใน `assets/` ผ่าน Vite imports
- `slide-top.vue`: component โลโก้หลักสูตร พร้อมรูปต้นฉบับใน `assets/`
- `deck-manifest.json`: รายการ decks และจำนวนหน้า

[กลับคู่มือแล็บต่อเนื่อง](../labs/README.md)

ภาพปกทั้ง 10 ภาพและโลโก้คัดลอกจากต้นฉบับโดยไม่แก้ภาพ ไม่ต้องอ้าง asset จากโครงการเดิม ส่วน source notes ชี้ไปที่ `../labs/` ในโครงการนี้

## สไลด์เพิ่มเติมบท 8 — Replication และ HA

ปรับทั้งภาษาไทยและ English เป็น **32 หน้า / 10 Fundamentals** ตาม pattern บท 1 ใช้ภาพต้นฉบับ topology, lag, physical/logical และ failover พร้อม SVG ที่แก้ไขได้ ลำดับแล็บตรงกับ **Step 1–15** ของคู่มือ native:

- [ภาษาไทย](module-08-replication-th.md)
- [English](module-08-replication.md)
- [คู่มือแล็บ replication](../labs/module-08-replication.md) และ [Compose 3 nodes](../labs/module08-replication/README.md)

จากโฟลเดอร์ `slides`:

```bash
npm run slides:8 -- --port 3038
npm run slides:8:en -- --port 3048
```

บท 8 ใช้ cluster แล็บแยก: single host primary :5432 / replica :5433 / optional replica2 :5434 ไม่ปนกับพอร์ตของ Compose หรือ shared claimsure_xx แยก receive/write/flush/replay และ commit acknowledgment; fence ก่อน promote และตรวจ endpoint หลัง routing ทุกครั้ง

## Infographic บท 1

บท 1 ใช้ภาพแนวคิดก่อนตัวอย่างแล็บตามรูปแบบต้นฉบับ `postgres-admin-labs/docs/slides/module-01-basic-sql.md`:

- Fundamentals รวม 9 หน้า: 5 หน้าใช้ SVG อธิบาย relational model, กลุ่มคำสั่ง, SELECT order, NULL และ ACID อีก 4 หน้าใช้ภาพ Connection Route, SQL anatomy, JOIN และ aggregation
- หน้า 6 แทรก PostgreSQL Connection Route ก่อนกลุ่มคำสั่ง SQL อธิบาย host/port, role และ database; ภาพเป็นตัวอย่างพอร์ต 6432 แต่แล็บ continuous หลัง SSH ใช้ direct port 5432
- เส้นทาง SSH → psql ปรับให้ตรงกับ `studentxx`, `student_xx`, `claimsure_xx` และ direct port 5432
- สรุป Schema/Tables ใช้ SVG ต้นฉบับโดยเปลี่ยน namespace เป็น `claimsure`
- ภาพ SQL anatomy, JOIN/Set operations และ Aggregation pipeline คัดลอกจากต้นฉบับโดยไม่แก้ภาพ พร้อมคำอธิบายไทยและขอบเขตของตัวอย่างใน Speaker Notes

ตัวเลขในภาพ Aggregation เป็นตัวอย่าง category A/B/C ไม่ใช่ผลแล็บจริง และวงกลม JOIN เป็นภาพช่วยจำ ต้องอ่าน matching condition และผล query ประกอบ

## ลำดับสไลด์บท 1 ตามรหัสแล็บ

รหัส **1A–1G** อ้างอิงหัวข้อใน [คู่มือบท 1](../labs/module-01-basic-sql.md)
หัวข้อสไลด์ใช้ `1A · Fundamental` สำหรับพื้นฐาน และ `Lab 1A` สำหรับเนื้อหาแล็บ
แล็บหนึ่งหัวข้ออาจมีหลายสไลด์ โดยไม่สร้างเลขขั้นย่อยที่ไม่มีในคู่มือ

| หัวข้อคู่มือ | หน้าพื้นฐานก่อนเริ่ม | หน้าแล็บ / ตรวจผล |
| --- | --- | --- |
| เตรียมการเชื่อมต่อ | 1–6: ภาพรวมและ connection | ตั้ง environment แล้วเปิด psql |
| 1A — สร้าง schema และตาราง | 7–8: กลุ่มคำสั่ง SQL และ relational model | 9–15: namespace, ความสัมพันธ์, constraints, DDL และสรุป |
| 1B — เพิ่มข้อมูลตัวอย่าง | 16: NULL / สามค่า ก่อน INSERT ที่มี NULL | 17–20: customer → policy → claim |
| 1C — อ่านข้อมูลโดยระบุลำดับ | 21–22: SELECT order และ SQL anatomy | 23–24: SELECT / ORDER BY และตัวอย่างอ่าน NULL |
| 1D — UPDATE ภายใน transaction | 25: Transaction / ACID ใช้ร่วมกับ 1E | 26: UPDATE และ COMMIT |
| 1E — DELETE แล้ว ROLLBACK | ใช้พื้นฐานหน้า 25 ต่อจาก 1D | 27: DELETE และ ROLLBACK |
| 1F — JOIN และ set operations | 28: JOIN / Set operations | 29–31: JOIN, zero-claim customer, UNION / INTERSECT |
| 1G — GROUP BY และ HAVING | 32: Aggregation pipeline | 33–35: GROUP BY, HAVING และตรวจจำนวนส่งต่อบท 2 |

## ลำดับสไลด์บท 2 ตามรหัสแล็บ

บท 2 ใช้ pattern เดียวกับบท 1: ภาพแนวคิดและ Fundamental มาก่อนคำสั่งแล็บ
หัวข้อและ footer อ้างอิง [คู่มือบท 2](../labs/module-02-advanced-sql.md) ด้วยรหัส 2A–2H
ใช้ `claimsure` และข้อมูลต่อเนื่องเดิม; เก็บ view/routines ไว้สำหรับบท 3

| หัวข้อคู่มือ | หน้าพื้นฐานก่อนเริ่ม | หน้าแล็บ / ตรวจผล |
| --- | --- | --- |
| เตรียมก่อน 2A | 1–3: รับข้อมูลบท 1 และตรวจ prerequisite | 3 customers / 3 policies / 6 claims |
| 2A — View | 4–7: reuse, เลือก object และ view contract | 8–9: สร้างและอ่าน claim_detail_v |
| 2B — SQL function | 10–11: signature / cardinality ใช้ร่วมกับ 2C–2D | 12–14: สูตรภาษี, function และตรวจค่า |
| 2C — Function คืนหลายแถว | 15: volatility และใช้พื้นฐานหน้า 10–11 | 16–17: RETURNS TABLE และ SELECT |
| 2D — Procedure | 18: validation → UPDATE → FOUND | 19–20: สร้าง procedure, CALL และ ROLLBACK |
| 2E — CTE | 21–22: อายุผลลัพธ์และ pipeline | 23: รวมภาษีแล้ว dense_rank |
| 2F — Window | 24–25: aggregate เทียบ window / OVER anatomy | 26–28: row_number, running sum และตรวจผล |
| 2G — Pivot | 29: GROUP + FILTER | 30–31: query และ status ที่รวมในรายงาน |
| 2H — Catalog | 32: pg_namespace / pg_proc / prokind | 33: ตรวจ 2 functions และ 1 procedure |
| ส่งต่อบท 3 | 34: ทบทวนผล 2A–2H | เก็บ objects และสถานะเคลมเดิม |

ภาพ object choice, window และ pivot คัดลอกจากต้นฉบับที่ผู้ใช้ระบุโดยไม่แก้ไฟล์ภาพ
ภาพ window ใช้ policy ตัวอย่าง ส่วนแล็บจริงแบ่งตาม customer; ภาพ pivot ใช้เดือน
แต่แล็บจริงใช้ customer และไม่มีคอลัมน์ NEW คำอธิบายและ Speaker Notes ระบุความต่างไว้
Fundamental อื่นใช้ SVG ที่แก้ไขได้ตามรูปแบบสีน้ำเงินของบท 1

## ลำดับสไลด์บท 3 ตามรหัสแล็บ

บท 3 ใช้ pattern เดียวกับบท 1–2: Fundamental และภาพแนวคิดก่อนคำสั่งที่เกี่ยวข้อง
หัวข้อและ footer อ้างอิง [คู่มือบท 3](../labs/module-03-performance-tuning.md) ด้วยรหัส **3A–3F**
คง `claimsure.claim` จริงและจำนวน **100,006** แถวของชุด continuous
ไม่ใช้ `claim_perf` หรือชุดข้อมูล 2,000,000 แถวจากต้นฉบับ

| หัวข้อคู่มือ | หน้าพื้นฐานก่อนเริ่ม | หน้าแล็บ / ตรวจผล |
| --- | --- | --- |
| 3A — ตรวจข้อมูลที่รับต่อ | 2: ความต่อเนื่องของตาราง / view / function | 3: ตรวจหกเคลมเดิม |
| 3B — เพิ่ม 100,000 แถวจากแม่แบบ | 4: 6 แม่แบบ → 100,000 แถวใหม่ → 100,006 รวม | 5: อ่าน mapping; ใช้ INSERT เต็มจากคู่มือ |
| 3C — Covering index | 6–8: evidence loop, estimated/actual และ access path | 9–10: baseline และ partial covering index |
| 3D — Index ตาม operator | 11–12: method / predicate และ query shape | 13: expression B-tree / GIN; ใช้ BRIN และ queries เต็มจากคู่มือ |
| 3D — Maintenance | 14–15: statistics / row versions / VACUUM | 16: ขนาด, idx_scan และ VACUUM (ANALYZE) |
| 3E — Partitioned report copy | 17–19: partition, สำเนารายงาน และ pruning | 20–21: DDL, routing และ pruning ของเดือนกุมภาพันธ์ |
| 3F — Materialized view | 22–23: live / stored result และ freshness | 24–25: สรุปภาษีและทดสอบ UPDATE / REFRESH / ROLLBACK |
| สรุป / ส่งต่อ | 26: หลักฐานการตัดสินใจ | 27: 100,006 แถวและหกเคลมเดิมสำหรับบท 4 |

ภาพ evidence loop, index selector, vacuum lifecycle, partition pruning และ live vs materialized
คัดลอกจากต้นฉบับโดยไม่แก้ไฟล์ภาพ พร้อมคำอธิบายไทยและ Speaker Notes
ภาพ pruning ใช้ events เดือน 08–10 และ default partition เป็นตัวอย่าง;
แล็บจริงใช้ cs_claim_report เดือน 01–03 และไม่มี default partition
Partial เป็นรูปแบบกำหนด predicate เพิ่มเติม ไม่ใช่ index access method อีกชนิด

## ลำดับสไลด์บท 4 ตามรหัสแล็บ

บท 4 ใช้ pattern เดียวกับบท 1–3: Fundamental และ infographic มาก่อนคำสั่งแล็บที่เกี่ยวข้อง
หัวข้อและ footer อ้างอิง [คู่มือบท 4](../labs/module-04-security.md) ด้วยรหัส **4.0 และ 4A–4F**
4.0 ใช้บัญชี Instructor; 4A–4F ใช้ student connection และ SET ROLE actor ตามคู่มือ

| หัวข้อคู่มือ | หน้าพื้นฐานก่อนเริ่ม | หน้าแล็บ / ตรวจผล |
| --- | --- | --- |
| 4.0 — Instructor เตรียม roles | 2–4: identity / grants / ownership และ student → actor → reader | 5: membership; ใช้ CREATE ROLE และตัวแปรเต็มจากคู่มือ |
| 4A — Student เก็บ baseline | 6: ownership เทียบ runtime | 7–8: objects เดิม, ตัวแปรนักเรียน และเก็บ ACL/RLS ตามคู่มือ |
| 4B — Schema / table gates | 9–11: effective role และขอบเขตสิทธิ์ | 12–13: expected 42501 และอ่านได้หลัง GRANT |
| 4C — Identity / nextval | 14: privilege ของ identity เทียบ direct sequence call | 15: ใช้บล็อกทดสอบเต็มในคู่มือและ ROLLBACK |
| 4D — Customer-based RLS | 16–18: object grant, trusted context และ row isolation | 19–22: mapping customer, policy, invoker view และ context simulation |
| 4E — Column UPDATE / audit | 23: invoker / definer / audit | 24–25: UPDATE(status), expected error และ audit ใน transaction |
| 4F — Defaults / ส่งต่อ | 26: default privileges สำหรับ object ในอนาคต | 27–29: สร้างตารางใหม่, ตรวจผล, คืน ACL/RLS และส่งต่อบท 5 |

ภาพ role architecture, ownership separation, permission gates และ tenant isolation
คัดลอกจากต้นฉบับโดยไม่แก้ไฟล์ภาพ พร้อมคำอธิบายการ map เข้าชุด continuous:
student_xx เป็นเจ้าของ objects เดิม; actor/reader เป็น NOLOGIN roles;
RLS ใช้ app.customer_id ผ่าน policy.customer_id แทน app.tenant_id ในภาพ
Permission map เป็นแผนที่ขอบเขต ไม่ใช่ขั้นบังคับที่ทุก SELECT ต้องผ่าน ownership
GUC เป็นการจำลอง context ไม่ใช่ token ที่ verify แล้ว; ทำ expected error / SAVEPOINT / ROLLBACK ตามคู่มือ

## ลำดับสไลด์บท 5 ตามรหัสแล็บ

บท 5 ใช้ pattern เดียวกับบท 1–4: Fundamental และภาพแนวคิดก่อนคำสั่งแล็บ
หัวข้อและ footer อ้างอิง [คู่มือบท 5](../labs/module-05-architecture.md) ด้วยรหัส **5A–5G**
ระบุ Session A/B ในหัวข้อที่ต้องสลับ connection ใช้ฐานของนักเรียนคนเดียวกันผ่าน direct port 5432

| หัวข้อคู่มือ | หน้าพื้นฐานก่อนเริ่ม | หน้าแล็บ / ตรวจผล |
| --- | --- | --- |
| เตรียม Session A/B | 2: สองเคลมเป้าหมายและข้อมูลจากบท 3 | บท 4 คืน ACL/RLS แล้ว |
| 5A — Backend และค่าเดิม | 3–7: architecture, command path, processes, row/tuple และ page state | 8: A เก็บสองเคลมและดู system columns; อ่านสถิติเต็มจากคู่มือ |
| 5B — UPDATE แต่ยังไม่ commit | 9: old/new versions และ index maintenance | 10: A เพิ่มยอด 100 แล้วค้าง transaction |
| 5C — Snapshot | 11–12: isolation และ snapshot หลัง commit | 13–15: B ตรึง snapshot → A COMMIT → B อ่านซ้ำแล้วจบ snapshot |
| 5D — DELETE / VACUUM | 16–17: deletion marks และ safe cleanup; 19–20: maintenance | 18: visibility ของ 006; 21: manual VACUUM และสถิติ |
| 5E — คืนสองเคลม | 22: logical keys และ identity เดิม | 23: คืนข้อมูลจาก cs_m5_original ใน A |
| 5F — WAL ของ 1,000 แถว | 24–25: WAL flush/writeback และขอบเขต LSN | 26–27: INSERT เต็มจากคู่มือและวัด before/after พร้อม relation path |
| 5G — คืนข้อมูลก่อนบท 6 | 28: ทบทวน visibility / durability / maintenance | 29: จบ B ก่อน A ลบเฉพาะ CLM-L5-*, VACUUM และ REFRESH summary |

ใช้ภาพ architecture, background processes, page/tuple, UPDATE, DELETE, WAL,
maintenance และ recap จากต้นฉบับโดยไม่แก้ไฟล์ภาพ พร้อม Speaker Notes ภาษาไทย
ภาพ UPDATE/DELETE ใช้ order id 1 และยอด 1000/1200; แล็บจริงใช้ CLM-L1-001 ยอด 15000/15100
และลบ CLM-L1-006 ภาพ page state ใช้ insurance.claim และ id/ctid ตัวอย่าง ไม่ใช่ค่าจริงของฐานนักเรียน
คง source `claimsure.claim`, จำนวน 100,006 แถว และลำดับสลับ A/B ของชุด continuous
insert LSN ไม่พิสูจน์ flush; WAL delta บน shared cluster อาจรวมงานอื่น; ไม่สั่ง CHECKPOINT บน shared server


## ลำดับสไลด์บท 6 ตามหัวข้อคู่มือ

[Configuration](module-06-configuration-simple.md) · **34 หน้า / 11 Fundamentals**

| หัวข้อคู่มือ | หน้าพื้นฐาน | หน้าแล็บ / ตรวจผล |
| --- | --- | --- |
| 6A | 3–5 | 6–7 |
| 6B | 8–9 | 10–11 |
| 6C | 12 | 13–14 |
| 6D.1–6D.4 | 15–16 | — |
| 6D.1 | — | 17–18 |
| 6D.2 | — | 19 |
| 6D.3 | — | 20 |
| 6D.3–6D.4 | — | 21 |
| 6D.4 | — | 22 |
| 6E | 23 | 24–27 |
| 6F.1–6F.2 | 28 | — |
| 6F.1 | — | 29 |
| 6F.2 | — | 30–31 |
| 6G | 32 | 33–34 |

6A/B/C/E ใช้ shared claimsure_xx; 6D/F ใช้ private copy ตามคู่มือ ภาพ WAL/checkpoint ไม่ใช่ค่าที่วัดจริง และ max_wal_size เป็น soft limit


## ลำดับสไลด์บท 7 ตามหัวข้อคู่มือ

[Backup & Recovery](module-07-backup-recovery.md) · **32 หน้า / 12 Fundamentals**

| หัวข้อคู่มือ | หน้าพื้นฐาน | หน้าแล็บ / ตรวจผล |
| --- | --- | --- |
| 7.1 | 3 | — |
| 7.1–7.4 | 4, 5, 6 | — |
| 7.1a–7.1d | — | 7 |
| 7.1e | — | 8 |
| 7.2a–7.2i | 9 | — |
| 7.2a | — | 10 |
| 7.2c–7.2d | — | 11 |
| 7.2e–7.2f | 12 | — |
| 7.2e | — | 13 |
| 7.2f–7.5a | 14 | — |
| 7.2f | — | 15 |
| 7.2g–7.2i | — | 16 |
| 7.3a–7.3b | 17 | 18 |
| 7.3c | — | 19 |
| 7.3d–7.3e | — | 20 |
| 7.4a–7.4h | 21, 22 | — |
| 7.4a–7.4b | 23 | — |
| 7.4a | — | 24 |
| 7.4b | — | 25 |
| 7.4b–7.4e | — | 26 |
| 7.4f | — | 27 |
| 7.4g | — | 28 |
| 7.4h | — | 29 |
| 7.5a | 30 | 31 |
| 7.6a–7.6b | — | 32 |

คง dependency customer → policy → claim; พิสูจน์แถวหลัง base backup ใน PITR, แยก paused recovery/verification และ cleanup ตามคู่มือ ใช้รหัส 7.1a–7.6b แทน A2/C1/D2 ของฉบับเก่า


## ลำดับสไลด์บท 8 ตามหัวข้อคู่มือ

[Replication & HA](module-08-replication-th.md) · **32 หน้า / 10 Fundamentals**

| หัวข้อคู่มือ | หน้าพื้นฐาน | หน้าแล็บ / ตรวจผล |
| --- | --- | --- |
| Step 1–15 | — | 2, 32 |
| Step 1–8 | 3 | — |
| Step 1 | — | 4–5 |
| Step 2–4 | 6 | — |
| Step 2 | — | 7 |
| Step 3–4 | — | 8 |
| Step 5 / 10–11 | 9 | — |
| Step 5 | — | 10 |
| Step 6–8 | 11 | — |
| Step 6 | — | 12 |
| Step 7 | — | 13 |
| Step 8 | — | 14 |
| Step 9 | — | 15 |
| Step 10 | 16 | 17–18 |
| Step 11 | — | 19 |
| Step 12 | 20 | 21 |
| Step 13a–f | 22–23 | — |
| Step 13a–b | — | 24 |
| Step 13c | — | 25 |
| Step 13d–e | — | 26 |
| Step 13f | — | 27 |
| Step 14 | 28 | 29 |
| Step 15 | 30 | 31 |

ตารางนี้ใช้กับทั้งภาษาไทยและ English; publication ใช้ lab_repl.canary แทน insurance ในตัวอย่างเดิม ไม่ถือว่าการสร้าง publication อย่างเดียวพิสูจน์ logical delivery


## ลำดับสไลด์บท 9 ตามหัวข้อคู่มือ

[Monitoring](module-09-monitoring.md) · **31 หน้า / 10 Fundamentals**

| หัวข้อคู่มือ | หน้าพื้นฐาน | หน้าแล็บ / ตรวจผล |
| --- | --- | --- |
| 9A–9G | — | 2 |
| 9A | 3–5, 7 | 6, 8–9 |
| 9B | 10 | 11 |
| 9C | 12 | 13–15 |
| 9D–9E | 16 | — |
| 9D | — | 17–19 |
| 9E | 20 | 21–23 |
| 9F | 24 | 25–26 |
| 9G | 27 | 28–29 |
| 9G / คืนค่า | — | 30–31 |

ใช้ native pgbench 120s ใน lab_m9_shell; ติดแท็ก module09_xx_; blocking รอ 60–90s ให้ scrape เห็น; ไม่ล้าง counters/history ภาพ pipeline เป็น architecture อ้างอิง ไม่ได้แปลว่าห้องเรียนมี Alertmanager, node_exporter, replica metrics หรือ app p99


## ลำดับสไลด์บท 10 ตามหัวข้อคู่มือ

[Modern PostgreSQL](module-10-modern-features-supabase.md) · **34 หน้า / 13 Fundamentals**

| หัวข้อคู่มือ | หน้าพื้นฐาน | หน้าแล็บ / ตรวจผล |
| --- | --- | --- |
| 10A–10H | 2 | — |
| 10A | — | 3, 6, 7 |
| 10A–10B | 4, 5 | — |
| 10B–10E | 8 | — |
| 10B | 9 | 10, 11 |
| 10C–10E | 12 | — |
| 10C | — | 13, 14 |
| 10D | 15, 16, 17 | 18, 19, 20 |
| 10E | 21 | 22, 23 |
| 10F.0–10F.1 | 24 | — |
| 10F.0–10G | 25 | — |
| 10F.1–10G | 26 | — |
| 10F.0 | — | 27 |
| 10F.1 | — | 28, 29, 30 |
| 10G | — | 31, 32 |
| 10H | — | 33, 34 |

10F.0 เป็นงาน Instructor และ 10F.1 เป็น Student context simulation; 10G ใช้ Supabase project แยกและ user access token จริง ภาพ partition ใช้ Jul–Sep แต่แล็บใช้ Jan–Mar 2026; toy vector(3) ไม่ใช่ embedding model จริง
