-- @teacher ==============================================================================
-- @teacher TEACHER EDITION | 07-backup-recovery.sql | PostgreSQL Lab
-- @teacher คำอธิบายภาษาไทย; ศัพท์และคำสั่ง Technical English คงตามต้นฉบับ
-- @teacher SOURCE: scripts/sql/07-backup-recovery.sql
-- @teacher LOGIN / DATABASE เริ่มต้น: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อ่าน README.md ใน Directory นี้ก่อนสอน; ใช้ไฟล์นี้เป็นคู่มือเลือกรันทีละส่วน
-- @teacher แต่ละ SQL มี START/END, Lab, Login, เหตุผล และผลที่ต้องสังเกต; Source Line อ้างไฟล์ต้นฉบับ
-- @teacher START/END ราย SQL ใช้ค้นคำอธิบาย ไม่ใช่ขอบเขต Commit: Transaction/Function ต้องรันครบชุด
-- @teacher คำสั่ง psql ขึ้นต้นด้วย Backslash; SQL Editor ทั่วไปให้ข้ามและจัด Branch/Variables เอง
-- @teacher ทุกบรรทัดที่เพิ่มขึ้นต้น -- @teacher; SQL/psql ต้นฉบับคงเดิม รวมคำสั่งเปลี่ยนข้อมูลและ Expected Errors
-- @teacher เป้าหมาย: Recovery Objectives → Baseline → Backup Scope → Restore Validation → WAL/PITR → Evidence
-- @teacher ชุดนี้อธิบาย Admin SQL 7A–7G ตาม 07-backup-recovery.sql; Lab 7E ในชุดนี้คือ Physical Backup Readiness
-- @teacher Databasus 7E เป็นอีก Track: docs/labs/module-07-databasus-student-manual.md ไม่ใช้ Lab Number สลับกัน
-- @teacher ต้องมี Enterprise insurance.claim พร้อม tenant_id/created_at/updated_at; Module 1 Fixture อาจไม่ตรง
-- @teacher psql Variables: snapshot=before_backup, claim_rpo_minutes=15, claim_rto_minutes=60, peak_claims_per_minute=40
-- @teacher รัน Setup + 7A/B ก่อน Backup; Backup ต้องครอบคลุม lab_m7 เพื่อให้ Baseline ไปถึง Restore Target
-- @teacher 7D: ต่อ isolated claimsure_restore หลัง Restore สำเร็จ และตั้ง snapshot=after_restore ก่อนเลือก Lab 7D
-- @teacher Guard เดิมเช็กชื่อไม่ใช่ claimsure เท่านั้น ไม่พอแยกฐานนักเรียน; ต้องตรวจ Connection เองก่อนทุกครั้ง
-- @teacher ข้อความ echo เป็นคำแนะนำ Shell ไม่ได้ Execute; อย่ารันไฟล์ทั้งก้อนเพื่อหวังว่าจะ Backup/Restore ให้เอง
-- @teacher ==============================================================================
-- =============================================================================
-- Module 7: ClaimSure Backup and Recovery Practice
--
-- Classroom students use the shell runner, not this file:
--   ./scripts/shells/run-lab07.sh --student xx --ask-pass logical
--   ./scripts/shells/run-lab07.sh --student xx --ask-pass physical
--   ./scripts/shells/run-lab07.sh --student xx --ask-pass snapshot
--   ./scripts/shells/run-lab07.sh --student xx --ask-pass pitr
--   ./scripts/shells/run-lab07.sh --student xx --ask-pass all
-- That runner reads claimsure_xx and restores schema insurance into
-- claimsure_backup_xx. It does not pg_basebackup or recover the shared cluster.
--
-- The SQL below is the superuser practice. It expects PostgreSQL 18 and the
-- postgres lab role. Students should not Execute All of this file.
-- Run all:        make lab-v3 LAB_NO=07
-- Run one lab:    make lab-v3 LAB_NO=lab07-A
-- Direct runner:  ./scripts/run-module7-lab.sh lab07-F
-- Requires: PostgreSQL 18, the ClaimSure primary, and the postgres lab role.
--
-- The SQL practices inspect readiness, capture business evidence, and create a
-- named restore point. Backup and restore commands remain explicit shell steps
-- because a recovery drill must not overwrite the running ClaimSure primary.
-- =============================================================================
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server; on=หยุดเมื่อ Error, off=ยอมไปต่อใน Expected Error block ที่ต้นฉบับกำหนด
\set ON_ERROR_STOP on
-- @teacher PSQL: ตั้งรูปแบบแสดงผลของ psql ไม่เปลี่ยนข้อมูลใน Database
\pset pager off
-- @teacher PSQL: แสดงเวลาใน Client; แยกจาก Execution Time ใน EXPLAIN
\timing on

