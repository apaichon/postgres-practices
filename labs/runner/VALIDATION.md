# ผลตรวจ continuous shell runner

> Account and database names in this text use `xx` as an anonymized placeholder. Raw screenshots and verification records are historical evidence; use your assigned account for new runs.

ตรวจวันที่ 10 พฤศจิกายน 2026 บน PostgreSQL **18.6** ใน container ใหม่ที่แยกจาก shared/private servers ของห้องเรียน ใช้ SQL login `student_xx` / ฐาน `claimsure_xx` และ OS user ที่ไม่ใช่ root

## ชุดหลัก

รันครบ **86 ขั้นหลัก** ของบท 1–7, 9 และ 10 ตามลำดับ รวม instructor role preparation/cleanup ของบท 4/10 ด้วย admin connection แยกจาก student connection

| ส่วน | หลักฐานที่ตรวจ |
| --- | --- |
| 1–3 | สร้าง customer/policy/claim, view/routines, ขยายเป็น 100,006 เคลม, indexes/report/materialized view |
| 4 | ตรวจ SQLSTATE 42501 ตามจำนวนที่คาด; คืน ACL/RLS/audit/default privileges; ลบ roles ทดลอง |
| 5 | MVCC สอง connections, committed delete, คืนสองเคลมพร้อม ID เดิม, ลบ WAL demonstration rows |
| 6 | 12 sort samples, 57014/55P03 timeouts, 120,000-row loads ที่ 64MB/256MB, autovacuum observation/reset, logging/row-lock waits |
| 7 | Logical restore, cold copy/restore, verified physical base, named-target PITR ที่ pause, คืน baseline |
| 9 | pgbench 30 วินาที, ตรวจคู่ blocked/blocker, deadlock 40P01 หนึ่ง victim, rollback ทั้งสองฝั่ง |
| 10 | JSONB/FTS/event partitions, customer-based RLS simulation, restore metadata/description และถอดส่วนเพิ่ม |

หลังจบ ข้อมูล `claimsure.claim` ทั้ง 100,006 แถวมีจำนวน, ยอดรวม และ hash ของทุกคอลัมน์เรียงตาม claim_id ตรงกับ baseline หลังบท 3–5: ยอดรวม `1,883,400,000.00` ไม่รวม sequence positions ในข้ออ้างนี้ เพราะการทดลองที่ rollback อาจทำให้ sequence ข้ามเลขได้ตามปกติ

ตรวจด้วยว่า RLS/FORCE RLS ปิดกลับ, autovacuum reloptions คืนค่าเดิม, ไม่มี NOLOGIN roles ทดลองเหลือ และไม่มี runner connections ค้าง

## การเลือกขั้นและรันต่อ

- บท 7 แยก `7.1`/`7.2` ใน invocation แรก แล้ว `--resume` ทำ cold backup/PITR ต่อใน invocation ใหม่สำเร็จ
- บท 10 แยก `10A`–`10D` แล้ว `--resume` ใน connection ใหม่; ใช้ CSV snapshot คืนหกเคลมสำเร็จ
- `run all --instructor --resume` ข้ามขั้นที่สำเร็จครบทุก module
- private servers ที่หยุดอยู่เปิดกลับจาก state เดิมได้ ทั้งบท 6 และ 7
- เตรียม/ลบ instructor roles คนละ invocation ได้
- ทดสอบ student **04** เพิ่มเติมในฐานของตนสำหรับบท 1–4 ยืนยันว่า runner ไม่ hardcode roles เป็น 01 และไม่รับ `PGUSER=postgres` มาแทน student session

## กรณีผิดพลาด

- ขั้นที่สำเร็จแล้วถูกกันไม่ให้รันซ้ำโดยไม่มี `--replay`
- เลือก 7.4b โดยไม่มี physical-base prerequisites ถูกปฏิเสธก่อน INSERT
- SQL error ที่ไม่คาดไว้ทำให้หยุด และ `--resume` ไม่ replay ขั้นที่ค้างโดยไม่มี `--retry-failed`
- state ที่ผูกกับ server/port อื่นถูกปฏิเสธ
- กด Ctrl+C ระหว่าง 6E หลัง UPDATE 5,000 แถว: ปิด connections, คืน statuses และ autovacuum options จาก snapshot; ตรวจ hash ทั้งตารางแล้วยังตรง baseline
- CLI `list`, `show`, `check` ทำงานโดยไม่เชื่อม PostgreSQL; module 8 และเลขนักเรียนผิดรูปแบบถูกปฏิเสธ

## ขอบเขต optional

ตรวจการแจ้งข้าม 9F และ 10E เมื่อไม่มี extension แล้ว ยังไม่ได้ทดสอบผลเชิงบวกของ pg_stat_statements, pgvector, Prometheus/Grafana หรือ Supabase project จริงในรอบนี้ ส่วนเหล่านี้ต้องมีบริการ/credentials ที่อาจารย์เตรียม และเลือกตาม [คู่มือ runner](../RUNNER.md)

1Z/2Z เป็นคำสั่งคืนค่าเมื่อจบคอร์ส จึงไม่รวมในการรันหลักที่ต้องเก็บ objects ไว้ให้บทถัดไป 7.6 เป็นคำอธิบายทางเลือก ไม่ใช่การทดลอง timestamp อีกครั้งโดยอัตโนมัติ

## ตรวจ CLI/recipes ซ้ำโดยไม่เชื่อมฐานข้อมูล

จากโฟลเดอร์ `command-line-continuous`:

```bash
python3 -m unittest discover -s runner -v
bash ./run-labs.sh check all
bash -n ./run-labs.sh
```

Unit tests **9 รายการ** ผ่าน ครอบคลุม selectors/group ordering, การกัน external/destructive steps จาก broad selectors, default course plan, expected SQLSTATE declarations, source-block references และ read-only/invalid CLI paths
