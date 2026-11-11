# Module 7E — Databasus backup and recovery

> สำเนานี้รวมคู่มือ ภาพหน้าจอ และ PDF ที่มีในต้นทาง ส่วน `run-lab07-databasus.sh` และ `scripts/databasus/classroom.sh` ไม่พบใน source ที่คัดลอก คำสั่ง helper เหล่านี้ใช้เมื่ออาจารย์ติดตั้งไว้บนเครื่องเรียนแล้ว การทำผ่าน Databasus UI ใช้ [student manual](module-07-databasus-student-manual.md) และ instance ที่อาจารย์เตรียม

Student tutorial: [illustrated step-by-step manual](module-07-databasus-student-manual.md)
with live Playwright screenshots, or its
[printable PDF](module-07-databasus-student-manual.pdf).

Use the existing self-hosted **Databasus 3.60.0** application to back up your
own `claimsure_xx` and restore into `claimsure_databasus_xx` on the same direct
PostgreSQL port **5432**. Each student has a separate Databasus login/workspace,
a scoped source configuration, local backup storage and a dedicated recovery
database. Twenty Databasus containers are not needed.

This is a **logical backup and recovery** lesson. The source includes only
`insurance` and `lab_m7_databasus`. Some security-lab schemas deliberately deny
student reads; a whole-database pg_dump would fail without extra privileges.
The classroom configuration preserves those restrictions. Existing Module 7
physical, staged snapshot and PITR exercises remain available in `run-lab07.sh`;
Databasus physical/PITR backup of the shared cluster is not enabled for students.

## 1. Open your account

On the classroom SSH terminal:

```bash
cd "$HOME/scripts"
./run-lab07-databasus.sh credentials
./run-lab07-databasus.sh verify
```

`credentials` prints **your own** web URL/email/password and SQL GUI details.
Databasus has a new generated web password; your PostgreSQL password is unchanged.
Your personal details are in `~/.databasus-lab.json` (0600). The instructor's
account and other students' credentials are not installed in your home.

Open the printed URL, sign in, and select **ClaimSure Student xx - Module 07**.
You should see only your workspace and the `claimsure_xx - Module 07` source.
You are a workspace **Member**, not an instance administrator. You can initiate
backups, download your own backups, restore and manage your workspace's source
configuration. Do not add another student's credentials or change the source
connection during the exercise.

For encrypted transport without publishing another web service, open this on
your **laptop** and leave it running:

```bash
ssh -N -L 14005:127.0.0.1:4005 studentxx@YOUR_CLASSROOM_HOST
```

Use your own SSH account, then open **http://127.0.0.1:14005**. This tunnels the
existing Databasus instance. The direct classroom URL remains available; no
certificate/domain or reverse proxy was changed by setup.

## 2. Check the configured backup source

In your workspace, open `claimsure_xx - Module 07` and its configuration:

| Setting | Value |
| --- | --- |
| Database type | PostgreSQL logical |
| Host | `postgres` — Docker's database service name |
| Port | `5432` |
| Database | `claimsure_xx` |
| User | `student_xx` |
| Password | Your existing PostgreSQL password; stored hidden by Databasus |
| SSL mode | `disable`, inside the existing Docker classroom network |
| Include schemas | `insurance`, `lab_m7_databasus` |
| CPU count | `1` |
| Storage | `Student xx local backups` |
| Retention | Count, keep `5` |
| Scheduled backups | **Disabled** initially; manual backups work |
| Encryption | `NONE` for this learning exercise; local storage remains private |
| Notifications | None configured; setup does not send emails |

Click **Test connection**. The hostname is `postgres` inside Docker. Your
laptop SQL management client instead uses the classroom server hostname/IP.
Do not use PgBouncer port 6432 for this backup/restore lesson.

## 3. Seed and inspect the practice table

Run on the classroom SSH terminal:

```bash
cd "$HOME/scripts"
./run-lab07-databasus.sh seed --reset-practice
./run-lab07-databasus.sh inspect --database main
```

Expected source practice rows:

```text
1 | CLAIM_REGISTERED | 100.00
2 | CLAIM_APPROVED   | 200.00
```

Only the marked `lab_m7_databasus` practice rows are reset. Your insurance rows
and the other Module 7 practice schema are preserved. Pause other SQL changes
to your database until you finish this exercise.

## 4. Create a backup from the web UI

Open your database's **Backups** tab and click **Make backup**. Wait for status
**COMPLETED**; record its UUID/time/size. A running or failed job is not a usable
backup. Open the backup log and confirm that the source is your own database.

