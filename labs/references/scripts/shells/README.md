# Lab Runner Quick Start

For native commands with Thai explanations, expected results and reset steps,
use the step-by-step command-line tutorials for Modules 1–7 and 9–10 (ส่วนแยกในต้นฉบับ: `docs/labs/command-line/README.md`).
Those tutorials do not call the shell runners below.

Legacy shell examples use the repository root; unified commands below specify their own working directory:

```bash
cd /opt/postgres-admin-labs
```

## Unified classroom runner: modules 1–7 and 9

The [complete course guide](course-labs-guide.md) covers student and instructor
commands, readiness vs execution, safe legacy-schema preservation, and scoped
reset with an insurance archive. Module 8/10 are excluded.

Student:

```bash
cd "$HOME/scripts"
./course-init-all.sh
./course-verify-all.sh
./course-labs.sh run 1
./course-labs.sh run 7.pitr
./course-run-all.sh
```

Reset previews by default; apply only after reviewing the scope:

```bash
./course-reset-all.sh
./course-reset-all.sh --yes
```

Instructor, using actual student SSH accounts and the existing private manifests:

```bash
cd /opt/setup-postgres-labs
./scripts/classroom-labs.sh prepare-all --preserve-legacy
./scripts/classroom-labs.sh verify-all
./scripts/classroom-labs.sh test-all
./scripts/classroom-labs.sh run --students 1 --module 5
./scripts/classroom-labs.sh run-all --dry-run
./scripts/classroom-labs.sh run-all --yes
```

Instructor `reset-all --yes` applies to all selected students' course fixtures.
Use `--students 1-5,20` to narrow the cohort. `--profile quick` selects workflow
smoke checks rather than full measurement/observation windows. Existing flat
runners and credentials remain untouched; the tested bundle is under
`~/scripts/course`. Legacy incompatible insurance schemas are archived and
renamed only with `--preserve-legacy`; saved data/restore SQL remain available.

## Configure your student account

Create the local environment file once:

```bash
cp .env.example .env
```

Set your student number and database password in `.env`:

```dotenv
STUDENT_NO=xx
DB_PASSWORD=your-database-password
```

Student `xx` is mapped automatically:

| Account | Value |
| --- | --- |
| SSH login | `studentxx` |
| Database user | `student_xx` |
| Main database | `claimsure_xx` |
| Backup database | `claimsure_backup_xx` |

For example, student xx connects as `student_xx` and can use
`claimsure_xx` only.

## Module 1: Basic SQL

Run the labs in order. Lab 1A creates the objects and Lab 1B inserts the seed data:

```bash
./scripts/shells/run-lab01.sh --student xx --ask-pass A
./scripts/shells/run-lab01.sh --student xx --ask-pass B
./scripts/shells/run-lab01.sh --student xx --ask-pass C
./scripts/shells/run-lab01.sh --student xx --ask-pass D
./scripts/shells/run-lab01.sh --student xx --ask-pass E
./scripts/shells/run-lab01.sh --student xx --ask-pass F
./scripts/shells/run-lab01.sh --student xx --ask-pass G
```

Run the whole module in one command:

```bash
./scripts/shells/run-lab01.sh --student xx --ask-pass all
```

Show the available Module 1 labs without connecting:

```bash
./scripts/shells/run-lab01.sh --list
```

## Module 2: Advanced SQL

Complete Module 1 first, then run these labs in order. Labs C and E-G use
objects created by Lab 2A or 2B.

```bash
./scripts/shells/run-lab02.sh --student xx --ask-pass A
./scripts/shells/run-lab02.sh --student xx --ask-pass B
./scripts/shells/run-lab02.sh --student xx --ask-pass C
./scripts/shells/run-lab02.sh --student xx --ask-pass D
./scripts/shells/run-lab02.sh --student xx --ask-pass E
./scripts/shells/run-lab02.sh --student xx --ask-pass F
./scripts/shells/run-lab02.sh --student xx --ask-pass G
./scripts/shells/run-lab02.sh --student xx --ask-pass H
```