-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :{?snapshot}
-- @teacher PSQL: Branch ทางเลือกของ psql; ไม่เลือก Execute ทั้งสอง Branch ใน SQL Editor
\else
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server
\set snapshot 'before_backup'
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :{?claim_rpo_minutes}
-- @teacher PSQL: Branch ทางเลือกของ psql; ไม่เลือก Execute ทั้งสอง Branch ใน SQL Editor
\else
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server
\set claim_rpo_minutes 15
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :{?claim_rto_minutes}
-- @teacher PSQL: Branch ทางเลือกของ psql; ไม่เลือก Execute ทั้งสอง Branch ใน SQL Editor
\else
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server
\set claim_rto_minutes 60
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :{?peak_claims_per_minute}
-- @teacher PSQL: Branch ทางเลือกของ psql; ไม่เลือก Execute ทั้งสอง Branch ใน SQL Editor
\else
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server
\set peak_claims_per_minute 40
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :{?restore_point}
-- @teacher PSQL: Branch ทางเลือกของ psql; ไม่เลือก Execute ทั้งสอง Branch ใน SQL Editor
\else
-- @teacher PSQL: psql Client Variable: ตั้งค่าหรือควบคุม Error Handling; ไม่ใช่ SQL ที่ส่งให้ Server
\set restore_point 'claimsure_before_recovery_drill'
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif

\echo '=== Module 7: ClaimSure Backup and Recovery ==='
-- @teacher PSQL: ยืนยัน Host/Port/Database/User ของ Connection ปัจจุบันก่อนรัน Lab
\conninfo

-- @teacher [START 07-SQL001] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: ตรวจ PostgreSQL 18+ และ postgres Superuser สำหรับ Admin Recovery Practice
-- @teacher ผล/ชวนสังเกต: นี่ไม่ใช่ Student Shell Track หรือ Databasus 7E; แยก Environment ก่อนเริ่ม
-- @teacher SOURCE: 07-backup-recovery.sql:52 | รัน SQL นี้ครบทั้ง Statement
DO $$
BEGIN
    IF current_setting('server_version_num')::int < 180000 THEN
        RAISE EXCEPTION 'This lab targets PostgreSQL 18 or newer; server is %', version();
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
        RAISE EXCEPTION 'Run this recovery lab as the postgres lab superuser.';
    END IF;
END
$$;
-- @teacher [END 07-SQL001]

-- @teacher [START 07-SQL002] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: สร้าง Schema สำหรับเก็บเป้าหมายและหลักฐานการกู้คืน
-- @teacher ผล/ชวนสังเกต: ต้องให้ข้อมูล Baseline นี้อยู่ในขอบเขต Backup หากต้องการนำไปเทียบที่ Restore Target
-- @teacher SOURCE: 07-backup-recovery.sql:63 | รัน SQL นี้ครบทั้ง Statement
CREATE SCHEMA IF NOT EXISTS lab_m7;
-- @teacher [END 07-SQL002]