The equivalent terminal command creates the backup through the **Databasus
API**, waits for completion and records its UUID/baseline counts:

```bash
./run-lab07-databasus.sh backup
./run-lab07-databasus.sh status
```

Use either the UI-created UUID explicitly in later commands, or use the terminal
command's recorded backup. Do not create another backup after damage and then
mistake that newer backup for the pre-damage recovery point.

## 5. Simulate a committed loss in the source

If you made the backup through the terminal helper:

```bash
./run-lab07-databasus.sh damage
./run-lab07-databasus.sh inspect --database main
```

For a UI-created backup, substitute its actual UUID:

```bash
./run-lab07-databasus.sh damage --backup-id YOUR_COMPLETED_BACKUP_UUID
```

The committed change deletes practice row 2 and inserts row 3 (`AFTER_LOSS`,
999.00). The source now contains **1,3**. The helper checks that the selected
backup belongs to your own configured source and is complete before changing
practice data. It does not damage `insurance`.

## 6. Restore through Databasus into your recovery database

Before a UI restore, prepare the dedicated target from your SSH terminal:

```bash
./run-lab07-databasus.sh prepare-target       # preview
./run-lab07-databasus.sh prepare-target --yes
```

On a repeated restore, PostgreSQL's `pg_restore --clean` can fail while dropping
an inherited partition primary key from the previous copy. This preparation
detaches only your owned target partitions in the selected schemas, keeping
their data/indexes until restore replaces them. It never detaches the source's
partitions and refuses cross-schema/foreign-owned target partitions. Close open
transactions on the recovery connection before preparation; otherwise its
five-second lock timeout may stop it. An empty first-time target has nothing
to detach. The terminal `restore --yes` runs this preparation automatically.

Select the **pre-damage completed backup** and click **Restore**. Enter:

| Restore setting | Value |
| --- | --- |
| Host / port | `postgres` / `5432` |
| Database | `claimsure_databasus_xx` |
| Username / password | `student_xx` / your existing PostgreSQL password |
| CPU count | `1` |
| Exclude extensions | **Enabled** |
| Restore ownership | **Disabled** |
| Restore privileges | **Disabled** |

The instructor has already created the target and necessary extensions. No
student gets superuser or replication privileges. The restore replaces objects
present in the selected archive in this dedicated target. It does not switch
the source connection or restore automatically back into `claimsure_xx`.
Choose the database name carefully: the target is neither the main database nor
the existing `claimsure_backup_xx` used by other lessons.

Wait for the restore's own status to become **COMPLETED**. A completed *backup*
does not mean the later restore succeeded.

Equivalent terminal commands:

```bash
# Preview the exact source backup and target
./run-lab07-databasus.sh restore
# Apply to the dedicated recovery database
./run-lab07-databasus.sh restore --yes

# Or explicitly choose your UI-created completed backup
./run-lab07-databasus.sh restore --backup-id YOUR_COMPLETED_BACKUP_UUID --yes
```

The helper refuses `--database main` for restore. Databasus's UI still permits
manual target selection under your own DB permissions, so use the recovery name
above and review it before submitting.

## 7. Observe the restored data in DBeaver or desktop pgAdmin

Create a **second connection** using your normal classroom server hostname,
port **5432**, user `student_xx`, existing SQL password, and database
**`claimsure_databasus_xx`**. Keep the original `claimsure_xx` connection so you
can compare the two.

Run this SQL in both connections (it has no `xx` substitution):

```sql
SELECT current_database(), current_user, current_setting('port');
SELECT event_id, description, amount
FROM lab_m7_databasus.claim_event
ORDER BY event_id;
SELECT table_name
FROM information_schema.tables
WHERE table_schema='insurance' AND table_type='BASE TABLE'
ORDER BY table_name;
```

Expected: source practice IDs **1,3**; recovery practice IDs **1,2**. Insurance
tables/counts in the recovery database should match the backup baseline.
Refresh the database navigator or open a new SQL editor against the recovery
connection if your GUI still shows the old source data.

```bash
./run-lab07-databasus.sh inspect --database main
./run-lab07-databasus.sh inspect --database recovery
./run-lab07-databasus.sh counts --database main
./run-lab07-databasus.sh counts --database recovery
```

The terminal backup records exact counts for the actual insurance tables, and
its restore checks those counts too. Different students can retain different
insurance models; no customer/policy/claim structure is forced by this lab.
For a UI-only backup, record the `counts` output before backing up and compare
it with the recovered output. You can also run `SELECT count(*)` on each listed
table in your GUI. Partition parents and children are reported separately;
do not sum those counts, because parent scans already include their partitions.
The controlled helper also checks its configured schema scope and recorded
practice IDs. Keep this assigned source unchanged; use a separate job in your
own workspace if the instructor asks you to explore other selection filters.

