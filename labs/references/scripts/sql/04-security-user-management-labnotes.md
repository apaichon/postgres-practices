# Module 4: ตาราง Login และลำดับ Lab สำหรับนักเรียน xx

ใช้คู่กับ [04-security-user-management.sql](04-security-user-management.sql) และ สไลด์ Module 4 (ส่วนแยกในต้นฉบับ: `docs/slides/module-04-security-user-management.md`)

ก่อนรันใน SQL editor ให้แทน `xx` ทุกแห่งด้วยเลขนักเรียนสองหลักของตน หรือใช้ `--student xx` กับ [shell runner](../shells/README.md#module-4-security-and-user-management) เพื่อแทนเลขให้อัตโนมัติ

**ใช้ postgres เฉพาะขั้น 0 และ Lab 4A ให้จบการเตรียมระบบ จากนั้นใช้ student_xx และบัญชีของนักเรียน xx เป็นหลัก** ทุก Connection ใช้ Database `claimsure_xx` บน Host และ Port เดียวกัน

## ตารางเลือก Login ก่อนรันแต่ละชุด

| Lab / ขั้น | Login ที่ต้องใช้ | Role ที่ทำงาน | งานที่ทำ |
| --- | --- | --- | --- |
| **0 และ 4A.1–4A.4** | **`postgres`** | `postgres` | สร้าง Role, ตั้ง Password, เตรียม Schema และมอบสิทธิ์ให้ `student_xx` |
| **4B.1–4B.3** | `student_xx` | `claimsure_owner_xx` ผ่าน SET LOCAL ROLE | สร้างตารางและข้อมูลตั้งต้น |
| **4C.1–4C.3** | `student_xx` | `student_xx`; ใช้ Owner ใน 4C.2 | ตรวจ CONNECT/Membership และให้สิทธิ์ Object |
| **4C.4–4C.6** | `claim_app_xx` | `claim_app_xx` | ทดสอบอ่าน/เพิ่มข้อมูล และทดสอบว่าสร้างตารางไม่ได้ |
| **4D.1** | `student_xx` | `claimsure_owner_xx` | ตั้ง RLS policy |
| **4D.2–4D.5** | `claim_app_xx` | `claim_app_xx` | ทดสอบการอ่านและเขียนตาม Tenant |
| **4E.1** | `student_xx` | `claimsure_owner_xx` | ให้สิทธิ์เฉพาะ Column |
| **4E.2–4E.4** | `internal_auditor_xx` | `internal_auditor_xx` | อ่านชื่อได้ แต่อ่าน Contact ไม่ได้ |
| **4E.5–4E.7** | `manager_th_xx` | `manager_th_xx` | แก้ Status ได้ แต่แก้จำนวนเงินไม่ได้ |
| **4F.1–4F.2** | `student_xx` | `claimsure_owner_xx` | สร้าง Function และ Audit trigger |
| **4F.3–4F.5** | `claim_app_xx` | `claim_app_xx` ที่จุดเรียก | เรียก Function, UPDATE และทดสอบว่าลบ Audit ไม่ได้ |
| **4F.6** | `internal_auditor_xx` | `internal_auditor_xx` | อ่านหลักฐาน Audit |
| **4G.1** | `student_xx` | `claimsure_owner_xx` | ตั้ง Default privileges และสร้างตารางใหม่ |
| **4G.2** | `claim_app_xx` | `claim_app_xx` | ทดสอบอ่านตารางใหม่ |
| **4H.1–4H.2** | `student_xx` | Owner ใน 4H.1; `student_xx` ใน 4H.2 | ตรวจสิทธิ์ Membership, Ownership และ RLS |

## จุดส่งมอบจาก postgres ไป student_xx

ต้องรัน **4A.4 ด้วย postgres ให้ครบก่อนเริ่ม 4B** ขั้นนี้เตรียม:

1. Schema `lab_m4_xx` ซึ่งเป็นของ `claimsure_owner_xx`
2. CONNECT สำหรับ Login ของ Lab
3. Membership ระหว่าง Group และ Login
4. สิทธิ์ให้ `student_xx` เปลี่ยนเป็น Owner อย่างชัดเจน:

~~~sql
GRANT claimsure_owner_xx TO student_xx
WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
~~~

คำสั่งนี้เป็นส่วนหนึ่งของ 4A.4 ให้รันทั้งชุดในไฟล์ SQL เพื่อให้ Schema และ Membership อื่นพร้อมด้วย

`student_xx` ไม่ได้รับ SUPERUSER หรือ CREATEROLE และไม่รับ Owner privileges อัตโนมัติ เมื่อทำ DDL จึงใช้ `SET LOCAL ROLE claimsure_owner_xx` ภายใน Transaction ตามที่ไฟล์ระบุ ส่วน App/Auditor/Manager ไม่ได้รับ Owner membership

## ตรวจ Connection ก่อนเริ่ม 4B

หลังจบ 4A.4 ให้เชื่อมต่อเป็น **student_xx** แล้วรัน:

~~~sql
SELECT session_user, current_user,
       pg_has_role(session_user, 'claimsure_owner_xx', 'SET')
         AS can_set_owner;
~~~

ต้องได้:

~~~text
session_user | current_user | can_set_owner
student_xx   | student_xx   | t
~~~

ถ้าได้ `f` ให้กลับไปตรวจ 4A.4 ด้วย Connection ของผู้ดูแลก่อน ไม่ต้องให้ SUPERUSER กับนักเรียน

## วิธีใช้ไฟล์ SQL ทีละชุด

- อ่าน `LOGIN` ด้านบนชุดคำสั่ง แล้วเลือก Connection ให้ตรง
- เลือกรันจาก `START <เลขขั้น>` ถึง `END <เลขขั้น>` ทีละชุด ไม่ใช้ Execute All
- ชุดที่ใช้ Owner มี BEGIN, SET LOCAL ROLE และ COMMIT หรือ ROLLBACK ให้ครบอยู่แล้ว
- ใน Connection ของ `student_xx` เมื่อ Transaction จบ Role จะกลับเป็น `student_xx`
- Function แบบ SECURITY DEFINER ใน 4F ทำงานภายในด้วย Owner privileges แล้วคืน Role ให้ผู้เรียกเมื่อจบ
- เมื่อเจอชุด EXPECTED ERROR ใน SQL editor ให้รันชุด RECOVERY ที่อยู่ถัดไปทันที
- Shell runner เปิด Session ใหม่ต่อคำสั่ง และตรวจ SQLSTATE พร้อม ROLLBACK ชุด EXPECTED ERROR ให้แล้ว จึงไม่ต้องรัน RECOVERY ซ้ำ

ตัวอย่างงานของ Owner โดย Login นักเรียน:

~~~sql
BEGIN;
SET LOCAL ROLE claimsure_owner_xx;
SELECT session_user, current_user;
-- รันคำสั่ง DDL หรือ GRANT ตามชุด Lab
COMMIT;
~~~

ระหว่าง Transaction: `session_user = student_xx` และ `current_user = claimsure_owner_xx` หลัง COMMIT: ทั้งสองกลับเป็น `student_xx`

หากมี Transaction ที่ Error ค้าง:

~~~sql
ROLLBACK;
~~~

หากต้องเริ่ม Lab ใหม่ ใช้ [ไฟล์ Reset ของ Module 4](04-security-user-management-reset.sql) ตามคำอธิบายในไฟล์นั้น การ Reset ต้องใช้ผู้ดูแล และจะลบ Schema พร้อมข้อมูลและ Role ของ Module 4 เฉพาะเลขนักเรียนที่เลือก
