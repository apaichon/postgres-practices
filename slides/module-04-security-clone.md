---
theme: default
title: "Module 4: Security Clone Schema"
layout: default
class: continuous-deck cs-module-four cs-module-four-clone cover
colorSchema: light
fonts:
  sans: Noto Sans Thai
  mono: JetBrains Mono
info: ClaimSure isolated security lab on PostgreSQL 18
transition: slide-left
mdc: true
lang: th
download: false
---

<CaseCover :module-id="4" />

# Module 4<br>Security

## Clone schema<br>ทดลองสิทธิ์และเก็บผลจริง

<footer class="cs-footer"><span>Security Clone · ภาพรวม</span><span>1 / 34</span></footer>

<!--
Speaker notes:
ใช้คู่กับ labs/module-04-security-clone.md เป็นอีก deck แยกจากเวอร์ชัน continuous เดิม เตรียมบท 1–2 และบท 3 หากต้องการ 100,006 แถว เปลี่ยน xx ทุกชื่อเป็นหมายเลข 01–20 ของตน รัน SQL ในคู่มือทีละขั้น สไลด์คัดเฉพาะคำสั่งสำคัญ ภาพปกใช้ asset หลักสูตรเดิม ./assets/module-04-security-cover-enterprise-blue.png

Source: ../labs/module-04-security-clone.md · ภาพรวม
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone cs-fundamental
---

# Fundamental: สำเนาข้อมูลสำหรับทดลองสิทธิ์

<SecurityCloneDiagram kind="clone" />

<p class="cs-concept-caption">ข้อมูลใหม่และ audit คงอยู่ใน lab_m4_clone_xx หลังปิด connection</p>

<footer class="cs-footer"><span>Security Clone · 4C.A</span><span>2 / 34</span></footer>

<!--
Speaker notes:
Clone ชุดตารางหลักจาก source snapshot เดียวกัน สิทธิ์และข้อมูลที่ทดลองเปลี่ยนใน schema ใหม่ บทถัดไปใช้ claimsure เดิม สำเนานี้ไม่ได้ sync ตามต้นทางอัตโนมัติ

Source: ../labs/module-04-security-clone.md · 4C.A
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.A: ขอบเขตที่ Clone

| Object | สิ่งที่อยู่ใน schema Lab |
| --- | --- |
| customer / policy / claim | โครงสร้างและข้อมูลทุกแถว |
| PK / UNIQUE / CHECK / indexes | คัดลอกด้วย LIKE INCLUDING ALL |
| Identity sequences | สร้างใหม่และตั้งเลขต่อจาก max(id) |
| Foreign keys | สร้างใหม่ให้อ้างตารางใน Lab |
| claim_detail_v | JOIN ตารางใน Lab ด้วย security_invoker |

<p class="cs-takeaway">Reports, partitions, routines และ ACL/RLS เดิมอยู่นอกขอบเขตการ clone นี้</p>

<footer class="cs-footer"><span>Security Clone · 4C.A</span><span>3 / 34</span></footer>

<!--
Speaker notes:
ใช้ scoped clone ตามโครงสร้าง course business tables ไม่ใช่คำสั่ง clone ทุก object ใน schema LIKE ไม่คัดลอก FK, ACL, RLS policies หรือ triggers ตามที่ Lab ต้องการ จึงสร้างความสัมพันธ์และสิทธิ์ใหม่ทั้งหมด generated columns คำนวณใหม่ตอน copy source ที่มี serial-style nextval default จะถูกปฏิเสธเพื่อป้องกันการใช้ source sequence ร่วมกัน

Source: ../labs/module-04-security-clone.md · 4C.A
Sources:
- https://www.postgresql.org/docs/18/sql-createtable.html
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone cs-fundamental
---

# Fundamental: FK และ Identity ของสำเนา

<SecurityCloneDiagram kind="foreignKeys" />

<p class="cs-concept-caption">policy อ้าง customer และ claim อ้าง policy ภายใน Lab</p>

<footer class="cs-footer"><span>Security Clone · 4C.A</span><span>4 / 34</span></footer>

<!--
Speaker notes:
INCLUDING IDENTITY สร้าง sequence ใหม่ การ copy ใช้ OVERRIDING SYSTEM VALUE เพื่อรักษา ID เดิม แล้วตั้ง setval ตาม max(id) เพื่อให้ INSERT รอบถัดไปไม่ชน FK ไม่ได้ติดมาจาก LIKE จึงสร้าง FK ใหม่ให้ชี้ clone ต้องเห็น sequence names ต่างจาก claimsure

Source: ../labs/module-04-security-clone.md · 4C.A
Sources:
- https://www.postgresql.org/docs/18/sql-createtable.html
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.0: บัญชีและหน้าที่

| Login / Group | หน้าที่ |
| --- | --- |
| m4c_read_a_xx / reader | อ่านเคลม CUS-001 |
| m4c_read_b_xx / reader | อ่านเคลม CUS-002 |
| m4c_create_a_xx / writer | เพิ่มเคลม NEW ของ CUS-001 |
| m4c_approve_a_xx / approver | แก้ status ของเคลม CUS-001 |
| m4c_audit_xx / auditor | อ่าน audit |

<p class="cs-takeaway">m4c_owner_xx เป็น NOLOGIN และเป็นเจ้าของ objects เท่านั้น</p>

<footer class="cs-footer"><span>Security Clone · 4C.0</span><span>5 / 34</span></footer>

