# Module 7 shared database command tutorial

Back up the practice data in your actual `claimsure_xx` database, commit a mistake,
and recover the earlier data into either your original `claimsure_xx` database
or your separate `claimsure_backup_xx` database. Both databases use the
shared Docker PostgreSQL server on **port 5432**. Your student account selects its
own number automatically.

This exercise resets `lab_m7_practice.claim_event` in your main database and
replaces the `lab_m7_practice` schema in the selected restore database. The
default restore target is your backup database. Insurance tables
and other schemas are outside the exercise.

## Run with one command

Log in to your student SSH account, then run:

```bash
bash "$HOME/scripts/module07-shared-tutorial.sh"
```

The tutorial executes the commands below in order. It stops if a step fails and
creates a new backup filename on every run. You can repeat it without changing
filenames or setting `STUDENT_NO` or `M7_BACKUP_DIR` in your terminal.

To display the commands without changing data:

```bash
bash "$HOME/scripts/module07-shared-tutorial.sh" --dry-run
```

## Copy the complete command block

Copy this entire block into one student SSH terminal. The opening and closing
`LAB7` lines are part of the command. `LAB7_DUMP` is defined inside the block,
so it does not depend on variables from an earlier terminal session.

```bash
bash <<'LAB7'
set -euo pipefail
cd "$HOME/scripts"
LAB7_DUMP="$HOME/backups/module07/shared-$(date -u +%Y%m%dT%H%M%SZ)-$$.dump"

./run-lab07.sh seed main --reset-practice
./run-lab07.sh practice-backup "$LAB7_DUMP"
./run-lab07.sh damage
./run-lab07.sh inspect main
./run-lab07.sh practice-restore "$LAB7_DUMP" --database backup
./run-lab07.sh inspect-recovery

printf '\nSaved backup: %s\n' "$LAB7_DUMP"
LAB7
```

## Choose the database to restore

To run the complete tutorial and recover the practice data back into your
original `claimsure_xx` database:

```bash
bash "$HOME/scripts/module07-shared-tutorial.sh" --database main
```

After this run, your main practice table has IDs **1 and 2** again. Read it with:

```bash
cd "$HOME/scripts"
./run-lab07.sh inspect main
```

For a separate restore into `claimsure_backup_xx`, choose `backup`:

```bash
bash "$HOME/scripts/module07-shared-tutorial.sh" --database backup
```

The restore command itself accepts a target after the saved archive path:

```text
./run-lab07.sh practice-restore ARCHIVE.dump --database main
./run-lab07.sh practice-restore ARCHIVE.dump --database backup
./run-lab07.sh practice-restore ARCHIVE.dump main
```

Substitute the saved archive path printed at the end of the tutorial for
`ARCHIVE.dump`. You can also supply your full database name: for studentxx,
`--database claimsure_xx` restores back into the original source, and
`--database claimsure_backup_xx` selects the backup database. Each account can
select only its own two databases. Without a target argument, the default is
`backup`; the interactive menu asks you to choose.

`inspect main` always reads the main database. `inspect-recovery` always reads
the backup database, even when the last restore selected `main`. The restore
command prints the actual selected database, login, port and rows afterward.

## Understand each step

| Step | Command | What it does |
| --- | --- | --- |
| 1 | `seed main --reset-practice` | Resets only the main practice table to IDs 1 and 2. |
| 2 | `practice-backup FILE` | Saves the complete practice schema before the mistake and writes its checksum. |
| 3 | `damage` | Deletes ID 2 and inserts ID 3 in `claimsure_xx`, then commits. |
| 4 | `inspect main` | Reads the main database; expect IDs 1 and 3. |
| 5 | `practice-restore FILE --database backup` | Verifies the archive and transactionally replaces only the practice schema in the selected own database. |
| 6 | `inspect-recovery` | Reads the backup database; expect IDs 1 and 2. |

The script prints `current_database`, the database login, and server port after
the change and during recovery inspection. For studentxx, these are
`claimsure_xx` / `claimsure_backup_xx`, login `student_xx`, and port `5432`.

## Expected final data for the default backup target

In the main database, `claimsure_xx`:

```text
 event_id |   description    | amount
----------+------------------+--------
        1 | CLAIM_REGISTERED | 100.00
        3 | AFTER_LOSS       | 999.00
```