Run the whole module in one command:

```bash
./scripts/shells/run-lab02.sh --student xx --ask-pass all
```

Show the available Module 2 labs without connecting:

```bash
./scripts/shells/run-lab02.sh --list
```

`--ask-pass` in the module-specific runners asks for the PostgreSQL
password. Omit it when `DB_PASSWORD` is already set in `.env`.

## Module 3: Performance Tuning

Each Lab 3 section prepares the shared 200,000-row performance workload, so
you can run a section independently:

```bash
./scripts/shells/run-lab03.sh --student xx --ask-pass A
./scripts/shells/run-lab03.sh --student xx --ask-pass B
./scripts/shells/run-lab03.sh --student xx --ask-pass C
./scripts/shells/run-lab03.sh --student xx --ask-pass D
./scripts/shells/run-lab03.sh --student xx --ask-pass E
```

Run the whole performance flow or list the sections:

```bash
./scripts/shells/run-lab03.sh --student xx --ask-pass all
./scripts/shells/run-lab03.sh --list
```

## Module 4: Security and User Management

The active sources are the Module 4 slide deck (ส่วนแยกในต้นฉบับ: `docs/slides/module-04-security-user-management.md`)
and [the student template](../sql/04-security-user-management.sql).
Open the slides with `make slides-m4` (or `make slides MODULE=4`).

Run **one START/END block at a time**, in source order. The runner substitutes
`xx` with `--student xx`, selects the database login from the block's `LOGIN`
comment, and checks the connected identity and database before executing SQL.
Whole-module `lab04` and whole-letter `lab04_A` execution are not supported.

```bash
./scripts/shells/run-lab.sh --list
./scripts/shells/run-lab.sh --student xx --dry-run lab04_A.1
# Use a service configured with the postgres credentials for 0 and 4A:
./scripts/shells/run-lab.sh --student xx --service claimsure_admin_xx lab04_0
./scripts/shells/run-lab.sh --student xx --service claimsure_admin_xx lab04_A.1
./scripts/shells/run-lab.sh --student xx --service claimsure_admin_xx lab04_A.2
```

`claimsure_admin_xx` is an example service name; configure it in the remote
`~/.pg_service.conf` with the class host/port and the actual postgres password.
Create a personal SQL copy and fill in all three `change_me_*` passwords before
running 4A.3. Keep `xx` in the copy; the runner substitutes the student number.

```bash
cp scripts/sql/04-security-user-management.sql /tmp/module4-personal.sql
# Edit /tmp/module4-personal.sql to set the passwords in 4A.3 first.
./scripts/shells/run-lab.sh --student xx --service claimsure_admin_xx \
  --sql-file /tmp/module4-personal.sql lab04_A.3
./scripts/shells/run-lab.sh --student xx --service claimsure_admin_xx lab04_A.4
# Continue all B-H blocks in order; these show selected examples:
./scripts/shells/run-lab.sh --student xx lab04_B.1
./scripts/shells/run-lab.sh --student xx --service claimsure_app_xx lab04_C.4
```

For B-H, use `claimsure_xx` for `student_xx`, and separate services with matching
passwords for `claim_app_xx`, `internal_auditor_xx`, and `manager_th_xx` as needed.
The runner always uses `claimsure_xx` as the database and the block's required
login. `--local` uses services on this machine instead of the remote account.

Each command opens a fresh database session. For an EXPECTED ERROR block, the
runner verifies SQLSTATE `42501` and rolls back in the same session; an unexpected
success or a different error fails the command. The following RECOVERY block is
still listed for the manual SQL editor workflow; it is optional with the runner.
`--ask-pass` asks for the SSH password, not the database password.

## Module 6: Docker configuration workshop (repository version)