<!--
Speaker notes:
ทุก group role ใช้ prefix m4c_ และ suffix _xx เช่น m4c_reader_xx ชื่อ Login ในคอลัมน์ซ้ายเป็นชื่อเต็ม ยกเว้นหลัง slash เป็นชื่อกลุ่มแบบย่อ Instructor สร้าง 5 groups และ 5 logins ไม่มี app Login เป็นสมาชิก owner บัญชีทุกตัว NOSUPERUSER NOCREATEROLE NOBYPASSRLS

Source: ../labs/module-04-security-clone.md · 4C.0
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone cs-fundamental
---

# Fundamental: Login และ Role inheritance

<SecurityCloneDiagram kind="roles" />

<p class="cs-concept-caption">INHERIT TRUE รับสิทธิ์จาก group และ SET FALSE จำกัดการสลับ role</p>

<footer class="cs-footer"><span>Security Clone · 4C.0</span><span>6 / 34</span></footer>

<!--
Speaker notes:
reader ให้ SELECT; writer และ approver สืบทอด reader ส่วน auditor อ่านเฉพาะ audit SET FALSE เป็นตัวเลือกของ membership เหล่านี้ ไม่ใช่การห้าม SET ROLE ทุก role ในระบบ อธิบายว่าการสืบทอด grants ไม่ได้ยก ownership หรือ superuser attributes ให้ app

Source: ../labs/module-04-security-clone.md · 4C.0
Sources:
- https://www.postgresql.org/docs/18/sql-grant.html
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.0: Instructor เตรียม Login

จาก root ของ repository เปิด psql ด้วย Instructor และ student_no ของตน

```sql
\i labs/module04-security-clone/01-roles.sql
\password :read_a
\password :read_b
\password :create_a
\password :approve_a
\password :audit_login
```

<p class="cs-takeaway">ตั้ง Password ผ่าน prompt และใช้ TCP/SCRAM ตาม HBA ของห้องเรียน</p>

<footer class="cs-footer"><span>Security Clone · 4C.0</span><span>7 / 34</span></footer>

<!--
Speaker notes:
เปิด psql -X -W -h 127.0.0.1 -p 5432 -U postgres -d claimsure_xx -v student_no=xx -v ON_ERROR_STOP=1 แทน xx ด้วยเลขจริงก่อน พาธ \i อ้างจาก repository root สคริปต์ตรวจ PostgreSQL 18+, ชื่อ database และ superuser สร้าง Login ด้วย PASSWORD NULL จึงต้องตั้งรหัสให้ครบ ไม่เก็บรหัสจริงใน SQL หรือ command history ชื่อซ้ำทำให้ script หยุดโดยไม่เขียนทับ

Source: ../labs/module-04-security-clone.md · 4C.0
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.A: Snapshot และสำเนาที่คงอยู่

```sql
\i labs/module04-security-clone/02-clone.sql

SELECT table_name, source_rows
FROM :"lab_schema".source_manifest
ORDER BY table_name;
```

<div class="cs-metrics"><div><b>3</b><span>ตารางธุรกิจ</span></div><div><b>100,006</b><span>เคลมเมื่อผ่านบท 3</span></div><div><b>COMMIT</b><span>เก็บสำเนาไว้ใช้งานต่อ</span></div></div>

<footer class="cs-footer"><span>Security Clone · 4C.A</span><span>8 / 34</span></footer>

<!--
Speaker notes:
Clone ใช้ REPEATABLE READ เพื่ออ่าน snapshot เดียวกัน หากทำเพียงบท 1–2 จำนวน claim จะเป็น 6 ไม่ hardcode จำนวนให้ตรงสไลด์ ตรวจ actual source_rows script เก็บ checksum ของทุกคอลัมน์ทุกแถว ACL/RLS และสถานะ source identity sequence ไว้เทียบตอนจบ การสำรองนี้มีไว้ตรวจการทดลอง ไม่ใช่ backup สำหรับ production

Source: ../labs/module-04-security-clone.md · 4C.A
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.A: หลักฐานว่า FK และ Sequence แยก

```sql
SELECT pg_get_serial_sequence('claimsure.claim', 'claim_id');
SELECT pg_get_serial_sequence(
  format('%I.claim', :'lab_schema'), 'claim_id');
```

| สิ่งที่ตรวจ | ผลที่ต้องได้ |
| --- | --- |
| Source sequence / Lab sequence | คนละชื่อและคนละ object |
| policy.customer_id FK | อ้าง lab_m4_clone_xx.customer |
| claim.policy_id FK | อ้าง lab_m4_clone_xx.policy |
| CLM-L1-* ในสำเนา | 6 แถว |

<footer class="cs-footer"><span>Security Clone · 4C.A</span><span>9 / 34</span></footer>

<!--
Speaker notes:
ใช้ query pg_constraint ในคู่มือเพื่อดู confrelid ของ FK จริง ตรวจ dependency ของ view ให้ชี้เฉพาะ clone ด้วย ข้อมูลชุดทดสอบต้นทางมี 100,006 แถวและผ่านการตรวจ FK/sequence แยกแล้ว แต่ให้ดูจำนวน source จริงเมื่อใช้ห้องเรียนอื่น

Source: ../labs/module-04-security-clone.md · 4C.A
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.B: App connection แยกจริง

```bash
psql -X -W -h "$PGHOST" -p "$PGPORT" \
  -U "m4c_read_a_$STUDENT_NO" \
  -d "claimsure_$STUDENT_NO" \
  -v student_no="$STUDENT_NO" -v ON_ERROR_STOP=1
```

