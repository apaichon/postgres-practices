# Docker Compose — Labs 8 and 10

Run these commands from the repository root with Docker Engine/Desktop,
Docker Compose v2 and Python 3.10+. These environments have their own databases
and named volumes. The continuous SQL runner (`run-labs.sh`) uses a separate
classroom database and does not start either Docker stack.

| Lab | Compose | Environment | Host endpoints |
| --- | --- | --- | --- |
| 8 — physical streaming replication / manual failover | [module08-replication/compose.yaml](module08-replication/compose.yaml) | PostgreSQL 18: `pg1`, `pg2`, `pg3` | `127.0.0.1:55811`, `55812`, `55813` |
| 10 — Supabase Data API + Authentication | [supabase/compose.yaml](supabase/compose.yaml) | PostgreSQL 17 + Auth + Data API + RLS; other services are optional exercises | Studio/API `http://127.0.0.1:18000`; SQL pooler `15480` / `16543` |

## Lab 8 — initialize, clone and verify

```bash
bash labs/docker-labs.sh 8 init
bash labs/docker-labs.sh 8 config
bash labs/docker-labs.sh 8 pull
bash labs/docker-labs.sh 8 up
bash labs/docker-labs.sh 8 verify
bash labs/docker-labs.sh 8 psql pg1
```

`init` generates private passwords in `labs/module08-replication/.env` without
overwriting an existing file. `up` starts pg1, creates physical slots, clones
empty pg2/pg3 volumes with `pg_basebackup`, then starts both standbys. Repeating
`up` resumes the original topology without cloning existing data.

`verify` finds the writable node, checks the cluster IDs, inserts a unique
probe and waits for replay on both standbys, then checks that standby writes
fail. It removes its probe afterward. Success begins with `PASS: one primary`.

For manual cloning, lag, failover and rejoin, follow the
[Lab 8 Docker walkthrough](module08-replication/README.md). After promotion,
use its explicit node commands; the startup helper refuses a changed topology.

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
# Resume the original topology / Supabase with the corresponding up command.
# Remove containers and networks while keeping named volumes:
bash labs/docker-labs.sh 8 down
bash labs/docker-labs.sh 10 down
```

Keep each `.env` together with its volumes; generating new secrets against
existing data does not rotate database credentials. Neither launcher passes
`--volumes` to `down`.

## Existing stacks and multiple students

The Lab 8 template uses `postgres-practices-m8_xx`: replace `xx` with your assigned number before startup. Lab 10 uses `postgres-practices-m10`. Set a unique `COMPOSE_PROJECT_NAME` and unused host
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
These exercises implement manual failover and local self-hosting; no automatic
primary election, public HTTPS or production HA is configured.

References: [PostgreSQL base backup](https://www.postgresql.org/docs/18/app-pgbasebackup.html),
[PostgreSQL failover](https://www.postgresql.org/docs/18/warm-standby-failover.html),
[Supabase Docker self-hosting](https://supabase.com/docs/guides/self-hosting/docker).