In the recovered database, `claimsure_backup_xx`:

```text
 event_id |   description    | amount
----------+------------------+--------
        1 | CLAIM_REGISTERED | 100.00
        2 | CLAIM_APPROVED   | 250.00
```

The main database keeps the committed mistake. The separate backup database
contains the earlier saved rows. The final line prints the full archive path
for future restores.

## Check the data in pgAdmin

Open Query Tool on your own `claimsure_xx` database and execute:

```sql
SELECT current_database() AS database,
       current_user AS login,
       current_setting('port') AS server_port;

SELECT event_id, description, amount
FROM lab_m7_practice.claim_event
ORDER BY event_id;
```

Expect IDs **1 and 3**. Open a separate Query Tool on `claimsure_backup_xx` and
run the same SQL; expect IDs **1 and 2**. Refresh the query results after each run.

## Inspect again from SSH

```bash
cd "$HOME/scripts"
./run-lab07.sh inspect main
./run-lab07.sh inspect-recovery
```

## Resolve common errors

| Message or symptom | Action |
| --- | --- |
| An old command expands to `/base` or `m7_` | Use this tutorial's whole block or runnable copy. It initializes its own archive variable and uses database shortcuts. |
| Archive already exists | Run the complete tutorial again; it generates a fresh filename. Keep the file and its `.sha256` together. |
| Query shows the wrong database | Check `current_database()` and port `5432`, then select your own main or backup database in pgAdmin. |
| No change in `insurance.claim` | Inspect `lab_m7_practice.claim_event`, the table used by this exercise. |
| A base-backup directory is rejected by `practice-restore` | Supply the logical `.dump` file printed by `practice-backup`. |

## Identify the PostgreSQL server

| Student01 connection | Database | Port or socket port |
| --- | --- | --- |
| Shared main | `claimsure_xx` | **5432** |
| Shared backup | `claimsure_backup_xx` | **5432** |
| Private source | `m7_xx` | **5700 + student number**, Unix socket under `~/m7/sock` |
| Private recovered cluster | `m7_xx` | **5800 + student number**, Unix socket under `~/m7/sock` |

`practice-restore --database main` targets the actual shared main database.
`snapshot-restore`, `physical-restore` and `pitr-restore` target private clusters.
A physical snapshot restores a whole cluster; it cannot replace just one
student database on the shared server. Matching the port number alone would
not make the private cluster the shared server.

## Lab C snapshot recovery visible on port 5432

Prefer original commands instead of wrappers? Use
[Manual Labs C/D](module07-manual-labs-c-d.md), also shown step by step in the
paired slides. Complete M1–M5 first; it supplies every connection variable,
configuration file location, activation rule and recovery check. Keep manual
and wrapper attempts separate: their private workspaces and socket ports differ.

Run the complete Lab C exercise with one command:

```bash
bash "$HOME/scripts/module07-claimsure-snapshot-tutorial.sh"
```

Or copy these commands:

```bash
cd "$HOME/scripts"
./run-lab07.sh seed main --reset-practice
./run-lab07.sh claimsure-snapshot-backup
./run-lab07.sh damage
./run-lab07.sh inspect main
./run-lab07.sh claimsure-snapshot-restore --database main
./run-lab07.sh inspect main
```

Observe `lab_m7_practice.claim_event` in your normal DBeaver/pgAdmin connection
to **`claimsure_xx` on port 5432**, using your `student_xx` database login and
assigned PostgreSQL password. Before recovery, IDs are **1,3**; afterward, IDs
are **1,2**. Refresh the query results to see the change.

The helper captures a logical copy of the shared practice schema into private
`m7_stage_xx`, snapshots that stopped staging cluster, then recovers the staging
snapshot. Finally, it logically imports the recovered practice schema into the
selected shared database. The snapshot covers the private staging copy, and the
last step is a logical import into the live shared server.

Backup and recovery paths are fresh on each run. The latest completed capture
is recorded automatically; no external shell variables are needed. The staging
snapshot is marked with the source/student identity. The older raw private
snapshot backups have a different scope and are rejected by this helper.

Choose a separate backup target with:

```bash
./run-lab07.sh claimsure-snapshot-restore --database backup
./run-lab07.sh inspect-recovery
```