```sql
SELECT 'lab_m4_clone_' || :'student_no' AS lab_schema \gset
SELECT current_database(), session_user, current_user;
```

<p class="cs-takeaway">สลับหน้าที่ด้วยการออกและเชื่อมใหม่ในชื่อ Login ที่ต้องทดสอบ</p>

<footer class="cs-footer"><span>Security Clone · 4C.B</span><span>10 / 34</span></footer>

<!--
Speaker notes:
ตั้ง STUDENT_NO=หมายเลขจริง, PGHOST และ PGPORT ตามคู่มือก่อนคำสั่งนี้ บัญชี Instructor ใช้เตรียม schema/grants เท่านั้น ส่วน app tests ใช้ connection จริงของแต่ละ Login ห้ามนำผลจาก postgres, owner หรือ student_xx มาอ้างเป็น app permission บล็อกเริ่ม app connection ไม่ใช้ context.sql เพราะไฟล์นั้นตรวจ Instructor

Source: ../labs/module-04-security-clone.md · 4C.B
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone cs-fundamental
---

# Fundamental: Autocommit และ Expected error

```sql
\set AUTOCOMMIT on
\set ON_ERROR_STOP off
SELECT claim_no FROM :"lab_schema".claim LIMIT 1;
\echo Expected 42501; actual :SQLSTATE
\set ON_ERROR_STOP on
```

| คำสั่งหนึ่งจบ | ผลที่ตรวจต่อได้ |
| --- | --- |
| คำสั่งสำเร็จ | ข้อมูลหรือสิทธิ์ commit แล้ว |
| คำสั่งถูกปฏิเสธ | อ่าน SQLSTATE แล้วลองคำสั่งถัดไป |

<p class="cs-takeaway">Expected errors อยู่ใน autocommit ทีละคำสั่ง</p>

<footer class="cs-footer"><span>Security Clone · 4C.B</span><span>11 / 34</span></footer>

<!--
Speaker notes:
ไม่เปิด BEGIN ยาวครอบขั้น expected errors จึงไม่ต้อง ROLLBACK TO SAVEPOINT เพื่อออกจาก failed transaction การปิด ON_ERROR_STOP เป็นเฉพาะช่วงที่ตั้งใจให้ error ไม่ใช้ซ่อนข้อผิดพลาดในการเตรียมระบบ BEGIN/COMMIT ใน setup scripts มีหน้าที่เก็บชุด DDL ที่สอดคล้องกัน

Source: ../labs/module-04-security-clone.md · 4C.B
Sources:
- https://www.postgresql.org/docs/18/app-psql.html
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone cs-fundamental
---

# Fundamental: ประตูสิทธิ์แต่ละระดับ

<SecurityCloneDiagram kind="gates" />

<p class="cs-concept-caption">Schema USAGE, table/column grants และ RLS มีหน้าที่ต่างกัน</p>

<footer class="cs-footer"><span>Security Clone · 4C.B</span><span>12 / 34</span></footer>

<!--
Speaker notes:
Schema USAGE ให้เข้าถึง objects ภายใน namespace แต่ยังต้องมี object privileges CREATE บน schema เป็นอีกสิทธิ์หนึ่งที่ app ไม่ได้รับ RLS จะกรองหรือบังคับค่าแถวเฉพาะ operation ที่มี grants แล้ว SQLSTATE 42501 อาจมาจาก schema, table, column หรือ RLS WITH CHECK ต้องอ่านรายละเอียด error ด้วย

Source: ../labs/module-04-security-clone.md · 4C.B
Sources:
- https://www.postgresql.org/docs/18/ddl-priv.html
- https://www.postgresql.org/docs/18/ddl-rowsecurity.html
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.B: ผลก่อนและหลัง GRANT

Instructor เปิด schema แล้วจึงเปิด table

```sql
GRANT USAGE ON SCHEMA :"lab_schema" TO :"reader_role";
GRANT SELECT ON :"lab_schema".claim TO :"reader_role";
```

| Reader A ทดสอบในแต่ละช่วง | ผล |
| --- | --- |
| ก่อนให้ USAGE | 42501: permission denied for schema |
| หลัง USAGE แต่ก่อน SELECT | 42501: permission denied for table |
| หลัง SELECT และยังไม่เปิด RLS | เห็น CLM-L1-* ทั้ง 6 แถว |

<p class="cs-takeaway">ให้ GRANT ทีละคำสั่ง แล้วกลับไปทดสอบ Reader ระหว่างขั้น</p>

<footer class="cs-footer"><span>Security Clone · 4C.B</span><span>13 / 34</span></footer>

<!--
Speaker notes:
อย่าวาง GRANT สองคำสั่งพร้อมกันถ้าต้องการเห็น table gate ที่ยังปิดอยู่ Instructor เป็นอีก Terminal จาก app Reader connection ดู SQLSTATE ของคำสั่งที่ตั้งใจ fail ได้ แล้วปิด ON_ERROR_STOP off กลับ on ตามคู่มือ ตอนนี้ยังไม่ติด RLS ให้เก็บผล 6 แถวเพื่อเทียบช่วง D

Source: ../labs/module-04-security-clone.md · 4C.B
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.C: Operations ของแต่ละ Group

| Group | สิทธิ์ที่กำหนดใน Lab |
| --- | --- |
| reader | SELECT claim และคอลัมน์ที่ view ใช้ |
| writer | INSERT เฉพาะคอลัมน์รับเคลมใหม่ |
| approver | UPDATE เฉพาะ status |
| auditor | SELECT claim_audit เมื่อเตรียม audit ใน D |

