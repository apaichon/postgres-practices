# Module 9: PostgreSQL monitoring in Grafana

The lesson uses this machine's existing PostgreSQL 18, postgres_exporter
**v0.20.1**, Prometheus and Grafana **11.5.2**. Each student uses their own
`claimsure_xx` database on **5432** and their assigned Grafana login. SQL samples
use only the marked `lab_m9_shell` schema, separate from business/other lab data.

## 1. Instructor: initialize the monitoring pipeline once

Run as the instructor account with Docker access and the existing private stack
`.env`. The scripts contain no passwords. Do not run the full classroom bootstrap
just to repair monitoring: that script also manages student account credentials.

```bash
cd /opt/setup-postgres-labs
./scripts/module09-stack.sh init-all --dry-run
./scripts/module09-stack.sh init-all
./scripts/module09-stack.sh check
```

Repository copies are also available in `/opt/postgres-admin-labs/scripts/shells`;
`M9_STACK_ROOT` selects another existing stack root if needed.

This setup creates/repairs the configured read-only `claim_monitor` login,
grants `pg_monitor` and CONNECT/statistics access to all 20 main databases,
verifies/creates the already-preloaded `pg_stat_statements` extension in them,
adds the Module 9 collector config, and provisions the dashboard.
It starts existing Grafana/Prometheus services if they are stopped, and
recreates **only postgres-exporter** to load the custom collectors. It does
not restart PostgreSQL, wipe Prometheus/Grafana volumes, recreate student
accounts, change student passwords, or run the earlier lab reset scripts.
Missing preload is reported for a separately planned instructor change.

Actual files:

| File | Purpose |
| --- | --- |
| `/opt/setup-postgres-labs/config/prometheus.yml` | Existing `postgres` job, 20 database targets, 30s scrapes |
| `config/module09-exporter-queries.yaml` | Student-tagged activity, capacity, table estimates, SQL query-ID metrics |
| `config/module09-monitoring.override.yaml` | Adds the collector flag/mount to the existing exporter only |
| `config/grafana/dashboards/claimsure-module09.json` | File-provisioned dashboard with stable UID `claimsure-module09` |
| `module09-grafana-import.json` | Portable UI import, null UID so a new copy can be created |

The custom-query flag is supported by the pinned exporter version but deprecated
upstream; test/migrate these collectors when upgrading it. Default collectors
remain enabled. No customer values or SQL text are added as Prometheus labels.

## 2. Student: initialize all your lab fixtures

Use your own SSH account, without sudo/Docker:

```bash
cd "$HOME/scripts"
./module09-init-all.sh --dry-run
./module09-init-all.sh
./run-lab09.sh doctor
```

`init-all` stops any of your earlier tagged Module 9 jobs, creates/seeds the
Module 9 workload/queue/lock tables, and saves an initial SQL snapshot. It is
repeatable. It does not initialize or repair the shared monitoring services;
the instructor performs step 1 first. Use `--skip-pipeline` only for an explicit
SQL-only exercise/test without Prometheus.

All reports live under `~/labs/module09/reports/RUN_ID`; background-worker logs
and job state live under `~/labs/module09/jobs`. Ordinary foreground commands
serialize their control changes. Workload runs are bounded; no cron job or
system service is installed.

## 3. Open Grafana and the provisioned dashboard

1. On your laptop, open `http://<SERVER_IP>:3000`.
2. Log in with **your assigned Grafana credentials**. The old slide's
   `admin / Grafana18` is not this machine's student login.
3. Open **Dashboards → ClaimSure → Module 9 - Student PostgreSQL Monitoring**.
4. Select datasource **Prometheus** and **Your student database = claimsure_xx**.
5. Set the time range to **Last 15 minutes** and refresh to **10 seconds**.
6. Check: exporter HTTP UP = **1**, PostgreSQL healthy = **1**, scrape error = **0**.

Direct URL: `http://<SERVER_IP>:3000/d/claimsure-module09`.
The database dropdown chooses the displayed database in this shared teaching
dashboard; it is not a Grafana authorization boundary.

Only a Prometheus datasource is required here. There is no second `ClaimSure`
PostgreSQL datasource in the current provisioned stack. No standby,
Alertmanager, node_exporter or application p99 exporter is deployed, so the lab
does not claim to measure those signals. The incident scenarios are conceptual.

## 4. Import your own JSON dashboard copy

Your assigned Grafana accounts have Editor access. If an account is Viewer,
the instructor imports/provisions the dashboard; no database privilege change
is needed. To transfer the JSON to your laptop, run on the laptop:

```bash
scp studentxx@SERVER_IP:scripts/module09-grafana-import.json .
```

Use your own `studentxx` SSH login. Alternatively use the copy at
`/opt/postgres-admin-labs/scripts/shells/module09-grafana-import.json`.

