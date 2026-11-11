# Run and prepare modules 1–7 and 9

These scripts join the existing per-module lessons into one student interface
and one instructor interface. Module 8 and Module 10 are excluded.

## Student commands

```bash
cd "$HOME/scripts"
./course-labs.sh list
./course-init-all.sh
./course-verify-all.sh
./course-labs.sh run 1
./course-labs.sh run 2
./course-labs.sh run 3
./course-labs.sh run 4
./course-labs.sh run 5
./course-labs.sh run 6
./course-labs.sh run 7
./course-labs.sh run 9
```

Run the entire course selection in order:

```bash
./course-run-all.sh --dry-run
./course-run-all.sh
```

This runs real exercises against your own `claimsure_xx` on direct port 5432.
Modules 1–3 intentionally change their course insurance objects/data. Module 6
uses measured before/after tests and exact rollback. Module 7 includes logical,
physical, staged snapshot and staged PITR recovery. Module 9 includes a bounded
workload, real blocking and one verified deadlock. D/F configuration tests and
physical recovery use your private native instances; they do not restart the
shared Docker database. Existing per-module scripts remain available.

The `teaching` profile is the default: repeated measurements, up to 75 seconds
observing autovacuum and 120 seconds observing Grafana activity. `quick` runs
bounded workflow smoke checks with smaller fixtures and shorter windows:

```bash
./course-run-all.sh --profile quick
```

Quick mode is not proof of a tuning improvement, completed autovacuum cycle or
a sampled Grafana rate chart. It still exercises real backup/recovery and SQL
behavior. Only an explicit `--skip-monitoring` bypasses the monitoring check;
that is for disposable SQL-only tests, not classroom readiness.

## Run one supported section

```bash
./course-labs.sh run 1.A
./course-labs.sh run 1.B
./course-labs.sh run 2.H
./course-labs.sh run 3.E
./course-labs.sh run 6.B
./course-labs.sh run 7.logical
./course-labs.sh run 7.physical
./course-labs.sh run 7.snapshot
./course-labs.sh run 7.pitr
```

Module 1 sections A–G, Module 2 A–H, Module 3 A–E and Module 6 A–G use their
existing lesson definitions. The classroom Module 3 search uses tenant 2
rather than tenant 1 so the generated UNDER_REVIEW workload actually has
matching rows. Run prerequisites first: 1A/1B before Module 2.
Module 4's integrated least-privilege/RLS/definer/audit proof and Module 5's
architecture/MVCC/WAL proof run as complete modules. For the individual Module 9
steps use the existing `run-lab09.sh` commands in `module09-grafana-lab.md`.

Modules 4/5 have student-specific variants because the original SQL uses shared
global role names, a different claim schema or a superuser requirement. The new
Module 4 creates NOLOGIN roles suffixed with your student number, verifies
schema CREATE denial, RLS tenant filtering/negative INSERT and audit behavior,
then rolls back all role/grant/policy/data changes. The tenant GUC is a trusted
application-context demonstration, not an authentication boundary for arbitrary
SQL clients. Module 5 uses `lab_m5_shell` fixtures and a real two-connection
Repeatable Read experiment, followed by a committed WAL batch and exact batch
cleanup. WAL generation and identity-sequence advances are not undone.

## Preserve an older incompatible insurance model

The older ClaimSure starter model uses policyholders/tenants rather than the
new Module 1 customer/policy/claim contract. Default prepare reports this
mismatch and leaves it untouched. To prepare the updated course while retaining
all old data, use the explicit preservation option:

```bash
./course-init-all.sh --preserve-legacy
```

Before any rename, this saves and validates a full custom-format insurance
archive under `~/backups/course-migrations/RUN_ID/`. In one transaction it
renames the existing owned schema to `insurance_saved_RUN_ID` and creates/seeds
the new course insurance schema. The old tables, rows, ownership, grants and
object identities remain in the saved schema; tracked external dependencies
continue to reference them. Old SQL that literally uses `insurance` now targets
the new course model and must be adapted or the namespace switch restored.

`migration.json`, the archive and an exact `restore-legacy.sql` are recorded in
the course report; `~/labs/course/migrations.jsonl` indexes prior migrations.
The restore SQL renames the newer course schema to a held name before restoring
the old name, preserving both versions. Review it before running against your
own database. Course reset never drops saved/held schemas or migration archives.
Compatible course schemas are not renamed, and existing learner rows are kept.

Instructor one-time preparation for an older cohort:

```bash
./scripts/classroom-labs.sh prepare-all --preserve-legacy
```

## Initialize and verify

`prepare` creates the course-compatible baseline only when absent, inserts
missing seed rows without overwriting existing rows, and adds marked fixtures
for the later modules. Incompatible or foreign-owned objects cause a failure
rather than automatic replacement. Existing Module 9 jobs/fixtures are preserved
if already initialized. Existing flat student scripts and credentials are not
overwritten by the separate versioned `~/scripts/course` bundle.