-- @teacher [START 07-SQL003] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: สร้างสัญญา RPO/RTO และ Peak Business Rate พร้อม Constraints
-- @teacher ผล/ชวนสังเกต: RPO=ยอมเสียข้อมูลย้อนหลังเท่าไร; RTO=เวลาที่ต้องกลับมาให้บริการ ไม่ใช่เวลาสร้าง Backup
-- @teacher SOURCE: 07-backup-recovery.sql:65 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS lab_m7.recovery_objective (
    service_name text PRIMARY KEY,
    rpo_minutes integer NOT NULL CHECK (rpo_minutes >= 0),
    rto_minutes integer NOT NULL CHECK (rto_minutes > 0),
    peak_business_rows_per_minute integer NOT NULL CHECK (peak_business_rows_per_minute >= 0),
    owner_name text NOT NULL,
    reviewed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
-- @teacher [END 07-SQL003]

-- @teacher [START 07-SQL004] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: สร้างหัวรายการ Validation Snapshot และ Routine Inventory
-- @teacher ผล/ชวนสังเกต: Snapshot ในที่นี้คือข้อมูลตรวจสอบที่บันทึกใน Table ไม่ใช่ Storage Snapshot หรือ Physical Backup
-- @teacher SOURCE: 07-backup-recovery.sql:74 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS lab_m7.validation_run (
    run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    snapshot_name text NOT NULL,
    captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    database_name name NOT NULL,
    server_version text NOT NULL,
    function_count bigint NOT NULL,
    procedure_count bigint NOT NULL
);
-- @teacher [END 07-SQL004]

-- Upgrade validation data created by the earlier Module 7 lab in place.
-- @teacher [START 07-SQL005] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: เพิ่ม server_version ให้โครงสร้าง Validation เก่ารันต่อได้
-- @teacher ผล/ชวนสังเกต: ADD COLUMN IF NOT EXISTS ไม่แก้ข้อมูลเดิมหรือสร้าง Backup ให้เอง
-- @teacher SOURCE: 07-backup-recovery.sql:85 | รัน SQL นี้ครบทั้ง Statement
ALTER TABLE lab_m7.validation_run
    ADD COLUMN IF NOT EXISTS server_version text;
-- @teacher [END 07-SQL005]
-- @teacher [START 07-SQL006] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: เติม Version ของ Server ปัจจุบันให้แถวเก่าที่ยังเป็น NULL
-- @teacher ผล/ชวนสังเกต: เป็นการ Backfill Metadata ณ ปัจจุบัน ไม่อาจยืนยัน Version ในอดีตของแถวเหล่านั้น
-- @teacher SOURCE: 07-backup-recovery.sql:87 | รัน SQL นี้ครบทั้ง Statement
UPDATE lab_m7.validation_run
SET server_version = current_setting('server_version')
WHERE server_version IS NULL;
-- @teacher [END 07-SQL006]
-- @teacher [START 07-SQL007] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: บังคับให้ Validation Run ใหม่และเก่ามีค่า server_version
-- @teacher ผล/ชวนสังเกต: ต้อง Backfill สำเร็จก่อนจึงตั้ง NOT NULL ได้
-- @teacher SOURCE: 07-backup-recovery.sql:90 | รัน SQL นี้ครบทั้ง Statement
ALTER TABLE lab_m7.validation_run
    ALTER COLUMN server_version SET NOT NULL;
-- @teacher [END 07-SQL007]

-- @teacher [START 07-SQL008] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: สร้างรายละเอียดจำนวนแถวและช่วง Timestamp ต่อ Table/Run
-- @teacher ผล/ชวนสังเกต: Foreign Key ผูกกับ validation_run; ลบ Run จะลบรายละเอียดตาม CASCADE
-- @teacher SOURCE: 07-backup-recovery.sql:93 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS lab_m7.table_validation (
    run_id bigint NOT NULL REFERENCES lab_m7.validation_run ON DELETE CASCADE,
    schema_name name NOT NULL,
    table_name name NOT NULL,
    row_count bigint NOT NULL,
    timestamp_column name,
    min_timestamp timestamptz,
    max_timestamp timestamptz,
    PRIMARY KEY (run_id, schema_name, table_name)
);
-- @teacher [END 07-SQL008]

-- @teacher [START 07-SQL009] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: สร้าง Evidence Log เพื่อบันทึก PASS/FAIL/NOT_RUN และ RPO/RTO ที่วัดจริง
-- @teacher ผล/ชวนสังเกต: สร้าง Table ยังไม่ใช่การผ่าน Restore Drill; ผู้สอนต้องบันทึกหลักฐานหลังทดสอบจริง
-- @teacher SOURCE: 07-backup-recovery.sql:104 | รัน SQL นี้ครบทั้ง Statement
CREATE TABLE IF NOT EXISTS lab_m7.recovery_evidence (
    evidence_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    exercise_name text NOT NULL,
    artifact_uri text,
    verification_method text NOT NULL,
    result text NOT NULL CHECK (result IN ('PASS', 'FAIL', 'NOT_RUN')),
    measured_rpo_minutes numeric,
    measured_rto_minutes numeric,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    notes text
);
-- @teacher [END 07-SQL009]

-- @teacher [START 07-SQL010] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: สร้าง Function ที่นับ Routines แล้ว Loop ทุก User Table เพื่อเก็บ Count และ Timestamp Range
-- @teacher ผล/ชวนสังเกต: เลือก Timestamp เพียงหนึ่ง Column ตามลำดับความสำคัญ; format %I Quote Identifiers; แต่ละ Scan มีต้นทุนและไม่ใช่หลักฐานความถูกต้องทุกค่า
-- @teacher SOURCE: 07-backup-recovery.sql:116 | รัน SQL นี้ครบทั้ง Statement
CREATE OR REPLACE FUNCTION lab_m7.capture_validation(p_snapshot_name text)
RETURNS bigint
LANGUAGE plpgsql
AS $function$
DECLARE
    v_run_id bigint;
    v_table record;
    v_timestamp_column name;
    v_count bigint;
    v_min timestamptz;
    v_max timestamptz;
BEGIN
    INSERT INTO lab_m7.validation_run(
        snapshot_name, database_name, server_version,
        function_count, procedure_count
    )
    SELECT p_snapshot_name, current_database(), current_setting('server_version'),
           count(*) FILTER (WHERE p.prokind IN ('f', 'a', 'w')),
           count(*) FILTER (WHERE p.prokind = 'p')
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'lab_m7')
      AND n.nspname !~ '^pg_toast'
    RETURNING run_id INTO v_run_id;

    FOR v_table IN
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'lab_m7')
          AND schemaname !~ '^pg_toast'
        ORDER BY schemaname, tablename
    LOOP
        SELECT c.column_name
        INTO v_timestamp_column
        FROM information_schema.columns AS c
        WHERE c.table_schema = v_table.schemaname
          AND c.table_name = v_table.tablename
          AND c.data_type IN (
              'timestamp with time zone', 'timestamp without time zone', 'date'
          )
        ORDER BY CASE c.column_name
            WHEN 'updated_at' THEN 1
            WHEN 'created_at' THEN 2
            WHEN 'event_time' THEN 3
            WHEN 'incident_at' THEN 4
            WHEN 'paid_at' THEN 5
            ELSE 10
        END, c.ordinal_position
        LIMIT 1;

        IF v_timestamp_column IS NULL THEN
            EXECUTE format('SELECT count(*) FROM %I.%I',
                           v_table.schemaname, v_table.tablename)
            INTO v_count;
            v_min := NULL;
            v_max := NULL;
        ELSE
            EXECUTE format(
                'SELECT count(*), min(%I)::timestamptz, max(%I)::timestamptz FROM %I.%I',
                v_timestamp_column, v_timestamp_column,
                v_table.schemaname, v_table.tablename
            ) INTO v_count, v_min, v_max;
        END IF;

        INSERT INTO lab_m7.table_validation(
            run_id, schema_name, table_name, row_count,
            timestamp_column, min_timestamp, max_timestamp
        ) VALUES (
            v_run_id, v_table.schemaname, v_table.tablename, v_count,
            v_timestamp_column, v_min, v_max
        );
        v_timestamp_column := NULL;
    END LOOP;

    RETURN v_run_id;