```sql
GRANT UPDATE(status) ON :"lab_schema".claim TO :"approver_role";
```

<p class="cs-takeaway">UPDATE(status) อนุญาตแก้สถานะโดยคงขอบเขตคอลัมน์อื่นไว้</p>

<footer class="cs-footer"><span>Security Clone · 4C.C</span><span>14 / 34</span></footer>

<!--
Speaker notes:
writer และ approver มี SELECT ผ่าน reader สิทธิ์ INSERT ระบุ claim_no,policy_id,status,incident_at,estimated_amount เท่านั้น writer จึงไม่แก้ยอดอนุมัติผ่าน INSERT ได้ในตัวอย่าง Auditor ยังไม่มี grant จนกว่าสคริปต์ 03 สร้าง audit table สำเร็จ ตารางนี้แสดงสิทธิ์สุดท้ายของแต่ละหน้าที่

Source: ../labs/module-04-security-clone.md · 4C.C
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.C: คอลัมน์ที่อ่านได้และคำสั่งที่ปฏิเสธ

```sql
GRANT SELECT(customer_id, customer_code, full_name)
  ON :"lab_schema".customer TO :"reader_role";
```

| Reader A ทดลอง | ผล |
| --- | --- |
| อ่าน customer_code / full_name | สำเร็จ |
| SELECT email | 42501 |
| CREATE TABLE ใน schema Lab | 42501 |
| INSERT claim | 42501 |

<p class="cs-takeaway">ทดสอบคอลัมน์และ operation ที่อยู่นอกหน้าที่ด้วย</p>

<footer class="cs-footer"><span>Security Clone · 4C.C</span><span>15 / 34</span></footer>

<!--
Speaker notes:
ไม่มี table-level SELECT บน customer; ให้เฉพาะคอลัมน์ที่ view ต้องใช้ ดังนั้น SELECT * ก็ไม่ได้ผ่านเพียงเพราะอ่านบางคอลัมน์ได้ ไม่ให้ schema CREATE แก่ app ส่วน policy ให้คอลัมน์ policy_id/customer_id/policy_no/product_code ที่ view และ query ต้องใช้

Source: ../labs/module-04-security-clone.md · 4C.C
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone cs-fundamental
---

# Fundamental: Identity INSERT และ nextval

<SecurityCloneDiagram kind="identity" />

<p class="cs-concept-caption">สิทธิ์เรียก sequence โดยตรงตรวจแยกจาก identity INSERT</p>

<footer class="cs-footer"><span>Security Clone · 4C.C</span><span>16 / 34</span></footer>

<!--
Speaker notes:
PostgreSQL identity default จ่าย ID ให้ INSERT ที่มีสิทธิ์คอลัมน์ โดยไม่ได้ต้องให้ sequence USAGE เพิ่มเหมือน serial-style default ส่วน nextval โดยตรงต้องมี USAGE หรือ UPDATE บน sequence ที่ Lab ให้ USAGE เป็นตัวอย่าง เลข sequence อาจข้ามได้จากการทดลองหรือคำสั่งที่ถูกปฏิเสธภายหลัง

Source: ../labs/module-04-security-clone.md · 4C.C
Sources:
- https://www.postgresql.org/docs/18/ddl-identity-columns.html
- https://www.postgresql.org/docs/18/functions-sequence.html
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.C: Writer เพิ่มเคลมผ่าน Identity

```sql
INSERT INTO :"lab_schema".claim
  (claim_no, policy_id, status, incident_at, estimated_amount)
SELECT 'CLM-M4C-SEQUENCE', policy_id, 'NEW', now(), 100
FROM :"lab_schema".policy
WHERE policy_no = 'POL-001'
RETURNING claim_id, claim_no;
```

<p class="cs-takeaway">เคลมอยู่จริงในสำเนา และ claim_id ต่อจากข้อมูลที่ copy มา</p>

<footer class="cs-footer"><span>Security Clone · 4C.C</span><span>17 / 34</span></footer>

<!--
Speaker notes:
ใช้ m4c_create_a_xx เป็น Login จริง อ่าน policy_id จากกรมธรรม์ที่มีอยู่ ไม่ hardcode identity เป็น 1 SELECT บน claim ที่สืบทอดให้ใช้ RETURNING ได้ ขั้นนี้ยังไม่เปิด RLS แต่ให้ INSERT ไว้ตามคอลัมน์ที่ระบุ เคลมนี้คงอยู่ใน Lab เมื่อทำขั้น D

Source: ../labs/module-04-security-clone.md · 4C.C
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.C: Direct nextval ก่อนและหลัง USAGE

Writer เรียกคำสั่งเดิมสองครั้ง โดยมี Instructor ให้ GRANT ระหว่างครั้ง

```sql
SELECT nextval(pg_get_serial_sequence(
  format('%I.claim', :'lab_schema'), 'claim_id'));
```

| ช่วงทดลอง | ผล |
| --- | --- |
| ก่อนให้ sequence USAGE | 42501 |
| หลังให้ sequence USAGE แก่ writer | ได้เลขจาก sequence ของ Lab |

<p class="cs-takeaway">เลขที่จ่ายแล้วไม่ต้องเรียงติดกันทุกเลข</p>

<footer class="cs-footer"><span>Security Clone · 4C.C</span><span>18 / 34</span></footer>

<!--
Speaker notes:
Instructor ใช้ format GRANT USAGE ON SEQUENCE ตาม pg_get_serial_sequence ในคู่มือ เพื่อเลือก sequence ที่ถูกต้อง ห้ามเรียก nextval บน claimsure.claim_claim_id_seq ต้นทางเพื่อทดลองขั้นนี้ source manifest ต้องยังเทียบ sequence state ได้ตรงเมื่อจบ

