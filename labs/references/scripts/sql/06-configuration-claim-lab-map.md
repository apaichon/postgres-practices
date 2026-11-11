# Module 6 — six groups / SQL and slide map

**New sequence:** 6A Connections → 6B Memory → 6C WAL/checkpoints → 6D Planning/storage → 6E Parallelism → 6F Autovacuum.

Use the dedicated-instance runbook (ส่วนแยกในต้นฉบับ: `labs/module06/README.md`), active slides (ส่วนแยกในต้นฉบับ: `docs/slides/module-06-configuration-claim.md`) and parameter guide (ส่วนแยกในต้นฉบับ: `docs/cheat-sheets/PostgreSQL_Parameter_Settings_Guide.md`).

One letter = one SQL experiment plus a file-change/activation/measurement/rollback exercise. A/B/E require restart; C/D/F require reload. The SQL file alone does not edit or activate configuration files. Every SQL uses postgres / claimsure_m6 on the dedicated Module 6 instance. Fixtures are generated in lab_m6c; no Module 1 prerequisite.

| Source step | Purpose | Slide(s) | Login / database |
| --- | --- | --- | --- |
| [0.1](06-configuration-claim.sql#L31) | Verify the dedicated instance and create reusable generated data | 15, 17 | postgres / claimsure_m6 |
| [6A.1](06-configuration-claim.sql#L71) | Read connection capacity and file activation | 4, 7, 14, 20, 21, 22 | postgres / claimsure_m6 |
| [6A.2](06-configuration-claim.sql#L85) | Test a claim-intake statement budget and restore it | 4, 13, 14, 20, 21, 22 | postgres / claimsure_m6 |
| [6B.1](06-configuration-claim.sql#L105) | Inspect the cache allocation separately from the workspace | 5, 23, 24, 25 | postgres / claimsure_m6 |
| [6B.2](06-configuration-claim.sql#L114) | Compare three work_mem values with three repeated report sorts | 5, 15, 23, 24, 25 | postgres / claimsure_m6 |
| [6B.3](06-configuration-claim.sql#L200) | Budget report memory and verify restoration | 5, 6, 13, 14, 15, 23, 24, 25 | postgres / claimsure_m6 |
| [6C.1](06-configuration-claim.sql#L215) | Snapshot checkpoints and the WAL insert position | 7, 8, 26, 27, 28 | postgres / claimsure_m6 |
| [6C.2](06-configuration-claim.sql#L232) | Generate 5000 claim events and read counter deltas | 7, 8, 15, 26, 27, 28 | postgres / claimsure_m6 |
| [6D.1](06-configuration-claim.sql#L258) | Prepare the same index before either planner test | 9, 29, 30, 31 | postgres / claimsure_m6 |
| [6D.2](06-configuration-claim.sql#L273) | Test random_page_cost narrowly before adopting a file default | 9, 29, 30, 31 | postgres / claimsure_m6 |
| [6E.1](06-configuration-claim.sql#L291) | Read worker capacity and compare serial versus eligible parallel plans | 10, 32, 33, 34 | postgres / claimsure_m6 |
| [6E.2](06-configuration-claim.sql#L314) | Calculate a report process memory illustration | 32, 33, 34 | postgres / claimsure_m6 |
| [6F.1](06-configuration-claim.sql#L328) | Prepare a 20000-row review queue and baseline counters | 11, 35, 36, 37 | postgres / claimsure_m6 |
| [6F.2](06-configuration-claim.sql#L345) | Apply queue thresholds and generate 2000 obsolete tuple versions | 11, 13, 14, 35, 36, 37 | postgres / claimsure_m6 |
| [6F.3](06-configuration-claim.sql#L369) | Reset only the four lab table overrides | 35, 36, 37, 38 | postgres / claimsure_m6 |

15 blocks including fixture setup and optional 6F.3. `sql F` leaves table overrides for asynchronous observation; run 6F.3 manually afterwards (or pass psql variable `m6_reset_table=true` when intentionally skipping observation). Keep the same connection during 6C for temporary snapshots; reconnect after every restart. See the runbook for exact host/container file paths and rollback.