END
$function$;
-- @teacher [END 07-SQL010]

-- @teacher [START 07-SQL011] Lab Setup | ตรวจ Environment และเตรียม Objects/ข้อมูลตั้งต้น
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: Upsert เป้าหมาย ClaimSure จาก psql Variables ลง Recovery Objective
-- @teacher ผล/ชวนสังเกต: Default 15/60/40 คือสมมติฐานฝึกสอน; เป้าหมายจริงต้องตกลงกับ Business Owner
-- @teacher SOURCE: 07-backup-recovery.sql:194 | รัน SQL นี้ครบทั้ง Statement
INSERT INTO lab_m7.recovery_objective(
    service_name, rpo_minutes, rto_minutes,
    peak_business_rows_per_minute, owner_name, reviewed_at
)
VALUES (
    'ClaimSure claim processing', :claim_rpo_minutes, :claim_rto_minutes,
    :peak_claims_per_minute, 'claims-platform', clock_timestamp()
)
ON CONFLICT (service_name) DO UPDATE
SET rpo_minutes = EXCLUDED.rpo_minutes,
    rto_minutes = EXCLUDED.rto_minutes,
    peak_business_rows_per_minute = EXCLUDED.peak_business_rows_per_minute,
    owner_name = EXCLUDED.owner_name,
    reviewed_at = EXCLUDED.reviewed_at;
-- @teacher [END 07-SQL011]

\echo '\n-- Lab 7A: ClaimSure recovery objectives and exposure'
-- @teacher [START 07-SQL012] Lab 7A | ClaimSure recovery objectives and exposure
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: แสดงเป้าหมายและคูณ RPO Minutes กับ Peak Rows ต่อ Minute
-- @teacher ผล/ชวนสังเกต: ค่า Default ได้ 600 Claims at Risk เป็นภาพประมาณ ไม่ใช่จำนวนแถวที่เสียจริงในการทดสอบ
-- @teacher SOURCE: 07-backup-recovery.sql:210 | รัน SQL นี้ครบทั้ง Statement
SELECT service_name, rpo_minutes, rto_minutes,
       peak_business_rows_per_minute,
       rpo_minutes * peak_business_rows_per_minute AS claims_at_risk_at_peak,
       owner_name, reviewed_at
FROM lab_m7.recovery_objective;
-- @teacher [END 07-SQL012]

-- @teacher [START 07-SQL013] Lab 7A | ClaimSure recovery objectives and exposure
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: เก็บขนาด Database, จำนวน Claims และช่วงเวลาข้อมูลธุรกิจ
-- @teacher ผล/ชวนสังเกต: ต้องมี Enterprise insurance.claim ที่มี created_at/updated_at; Fixture Module 1 อย่างเดียวอาจไม่ตรง
-- @teacher SOURCE: 07-backup-recovery.sql:216 | รัน SQL นี้ครบทั้ง Statement
SELECT current_database() AS database_name,
       pg_size_pretty(pg_database_size(current_database())) AS database_size,
       count(*) AS claim_rows,
       min(created_at) AS oldest_claim,
       max(updated_at) AS latest_claim_change
FROM insurance.claim;
-- @teacher [END 07-SQL013]

-- @teacher [START 07-SQL014] Lab 7A | ClaimSure recovery objectives and exposure
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: เก็บ Distribution ของ Claim Status และยอด Estimated Amount
-- @teacher ผล/ชวนสังเกต: ใช้เทียบกับ Restore เพิ่มจาก Row Count; จำนวนแถวเท่ากันยังอาจมี Status/Amount ผิด
-- @teacher SOURCE: 07-backup-recovery.sql:223 | รัน SQL นี้ครบทั้ง Statement
SELECT status, count(*) AS claims,
       sum(estimated_amount) AS estimated_claim_amount
FROM insurance.claim
GROUP BY status
ORDER BY status;
-- @teacher [END 07-SQL014]

-- The protection schedule must keep measured data loss and recovery duration
-- within the accepted RPO and RTO. Replace the teaching arrival rate with the
-- monitored peak rate before using the exposure estimate operationally.

\echo '\n-- Lab 7B: Capture a business validation baseline before backup'
-- @teacher [START 07-SQL015] Lab 7B | Capture a business validation baseline before backup
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: Capture Baseline ก่อน Backup แล้วเก็บ Run ID ใน psql Variable
-- @teacher ผล/ชวนสังเกต: ใช้ snapshot=before_backup; gset ไม่พิมพ์ Result แบบ Table และต้องให้ Backup ครอบคลุม lab_m7 ด้วย
-- @teacher SOURCE: 07-backup-recovery.sql:234 | รัน SQL นี้ครบทั้ง Statement
SELECT lab_m7.capture_validation(:'snapshot') AS validation_run_id \gset
-- @teacher [END 07-SQL015]