`verify` checks real main/backup login and ownership, non-superuser/CREATEROLE
requirements, available PostgreSQL 18 tools, compatible insurance seed/schema,
module fixtures, pg_stat_statements and own exporter health. Instructor verify
also checks each student's actual Grafana dashboard access. Readiness is not a
claim that all exercises have just executed; `run-all` provides that execution.

Reports are saved in `~/labs/course/RUN_ID`: transcript, readiness JSON and
per-module execution status/logs. Native helpers also retain their own module
reports. Use the printed report path when reviewing a failure.

## Reset all selected student labs

Preview is the default; applying requires `--yes`:

```bash
./course-reset-all.sh
./course-reset-all.sh --yes
./course-init-all.sh
```

Scope: course `insurance` (shared by Modules 1–3), marked Module 4/5/6 fixtures,
Module 7 practice data in main/backup plus private clusters/standard backup files,
and tagged Module 9 clients/fixtures. Module 6 settings are restored before its
private cluster is removed. Reset stops only this student's marked lab processes.

Before deleting the primary insurance objects, reset saves and validates a
custom-format archive under `~/backups/course-resets/RUN_ID/`, with SHA-256.
Those archives and course/module reports are retained. The separate backup DB's
insurance data is preserved unless requested explicitly:

```bash
./course-reset-all.sh --yes --include-backup
```

Reset uses named course objects and RESTRICT dependency checks. Unknown objects,
foreign ownership or external dependencies cause a failure/rollback rather than
a cascading deletion into Module 8/10 or another schema. It does not reset
passwords, global roles, PostgreSQL/pg_stat_statements counters, Grafana dashboards
or Prometheus history. It does remove course practice data: review the preview.
Resetting modules 1–3 necessarily resets their shared insurance fixture together.
Close other ongoing lab commands before reset. Filesystem/process cleanup and
multiple DBs are separate steps; after an error inspect the report and repeat
the appropriate step, rather than assuming a globally atomic reset.

## Instructor: all 20 students

Run as the instructor with Docker access and existing private credential files.
The script uses actual student SSH logins; it never prints or changes passwords.

```bash
cd /opt/setup-postgres-labs
./scripts/classroom-labs.sh prepare-all --dry-run
./scripts/classroom-labs.sh prepare-all
./scripts/classroom-labs.sh verify-all
```

Prepare installs a consistent bundle in every selected home, checks the existing
monitoring pipeline (repairs it only if necessary) and prepares/validates the
student fixtures. Existing compatible insurance rows remain. Account verification
is not a simultaneous full-class load benchmark.

Choose a student/module or run all modules for everyone:

```bash
./scripts/classroom-labs.sh run --students 1 --module 5
./scripts/classroom-labs.sh run --students 1,2 --module 7.pitr
./scripts/classroom-labs.sh run-all --students all --dry-run
./scripts/classroom-labs.sh run-all --students all --yes
```

Full classroom execution is sequential to limit resource spikes and can take
substantial time. `--profile quick` selects the clearly labelled smoke profile.
Instructor `run-all` requires `--yes` because it performs real exercises/data
changes for everyone. `run` with a selected module is already explicit.

Reset all selected students' modules, then prepare again:

```bash
./scripts/classroom-labs.sh reset-all --dry-run
./scripts/classroom-labs.sh reset-all --yes
./scripts/classroom-labs.sh prepare-all
```

Use `--students 1-5,20` or `--students 1` to narrow any action. Include
`--include-backup` only if backup insurance should also be reset. Reports are
private under `/opt/setup-postgres-labs/reports/classroom/RUN_ID`, including
`summary.json` and each student's SSH log. Failures are reported by student;
read the report before starting a destructive retry. The default SSH target is
this machine's `127.0.0.1:22`, configurable with `--host` and `--port`.


## Repeat the isolated functional tests

```bash
cd /opt/setup-postgres-labs
./scripts/classroom-labs.sh test-all
```

This starts a disposable PostgreSQL 18 container with networking disabled and
read-only source mounts. It runs actual modules 1–5 for all 20 ordinary roles,
checks the complete quick 1–7/9 sequence for SID 01, and verifies archive/reset,
legacy schema preservation/restoration, MVCC, role rollback and dependency guards.
It does not run real students' workloads or simulate a simultaneous 20-user load.
The Module 6/7/9 module-specific integration scripts remain under `scripts/`.
Live `verify-all` complements these tests with actual SSH/DB/monitoring access.

Module 5 WAL LSNs are cluster-wide: concurrent writes can contribute to their
difference. The committed batch count is exact; its LSN byte delta is not an
exclusive per-student WAL measurement on a shared busy server.
