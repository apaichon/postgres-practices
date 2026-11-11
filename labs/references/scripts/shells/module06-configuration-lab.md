# Module 6: measure, understand the original, and restore

Run as your own student SSH account. The scripts use your private `~/.env`,
`student_xx`, and your own `claimsure_xx` on direct PostgreSQL port **5432**.
PgBouncer is on **6432**; these session experiments bypass it. This machine does
not have the primary/replica ports 15432/15433 used by the older slide examples.

```bash
cd "$HOME/scripts"
./run-lab06.sh doctor
./run-lab06.sh baseline
./run-lab06.sh --dry-run all
./run-lab06.sh all
```

`all` runs A–G and resets afterward. Individual labs are repeatable:

```bash
./run-lab06.sh A
./run-lab06.sh B --repeat 3
./run-lab06.sh C
./run-lab06.sh D
./run-lab06.sh E --wait 75
./run-lab06.sh F
./run-lab06.sh G
./run-lab06.sh reset
```

Each lab also has its own shell entry point with the same options:

```bash
./module06-A.sh
./module06-B.sh --repeat 3
./module06-C.sh
./module06-D.sh
./module06-E.sh --wait 75
./module06-F.sh
./module06-G.sh
./module06-reset.sh
```

A/B/C/E use only your shared database and disposable `lab_m6_shell` objects.
D/F create your own native PostgreSQL 18 instance under `~/m6`, with a private
Unix socket, port `5600+xx`, database `m6_xx` and local user `labadmin`.
That server has no TCP listener. Students do not need sudo or Docker access.
The instructor-provided PostgreSQL 18 runtime must already be installed.
`--database backup` chooses your own backup database for the shared exercises.

Every run saves a transcript, original/restored settings CSVs, and measurements
under `~/labs/module06/RUN_ID`. The private server log is `~/m6/server.log`.
The scripts do not change shared cluster settings, restart the Docker service,
grant privileges, or modify `insurance` tables. Existing `lab_m6` / `lab_m6c`
fixtures from other course exercises are separate.

## Three meanings of “original”

| Field | Meaning | Correct use |
| --- | --- | --- |
| `boot_val` | PostgreSQL's built-in startup value when no override exists | Understand the PostgreSQL baseline; this is not necessarily the initdb configuration |
| `setting`, `current_setting(name)` | Value effective in this connection now | Capture before changing anything; `current_setting` formats units |
| `reset_val` | Value `RESET parameter` would restore in this session | Restore session defaults, including applicable role/database defaults |
| `source` | Where the current value came from | Distinguish command line, file, role/database and session |
| `sourcefile`, `sourceline` | File source when visible to your role | NULL can mean a non-file source or insufficient visibility |
| `context`, `pending_restart` | Allowed activation class and restart status | Determine whether session, reload or restart is needed |

The numeric `setting`, `boot_val`, and `reset_val` use the `unit` column.
For example, 8192 with unit kB is 8MB; 1048576 with unit 8kB is 8GB.
`ROLLBACK` restores the preceding value for a transaction-local test. `RESET`
does not mean “return to the PostgreSQL built-in default”.

Manual query in DBeaver/pgAdmin or `psql "service=claimsure"`:

```sql
SELECT name, current_setting(name) AS effective,
       setting, unit, boot_val, reset_val, context, source,
       sourcefile, sourceline, pending_restart
FROM pg_settings
WHERE name IN ('work_mem','shared_buffers','max_connections',
               'maintenance_work_mem','effective_cache_size',
               'max_wal_size','checkpoint_timeout','log_min_duration_statement')
ORDER BY name;
```

## Actual shared machine baseline

Observed on 2026-11-08; always run `baseline` for the current values.

| Setting | PostgreSQL boot baseline | This shared Docker server | Origin |
| --- | --- | --- | --- |
| `shared_buffers` | 128MB | 8GB | Compose `postgres -c` |
| `work_mem` | 4MB | 8MB before role/session overrides | Compose `postgres -c` |
| `maintenance_work_mem` | 64MB | 256MB | Compose `postgres -c` |
| `effective_cache_size` | 4GB | 28GB | Compose `postgres -c` |
| `max_connections` | 100 | 200 | Compose `postgres -c` |
| `max_wal_size` | 1GB | 8GB | Compose `postgres -c` |
| `checkpoint_timeout` | 5min | 15min | Compose `postgres -c` |
| `autovacuum_vacuum_scale_factor` | 0.2 | 0.05 | Compose `postgres -c` |
| `log_min_duration_statement` | -1, disabled | 500ms | Compose `postgres -c` |
| `log_lock_waits` | off | on | Compose `postgres -c` |