-- @teacher [START 07-SQL016] Lab 7B | Capture a business validation baseline before backup
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: อ่านหัว Baseline พร้อมยอดรวม Count ของ Tables ที่บันทึก
-- @teacher ผล/ชวนสังเกต: Parent/Child Partitions อาจนับข้อมูลซ้ำเมื่อรวมยอด; ตรวจราย Table ในคำสั่งถัดไปประกอบ
-- @teacher SOURCE: 07-backup-recovery.sql:236 | รัน SQL นี้ครบทั้ง Statement
SELECT r.run_id, r.snapshot_name, r.captured_at, r.database_name,
       r.server_version, r.function_count, r.procedure_count,
       sum(t.row_count) AS total_rows
FROM lab_m7.validation_run AS r
JOIN lab_m7.table_validation AS t USING (run_id)
WHERE r.run_id = :validation_run_id
GROUP BY r.run_id
ORDER BY r.run_id;
-- @teacher [END 07-SQL016]

-- @teacher [START 07-SQL017] Lab 7B | Capture a business validation baseline before backup
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: อ่าน Row Counts และ Timestamp Range รายชื่อ Table ของ Baseline
-- @teacher ผล/ชวนสังเกต: เก็บผลนี้ก่อน Backup; การนับข้อมูลไม่ได้แทน Constraints, Routines และ Functional Tests
-- @teacher SOURCE: 07-backup-recovery.sql:245 | รัน SQL นี้ครบทั้ง Statement
SELECT schema_name, table_name, row_count,
       timestamp_column, min_timestamp, max_timestamp
FROM lab_m7.table_validation
WHERE run_id = :validation_run_id
ORDER BY schema_name, table_name;
-- @teacher [END 07-SQL017]

-- @teacher [START 07-SQL018] Lab 7B | Capture a business validation baseline before backup
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: อ่าน Claims ตัวอย่างสาม Tenants เพื่อใช้เป็น Business Spot Check
-- @teacher ผล/ชวนสังเกต: ต้องมี Seed CLM-1001/2001/3001 ตาม Environment; Query ว่างไม่ใช่หลักฐาน Restore สำเร็จ
-- @teacher SOURCE: 07-backup-recovery.sql:251 | รัน SQL นี้ครบทั้ง Statement
SELECT claim_no, tenant_id, status, estimated_amount, created_at, updated_at
FROM insurance.claim
WHERE claim_no IN ('CLM-1001', 'CLM-2001', 'CLM-3001')
ORDER BY claim_no;
-- @teacher [END 07-SQL018]

\echo '\n-- Lab 7C: Logical backup scope and artifact checks'
-- @teacher [START 07-SQL019] Lab 7C | Logical backup scope and artifact checks
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: อ่านขนาดรวม/Estimated Rows เพื่อเลือก Scope และประมาณภาระ Logical Backup
-- @teacher ผล/ชวนสังเกต: reltuples เป็น Estimate; Partitioned Parent ต้องพิจารณา Children; คำสั่งนี้ยังไม่ได้เรียก pg_dump
-- @teacher SOURCE: 07-backup-recovery.sql:257 | รัน SQL นี้ครบทั้ง Statement
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
       c.reltuples::bigint AS estimated_rows
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND n.nspname = 'insurance'
ORDER BY pg_total_relation_size(c.oid) DESC, c.relname;
-- @teacher [END 07-SQL019]

-- @teacher [START 07-SQL020] Lab 7C | Logical backup scope and artifact checks
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: นับ Login/Group/Superuser Roles เพื่ออธิบายว่า Globals อยู่นอก pg_dump Database
-- @teacher ผล/ชวนสังเกต: ต้องมี pg_dumpall --globals-only หากต้องการเก็บ Roles/Tablespaces; Counts อย่างเดียวไม่เก็บ Definition
-- @teacher SOURCE: 07-backup-recovery.sql:267 | รัน SQL นี้ครบทั้ง Statement
SELECT count(*) FILTER (WHERE rolcanlogin) AS login_roles,
       count(*) FILTER (WHERE NOT rolcanlogin) AS group_roles,
       count(*) FILTER (WHERE rolsuper) AS superusers
FROM pg_roles;
-- @teacher [END 07-SQL020]

-- @teacher [START 07-SQL021] Lab 7C | Logical backup scope and artifact checks
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: บันทึก Extension Versions ก่อนย้ายหรือ Restore ไปเครื่องใหม่
-- @teacher ผล/ชวนสังเกต: ปลายทางต้องติดตั้ง Extension ที่เข้ากันได้; รายชื่อ Extension ไม่รวม Binary ของ Extension ใน Dump
-- @teacher SOURCE: 07-backup-recovery.sql:272 | รัน SQL นี้ครบทั้ง Statement
SELECT extname, extversion
FROM pg_extension
ORDER BY extname;
-- @teacher [END 07-SQL021]

\echo 'Create and inspect a custom-format ClaimSure backup from the host:'
\echo '  ./scripts/backup-logical.sh'
\echo '  DUMP_FILE=$(ls -t backup/claimsure-*.dump | head -1)'
\echo '  docker compose exec -T primary pg_restore --list < "$DUMP_FILE"'
\echo 'Capture globals separately because roles and tablespaces are not in pg_dump:'
\echo '  docker compose exec -T primary pg_dumpall -U postgres --globals-only > backup/globals.sql'

