# ผลตรวจ Lab Security ตามสไลด์ภาษาไทย

ตรวจวันที่ 11 พฤศจิกายน 2026 บน **PostgreSQL 18.6** ใน Container ชั่วคราวที่แยกจากฐานข้อมูลห้องเรียนทั้งหมด

## Source ที่ตรวจ

- สไลด์ภาษาไทยที่นำเข้า: **38 หน้า** ตามลำดับต้นทาง
- Pure SQL: **36 START/END blocks** ตั้งแต่ `0` ถึง `4H.2`
- Source SQL และ Reset SQL ปรับชื่อ NOLOGIN roles ให้ใช้ prefix `role_` ตามมาตรฐานของ Lab โดยเก็บ SHA-256 ของต้นฉบับและไฟล์ที่ปรับแล้วแยกกันใน [upstream.json](upstream.json)
- SQL blocks ใน [คู่มือ](../module-04-security-user-management-th.md) ตรงกับ Source SQL ที่ปรับชื่อแล้วทุกบล็อก

## วิธีทดสอบและผล

ใช้ **TCP/SCRAM connections ที่คง session จริง** ห้าบัญชี ได้แก่ A=`postgres`, S=`student_01`, B=`claim_app_01`, C=`internal_auditor_01`, D=`manager_th_01` รันแต่ละ Block ตาม LOGIN ที่ Source ระบุ

| ส่วน | ผล |
| --- | --- |
| 0 / 4A | ตรวจ database/administrator/version ผ่าน, สร้างครบ 11 roles และส่งมอบ SET ROLE Owner ให้ S |
| 4B | S เป็นผู้ใช้ปกติ, Activate Owner ได้, สร้างตาราง/seed แล้วกลับเป็น student หลัง COMMIT |
| 4C | CONNECT, object grants และ membership ถูกต้อง; App อ่าน seed สามแถวได้; CREATE TABLE ได้ 42501 |
| 4D | Tenant 101 อ่านสองแถว, เพิ่มแถวของตนชั่วคราวได้, INSERT ข้าม tenant ได้ 42501, ไม่มี context เห็นศูนย์แถว |
| 4E | Auditor อ่านชื่อได้แต่ contact fields ได้ 42501; Manager แก้ status ได้แต่ amount ได้ 42501 |
| 4F | Count function คืน 2, UPDATE ที่ COMMIT เป็น UNDER_REVIEW, Auditor อีก connection อ่าน audit ได้ actor=claim_app_01 / operation=UPDATE |
| 4G | App อ่าน future_note ได้หนึ่งแถวผ่าน default ACL โดยไม่ต้องเพิ่ม grant รายตาราง |
| 4H | Effective matrix เป็น true,true,false,true,false,false; owner และ RLS flags ตรงตาม Source |
| Recovery | Expected error ทั้งห้าบล็อกได้ 42501; query ก่อน recovery ได้ 25P02; ROLLBACK ใน connection เดิมแล้วทำงานต่อได้ |
| Reset | ปฏิเสธเลขนักเรียนไม่ตรง, ลบ schema/11 roles ของ Lab ได้ และคง database, student_01 กับตาราง claimsure.keep_me นอก Lab ไว้ |

สถานะสุดท้ายก่อน reset: claim_secure **3 แถว**, SEC-101-001 เป็น **UNDER_REVIEW**, audit **1 แถว**, ไม่มี SEC-C-ALLOWED / SEC-D-ALLOWED / SEC-D-DENIED ค้างอยู่

ดู [verification.json](verification.json) สำหรับผลแต่ละ block ไม่บันทึกรหัสผ่านหรือ API tokens ในรายงาน Passwords ที่ใช้ทดสอบสุ่มขึ้นสำหรับ Container ชั่วคราวเท่านั้น ไม่ใช้ Password placeholders ของ Source เป็นรหัสจริง

สไลด์ทั้ง 38 หน้า build และเปิดตรวจผ่าน Slidev ได้ รูปประกอบโหลดครบและไม่มี browser script errors นำ shared CSS ของ Module 4 ต้นทางมารองรับการเปิดตรง URL ของแต่ละหน้า โดยจำกัด selectors ให้ชุด Pure SQL ส่วนหน้าเนื้อหายาวยังเลื่อนแนวตั้งได้ตามต้นฉบับ ไฟล์สไลด์ Module 4 เวอร์ชันเดิม, Clone และธีมร่วมเดิมไม่ถูกแก้ไข

การทดสอบนี้ยืนยัน SQL และลำดับ Login ของชุดฝึก ไม่ได้ทำให้ custom GUC app.tenant_id เป็น Authentication ที่เชื่อถือได้สำหรับแอปจริง และไม่รับรอง HBA/Password configuration ของ server ห้องเรียนโดยอัตโนมัติ
