# postgres-practices

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
make slides MODULE=4:clone PORT=3044
make slides MODULE=4:th PORT=3046
make slides MODULE=8:en PORT=3048
make slides ARGS=--open
```

Use `MODULE=0` for the overview and `MODULE=1` through `MODULE=10` for chapters. Module 8 defaults to Thai;
`MODULE=8:en` selects English. `make` and `make start` also start the slides.
Run `make help` for available options, or see [the slides guide](slides/README.md).

Docker Compose environments for **Lab 8 (PostgreSQL replication / failover)**
and **Lab 10 (Supabase Data API / Authentication)** are ready in `labs/`.
See [Docker lab setup and commands](labs/DOCKER-LABS.md).