1. Grafana: **Dashboards → New → Import**.
2. Choose **Upload dashboard JSON file** and select `module09-grafana-import.json`.
3. Give your copy a unique name, e.g. `Module 9 - Student xx`.
4. Choose a folder you can edit. Leave UID new/empty so you do not overwrite the
   shared file-provisioned dashboard.
5. Click **Import**.
6. Select the **Prometheus datasource** variable and your **claimsure_xx**.
7. Check the same three health panels. Open a panel menu → **Inspect → Query**
   if it reports an error.

The import JSON contains datasource/database variables, no passwords. It uses
custom metrics supplied by step 1; importing JSON alone does not install a
collector or start a workload.

## 5. Lab 9A: generate and observe normalized SQL

Capture the baseline, start two bounded clients and inspect activity:

```bash
./run-lab09.sh snapshot
./module09-workload.sh --seconds 120 --workers 2
./module09-observe.sh
./run-lab09.sh status
```

Wait **60–90 seconds**: a 30s scrape interval requires at least two fresh
samples for `rate()`. A Grafana refresh every 10s does not change collection
frequency. Expected: tagged sessions rise, SQL calls/s and transaction activity
appear, and query IDs appear in the top SQL panel. A small workload may not
produce disk spills; zero temp bytes is a valid result.

`observe` shows each query ID with your own normalized SQL and timing, filtered
by database and role. Match that query ID to Grafana. The execution-time-rate
panel shows seconds of execution per second, **not mean latency or p99**.
No `ALTER SYSTEM`, database restart, `pg_stat_statements_reset`, or statistics
reset is needed. Preload/extension setup is instructor work and already verified.

The workload reads a 20,000-row disposable table and updates small queue batches
at a bounded pace. Defaults are 2 clients, 120 seconds. Allowed ranges: 1–3
clients, 5–300 seconds. Do not raise a role connection limit to run this lab;
stop an earlier drill or reduce `--workers` instead.

## 6. Lab 9B: blocking in SQL and Grafana

Keep the workload running if desired, then:

```bash
./module09-blocking.sh --seconds 120
./module09-observe.sh
```

The script starts a holder on lab row 1, then a waiter on the same row. A third,
foreground observer captures **blocked PID → blocker PID** before cleanup.
The holder keeps a bounded transaction open. Expected Grafana evidence after
scrapes: blocked clients **at least 1**, oldest wait and transaction age increase, and
an idle-in-transaction session is visible between holder heartbeats. Workload
clients can briefly contend with one another too; use the SQL PID mapping to
distinguish their wait from the intentionally held lock.

Save the SQL snapshot/worker logs and record your observation time. Resolve
using the lab-specific stop command:

```bash
./run-lab09.sh blocking-stop
./module09-observe.sh
```

This stops only the tagged holder/waiter, so their transactions roll back. It
leaves the workload clients running. Blocking falls to zero after the next
scrape; the graph's older samples remain. The production lesson remains:
identify the owner/blocker and preserve evidence before cancellation. Lab cleanup
is an explicit runbook for known disposable sessions, not permission to kill
arbitrary production PIDs.

## 7. Lab 9C: a real deadlock and SQLSTATE 40P01

The deadlock command stops any lab blocker/waiter first, then uses two sessions
that lock the two disposable rows in opposite order:

```bash
./module09-deadlock.sh
./module09-observe.sh
```

Expected: exactly one **40P01** victim and one **00000** counterpart. Both
transactions roll back, leaving the two lock-demo rows unchanged. The script
verifies the SQLSTATEs and saves `deadlock.json` with the two job records;
worker `.log` files contain the server error details.

Grafana's **Database deadlocks in last 5 minutes** will rise after a scrape.
Prometheus `increase()` extrapolates and can be fractional. Confirm the exact
event with SQL/worker evidence rather than expecting the graph to equal exactly
1. Existing incidents in the same database also contribute to the lifetime
counter; compare before/after. Application recovery is a bounded retry of the
whole transaction with consistent lock ordering, not a DBA retry loop.

## 8. Lab 9D: verify the whole pipeline

In Grafana Explore choose Prometheus:

```promql
up{job="postgres",instance="postgres:5432/claimsure_xx"}
pg_up{job="postgres",instance="postgres:5432/claimsure_xx"}
pg_exporter_last_scrape_error{job="postgres",instance="postgres:5432/claimsure_xx"}
claimsure_m9_activity_blocked{job="postgres",datname="claimsure_xx"}
```

Replace `01` with your own number. The first three results should be **1, 1, 0**.
`up=1` proves the HTTP scrape, not database authentication. This machine's
original missing `claim_monitor` role produced `up=1` with `pg_up=0`; instructor
initialization repairs that condition.