A student's login can have a narrower role/database override. Its original is
what the script captures from that student's actual connection.

## If you do not run the shell script: where to set it

| Scope | Manual command or file | Takes effect | Restore |
| --- | --- | --- | --- |
| One transaction | `BEGIN; SET LOCAL work_mem='32MB'; ...; ROLLBACK;` | Next statements in this transaction | `ROLLBACK`/transaction end |
| One session | `SET work_mem='32MB';` | Current session | Restore saved value, `RESET work_mem`, or disconnect |
| Your role in your database | `ALTER ROLE student_xx IN DATABASE claimsure_xx SET work_mem='32MB';` | New login connection | Restore saved prior entry, or RESET that entry if originally absent |
| Your database | `ALTER DATABASE claimsure_xx SET work_mem='32MB';` | New login connections to that DB | Restore saved prior database entry |
| One owned table | `ALTER TABLE lab_m6_shell.queue SET (...)` | Table-specific behavior | Restore saved reloptions, not an assumed default |
| Cluster, file managed | Actual `config_file` and included files; `ALTER SYSTEM` writes `postgresql.auto.conf` | Reload or restart, according to `context` | Restore exact prior file/entry and activate it |
| This Docker cluster | `/opt/setup-postgres-labs/compose.yaml`, service `postgres`, `command: postgres -c ...` | Instructor recreates the service to change startup arguments | Restore exact prior Compose values and recreate again |

Command-line `-c` values override the configuration files. Writing a competing
value with `ALTER SYSTEM` will not override such a command-line setting.
Do not edit the versioned `config/postgres-lab.conf` and assume it controls this
machine: it is a reference in the other course stack, not this live origin.

Instructor inspection SQL (some paths are hidden from ordinary students):

```sql
SHOW config_file;
SHOW hba_file;
SHOW data_directory;
SELECT sourcefile,sourceline,name,setting,applied,error FROM pg_file_settings;
```

Verified live paths: PostgreSQL config `/var/lib/postgresql/18/docker/postgresql.conf`,
data `/var/lib/postgresql/18/docker`, and HBA `/etc/postgresql/pg_hba.conf` inside
`claimsure-postgres`. HBA is mounted from `/opt/setup-postgres-labs/config/pg_hba.conf`.
Cluster changes/reloads are instructor work. A Compose recreation disconnects
students; none is performed by these labs. `context='postmaster'` requires a
restart; `sighup` requires reload; user/superuser settings may allow scoped tests.
`SET LOCAL` must be inside `BEGIN`/`COMMIT` or `ROLLBACK`.

## Manual preparation without the shell runner

All SQL helpers are readable and can be run with `psql`. This creates only the
Module 6 shell fixture schema in your own database:

```bash
cd "$HOME/scripts"
psql "service=claimsure" -X -v ON_ERROR_STOP=1 -v rows=100000 -f module06-setup.sql
psql "service=claimsure" -X -v ON_ERROR_STOP=1 -f module06-baseline.sql
```

For repository copies, use `/opt/postgres-admin-labs/scripts/shells` instead.
Existing student service profiles provide credentials. Do not put passwords in
commands or course files. Avoid GUI result limits for benchmark statements;
`EXPLAIN ANALYZE` executes the SQL on the server and reports its plan.

## Lab 6A: inspect, test one scope, restore

Before: record built-in, effective, reset, source, and current role/database entries.
After: a transaction-scoped `work_mem=32MB` and an own-role/default demonstration.
Reset: `ROLLBACK` restores both; the script checks the session value.
Role defaults apply to a new login, not `SET ROLE` in an existing session.

Manual SQL:

```sql
SHOW work_mem;
BEGIN;
SET LOCAL work_mem='32MB';
SHOW work_mem;
ROLLBACK;
SHOW work_mem;
```

The runnable equivalent is `module06-A.sql`; it also demonstrates role catalog
changes only for the current user/database, and rolls them back.

## Lab 6B: report memory before and after