## 8. Run the complete terminal drill or reset its practice rows

```bash
# Preview only
./run-lab07-databasus.sh all
# Real Databasus backup, committed damage and restore, with data checks
./run-lab07-databasus.sh all --yes

# Repeat only the initial practice state
./run-lab07-databasus.sh seed --reset-practice

# Reset preview; --yes removes only this marked practice schema in both DBs
./run-lab07-databasus.sh reset
./run-lab07-databasus.sh reset --yes
```

For a repeated `all --yes` drill, any already restored **marked practice table**
in the recovery database is first changed to row 9. The restore must then replace
it with the recorded baseline, so old rows from an earlier run cannot falsely
pass the recovery check. Other target schemas are not changed by that test step.

Reset uses named tables and RESTRICT checks; unknown dependencies cause an error.
It retains insurance data, Databasus accounts/settings, backup files/history,
the recovery database, and other Module 7 fixtures. Per-command evidence and the
recorded backup UUID are under `~/labs/module07-databasus/`. Store screenshots of
backup completion, restore completion, and the two SQL results with your report.

## 9. Scheduling, retention and downloads

After the manual restore works, inspect the schedule/retention controls. If the
instructor allows scheduling, enable a daily or staggered schedule and check the
next run time and displayed timezone. Disable it again after observing it.
Do not turn all twenty sources into simultaneous minute-by-minute backups.
Retention of five means older managed backups may be deleted; keep an independent
copy of an important recovery point before testing retention.

Use **Download** for your own backup and save it outside this server. Local
Databasus storage is under its existing persistent `/databasus-data` mount;
application workspaces restrict access to the managed files. Local copies do
not protect against loss of the VM/disk. A backup being downloadable is not proof
of recovery; the restore and SQL checks above are the evidence.

## Instructor setup and verification

```bash
cd /opt/postgres-admin-labs
./scripts/databasus/classroom.sh init-all
./scripts/databasus/classroom.sh verify-all

# Run actual student SSH helpers sequentially; source changes affect only practice
./scripts/databasus/classroom.sh test-all --students 1
./scripts/databasus/classroom.sh test-all
```

Setup backs up the application's metadata before provisioning, reuses the
existing instance, registers one instructor and twenty separate student
accounts, creates workspaces/storage/sources, closes external registration,
disallows student workspace creation/invitations, and installs the private
logins/helpers. It uses the account-invitation API record without sending email;
existing users are added to workspaces only after activation. It never resets
an existing admin's password. If the instance is already claimed and no managed
admin credential file exists, provide `DATABASUS_ADMIN_EMAIL` and
`DATABASUS_ADMIN_PASSWORD` through the environment once.

Private instructor records:

- `/opt/setup-postgres-labs/secrets/databasus-admin.json`
- `/opt/setup-postgres-labs/secrets/databasus-students.json`
- `/opt/setup-postgres-labs/backups/databasus-bootstrap/`
- `/opt/setup-postgres-labs/reports/databasus/RUN_ID/summary.json`

Do not distribute those files. Each student receives only their own 0600
`~/.databasus-lab.json`. `verify-all` checks login/global role, workspace/source/
storage isolation, PostgreSQL target ownership/connection privileges, and
cross-student backup-history/restore-history/download denial when backups exist.
`test-all` executes the real backup/damage/restore drill through each installed
student SSH account, sequentially. It leaves the source practice **1,3** and
recovered copy **1,2**, ready for GUI inspection. Setup preserves existing marked
practice rows and refuses an unmarked/foreign-owned recovery database.

The Databasus API automation is intentionally version-checked for **3.60.0**;
do not upgrade its image in the middle of class. The existing database, Grafana,
Prometheus, SSH credentials and learner insurance data are not restarted/reset
by this setup. Use the classroom recovery helper if existing containers stop.

The metadata snapshot made before setup does not contain the later backup
files. For recovery of Databasus itself, preserve its **whole persistent
`/opt/setup-postgres-labs/databasus-data` volume** with a consistent stopped
copy or supported backup procedure, and keep a protected copy off-host. This
contains accounts, encryption keys and database secrets as well as backup files;
it is an instructor backup, not a student download kit. Students export only
their own database backups through their own workspace.

Official references:

- [Databasus installation](https://databasus.com/installation/)
- [Databasus workspace access management](https://databasus.com/access-management/)
- [Databasus 3.60.0 source](https://github.com/databasus/databasus/tree/v3.60.0)