Source: ../labs/module-04-security-clone.md · 4C.C
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone cs-fundamental
---

# Fundamental: RLS จาก Login ที่ยืนยันแล้ว

<SecurityCloneDiagram kind="rls" />

<p class="cs-concept-caption">Login ต่างคนใช้ reader group เดียวกัน แต่จับคู่ลูกค้าคนละราย</p>

<footer class="cs-footer"><span>Security Clone · 4C.D</span><span>19 / 34</span></footer>

<!--
Speaker notes:
Database ใช้ SCRAM ตรวจ Login แล้ว session_user ระบุ Login เริ่มต้น private login_customer map บัญชีไปยัง customer_id Function allowed_policy_ids ใช้ SECURITY DEFINER อ่าน mapping และ policy โดยจำกัด search_path เป็น pg_catalog,lab_schema,pg_temp ถอน PUBLIC EXECUTE แล้วให้ reader เท่านั้น ไม่รับ customer_id เป็น parameter

Source: ../labs/module-04-security-clone.md · 4C.D
Sources:
- https://www.postgresql.org/docs/18/ddl-rowsecurity.html
- https://www.postgresql.org/docs/18/sql-createfunction.html
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.D: Mapping, Policies และ Audit

```sql
\i labs/module04-security-clone/03-rls-audit.sql
```

| Login | ลูกค้า / สิทธิ์ |
| --- | --- |
| read_a / create_a / approve_a | CUS-001 |
| read_b | CUS-002 |
| audit (ไม่มี mapping) | อ่าน audit ตาม table grant |

<p class="cs-takeaway">เปิด ENABLE และ FORCE RLS พร้อม policies แยก SELECT / INSERT / UPDATE</p>

<footer class="cs-footer"><span>Security Clone · 4C.D</span><span>20 / 34</span></footer>

<!--
Speaker notes:
ชื่อ Login ย่อในตารางต้องมี prefix m4c_ และ suffix _xx เหมือนรายชื่อเต็มในหน้า 5 Auditor ไม่มี customer mapping เพราะไม่รับ SELECT claim owner มี maintenance policy ของตนแยกไว้ ไม่ได้ให้ app เข้า owner การสร้าง trigger ในไฟล์เดียวกันไม่ให้ app INSERT audit โดยตรง

Source: ../labs/module-04-security-clone.md · 4C.D
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.D: SELECT เดียวกัน เห็นข้อมูลคนละชุด

```sql
SELECT customer_code, claim_no, status
FROM :"lab_schema".claim_detail_v
WHERE claim_no LIKE 'CLM-L1-%'
ORDER BY claim_no;
```

| Login ที่เปิด connection | แถวที่ต้องเห็น |
| --- | --- |
| m4c_read_a_xx | CUS-001: CLM-L1-001 ถึง 004 |
| m4c_read_b_xx | CUS-002: CLM-L1-005 ถึง 006 |

<p class="cs-takeaway">กรอง CLM-L1-* เพื่อให้เทียบผล 4 และ 2 แถวได้แน่นอน</p>

<footer class="cs-footer"><span>Security Clone · 4C.D</span><span>21 / 34</span></footer>

<!--
Speaker notes:
สลับ Login ด้วย connection ใหม่ ไม่ใช่ SET ROLE เพื่อให้ session_user ตรงกับ mapping ผล SELECT ทั้งตารางจะมีเคลมจากบท 3 และเคลมใหม่ใน Lab ตาม customer ด้วย ชื่อ role group เหมือนกันไม่ได้แปลว่าเห็นทุกแถวเหมือนกัน

Source: ../labs/module-04-security-clone.md · 4C.D
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone cs-fundamental
---

# Fundamental: USING และ WITH CHECK

| เงื่อนไข | ตรวจอะไร | ตัวอย่างผล |
| --- | --- | --- |
| SELECT USING | แถวที่อ่านได้ | อีกลูกค้าหายจากผลลัพธ์ |
| UPDATE USING | แถวเดิมที่เข้าไปแก้ได้ | เคลมคนอื่น UPDATE 0 |
| INSERT / UPDATE WITH CHECK | ค่าของแถวที่จะเก็บ | ข้ามลูกค้าหรือ INSERT ผิด status ได้ 42501 |

<p class="cs-takeaway">INSERT policy ของ writer ตรวจทั้งลูกค้าและ status = NEW</p>

<footer class="cs-footer"><span>Security Clone · 4C.D</span><span>22 / 34</span></footer>

<!--
Speaker notes:
Lab มี policy เฉพาะคำสั่ง SELECT TO reader, INSERT TO writer และ UPDATE TO approver INSERT WITH CHECK กำหนด NEW เท่านั้น UPDATE policy คุม customer ส่วน column ACL จำกัดให้ approver แก้ status ไม่รวม amount หรือ policy_id WITH CHECK failure เป็น error แต่แถวที่ UPDATE USING กรองออกทำให้ UPDATE 0

Source: ../labs/module-04-security-clone.md · 4C.D
Sources:
- https://www.postgresql.org/docs/18/ddl-rowsecurity.html
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.D: ผล INSERT ของ Writer

```sql
INSERT INTO :"lab_schema".claim
  (claim_no, policy_id, status, incident_at, estimated_amount)
SELECT 'CLM-M4C-OWN', policy_id, 'NEW', now(), 250
FROM :"lab_schema".policy WHERE policy_no = 'POL-001'
RETURNING claim_id, claim_no, status;
```