`make slides-m6` opens the active deck (ส่วนแยกในต้นฉบับ: `docs/slides/module-06-configuration-claim.md`).
Follow the six-lab runbook (ส่วนแยกในต้นฉบับ: `labs/module06/README.md`): Connections → Memory →
WAL/checkpoints → Planning/storage → Parallelism → Autovacuum, one SQL lab A–F per group.
This version starts its own PostgreSQL 18 Docker Compose instance (`postgres` / `claimsure_m6`)
and generates ClaimSure data in `lab_m6c`; Module 1 and the shared SSH service are not needed.

```bash
cp labs/module06/.env.example labs/module06/.env
# Edit project name, host port and password in that file.
./scripts/shells/run-lab06-docker.sh up
./scripts/shells/run-lab06-docker.sh sql A
./scripts/shells/run-lab06-docker.sh set A candidate
./scripts/shells/run-lab06-docker.sh reload
./scripts/shells/run-lab06-docker.sh restart
./scripts/shells/run-lab06-docker.sh sql A
./scripts/shells/run-lab06-docker.sh set A baseline
./scripts/shells/run-lab06-docker.sh restart
```

Host configuration: `labs/module06/config/conf.d/`; server path:
`/etc/postgresql/module06/conf.d/`. A/B/E require restart; C/D/F require reload.
Each letter has baseline/candidate presets and explicit rollback in the runbook.
There are **15 START/END SQL blocks**, including fixture setup and optional 6F.3 reset.
Keep one connection inside a lettered lab; reconnect after restart. 6F.3 is skipped
by default so table overrides remain available for asynchronous autovacuum observation.

`run-lab.sh lab06_A` delegates to this dedicated runner when local classroom mode is off.
With `--local` or `LAB_RUN_LOCAL=1`, the general runner selects the classroom runner below. `--service` and custom
psql arguments are rejected for Module 6 to avoid using the classroom service.
`run-lab06-docker.sh sql all` / `run-lab.sh lab06` runs only the SQL experiments; it does
not edit files, reload, or restart. Complete those stages separately in the runbook.
See the [SQL and slide map](../sql/06-configuration-claim-lab-map.md).

## Running from a student SSH session

After logging in once, run labs locally without another SSH password:

```bash
cd ~/scripts
./run-lab.sh lab01_C
./shells/run-lab.sh lab01_C
```

The student installer sets `LAB_RUN_LOCAL=1` in your private `~/.env`.
Both paths load it automatically. Omit `--ask-pass` inside this session.
For an older installation, use `./shells/run-lab.sh --local lab01_C`.

## Module 6: configuration measurements and reset

Run from your own student SSH account. Shared tests connect directly to your own
`claimsure_xx` on **5432**; private D/F tests use `~/m6` and a Unix socket.
The runner automatically loads your private `~/.env`.

```bash
cd "$HOME/scripts"
./run-lab06.sh doctor
./run-lab06.sh baseline
./run-lab06.sh --dry-run all
./run-lab06.sh all
```

| Lab | Shell entry point | Evidence |
| --- | --- | --- |
| A | `./module06-A.sh` | PostgreSQL boot/effective/RESET values and origins |
| B | `./module06-B.sh --repeat 3` | Original and candidate report-sort medians/temp blocks |
| C | `./module06-C.sh` | Session counts/limits, statement/lock timeout ms and SQLSTATEs |
| D | `./module06-D.sh` | Private WAL bytes and checkpoint deltas at two WAL sizes |
| E | `./module06-E.sh --wait 75` | Actual autovacuum/dead tuples, exact table-option restoration |
| F | `./module06-F.sh` | Private before/after logging workload and counted events |
| G | `./module06-G.sh` | Summary and keep/revert worksheet |
| Reset | `./module06-reset.sh` | Restore pending exact table/private originals; stop private server |

