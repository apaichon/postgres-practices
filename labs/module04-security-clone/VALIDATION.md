# ผลตรวจ Lab 4 — Clone schema

ตรวจวันที่ 11 พฤศจิกายน 2026 บน **PostgreSQL 18.6** ใน Container ชั่วคราวที่แยกจากฐานข้อมูลห้องเรียน ใช้ตารางและข้อมูลจากบท 1–3: ลูกค้า 3 ราย, กรมธรรม์ 3 ฉบับ และเคลม **100,006 แถว**

ทดสอบ app ด้วย **TCP/SCRAM Login จริงทั้งห้าบัญชี** ไม่ใช้ superuser หรือ `SET ROLE` จำลองผู้ใช้ app ผลตรวจ:

| ส่วน | ผล |
| --- | --- |
| Clone | ทุกแถวถูก copy, identity sequences แยก, FK ทั้งสองชี้ schema Lab และ view ไม่ขึ้นกับตารางต้นทาง |
| Permission gates | ยังไม่มี schema USAGE → 42501; มี USAGE แต่ไม่มี table SELECT → 42501; ให้ SELECT แล้วอ่านหกเคลมตั้งต้นได้ |
| Role inheritance / column grants | Writer รับ SELECT ผ่าน reader; อ่าน email, สร้าง table, Reader INSERT ถูกปฏิเสธ |
| Sequence | Identity INSERT สำเร็จก่อนให้ sequence USAGE; direct nextval ถูกปฏิเสธก่อน GRANT และสำเร็จหลัง GRANT |
| RLS | Reader A เห็น CLM-L1-001–004, B เห็น 005–006; ตั้ง `app.customer_id` เองไม่เปลี่ยนผล; อ่าน mapping/สลับเป็น owner ไม่ได้ |
| INSERT | NEW ของตนสำเร็จและอ่านได้จาก connection ใหม่; ผู้อื่นมองไม่เห็น; INSERT ข้ามลูกค้า/ตั้ง APPROVED ถูกปฏิเสธ |
| UPDATE / DELETE | Approver แก้ status ของตนได้; ของลูกค้าอื่น UPDATE 0; แก้ amount, DELETE และ Writer UPDATE ถูกปฏิเสธ |
| Audit | บันทึก REVIEW → APPROVED และชื่อ Login ของ Approver จริง; Auditor อ่านได้แต่แก้ไม่ได้ และอ่าน claim ไม่ได้ |
| Default privileges | ตารางเดิมไม่รับ SELECT ย้อนหลัง; ตารางที่ owner สร้างหลังตั้งค่าอ่านได้ |
| Source isolation | เทียบจำนวน, hash ของทุกคอลัมน์ทุกแถว, table ACL, RLS flags และ identity sequence state ของ source ทั้งสามตาราง: ตรงทั้งหมด |
| Guard | เตรียมซ้ำ, Database/หมายเลขไม่ตรง, cleanup ไม่มี confirmation/ชื่อผิด หยุดด้วย psql exit 3 |
| Cleanup / เริ่มใหม่ | ลบ schema Lab และ roles ได้รวม default ACL dependencies; source ยังมี 100,006 แถว และสร้าง Lab ใหม่ได้ |

ชุด permission/RLS/audit/default-privilege matrix ผ่าน 36 checks ก่อนตรวจ source และ cleanup เพิ่มเติม ตรวจ Bash syntax, ลิงก์ในคู่มือ และยืนยันว่าไม่มีคำสั่ง SQL `ROLLBACK`/`SAVEPOINT` ในคู่มือเวอร์ชันนี้และไฟล์ประกอบ

ตรวจ Password prompt ของ psql `\password :read_a` แยกด้วย pseudo-terminal และยืนยันว่าใช้รหัสที่ตั้งใหม่ Login ทาง TCP/SCRAM ได้จริง ไม่เก็บ Passwords ไว้ในเอกสารนี้

ผลนี้เป็นการตรวจบน source fixture ของหลักสูตร ไม่ใช่การรับรอง clone schema ใด ๆ โดยอัตโนมัติ หากเปลี่ยน types, defaults, FKs หรือโครงสร้าง core tables ให้ทบทวนขอบเขตของ [คู่มือ](../module-04-security-clone.md) ก่อนใช้