The full Lab C runner also accepts `--database main`, `backup`, or a full own
database name, and `--dry-run` previews the steps without changing data.

## Optional raw private snapshot recovery

The original private-only exercise remains available. It restores `m7_xx` on
its private socket; it does not import data into `claimsure_xx`:

```bash
./run-lab07.sh stop
./run-lab07.sh sandbox-start
./run-lab07.sh snapshot-restore "$HOME/backups/module07/snapshot" auto
./run-lab07.sh inspect-sandbox-recovery
```

This requires the older raw private snapshot backup. `auto` allocates a fresh
recovery directory and preserves earlier recovery files.

## Lab D: PITR with results in claimsure_xx on port 5432

Run the full lesson (resets only your main practice table):

```bash
bash "$HOME/scripts/module07-claimsure-pitr-tutorial.sh"
```

Or copy each command:

```bash
cd "$HOME/scripts"
./run-lab07.sh seed main --reset-practice
./run-lab07.sh claimsure-pitr-backup
./run-lab07.sh claimsure-pitr-event
./run-lab07.sh claimsure-pitr-mark
./run-lab07.sh damage
./run-lab07.sh inspect main
./run-lab07.sh claimsure-pitr-restore --database main
./run-lab07.sh inspect main
```

| Step | Committed IDs in shared `claimsure_xx:5432` |
| --- | --- |
| Reset and base backup | 1,2 |
| Commit row 4, then mark | 1,2,4 |
| Damage | 1,3,4 |
| PITR and import | 1,2,4 |

Row 4 (`AFTER_BASE_BEFORE_POINT`, 400.00) was committed after the base.
Keeping it proves WAL replay; excluding row 3 proves recovery stopped before
loss. The helper explicitly copies shared practice states into a private
staging cluster, performs real physical recovery and staging WAL replay there,
then logically imports the recovered practice schema into your selected shared
database. It does not continuously archive the Docker server's WAL.

Use your usual DBeaver/pgAdmin connection, `student_xx`, existing password,
port **5432**, database **claimsure_xx**. Re-run the query after each step:

```sql
SELECT event_id, description, amount
FROM lab_m7_practice.claim_event ORDER BY event_id;
```

Alternative target and timestamp examples (after completing the chain above):

```bash
./run-lab07.sh claimsure-pitr-restore --database backup
./run-lab07.sh inspect-recovery
./run-lab07.sh claimsure-pitr-restore --at-time saved --database main
./run-lab07.sh inspect-sandbox-recovery
./run-lab07.sh stop
```

Full own database names work too. The runner supports `--database backup` and
`--dry-run`. Fresh backup/recovery paths and a unique named point are automatic.
The shared result remains available after stopping private clusters.

Read the complete lab:

```bash
cat "$HOME/scripts/module07-backup-recovery.txt"
```

## Clear Module 7 practice data and backup files

Preview the cleanup first (no changes):

```bash
cd "$HOME/scripts"
./module07-cleanup.sh
```

Clear your Module 7 practice data and files:

```bash
./module07-cleanup.sh --yes
```

This removes `lab_m7_practice.claim_event` and its otherwise empty schema from
both your `claimsure_xx` and `claimsure_backup_xx` databases on **5432**. It stops
your private Module 7 PostgreSQL instances and removes the marked `~/m7`
sandbox plus `~/backups/module07`, including WAL, backups and recovery copies.
Your insurance data, databases, credentials, scripts and other labs remain.
Objects outside the practice table that depend on it cause a database rollback;
the script does not cascade into other schemas.

Choose one scope if needed:

```bash
./module07-cleanup.sh --yes --data-only
./module07-cleanup.sh --yes --files-only
```

`--data-only` leaves private instances and files. `--files-only` leaves the shared
practice data. `--dry-run` always previews, even together with `--yes`.
Custom backup destinations outside `~/backups/module07` must be cleaned separately;
a custom `M7_BACKUP_DIR` is rejected for file cleanup. Database cleanup runs one
transaction per database and stops on an error, so read the reported database
if a cleanup is interrupted. Re-running cleanup handles already absent objects.

To begin the next attempt:

```bash
./run-lab07.sh seed main --reset-practice
```

Labs C/D recreate private staging automatically. For the raw private exercises,
run `./run-lab07.sh sandbox-init` again after full cleanup.