\echo '\n-- Lab 7D: Post-restore validation and difference report'
-- Run this section against claimsure_restore with snapshot=after_restore.
-- A baseline named before_backup must exist inside the restored dump.
-- @teacher [START 07-SQL022] Lab 7D | Post-restore validation and difference report
-- @teacher LOGIN / DATABASE: postgres | isolated claimsure_restore หลัง Restore; snapshot=after_restore
-- @teacher อธิบาย: ตรวจ Guard เดิมก่อนทำ Validation บน Restore Target
-- @teacher ผล/ชวนสังเกต: Guard เช็กแค่ชื่อไม่ใช่ claimsure จึงไม่พอสำหรับฐาน claimsure_xx; ผู้สอนต้องยืนยันเป็น isolated claimsure_restore และตั้ง snapshot=after_restore เอง
-- @teacher SOURCE: 07-backup-recovery.sql:286 | รัน SQL นี้ครบทั้ง Statement
SELECT current_database() <> 'claimsure' AS isolated_restore_database \gset
-- @teacher [END 07-SQL022]
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :isolated_restore_database
-- @teacher [START 07-SQL023] Lab 7D | Post-restore validation and difference report
-- @teacher LOGIN / DATABASE: postgres | isolated claimsure_restore หลัง Restore; snapshot=after_restore
-- @teacher อธิบาย: Capture ข้อมูลหลัง Restore ลง Run ใหม่บนฐานปลายทางที่แยกแล้ว
-- @teacher ผล/ชวนสังเกต: รันหลัง Shell Restore สำเร็จเท่านั้น; ไม่ใช้ชื่อ before_backup ซ้ำเพราะจะเทียบ Baseline กับตัวเอง
-- @teacher SOURCE: 07-backup-recovery.sql:288 | รัน SQL นี้ครบทั้ง Statement
SELECT lab_m7.capture_validation(:'snapshot') AS restored_validation_run_id \gset
-- @teacher [END 07-SQL023]

-- @teacher [START 07-SQL024] Lab 7D | Post-restore validation and difference report
-- @teacher LOGIN / DATABASE: postgres | isolated claimsure_restore หลัง Restore; snapshot=after_restore
-- @teacher อธิบาย: เทียบ Count ราย Table ระหว่าง Baseline ล่าสุดกับ Snapshot หลัง Restore
-- @teacher ผล/ชวนสังเกต: PASS หมายถึง Count เท่ากันเท่านั้น; MISSING SNAPSHOT ต้องแก้หลักฐาน ไม่สรุป PASS จากผลว่าง
-- @teacher SOURCE: 07-backup-recovery.sql:290 | รัน SQL นี้ครบทั้ง Statement
WITH chosen AS (
    SELECT DISTINCT ON (snapshot_name)
           run_id, snapshot_name, database_name, captured_at,
           function_count, procedure_count
    FROM lab_m7.validation_run
    WHERE snapshot_name IN ('before_backup', :'snapshot')
    ORDER BY snapshot_name, run_id DESC
), table_compare AS (
    SELECT t.schema_name, t.table_name,
           max(t.row_count) FILTER (WHERE c.snapshot_name = 'before_backup')
               AS before_rows,
           max(t.row_count) FILTER (WHERE c.snapshot_name = :'snapshot')
               AS restored_rows
    FROM chosen AS c
    JOIN lab_m7.table_validation AS t USING (run_id)
    GROUP BY t.schema_name, t.table_name
)
SELECT schema_name, table_name, before_rows, restored_rows,
       restored_rows - before_rows AS row_difference,
       CASE
           WHEN before_rows IS NULL OR restored_rows IS NULL THEN 'MISSING SNAPSHOT'
           WHEN before_rows = restored_rows THEN 'PASS'
           ELSE 'REVIEW'
       END AS result
FROM table_compare
ORDER BY result DESC, schema_name, table_name;
-- @teacher [END 07-SQL024]

-- @teacher [START 07-SQL025] Lab 7D | Post-restore validation and difference report
-- @teacher LOGIN / DATABASE: postgres | isolated claimsure_restore หลัง Restore; snapshot=after_restore
-- @teacher อธิบาย: เทียบ Function/Procedure Counts และเวลาของสอง Snapshots
-- @teacher ผล/ชวนสังเกต: ต้องมีสองชื่อและ Baseline ถูก Restore มาด้วย; ยังต้องทดสอบ Behavior/Permissions เพิ่ม
-- @teacher SOURCE: 07-backup-recovery.sql:317 | รัน SQL นี้ครบทั้ง Statement
SELECT snapshot_name, database_name, captured_at,
       function_count, procedure_count
FROM lab_m7.validation_run
WHERE run_id IN (
    SELECT max(run_id)
    FROM lab_m7.validation_run
    WHERE snapshot_name IN ('before_backup', :'snapshot')
    GROUP BY snapshot_name
)
ORDER BY snapshot_name;
-- @teacher [END 07-SQL025]
-- @teacher PSQL: Branch ทางเลือกของ psql; ไม่เลือก Execute ทั้งสอง Branch ใน SQL Editor
\else
\echo 'Lab 7D skipped: select an isolated database, for example:'
\echo '  TARGET_DATABASE=claimsure_restore ./scripts/run-module7-lab.sh lab07-D'
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif

\echo 'Isolated logical restore commands:'
\echo '  docker compose exec -T primary dropdb -U postgres --if-exists claimsure_restore'
\echo '  docker compose exec -T primary createdb -U postgres -T template0 claimsure_restore'
\echo '  docker compose exec -T primary pg_restore -U postgres -d claimsure_restore --exit-on-error < "$DUMP_FILE"'
\echo 'The Module 7 runner performs these steps through restore-logical.sh.'

\echo '\n-- Lab 7E: Physical backup and WAL archive readiness'
-- @teacher [START 07-SQL026] Lab 7E | Physical backup and WAL archive readiness
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: อ่าน Physical Backup/WAL Prerequisites และ pending_restart
-- @teacher ผล/ชวนสังเกต: บางค่าต้อง Restart เช่น wal_level/archive_mode; SQL นี้แค่อ่าน ไม่ตั้งค่า และไม่สร้าง Base Backup
-- @teacher SOURCE: 07-backup-recovery.sql:339 | รัน SQL นี้ครบทั้ง Statement
SELECT name, setting, unit, context, source, pending_restart
FROM pg_settings
WHERE name IN (
    'archive_mode', 'archive_command', 'wal_level', 'max_wal_senders',
    'max_replication_slots', 'wal_keep_size', 'full_page_writes',
    'data_checksums'
)
ORDER BY name;
-- @teacher [END 07-SQL026]

-- @teacher [START 07-SQL027] Lab 7E | Physical backup and WAL archive readiness
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: อ่านความสำเร็จ/ล้มเหลวของ WAL Archiver พร้อมเวลาล่าสุด
-- @teacher ผล/ชวนสังเกต: Counter สะสมหรือ Success เก่าไม่รับประกันว่า WAL ถึง Target ครบและเรียกคืนได้จริง
-- @teacher SOURCE: 07-backup-recovery.sql:348 | รัน SQL นี้ครบทั้ง Statement
SELECT archived_count, failed_count, last_archived_wal,
       last_archived_time, last_failed_wal, last_failed_time,
       stats_reset
FROM pg_stat_archiver;
-- @teacher [END 07-SQL027]

-- @teacher [START 07-SQL028] Lab 7E | Physical backup and WAL archive readiness
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: ตรวจ Replication Slots ที่อาจ Retain WAL ระหว่าง Backup/Replication
-- @teacher ผล/ชวนสังเกต: Inactive Slot อาจยังเก็บ WAL; อ่าน wal_status/safe_wal_size ประกอบ และไม่ลบ Slot โดยเดา
-- @teacher SOURCE: 07-backup-recovery.sql:353 | รัน SQL นี้ครบทั้ง Statement
SELECT slot_name, slot_type, active, restart_lsn,
       wal_status, safe_wal_size
FROM pg_replication_slots
ORDER BY slot_name;
-- @teacher [END 07-SQL028]

-- @teacher [START 07-SQL029] Lab 7E | Physical backup and WAL archive readiness
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: อ่าน Checkpoint Counters เพื่ออธิบายงานเขียนก่อน Physical Backup
-- @teacher ผล/ชวนสังเกต: เป็นสถิติ Cluster ไม่ใช่การ Verify Backup; pg_basebackup/pg_verifybackup เป็นขั้น Shell แยก
-- @teacher SOURCE: 07-backup-recovery.sql:358 | รัน SQL นี้ครบทั้ง Statement
SELECT num_timed, num_requested, num_done,
       buffers_written, write_time, sync_time, stats_reset
FROM pg_stat_checkpointer;
-- @teacher [END 07-SQL029]

\echo 'Create and verify a physical base backup from the host:'
\echo '  ./scripts/backup-physical.sh'
\echo '  BASE=$(ls -dt backup/base_* | head -1)'
\echo '  docker compose exec -T primary pg_verifybackup "/backup/$(basename "$BASE")"'

\echo '\n-- Lab 7F: Named restore point and recovery boundary'
-- @teacher [START 07-SQL030] Lab 7F | Named restore point and recovery boundary
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: ตรวจ Primary/Standby ก่อนสร้าง Restore Point
-- @teacher ผล/ชวนสังเกต: pg_create_restore_point ใช้บน Primary; psql Branch ข้ามบน Standby
-- @teacher SOURCE: 07-backup-recovery.sql:368 | รัน SQL นี้ครบทั้ง Statement
SELECT pg_is_in_recovery() AS is_replica \gset
-- @teacher [END 07-SQL030]
-- @teacher PSQL: เริ่ม Branch ฝั่ง psql ตาม Variable; SQL Editor ต้องเลือกเฉพาะ Branch ที่ตรง Environment
\if :is_replica
\echo 'Run Lab 7F on the ClaimSure primary. A standby cannot create a restore point.'
-- @teacher PSQL: Branch ทางเลือกของ psql; ไม่เลือก Execute ทั้งสอง Branch ใน SQL Editor
\else
-- @teacher [START 07-SQL031] Lab 7F | Named restore point and recovery boundary
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: สร้าง Named Restore Point เป็น WAL Record พร้อมเก็บชื่อ/LSN/เวลาสำหรับ Target
-- @teacher ผล/ชวนสังเกต: ไม่ใช่ Base Backup; PITR ต้องมี Base Backup ก่อนจุดนี้และ WAL Chain ถึง Target ครบ
-- @teacher SOURCE: 07-backup-recovery.sql:372 | รัน SQL นี้ครบทั้ง Statement
SELECT clock_timestamp() AS restore_point_time,
       :'restore_point' AS restore_point_name,
       pg_create_restore_point(:'restore_point') AS restore_point_lsn \gset