| ทดสอบเพิ่ม | ผล |
| --- | --- |
| NEW ให้ POL-003 ของ CUS-002 | 42501 จาก RLS |
| APPROVED ให้ POL-001 ของตน | 42501 จาก NEW-only policy |

<p class="cs-takeaway">Reader A อ่าน OWN ได้หลัง reconnect ส่วน Reader B เห็น 0 แถว</p>

<footer class="cs-footer"><span>Security Clone · 4C.D</span><span>23 / 34</span></footer>

<!--
Speaker notes:
ใช้รหัส WRONG/PREAPPROVED ในคู่มือสำหรับ negative tests ไม่วาง SQL ทั้งบล็อกพร้อมกับ ON_ERROR_STOP on โดยไม่เปิดช่วง expected errors writer UPDATE status ของ OWN ก็ถูกปฏิเสธที่ privilege ระดับคอลัมน์/ตาราง แถวที่ INSERT สำเร็จคงอยู่จริง ส่วนคำสั่งที่ถูกปฏิเสธไม่ได้เพิ่มแถว

Source: ../labs/module-04-security-clone.md · 4C.D
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.D: Context ที่ผู้เรียกตั้งเอง

Reader A ลองตั้ง customer ID เอง

```sql
SET app.customer_id = '2';
SELECT customer_code, claim_no
FROM :"lab_schema".claim_detail_v
WHERE claim_no LIKE 'CLM-L1-%';
```

| ตรวจเพิ่มเติม | ผล |
| --- | --- |
| ผลอ่านของ Reader A | ยังเป็น CUS-001 สี่แถว |
| อ่าน login_customer / SET ROLE owner | 42501 |

<p class="cs-takeaway">Policy นี้อ้าง session_user ของ Login จริง</p>

<footer class="cs-footer"><span>Security Clone · 4C.D</span><span>24 / 34</span></footer>

<!--
Speaker notes:
ค่า 2 เป็น custom GUC ที่แอปตั้งได้ ไม่จำเป็นต้องตรง customer_id จริงในฐานนี้ เพราะ Lab ไม่อ่าน GUC ดังกล่าวอยู่แล้ว session_user เป็นขอบเขตที่เหมาะกับ Lab ที่แยก DB Login ต่อผู้ใช้ แอปที่ใช้ connection pool/login ร่วมกันต้องใช้ trusted identity ที่ออกแบบกับระบบ authentication ของแอป

Source: ../labs/module-04-security-clone.md · 4C.D
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone cs-fundamental
---

# Fundamental: Security invoker view

<SecurityCloneDiagram kind="view" />

<p class="cs-concept-caption">View ใน Lab ใช้สิทธิ์ของผู้เรียกเมื่อเข้าถึงตารางฐาน</p>

<footer class="cs-footer"><span>Security Clone · 4C.D</span><span>25 / 34</span></footer>

<!--
Speaker notes:
security_invoker=true ทำให้ตรวจ privileges และ RLS ของ base relations โดยใช้ผู้เรียกของ view Reader ต้องมี SELECT บน view และคอลัมน์ที่ view ใช้ใน claim/policy/customer ลอง query ผ่าน view เพื่อยืนยันผลแถว 4/2 ด้วย ไม่ตรวจเฉพาะ base table

Source: ../labs/module-04-security-clone.md · 4C.D
Sources:
- https://www.postgresql.org/docs/18/sql-createview.html
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.E: Approver แก้ status ตามลูกค้า

```sql
UPDATE :"lab_schema".claim SET status = 'APPROVED'
WHERE claim_no = 'CLM-L1-001' RETURNING claim_no, status;

UPDATE :"lab_schema".claim SET status = 'APPROVED'
WHERE claim_no = 'CLM-L1-005' RETURNING claim_no, status;
```

| เคลม | ผลของ m4c_approve_a_xx |
| --- | --- |
| 001 ของ CUS-001 | UPDATE 1 |
| 005 ของ CUS-002 | UPDATE 0 |

<p class="cs-takeaway">UPDATE 0 เป็นผลจากแถวที่ RLS กรองออก</p>

<footer class="cs-footer"><span>Security Clone · 4C.E</span><span>26 / 34</span></footer>

<!--
Speaker notes:
ใช้ approver Login จริง มี SELECT ผ่าน reader, UPDATE(status) และ UPDATE policy ที่ตรงกับ customer อย่าให้ UPDATE ทั้งตารางเพิ่มเพื่อแก้ error เพราะจะเปลี่ยนขอบเขตคอลัมน์ที่ทดลอง ถ้า 001 เป็น APPROVED อยู่แล้ว UPDATE ยังอาจนับ 1 แต่ audit trigger ไม่เพิ่มแถวเมื่อค่า status ไม่เปลี่ยน

Source: ../labs/module-04-security-clone.md · 4C.E
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone cs-fundamental
---

# Fundamental: Audit ด้วยสิทธิ์ที่จำกัด

<SecurityCloneDiagram kind="audit" />

<p class="cs-concept-caption">ฟังก์ชันใช้สิทธิ์ owner แต่เก็บชื่อผู้ Login จาก session_user</p>

<footer class="cs-footer"><span>Security Clone · 4C.E</span><span>27 / 34</span></footer>

