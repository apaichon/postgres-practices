# postgres-practices

[Workshop CLI Cheatsheet ภาษาไทย — SSH และ psql](labs/references/cheat-sheets/workshop-command-line-th.md)

Start the slides from the project root with Node.js **22.12.0 or newer**:

```bash
make slides
```

Before module 1, open the student SSH and lab prerequisite overview:

```bash
make overview
# or: make slides MODULE=0
```

The overview covers each student's SSH account, PostgreSQL credentials, terminal
commands, manual labs, the optional runner, and concurrent sessions. Replace the
server, SSH port, student number, and server-side repository path with the values
provided by the instructor.

Dependencies are installed automatically with `npm ci` when needed. Module 1
starts at http://localhost:3031. Stop the server with Ctrl+C.

```bash
make slides MODULE=2 PORT=3032
make slides MODULE=5 PORT=3035
make slides MODULE=4:clone PORT=3044
make slides MODULE=4:th PORT=3046
make slides7-docker
make slides MODULE=8 PORT=3048
make slides ARGS=--open
```

Module 5 defaults to the source Thai architecture deck; its [lab guide](labs/module-05-architecture.md) uses a dedicated database.

Use `MODULE=0` for the overview and `MODULE=1` through `MODULE=10` for chapters. Module 8 uses the source English deck by default;
`MODULE=8:th` selects its Thai version (`8:en` remains an English alias). `make` and `make start` also start the slides.
Run `make help` for available options, or see [the slides guide](slides/README.md).

Docker Compose environments for **Lab 8 (PostgreSQL replication / failover)**
and **Lab 10 (Supabase Data API / Authentication)** are ready in `labs/`.
See [Docker lab setup and commands](labs/DOCKER-LABS.md).