Prometheus is bound to the server's localhost **9090**, and the exporter has no
published host port. To open Prometheus from your laptop, use an SSH tunnel:

```bash
ssh -L 9090:127.0.0.1:9090 studentxx@SERVER_IP
```

Then open `http://127.0.0.1:9090/targets`. Target job is **postgres**, with an
instance per `postgres:5432/claimsure_xx`, not `job="postgres-exporter"`.
The SQL lab does not require the laptop tunnel; Grafana reaches Prometheus
through the Docker network. Do not use the old 13000/19090/19187 slide ports.

## 9. Interpret the 20 panels correctly

| Panel group | Expected evidence / limitation |
| --- | --- |
| HTTP / DB health / scrape error | 1 / 1 / 0; diagnose the first failing layer |
| Tagged sessions, active/idle/blocked | Only your Module 9 application tags |
| Own-role sessions/limit | Real per-role limit; includes other own-role clients |
| Oldest transaction/wait | Gauges that grow during blocking |
| SQL calls/s and top query ID time rate | Need rate samples; not user p99 |
| Database commits and deadlocks | Database-wide; includes other exercises |
| Lab dead tuples | Estimates; autovacuum can reduce them |
| Cache hit fraction | No value when both read/hit rates are zero; not OS cache |
| Temp bytes/s | Zero is normal without a spill |
| Database size/backends | Includes more than the tagged exercise |
| Archive failures | Shared cluster counter; never sum duplicate copies across 20 targets |

A replica-lag or CPU panel would need the missing replica/host collector. Do not
turn “no data” into a healthy zero when a collector/target is actually absent.
Every alert proposal needs an owner, an observation window and a first evidence
query; this bundle provisions a dashboard, not Alertmanager alert routing.

## 10. Stop or reset all your Module 9 work

Stop the clients while retaining fixtures:

```bash
./run-lab09.sh stop
```

Clear all fixtures created by this lesson and stop its clients:

```bash
./module09-reset-all.sh --dry-run
./module09-reset-all.sh
```

Reset targets only your database, role and exact Module 9 application prefix.
It validates its workspace/schema markers, verifies worker PID identity before
signalling, and drops only the known lab tables and their otherwise empty
schema in one transaction. Extra unknown objects/dependencies prevent schema
cleanup and roll that database transaction back; no CASCADE is used.

It preserves insurance data, other students/labs, credentials, dashboard copies,
Prometheus/Grafana history, database statistics and `pg_stat_statements` counters.
Therefore an older deadlock remains visible in the Last 15 minutes graph after
reset. Deleted fixture series become stale after a scrape; health panels remain
healthy. Files/reports remain for assessment. `init-all` prepares the next run.

Instructor-only reset of this lesson across all 20 main databases:

```bash
cd /opt/setup-postgres-labs
./scripts/module09-stack.sh reset-all --dry-run
./scripts/module09-stack.sh reset-all --yes
```

This explicitly named reset stops only tagged Module 9 database clients and
removes only marked fixtures. It retains the monitoring role/configuration,
services and all monitoring history. Each database cleanup is transactional;
a failure stops the loop, so check the reported database before repeating.
Disconnected worker jobs may report the reset as a client disconnect.

## 11. Optional complete bounded drill

```bash
./run-lab09.sh all --seconds 120 --workers 2
```

This initializes fixtures, checks the pipeline, opens a workload and blocking
observation window, then releases the blocker, runs the deadlock, stops clients
and saves final evidence. It retains fixtures for review; run `reset-all` when
finished. The default is 120 seconds. A short SQL-only automated test can use
`--skip-pipeline`; it is not a Grafana scrape-latency test.

## Troubleshooting

- No Import button: check your Grafana role. Use the provisioned dashboard or
  ask the instructor to import; database privileges do not control Grafana roles.
- Empty rate panels: confirm 1/1/0 health, correct datasource/database/time range,
  generate activity, then allow 60–90 seconds for samples.
- Missing custom metrics: instructor must run the Module 9 stack initialization;
  a JSON import alone cannot install collectors.
- Blocking already ended: use a 90–120 second window and capture while it runs.
- Connection limit reached: stop old Module 9 jobs/close surplus own GUI sessions;
  do not change the shared server or other students' sessions.
- Worker errors: inspect the printed job `.log` and `status`. All workloads are
  bounded; `reset-all` provides targeted cleanup.

## References

- [Grafana dashboard import](https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/import-dashboards/)
- [Grafana file provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Pinned postgres_exporter collectors and multi-target configuration](https://github.com/prometheus-community/postgres_exporter/tree/v0.20.1)
- [PostgreSQL pg_stat_statements](https://www.postgresql.org/docs/18/pgstatstatements.html)
- [PostgreSQL server signalling](https://www.postgresql.org/docs/18/functions-admin.html)