-- @teacher [END 07-SQL031]

-- @teacher [START 07-SQL032] Lab 7F | Named restore point and recovery boundary
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: อ่านชื่อ Restore Point, LSN และ WAL Segment ที่เกี่ยวข้อง
-- @teacher ผล/ชวนสังเกต: บันทึกผลไว้นอกฐานต้นทาง; pg_walfile_name ใช้บน Primary และการรู้ชื่อยังไม่ยืนยัน Archive สำเร็จ
-- @teacher SOURCE: 07-backup-recovery.sql:376 | รัน SQL นี้ครบทั้ง Statement
SELECT :'restore_point_name' AS restore_point_name,
       :'restore_point_lsn'::pg_lsn AS restore_point_lsn,
       pg_walfile_name(:'restore_point_lsn'::pg_lsn) AS required_wal_file,
       pg_current_wal_lsn() AS current_lsn;
-- @teacher [END 07-SQL032]
-- @teacher PSQL: จบ Conditional Branch ของ psql
\endif

-- @teacher [START 07-SQL033] Lab 7F | Named restore point and recovery boundary
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: อ่าน Archiver อีกครั้งเพื่อเช็กความคืบหน้าหลังสร้าง Restore Point
-- @teacher ผล/ชวนสังเกต: WAL Segment อาจยังไม่ถูก Archive ทันที; ต้องพิสูจน์การกู้คืนใน Instance แยก
-- @teacher SOURCE: 07-backup-recovery.sql:382 | รัน SQL นี้ครบทั้ง Statement
SELECT archived_count, failed_count, last_archived_wal,
       last_archived_time, last_failed_wal, last_failed_time
FROM pg_stat_archiver;
-- @teacher [END 07-SQL033]

\echo 'A PITR chain needs a base backup before the target and every required'
\echo 'WAL segment through the target. The Module 7 runner continues with:'
\echo '  PITR_PORT=15544 ./scripts/pitr-recover.sh'

\echo '\n-- Lab 7G: Recovery evidence and keep-or-fix decision'
-- @teacher [START 07-SQL034] Lab 7G | Recovery evidence and keep-or-fix decision
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: แสดงเป้าหมาย Recovery คู่กับ Evidence ที่บันทึกไว้
-- @teacher ผล/ชวนสังเกต: หาก Evidence เป็น NULL แปลว่ายังไม่มีบันทึก ไม่ใช่ PASS; เปรียบเทียบค่าที่วัดกับ Target หลัง Restore Drill
-- @teacher SOURCE: 07-backup-recovery.sql:391 | รัน SQL นี้ครบทั้ง Statement
SELECT o.service_name, o.rpo_minutes AS target_rpo_minutes,
       o.rto_minutes AS target_rto_minutes,
       e.exercise_name, e.artifact_uri, e.verification_method,
       e.result, e.measured_rpo_minutes, e.measured_rto_minutes,
       e.recorded_at, e.notes
FROM lab_m7.recovery_objective AS o
LEFT JOIN lab_m7.recovery_evidence AS e ON true
ORDER BY e.recorded_at DESC NULLS LAST;
-- @teacher [END 07-SQL034]

\echo 'Record one row after an isolated restore drill, for example:'
\echo '  INSERT INTO lab_m7.recovery_evidence('
\echo '    exercise_name, artifact_uri, verification_method, result,'
\echo '    measured_rpo_minutes, measured_rto_minutes, notes)'
\echo '  VALUES ('
\echo '    ''monthly logical restore'', ''backup/claimsure-...dump'','
\echo '    ''row counts + claim samples + routine inventory'', ''PASS'','
\echo '    8, 24, ''restored into claimsure_restore'');'

-- @teacher [START 07-SQL035] Lab 7G | Recovery evidence and keep-or-fix decision
-- @teacher LOGIN / DATABASE: postgres | claimsure บน Primary สำหรับ Setup/7A–C/7E–G; 7D ใช้ isolated claimsure_restore
-- @teacher อธิบาย: อ่านประวัติ Snapshots ล่าสุดเพื่อปิดการสอนด้วยหลักฐาน
-- @teacher ผล/ชวนสังเกต: สรุป Artifact Integrity + Restore + Business Validation + RPO/RTO; ข้อความ echo ตัวอย่าง INSERT ไม่ได้ Execute ให้เอง
-- @teacher SOURCE: 07-backup-recovery.sql:409 | รัน SQL นี้ครบทั้ง Statement
SELECT snapshot_name, database_name, captured_at,
       function_count, procedure_count
FROM lab_m7.validation_run
ORDER BY run_id DESC
LIMIT 10;
-- @teacher [END 07-SQL035]

\echo 'Recovery approval requires:'
\echo '1. Artifact integrity check passed'
\echo '2. Restore completed in an isolated compatible target'
\echo '3. Claim counts, timestamps, and sample claims match the expected point'
\echo '4. Measured RPO and RTO meet the ClaimSure objectives'
\echo '5. Owner recorded the result, exceptions, and next test date'

-- @teacher PSQL: แสดงเวลาใน Client; แยกจาก Execution Time ใน EXPLAIN
\timing off
