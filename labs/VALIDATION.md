# ผลการตรวจเวอร์ชันต่อเนื่อง

> Account and database names in this text use `xx` as an anonymized placeholder. Raw screenshots and verification records are historical evidence; use your assigned account for new runs.

[กลับสารบัญ](README.md)

ตรวจวันที่ 2026-11-09 บน PostgreSQL **18.6** ใน instance ทดสอบแยก ไม่มีการเชื่อมไปเปลี่ยน shared server ของห้องเรียน ใช้ claimsure_xx / student_xx ที่ไม่มี SUPERUSER/CREATEROLE; instructor เตรียม NOLOGIN roles และ labadmin ใช้เฉพาะ private instances

## ลำดับที่รันจริง

รัน 1 → 2 → 3 → 4 → 5 → 6 → 7 → 9 → 10 บนข้อมูลชุดเดียวกันใน schema claimsure: ลูกค้า 3 ราย กรมธรรม์ 3 ฉบับ เคลมเดิม 6 แถว และ CLM-L3-* เพิ่ม 100,000 แถว

| บท | ผลที่ตรวจผ่าน |
| --- | --- |
| 1–2 | SQL ก่อน optional cleanup ครบ; CRUD, JOIN, view/functions/procedure, CTE/window/FILTER และ procedure rollback |
| 3 | ขยาย claim จริงโดยอ้างกรมธรรม์/ลูกค้าเดิม; partial covering, expression, GIN, BRIN, maintenance, report partitions; materialized view ใช้ claim_tax เดิม; stale → refresh (+7.00 ในกลุ่มที่ทดลอง) → rollback |
| 4 | Schema/table/direct sequence/RLS/column ได้ 42501 ทั้ง 5 จุด; identity INSERT สำเร็จโดยไม่ grant sequence; customer-based RLS ผ่าน view, audit และ default privileges; rollback และลบเฉพาะ NOLOGIN roles |
| 5 | สอง sessions อ่าน 15000 → snapshot 15000 → ใหม่ 15100; DELETE visibility, คืนแถวด้วย claim_id เดิม, WAL ของ 1,000 เคลมใหม่ และลบเฉพาะ CLM-L5-* |
| 6 shared | ค่าเดิม/role default rollback; sort ที่ original/64kB/4MB/32MB; statement 57014 และ lock 55P03; autovacuum จริงจาก 5,000 dead tuples เป็น 0 และ count +1; คืน options/status |
| 6 private | Dump/restore สามตารางและ sequences/indexes จาก shared; INSERT CLM-WAL-* 120,000 แถวเท่ากันสอง pass ที่ 64MB/256MB; counters/WAL; log มี slow/temp/lock events หลังเปิด candidate; rollback settings และหยุด private |
| 7 | Logical loss/ordered data-only restore; cold copy + checksum/recovery; basebackup + verifybackup; named-target PITR ที่ in recovery/paused; CLM-L1-002 กลับมาและ CLM-L7-AFTER-BASE ถูก replay โดยไม่มี CLM-L7-LOSS; import/คืน baseline/หยุด private |
| 9 | Native pgbench บน claim เดิม, failed transactions=0; blocked/blocker จริง; deadlock 40P01; rollback ยอดเงินทุกเคลม |
| 10 | JSONB/expression index, generated FTS บน claim จริง, partitions จาก incident_at ของ 6 เคลม, detach rollback; simulated API RLS ตาม customer ได้ 4/2/0 เคลมตั้งต้น; scoped cleanup และคืนค่าข้อมูล |

เทียบ hash ของข้อมูลทุกคอลัมน์ใน **claim ทั้ง 100,006 แถว** ก่อนบท 5 กับหลัง reset ของบท 6 และหลังจบบท 10 แล้วตรงกัน ตารางหลัก/view/routines บท 2 ยังคงอยู่ RLS/reloptions คืนค่าเดิม Sequence อาจมีช่องว่างจาก rollback/การทดลอง และไม่จำเป็นต้องย้อนตัวเลขให้เท่าก่อนเริ่ม

## ขอบเขตการวัด

- การตรวจ work_mem ใช้หนึ่งรอบต่อค่าเพื่อตรวจ workflow; คู่มือให้นักเรียนวัดอย่างน้อยสามรอบเพื่อหา median ไม่ใช้เวลาของ test instance เป็นผล benchmark ห้องเรียน
- pgbench ใช้ 3 วินาทีใน smoke test; คู่มือใช้ 30 วินาทีและจบ transaction ด้วย ROLLBACK จึงไม่สะสมยอดเคลม
- Autovacuum test instance ใช้ naptime=1s; คู่มือให้สังเกตอย่างน้อย 75 วินาที/วัดตาม worker จริง ไม่ยกเวลาทดสอบนี้เป็น SLA
- Harness ของ logging ถือ lock แบบ bounded เพื่อประสานสอง sessions; คู่มือให้นักเรียนเริ่ม sleep 3 วินาทีเมื่อเห็นอีก session รอแล้ว
- WAL ของ claim ที่มี PK/FK/indexes แตกต่างจาก wal_probe ในเวอร์ชันเดิม; ไม่ย้ายตัวเลข 192MiB หรือจำนวน checkpoints จากสไลด์มาเป็น expected result ของเวอร์ชันนี้

## Optional ที่ต้องมีบริการของห้องเรียน

- **pgvector:** ทดสอบทางเลือกเมื่อไม่มี extension แล้วข้ามได้; vector/HNSW เมื่อมี extension ยังต้องตรวจบน image ที่อาจารย์อนุมัติ
- **pg_stat_statements และ Prometheus/Grafana:** ไม่มี preload/stack ใน instance นี้ ต้องตรวจ query/labels/dashboard บนสภาพแวดล้อมห้องเรียน ไม่ reset สถิติรวม คู่มือบท 9 หลังรอบตรวจนี้ใช้ schema `lab_m9_shell` และชื่อ `module09_xx_` ตาม collector ของ Grafana lab แถวบท 9 ในตารางด้านบนเป็นผลของรอบที่ยังทดลองบน claim แล้ว ROLLBACK
- **Supabase จริง:** ยังไม่ได้เรียก project API หรือยืนยัน user token จริง ทดสอบ native CSV → TEMP staging → course_claim แล้วในฐานข้อมูลจำลองแยก ได้ 6 แถว/owner เดียว ครอบคลุมรูปแบบ COPY/psql variables แต่ไม่ใช่การทดสอบ auth.uid หรือ Data API ของ Supabase
- **Timestamp PITR:** ทดสอบหลักครบด้วย named restore point; ทางเลือก timestamp ต้องเริ่มจาก base ใหม่และตรวจ paused/เคลมซ้ำตามคู่มือ

## ตรวจรูปแบบ

ตรวจ 51 Bash blocks ด้วย bash -n, code fences, ลิงก์ไฟล์ภายใน และการไม่มีคำสั่งเรียก shell runner/DROP SCHEMA ใน code blocks คู่มือแสดง SQL/native PostgreSQL commands ให้รันทีละขั้น ไม่ให้ผู้เรียนเรียก harness ที่ใช้ตรวจเอกสารนี้