Equivalent actions are `./run-lab06.sh A` through `G` and `reset`. Add
`--dry-run` to preview. The repository copies can run directly from
`/opt/postgres-admin-labs/scripts/shells` on the student host too.

`all` includes reset at the end. Reports remain in `~/labs/module06/RUN_ID`.
No shared cluster configuration, insurance table or other student's database is
changed. [The full manual](module06-configuration-lab.md) explains exact settings,
original values, configuration locations and copyable SQL without the shell
runner. Module 6 slides (ส่วนแยกในต้นฉบับ: `docs/slides/module-06-configuration.md`) use the
same lab actions. PostgreSQL 18 binaries and Python 3 are prerequisites.

## Module 7: Backup and Recovery

The dedicated `run-lab07.sh` runner teaches logical backup, physical backup,
staging snapshots and point-in-time recovery. It prints command formats and the
commands it executes. Missing parameters are prompted; `--dry-run` previews them.

On the classroom machine, use your own student SSH account. Each student already
has an installed copy in `~/scripts` that loads `~/.env` automatically:

```bash
cd "$HOME/scripts"
./run-lab07.sh --help
./run-lab07.sh doctor
./run-lab07.sh
```

To run the repository copies directly on this machine, load your student
configuration into the environment first:

```bash
cd /opt/postgres-admin-labs/scripts/shells
set -a
source "$HOME/.env"
set +a
./run-lab07.sh --help
./run-lab07.sh doctor
```

The configuration stays in your private home directory. PostgreSQL 18 server
binaries (or the classroom runtime bundle) and Python 3 are required for the
private cluster and cleanup exercises. Students do not need sudo or Docker.

| File | Learning exercise |
| --- | --- |
| `run-lab07.sh` | Guided menu and individual backup/recovery commands |
| `module07-shared-tutorial.sh` | Logical backup, committed damage, selected shared restore target |
| `module07-claimsure-snapshot-tutorial.sh` | Lab C staging snapshot, recovery, import to shared port 5432 |
| `module07-claimsure-pitr-tutorial.sh` | Lab D physical base, WAL replay to a target, import to shared port 5432 |
| `module07-cleanup.sh` | Preview or clear only your Module 7 practice data and lab files |
| `module07-cleanup-files.py` | Internal file ownership/path checks and cleanup helper |
| `module07-practice.sql` | Disposable practice schema and seed rows |
| [module07-command-tutorial.md](module07-command-tutorial.md) | Copyable commands and expected results |
| [module07-manual-labs-c-d.md](module07-manual-labs-c-d.md) | Native-command Labs C/D, source/recovery config and flow without wrappers |
| [module07-backup-recovery.txt](module07-backup-recovery.txt) | Full lab, raw physical recovery and troubleshooting |

Preview the runnable lessons from either script directory above:

```bash
./module07-shared-tutorial.sh --dry-run
./module07-claimsure-snapshot-tutorial.sh --dry-run
./module07-claimsure-pitr-tutorial.sh --dry-run
./module07-cleanup.sh
```

Run the shared lessons (each resets only the main Module 7 practice table):

```bash
./module07-shared-tutorial.sh --database main
./module07-claimsure-snapshot-tutorial.sh --database main
./module07-claimsure-pitr-tutorial.sh --database main
```

Shared results use your normal `student_xx` login and password, database
`claimsure_xx`, port **5432**. Choose `--database backup` or your full own database
name for another restore destination. Labs C/D perform physical recovery/WAL
replay on a private staging cluster, then logically import recovered practice
rows into the selected shared database. They do not restore the entire shared
Docker cluster. The full handout also covers raw private physical backups.

Original PostgreSQL commands for Labs C/D, matching the added manual slides,
are in [the native-command guide](module07-manual-labs-c-d.md). It uses a separate
`m7-manual.*` workspace and documents its native shutdown commands.

Cleanup previews by default; only an explicit `--yes` applies it:

```bash
./module07-cleanup.sh --yes
```