<!--
Speaker notes:
ใน SECURITY DEFINER current_user เป็นเจ้าของ function ส่วน session_user ยังคงเป็น Login เริ่มต้นซึ่งต้องการบันทึก audit ถอน PUBLIC EXECUTE และกำหนด search_path ที่ปลอดภัย Trigger เขียน audit ใน statement เดียวกับ UPDATE ที่สำเร็จ App ไม่ได้รับ INSERT/UPDATE บน audit table จึงแยกหน้าที่ผู้แก้และผู้ตรวจ

Source: ../labs/module-04-security-clone.md · 4C.E
Sources:
- https://www.postgresql.org/docs/18/sql-createfunction.html
- https://www.postgresql.org/docs/18/sql-createtrigger.html
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.E: หลักฐานที่ยังอยู่หลัง Reconnect

Auditor อ่านข้อมูลที่ trigger เก็บไว้

```sql
SELECT claim_no, old_status, new_status, login_name
FROM :"lab_schema".claim_audit ORDER BY audit_id;
```

| Field | ผลจาก fixture ของบท 1–3 |
| --- | --- |
| claim_no / old_status / new_status | CLM-L1-001 / REVIEW / APPROVED |
| login_name | m4c_approve_a_xx |
| Reader A เปิด connection ใหม่ | ยังอ่าน 001 เป็น APPROVED |

<p class="cs-takeaway">ผล UPDATE และ audit เก็บอยู่จริงในสำเนา</p>

<footer class="cs-footer"><span>Security Clone · 4C.E</span><span>28 / 34</span></footer>

<!--
Speaker notes:
old_status ต้องตรงกับค่าที่ clone มาจริง fixture หลัง 1D เป็น REVIEW หาก source ต่างจาก fixture ให้เทียบค่าจริง ถ้าค่าเดิม APPROVED อยู่แล้วจะไม่มี audit เพิ่ม เพราะ trigger บันทึกเฉพาะ OLD.status IS DISTINCT FROM NEW.status ตรวจผลหลังออกและเปิด Reader A connection ใหม่ ไม่ต้องใช้ transaction ค้างเพื่อรักษาการทดลอง

Source: ../labs/module-04-security-clone.md · 4C.E
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.E: ผลการปฏิเสธแต่ละหน้าที่

| Login | Operation ที่ทดลอง | ผล |
| --- | --- | --- |
| Writer | UPDATE status | 42501 |
| Approver | UPDATE estimated_amount | 42501 |
| Approver | DELETE claim | 42501 |
| Approver | INSERT audit เอง | 42501 |
| Auditor | SELECT claim | 42501 |
| Auditor | UPDATE claim_audit | 42501 |

<p class="cs-takeaway">Auditor ได้ SELECT audit ผ่าน table grant ที่แยกไว้</p>

<footer class="cs-footer"><span>Security Clone · 4C.E</span><span>29 / 34</span></footer>

<!--
Speaker notes:
คำสั่งที่ตั้งใจให้ fail ใช้ ON_ERROR_STOP off เฉพาะบล็อก อ่าน SQLSTATE แล้วคืน on ตามคู่มือ ทดสอบทั้งช่องทางที่ควรผ่านและช่องทางที่ต้องถูกปฏิเสธ ไม่ยก privileges ให้สูงขึ้นเพื่อให้ทุกคำสั่งผ่าน Audit table เป็นตัวอย่างสอนการแบ่งสิทธิ์ ไม่ได้ทำให้ superuser หรือ owner แก้หลักฐานไม่ได้

Source: ../labs/module-04-security-clone.md · 4C.E
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone cs-fundamental
---

# Fundamental: Default privileges ตามผู้สร้าง

<SecurityCloneDiagram kind="defaults" />

<p class="cs-concept-caption">Default privileges กำหนด ACL เริ่มต้นของ object ใหม่</p>

<footer class="cs-footer"><span>Security Clone · 4C.F</span><span>30 / 34</span></footer>

<!--
Speaker notes:
ตั้ง default privileges ในบริบท m4c_owner_xx เพราะเป็น role ที่สร้างตารางทดลอง ไม่ย้อนเปลี่ยนตารางก่อนหน้า และ default privileges ของ membership ไม่ได้ถูกนำมารวมอัตโนมัติกับทุก role ที่สร้าง object การให้ SELECT ใหม่ไม่ได้สร้าง RLS หรือ customer policy ให้ตารางนั้น

Source: ../labs/module-04-security-clone.md · 4C.F
Sources:
- https://www.postgresql.org/docs/18/sql-alterdefaultprivileges.html
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.F: ตารางก่อนและหลัง Default grant

```sql
SET ROLE :"owner_role";
CREATE TABLE :"lab_schema".note_before_default(note text);
ALTER DEFAULT PRIVILEGES IN SCHEMA :"lab_schema"
  GRANT SELECT ON TABLES TO :"reader_role";
CREATE TABLE :"lab_schema".note_after_default(note text);
RESET ROLE;
```

| Reader A อ่าน | ผล |
| --- | --- |
| note_before_default | 42501 |
| note_after_default | อ่านได้ |

<p class="cs-takeaway">ใช้บล็อกเต็มในคู่มือเพื่อเพิ่มข้อความ note ก่อนตรวจผล</p>

<footer class="cs-footer"><span>Security Clone · 4C.F</span><span>31 / 34</span></footer>

<!--
Speaker notes:
Instructor SET ROLE owner เพื่อให้ตัวอย่างตรงเจ้าของที่กำหนด default privileges ไว้ ตาราง note มีข้อความทั่วไปที่ตั้งใจให้ Reader ทั้งสองอ่านร่วมกัน Policy ของ claim ไม่ได้คุ้มครองตาราง note ที่สร้างใหม่อัตโนมัติ หากเป็นข้อมูลตามลูกค้าต้องออกแบบ RLS/grants ให้ตารางนั้นเพิ่ม

