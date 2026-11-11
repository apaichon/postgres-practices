# Lab Runner Quick Start

Run every command from the repository root:

```bash
cd /Users/apaichon/Projects/Courses/postgres/setup-postgres-server/postgres-admin-labs
```

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
| [module07-manual-labs-c-d.md](module07-manual-labs-c-d.md) | Original PostgreSQL commands for Labs C/D, including configuration, staging, recovery and shared import without wrappers |
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

For the same Labs C/D **without running shell wrappers**, follow
[the native-command walkthrough](module07-manual-labs-c-d.md): M1–M5 → C1–C5 →
D1–D7 → Z1. It explains which user runs each command, where source/recovery
configuration is written, and how to check archiving, paused replay and the
shared result on 5432. Its `~/m7-manual.*` workspace uses separate socket ports;
stop it with the documented native `pg_ctl` commands. The guided cleanup below
manages only the wrapper workspace.

Cleanup previews by default; only an explicit `--yes` applies it:

```bash
./module07-cleanup.sh --yes
```

It removes only the practice table/schema in your own main and backup databases,
stops private Module 7 instances and removes the marked `~/m7` sandbox and
`~/backups/module07`. Insurance data, credentials and scripts remain. See the
command tutorial for `--data-only`, `--files-only` and custom-path restrictions.

## Modules 4-10 over SSH

The general runner sends SQL to the lab server over SSH. Run an entire module
with one of these commands:

```bash
./scripts/shells/run-lab.sh --ask-pass lab04
./scripts/shells/run-lab.sh --ask-pass lab05
./scripts/shells/run-lab.sh --ask-pass lab06
./scripts/shells/run-lab.sh --ask-pass lab07
./scripts/shells/run-lab.sh --ask-pass lab08
./scripts/shells/run-lab.sh --ask-pass lab09
./scripts/shells/run-lab.sh --ask-pass lab10
```

Add the section suffix to run only one sub-lab:

```bash
./scripts/shells/run-lab.sh --ask-pass lab05_D.1
./scripts/shells/run-lab.sh --ask-pass lab07_D
```

`lab07_D` automatically uses the student's backup database service. Use two
terminals for the concurrent-session exercises:

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