It removes only the practice table/schema in your own main and backup databases,
stops private Module 7 instances and removes the marked `~/m7` sandbox and
`~/backups/module07`. Insurance data, credentials and scripts remain. See the
command tutorial for `--data-only`, `--files-only` and custom-path restrictions.

## Module 9: Grafana monitoring, initialization and reset

The full [step-by-step Grafana lab](module09-grafana-lab.md) covers instructor
setup, JSON import, bounded SQL workloads, blocking/deadlock evidence and reset.
The [dashboard JSON](module09-grafana-import.json) imports into Grafana 11 with
Prometheus/database variables and no embedded credentials.

Instructor (existing stack and private `.env`, Docker access):

```bash
cd /opt/setup-postgres-labs
./scripts/module09-stack.sh init-all
./scripts/module09-stack.sh check
```

Each student, from their own SSH account:

```bash
cd "$HOME/scripts"
./module09-init-all.sh
./run-lab09.sh doctor
./module09-workload.sh --seconds 120
./module09-blocking.sh --seconds 120
./module09-observe.sh
./run-lab09.sh blocking-stop
./module09-deadlock.sh
./module09-reset-all.sh
```

Use Grafana **http://SERVER_IP:3000**, your assigned login, **Prometheus** and
**claimsure_xx**. The provisioned dashboard is **ClaimSure / Module 9 - Student
PostgreSQL Monitoring**. Alternatively import `module09-grafana-import.json` as
a uniquely named copy. Wait 60–90s for rate samples (30s scrape interval).
The 20 panels distinguish HTTP exporter reachability from PostgreSQL health.

`run-lab09.sh all --seconds 120` runs the complete bounded drill and stops clients;
`reset-all` removes this lesson's marked fixtures. Add `--dry-run` for a preview.
Reset preserves insurance data, other students/labs, credentials, dashboards,
global statistics and monitoring history. An old deadlock remains in historical
graphs. Instructor `module09-stack.sh reset-all --yes` scopes this reset to all
20 main databases. It does not wipe the monitoring stack.

## Module 7: legacy insurance-schema runner

The earlier insurance-schema demonstration remains available as
`./scripts/shells/run-lab07-legacy.sh --student xx --dry-run logical`.
Use the canonical `run-lab07.sh` for the guided practice-schema, snapshot and PITR
labs described above and in the active slide deck.

## Modules 5 and 8-10 over SSH

The general runner sends SQL to the lab server over SSH. Run an entire module
with one of these commands:

```bash
./scripts/shells/run-lab.sh --ask-pass lab05
./scripts/shells/run-lab.sh --ask-pass lab08
./scripts/shells/run-lab.sh --ask-pass lab09
./scripts/shells/run-lab.sh --ask-pass lab10
```

Module 7 uses [run-lab07.sh](run-lab07.sh) instead of this SSH runner.
Add the section suffix to run only one sub-lab:

```bash
./scripts/shells/run-lab.sh --ask-pass lab05_D.1
```

Use two terminals for the concurrent-session exercises:

```bash
# Terminal 1
./scripts/shells/run-lab.sh --ask-pass lab05_mvcc_a

# Terminal 2
./scripts/shells/run-lab.sh --ask-pass lab05_mvcc_b
```

The same pattern applies to `lab09_lock_a` and `lab09_lock_b`.

List every valid lab ID:

```bash
./scripts/shells/run-lab.sh --list
```

The general runner's `--ask-pass` option asks for the SSH password and requires
`sshpass`. If SSH keys are configured, omit `--ask-pass`.

## Preview before running

Use `--dry-run` to verify the account, database, and extracted SQL without
connecting:

```bash
./scripts/shells/run-lab01.sh --student xx --dry-run A
./scripts/shells/run-lab02.sh --student xx --dry-run E
./scripts/shells/run-lab03.sh --student xx --dry-run D
./scripts/shells/run-lab.sh --dry-run lab07_D
```