Source: ../labs/module-04-security-clone.md · 4C.F
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Lab 4C.G: ต้นทางตรงกับ Snapshot ก่อนทดลอง

```sql
\i labs/module04-security-clone/04-check-source.sql
```

| Source table | Count | Full-row hash | ACL / RLS | Sequence state |
| --- | --- | --- | --- | --- |
| customer | ตรง | ตรง | ตรง | ตรง |
| policy | ตรง | ตรง | ตรง | ตรง |
| claim | ตรง | ตรง | ตรง | ตรง |

<p class="cs-takeaway">พักงานที่เขียน source ระหว่าง Lab เพื่อให้เทียบ snapshot ได้</p>

<footer class="cs-footer"><span>Security Clone · 4C.G</span><span>32 / 34</span></footer>

<!--
Speaker notes:
ตารางนี้แสดงผลตรวจจริงบน PostgreSQL 18.6 ใน isolated test container กับ source fixture 100006 claims ดู labs/module04-security-clone/VALIDATION.md การเทียบ hash ครอบคลุมทุกคอลัมน์ทุกแถวของ source core tables ตรวจ ACL/RLS flags และ last_value/is_called ของ source identity sequence ด้วย หากมีงานอื่นเขียนต้นทางพร้อมกันผลต่างอาจมาจากงานนั้น ห้าม reset source เพื่อให้ checksum ตรง

Source: ../labs/module-04-security-clone.md · 4C.G
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# การเก็บ Lab และ Cleanup เฉพาะสำเนา

หลังจบ เก็บ schema, grants, เคลมที่เพิ่ม และ audit ไว้สำรวจต่อได้

```sql
\set confirm_cleanup :lab_schema
\i labs/module04-security-clone/99-cleanup.sql
```

| Guard ก่อน Cleanup | ต้องตรงกับ Lab |
| --- | --- |
| Schema name / marker / owner | lab_m4_clone_xx และ owner ของเวอร์ชันนี้ |
| ขอบเขตที่ลบ | Schema Lab และ dedicated roles |

<p class="cs-takeaway">Cleanup ใช้เฉพาะเมื่อตั้งใจทิ้งผลการทดลองและเริ่มใหม่</p>

<footer class="cs-footer"><span>Security Clone · เริ่มใหม่ / cleanup</span><span>33 / 34</span></footer>

<!--
Speaker notes:
Cleanup ไม่ใช่ขั้นบังคับหลัง Lab ปิด app connections ก่อนใช้ คำสั่ง DROP SCHEMA CASCADE ลบ objects ในสำเนา และ dedicated role cleanup ถอน CONNECT ของ role เหล่านั้น ไม่ใช้ DROP OWNED ไม่ลบ claimsure สคริปต์ตรวจชื่อ schema marker และ owner ก่อนดำเนินการ เมื่อ cleanup แล้วจึงเริ่ม 01-roles ใหม่ได้

Source: ../labs/module-04-security-clone.md · เริ่มใหม่ / cleanup
-->

---
layout: default
class: continuous-deck cs-module-four cs-module-four-clone
---

# Module 4 Clone: ผลที่ผู้เรียนต้องอธิบายได้

| การทดลอง | หลักฐาน |
| --- | --- |
| Schema / table / column grants | SQLSTATE 42501 ตาม gate ที่ยังปิด |
| Reader A / Reader B | เห็นเคลมตั้งต้น 4 / 2 แถว |
| Writer / Approver | INSERT NEW / UPDATE(status) ตามลูกค้า |
| Audit และ Reconnect | Login ผู้แก้จริง และผลที่ยังคงอยู่ |
| Default privileges / Source checks | ตารางใหม่รับ SELECT และ source ยังตรงเดิม |

คู่มือคำสั่งเต็ม: `labs/module-04-security-clone.md`

<p class="cs-takeaway">ทดลองบนสำเนา เก็บผลจริง และตรวจขอบเขตสิทธิ์ด้วย Login ของแต่ละหน้าที่</p>

<footer class="cs-footer"><span>Security Clone · สรุป</span><span>34 / 34</span></footer>

<!--
Speaker notes:
ปิดบทโดยให้ผู้เรียนอธิบายว่าทำไม USING อาจให้ UPDATE 0 แต่ WITH CHECK ผิดเงื่อนไขให้ error ทำไม identity INSERT ผ่านก่อน nextval และทำไม default privileges ต้องตรงผู้สร้าง ข้อมูล fixture ผ่านการตรวจ 36 permission matrix checks พร้อม source/cleanup guards ตาม VALIDATION.md ชุดสไลด์เดิมยังเรียกด้วย MODULE=4 ส่วนชุดนี้ใช้ MODULE=4:clone ไม่เพิ่มเข้า continuous run all โดยอัตโนมัติ

Source: ../labs/module-04-security-clone.md · สรุป
-->

<style>
/* Scoped to the new deck; shared theme and the original Module 4 stay unchanged. */
.cs-module-four-clone .cs-metrics { gap: 1.4rem; }
.cs-module-four-clone .cs-metrics b { font-size: 2.25rem; }
.cs-module-four-clone .cs-metrics span { font-size: 1rem; }
.cs-module-four-clone.cover h1 { max-width: 43%; font-size: 2.65rem; }
.cs-module-four-clone.cover h2 { max-width: 42%; font-size: 1.1rem; line-height: 1.6; }
</style>