The same 100,000-row fixture and sort run three times at the actual original
memory, then at 64kB, 4MB, and 32MB. Compare sort type, temp written blocks,
sort space and median execution time. Keep parallelism fixed at zero for this
comparison. Warm caches and shared host load can change latency; an increase
in memory does not guarantee faster execution. No host cache is flushed.

Manual complete measurement without the shell:

```bash
psql "service=claimsure" -X -v ON_ERROR_STOP=1 \
  -v run_id="manual-B-$(date -u +%Y%m%dT%H%M%SZ)" -v repeat=3 -f module06-B.sql
```

Each SQL helper call uses transaction-local memory and restores it when the
statement transaction ends. For a simple manual one-off test:

```sql
BEGIN;
SET LOCAL work_mem='32MB';
SET LOCAL max_parallel_workers_per_gather=0;
EXPLAIN (ANALYZE,BUFFERS,SETTINGS)
SELECT claim_no,branch_code,status,estimated_amount,payload
FROM lab_m6_shell.report_workload
WHERE status IN ('NEW','UNDER_REVIEW','APPROVED')
ORDER BY branch_code,status,estimated_amount DESC,claim_no;
ROLLBACK;
```

For manual index-building experiments, use a disposable lab table with a
session/transaction `maintenance_work_mem`; record before/after build times and
restore the saved value. The script does not create indexes on `insurance.claim`.

## Lab 6C: timeout measurements

The same 400ms sleep is measured under the original `statement_timeout` and
then 200ms. The same held lab row is tested under the original `lock_timeout`
and then 200ms. Expect SQLSTATE **57014** for statement cancellation and **55P03**
for lock timeout. The script verifies these expected errors and records elapsed
milliseconds; an expected cancellation is part of the lesson. The row update
rolls back. It also displays a 2-minute idle-transaction timeout and rolls it back;
it does not wait two minutes or claim to have measured an idle disconnect.

Manual statement test (send these as separate statements):

```sql
BEGIN;
SET LOCAL statement_timeout='200ms';
SELECT pg_sleep(.4);
ROLLBACK;
SHOW statement_timeout;
```

Manual lock test: in session 1, hold your lab row:

```sql
BEGIN;
SELECT * FROM lab_m6_shell.capacity_probe WHERE id=1 FOR UPDATE;
SELECT pg_sleep(10);
COMMIT;
```

While session 1 holds it, in session 2:

```sql
BEGIN;
SET LOCAL lock_timeout='200ms';
UPDATE lab_m6_shell.capacity_probe SET amount=amount+1 WHERE id=1;
ROLLBACK;
SHOW lock_timeout;
```

C also saves own-session active/idle counts and the actual cluster/role limits
before and after the tests. These bounded tests do not benchmark total
connection capacity, leak pools or
change `max_connections`. The real connection/role limits remain in force.

## Lab 6D: WAL and checkpoints on your private server

The helper creates an isolated native server with `max_wal_size=64MB`,
`min_wal_size=32MB`, and `checkpoint_timeout=30min`. These are teaching fixture
values, distinct from both PostgreSQL boot defaults and shared Docker values.
It writes the same 120,000 logged rows in committed batches at 64MB and 256MB,
records WAL bytes, execution time, requested/completed checkpoint deltas and
checkpoint write time, then restores the exact pre-test `postgresql.auto.conf`.

Both samples begin with a deliberate private CHECKPOINT **before** the measured
interval. No shared checkpoint or statistics reset is issued. Counter samples
are checked for a matching `stats_reset`. A short run can finish while a
checkpoint is still writing; do not infer recovery objectives from this test.
`--wal-rows` controls the workload. Timing and checkpoint improvement are not
asserted as universal outcomes.

If doing this manually, use your own isolated administrator connection. Record
`SHOW max_wal_size`, `pg_settings.source`, and the existing auto-config entry/file
first. Use `module06-D.sql` for the repeatable workload, supplying `phase`,
`run_id`, and `wal_rows` as psql variables. The configuration commands are:

```sql
ALTER SYSTEM SET max_wal_size='256MB';
SELECT pg_reload_conf();
SHOW max_wal_size;
```

`ALTER SYSTEM` runs outside a transaction. If no auto-config entry existed
before the test, reset that entry and reload. If one did exist, restore the
saved value/file. Do not replace an existing original with an assumed 64MB.
On the live classroom server this parameter originates in Compose `-c`, so the
same ALTER SYSTEM example is not an effective live-server override.

