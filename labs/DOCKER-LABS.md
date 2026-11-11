# Docker Compose — Labs 8 and 10

Run these commands from the repository root with Docker Engine/Desktop,
Docker Compose v2 and Python 3.10+. These environments have their own databases
and named volumes. The continuous SQL runner (`run-labs.sh`) uses a separate
classroom database and does not start either Docker stack.

| Lab | Compose | Environment | Host endpoints |
| --- | --- | --- | --- |
| 8 — 8A–8E replication / logical / pooler | [module08-replication/compose.yaml](module08-replication/compose.yaml) | PostgreSQL 18: `primary`, `replica`, optional `replica2` / `subscriber`, PgBouncer | `127.0.0.1:55811`–`55814`; pooler `55820` |
| 10 — Supabase Data API + Authentication | [supabase/compose.yaml](supabase/compose.yaml) | PostgreSQL 17 + Auth + Data API + RLS; other services are optional exercises | Studio/API `http://127.0.0.1:18000`; SQL pooler `15480` / `16543` |

## Lab 8 — source slide workshop 8A–8E

Run from the repository root:

```bash
make lab8-init
make lab8-config
make up
make sql-m8
make lab8-verify
make node-add
make node-down NODE=replica2
make lab8-wal
make node-up NODE=replica2
make logical-up
make logical-verify
make pool-verify
```

`up` starts **primary + replica + PgBouncer**. Empty physical standby volumes
clone automatically with `pg_basebackup`; resume keeps existing data. `node-add`
starts optional `replica2` (`ha-lab` profile). `logical-up` starts a separate
logical `subscriber` (`logical-lab` profile) for the two published tables.

The shared launcher remains available, for example
`bash labs/docker-labs.sh 8 up` and `bash labs/docker-labs.sh 8 psql primary`.
`verify` checks physical replay/read-only behavior, `logical-verify` checks
row changes on the subscriber, and `pool-verify` checks transaction pooling
with a real app login and tenant RLS.

Use the [Thai Lab 8 workbook](module-08-replication.md) for commands, SQL,
expected results and the closing failover runbook. Slide command:
`make slides MODULE=8 PORT=3048` (English source) or `MODULE=8:th` (Thai).

## Lab 10 — Supabase, Auth and RLS

```bash
bash labs/docker-labs.sh 10 init
# Before the first up, check labs/supabase/.env for available host ports.
bash labs/docker-labs.sh 10 config
bash labs/docker-labs.sh 10 pull
bash labs/docker-labs.sh 10 up
bash labs/docker-labs.sh 10 seed
bash labs/docker-labs.sh 10 api-demo
bash labs/docker-labs.sh 10 verify
```

Open **http://127.0.0.1:18000**. Dashboard Basic Auth uses
`DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` in `labs/supabase/.env`.
Application demo users use `DEMO_PASSWORD`; SQL clients use
`postgres.claimsure` and `POSTGRES_PASSWORD` via the pooler.

`seed` prepares two synthetic Auth users and four claims with RLS. `api-demo`
shows real HTTP statuses and JSON: `anon` sees no rows, the two `authenticated`
users each see their own two rows, and backend `service_role` sees all four.
Both users share the same database role; their JWT identities select different
rows through RLS. `verify` checks 15 Auth / Data API / RLS cases, including
allowed and rejected writes. This demonstrates CRUD APIs and Login without
writing application routes or an authentication backend.

Follow the [API-first tutorial with curl](../docs/tutorials/supabase-self-hosted/API-LAB.md)
or [HTML lesson](../docs/tutorials/supabase-self-hosted/index.html).
For numbered hands-on exercises, expected results and a submission checklist,
use the [Supabase Markdown workbook — SB0–SB10](module-10-supabase.md).
Storage/Functions are supplementary: use `seed --extended` and `verify --extended`
only when choosing those exercises. Keep service-role keys in backend tools.

The [continuous Module 10 SQL lab](module-10-modern-features.md) covers JSONB,
search, partitioning and simulated JWT subjects on the classroom ClaimSure
schema. This Supabase environment supplies the separate real HTTP/Auth/RLS
exercise. Its demo table is `public.claimsure_claims`; it does not import the
continuous lab's `claimsure.claim` table automatically.

## Stop and resume

```bash
bash labs/docker-labs.sh 8 status
bash labs/docker-labs.sh 10 status
bash labs/docker-labs.sh 8 stop
bash labs/docker-labs.sh 10 stop
# Resume Lab 8 core / Supabase with up; add Lab 8 optional nodes with node-add / logical-up.
# Remove containers and networks while keeping named volumes:
bash labs/docker-labs.sh 8 down
bash labs/docker-labs.sh 10 down
```

Keep each `.env` together with its volumes; generating new secrets against
existing data does not rotate database credentials. Neither launcher passes
`--volumes` to `down`.

## Existing stacks and multiple students

The Lab 8 template uses `postgres-practices-m8`; add a student suffix when running multiple stacks. Lab 10 uses `postgres-practices-m10`. Set a unique `COMPOSE_PROJECT_NAME` and unused host
ports in each `.env` before first startup. Ports are bound to loopback.
If another Supabase already uses port 18000, change all three together:

```dotenv
API_GW_HTTP_PORT=18010
SUPABASE_PUBLIC_URL=http://127.0.0.1:18010
API_EXTERNAL_URL=http://127.0.0.1:18010/auth/v1
DB_SESSION_PORT=15490
DB_TRANSACTION_PORT=16553
```

Keep the internal `POSTGRES_PORT=5432`. For a second Supabase instance, use a
separate directory copy so Functions/Snippets bind mounts are independent too.
Lab 8 implements replica outage/catch-up, logical replication and pooling;
its closing failover runbook explains primary cutover. Automatic primary
election, public HTTPS and production HA are outside these workshop stacks.

References: [PostgreSQL base backup](https://www.postgresql.org/docs/18/app-pgbasebackup.html),
[PostgreSQL failover](https://www.postgresql.org/docs/18/warm-standby-failover.html),
[Supabase Docker self-hosting](https://supabase.com/docs/guides/self-hosting/docker).