## Lab 6E: autovacuum before and after

Preparation reseeds and manually vacuums the disposable fixture before the
comparison. Insert-triggered vacuum is disabled on this lab table in BOTH
samples, so bulk-insert cleanup does not obscure the update-threshold experiment.
Its exact prior option is also restored.
Before: save all original table options, update 5,000 lab rows, capture dead
tuples, autovacuum count and relation bytes. After: set a table-specific teaching
trigger of about 3,000 dead tuples (base 500 plus scale × estimated rows), then
observe up to 75 seconds. The script records whether an automatic vacuum really
completed. If it did not, it says so; it does not substitute a manual VACUUM and
call that an autovacuum improvement. Extend `--wait` or inspect old transactions,
workers, `autovacuum`, and `autovacuum_naptime` before drawing a conclusion.

Manual equivalent after preparation:

```bash
psql "service=claimsure" -X -v ON_ERROR_STOP=1 -v rows=100000 -f module06-E.sql
psql "service=claimsure" -X -v ON_ERROR_STOP=1 -v rows=100000 -f module06-E-candidate.sql
```

Observe in fresh transactions/connections:

```sql
SELECT n_live_tup,n_dead_tup,autovacuum_count,last_autovacuum
FROM pg_stat_user_tables WHERE relid='lab_m6_shell.queue'::regclass;
SELECT reloptions FROM pg_class WHERE oid='lab_m6_shell.queue'::regclass;
```

Restore the exact saved options, including pre-existing overrides:

```sql
SELECT lab_m6_shell.restore_queue_options();
```

The table-specific threshold is not a cluster parameter change. Unrelated
options such as fillfactor are preserved. Dead-tuple counts are estimates;
read several observations, not one stale transaction snapshot.

## Lab 6F: diagnostic logs before and after

The private server executes the same 600ms sleep, spilling sort and held row
update under original logging and under transaction-local 500ms duration,
`log_temp_files=0`, `log_lock_waits=on`, `deadlock_timeout=100ms`.
The helper filters logs by the tested application's name and writes both raw
server-log excerpts and counts of slow statements, temp files and lock waits.
After ROLLBACK it captures restored logging values. These observations are from
the private server, not the live Docker server's shared logging pipeline.

Manual, on an isolated administrator connection:

```sql
BEGIN;
SET LOCAL log_min_duration_statement='500ms';
SET LOCAL log_temp_files=0;
SET LOCAL log_lock_waits=on;
SET LOCAL deadlock_timeout='100ms';
SELECT pg_sleep(.6);
ROLLBACK;
```

Observe `~/m6/server.log` for the scripted private instance. On the shared Docker
server, logs go to stderr (`logging_collector=off`); the instructor reads
`docker logs claimsure-postgres`. Ordinary students may not have SET privileges
for every logging parameter, so the shell test uses their private admin role.
A reload does not create log evidence by itself; execute the relevant workload.

## Lab 6G and reset

G prints measured shared/private summaries and saves a keep/revert worksheet.
Explain the workload, baseline origin, change, activation, measurements,
guardrails and decision. Evidence of improvement is required; the script does
not automatically promote any setting to a role, database or cluster default.

```bash
./run-lab06.sh G
./run-lab06.sh reset
```

Reset restores a pending saved queue-options record, restores a pending private
auto-configuration file and stops the private server. Normal A/B/C/F session
changes and A role-default tests have already rolled back/disconnected. Reports
and disposable fixture rows remain for review; reset is not a data cleanup.
`all` includes reset at the end. Normal errors and interrupts also attempt the
restoration; after a hard kill or unavailable server, reconnect and run reset.
The queue restore record and original private file persist until restored.

## Sources

- [pg_settings fields](https://www.postgresql.org/docs/18/view-pg-settings.html)
- [Configuration sources and precedence](https://www.postgresql.org/docs/18/config-setting.html)
- [Role defaults](https://www.postgresql.org/docs/18/sql-alterrole.html)
- [WAL and checkpoint settings](https://www.postgresql.org/docs/18/runtime-config-wal.html)
- [Autovacuum settings](https://www.postgresql.org/docs/18/runtime-config-vacuum.html)
- [Statistics and snapshot behavior](https://www.postgresql.org/docs/18/monitoring-stats.html)
- [Logging](https://www.postgresql.org/docs/18/runtime-config-logging.html)
