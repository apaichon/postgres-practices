#!/usr/bin/env python3
"""Run the continuous Markdown labs using native PostgreSQL command-line tools.

SQL is read from the student guides. Explicit recipes handle choices, repeated
experiments, expected errors, and concurrent sessions rather than blindly executing
every fenced block. No third-party Python packages are required.
"""
import argparse
import collections
import concurrent.futures
import contextlib
import datetime
import fcntl
import getpass
import json
import os
from pathlib import Path
import queue
import re
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time
import uuid
from dataclasses import dataclass

DOCS = Path(__file__).resolve().parent.parent
MODULES = (1, 2, 3, 4, 5, 6, 7, 9, 10)
FILES = {n: DOCS / filename for n, filename in {
    1: "module-01-basic-sql.md",
    2: "module-02-advanced-sql.md",
    3: "module-03-performance-tuning.md",
    4: "module-04-security.md",
    5: "module-05-architecture-continuous.md",
    6: "module-06-configuration.md",
    7: "module-07-backup-recovery.md",
    9: "module-09-monitoring.md",
    10: "module-10-modern-features.md",
}.items()}
ERROR_RE = re.compile(r"(?:ERROR|FATAL):\s+([A-Z0-9]{5}):")
STATE_VARS = "LAB PRIMARY SOCKET WAL BACKUPS SOURCE_PORT RECOVERY_PORT MAIN STAGE SHARED PRIVATE RECOVERED CORE_TABLES C_BACKUP C_RECOVERY D_BASE POINT SEGMENT TARGET_TIME D_RECOVERY M6_LAB M6_PORT".split()


class LabError(RuntimeError):
    pass


class Guide:
    def __init__(self, module):
        self.path = FILES[module]
        self.sections = collections.OrderedDict()
        section = "intro"
        self.sections[section] = {"title": "Introduction", "blocks": [], "text": ""}
        lines = self.path.read_text().splitlines()
        i = 0
        while i < len(lines):
            line = lines[i]
            heading = re.match(r"^#{2,3} (.+)$", line)
            if heading:
                title = heading[1]
                section = title.split(" — ")[0]
                self.sections[section] = {"title": title, "blocks": [], "text": ""}
            if line in ("```sql", "```bash"):
                lang, begin = line[3:], i + 1
                i += 1
                while i < len(lines) and lines[i] != "```":
                    i += 1
                if i == len(lines):
                    raise LabError(f"Unclosed fence in {self.path}:{begin}")
                self.sections[section]["blocks"].append((lang, "\n".join(lines[begin:i]) + "\n"))
            else:
                self.sections[section]["text"] += line + "\n"
            i += 1

    def block(self, section, lang="sql", index=0):
        try:
            return [s for kind, s in self.sections[section]["blocks"] if kind == lang][index]
        except (KeyError, IndexError) as exc:
            raise LabError(f"Guide changed: missing {section}/{lang}/{index} in {self.path.name}") from exc


@dataclass
class Step:
    id: str
    title: str
    actions: list
    optional: bool = False
    instructor: bool = False
    requires: tuple = ()


def S(section, index=0, session="A", expected=()):
    return ("sql", section, index, session, expected)


def B(section, index=0):
    return ("bash", section, index)


def build_steps(module, guide):
    result = []
    def add(id, actions, *, title=None, optional=False, instructor=False, requires=()):
        label = title or guide.sections[id]["title"]
        label = label.removeprefix(id + " — ")
        result.append(Step(id, label, actions, optional, instructor, requires))
    if module in (1, 2, 3):
        letters = {1: "ABCDEFG", 2: "ABCDEFGH", 3: "ABCDEF"}[module]
        for letter in letters:
            id = f"{module}{letter}"
            add(id, [S(id)])
        if module == 3:
            add("3Z", [S("ส่งต่อและทำซ้ำ")], title="ตรวจข้อมูลส่งต่อ")
        elif module == 2:
            add("2Z", [S("ทางเลือกคืนค่าเมื่อจบคอร์สแล้ว")], title="ถอด routines/views เมื่อจบคอร์ส", optional=True)
        else:
            add("1Z", [S("คืนค่าและทำซ้ำ"), S("1B")], title="คืนข้อมูลตัวอย่างด้วย INSERT ของ 1B", optional=True)
    elif module == 4:
        add("4.0", [S("4.0", session="admin")], instructor=True, optional=True)
        add("4A", [("security_setup",)])
        add("4B", [S("4B", expected=("42501", "42501"))])
        for letter in "CDE":
            add("4" + letter, [S("4" + letter, expected=("42501",))])
        add("4F", [S("4F")])
        add("4Z", [S("4F", 1, "admin")], title="Instructor: ลบ roles ที่เตรียม", optional=True, instructor=True)
    elif module == 5:
        add("5A", [("m5_snapshot",)])
        add("5B", [S("5B")], requires=("5A",))
        add("5C", [S("5C", session="B"), S("5C", 1), S("5C", 2, "B")], requires=("5B",))
        add("5D", [S("5D"), S("5D", 1, "B"), S("5D", 2), S("5D", 3, "B")], requires=("5A",))
        add("5E", [("m5_restore",)], requires=("5A",))
        add("5F", [S("5F")])
        add("5G", [S("5G")])
    elif module == 6:
        add("6A", [S("6A")])
        add("6B", [("memory",)])
        add("6C", [S("6C", expected=("57014",)), S("6C", 1, "B", ("55P03",)), S("6C", 2)])
        add("6D.1", [B("6D.1")])
        add("6D.2", [S("6D.2", session="P")], requires=("6D.1",))
        add("6D.3", [S("6D.3", session="P")], requires=("6D.2",))
        add("6D.4", [("wal_candidate",)], requires=("6D.3",))
        add("6E", [("autovacuum",)])
        add("6F.1", [("logging", False)], requires=("6D.1",))
        add("6F.2", [("logging", True)], requires=("6F.1",))
        add("6G", [("note", "6G"), ("verify", 100006)])
    elif module == 7:
        previous = None
        for id, data in guide.sections.items():
            if not re.fullmatch(r"7\.[1-6][a-z]", id):
                continue
            actions = [("module7", id)] if data["blocks"] else [("note", id)]
            add(id, actions, optional=id.startswith("7.6"), requires=(previous,) if previous and not id.startswith("7.6") else ())
            if not id.startswith("7.6"):
                previous = id
    elif module == 9:
        add("9A", [S("9A")])
        add("9B", [S("9B", session="C")])
        add("9C", [("workload",)])
        add("9D", [("blocking",)])
        add("9E", [("deadlock",)])
        add("9F", [("statements",)], optional=True)
        add("9G", [B("9G")], optional=True)
        add("9Z", [S("คืนค่า", session="C")], title="ตรวจข้อมูลส่งต่อและจบ sessions")
    elif module == 10:
        add("10A", [("m10_snapshot",)])
        for letter in "BCD":
            add("10" + letter, [S("10" + letter)], requires=("10A",))
        add("10E", [S("10E")], optional=True, requires=("10A",))
        add("10F.0", [S("10F.0", session="admin")], optional=True, instructor=True)
        add("10F.1", [S("10F.1")])
        add("10G", [("supabase",)], optional=True)
        add("10H", [("m10_restore",)], requires=("10A",))
        add("10Z", [S("10H", 1, "admin")], title="Instructor: ลบ API role", optional=True, instructor=True)
    return result


class Session:
    """A real persistent psql process, with bounded waits and explicit completion tokens."""
    def __init__(self, args, env, name, emit):
        self.name, self.emit = name, emit
        self.queue = queue.Queue()
        self.pending = False
        self.process = subprocess.Popen(
            ["psql", "-X", "-w", "-q", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", *args],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1, env=env, start_new_session=True)
        def read():
            for line in self.process.stdout:
                self.queue.put(line.rstrip("\n"))
            self.queue.put(None)
        self.reader = threading.Thread(target=read, daemon=True)
        self.reader.start()
        self.run("\\pset pager off\n\\timing on\nSET TIME ZONE 'Asia/Bangkok';", quiet=True)

    def send(self, sql):
        if self.pending:
            raise LabError(f"Session {self.name} already has a pending statement")
        self.token = "__LAB_DONE_" + uuid.uuid4().hex
        self.pending = True
        try:
            self.process.stdin.write(sql.rstrip() + "\n\\echo " + self.token + "\n")
            self.process.stdin.flush()
        except (BrokenPipeError, OSError) as exc:
            raise LabError(f"Session {self.name} exited") from exc

    def finish(self, expected=(), timeout=180, quiet=False):
        deadline, lines = time.monotonic() + timeout, []
        while True:
            if time.monotonic() >= deadline:
                raise LabError(f"Timed out waiting for {self.name}; inspect the log before resuming")
            try:
                line = self.queue.get(timeout=max(.01, deadline - time.monotonic()))
            except queue.Empty as exc:
                raise LabError(f"Timed out waiting for {self.name}; open transactions will be rolled back") from exc
            if line is None:
                self.pending = False
                raise LabError(f"psql {self.name} exited before completing the step (see log)")
            if line == self.token:
                break
            lines.append(line)
            if not quiet or ERROR_RE.search(line):
                self.emit(f"[{self.name}] {line}")
        self.pending = False
        errors = ERROR_RE.findall("\n".join(lines))
        if collections.Counter(errors) != collections.Counter(expected):
            raise LabError(f"{self.name}: expected SQLSTATEs {list(expected)}, observed {errors}")
        return "\n".join(lines)

    def run(self, sql, expected=(), timeout=180, quiet=False):
        self.send(sql)
        return self.finish(expected, timeout, quiet)

    def close(self):
        if self.process.poll() is None:
            try:
                self.process.stdin.write("ROLLBACK;\n\\q\n")
                self.process.stdin.flush()
                self.process.wait(timeout=3)
            except (BrokenPipeError, OSError, subprocess.TimeoutExpired):
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(self.process.pid, signal.SIGTERM)
                try:
                    self.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(self.process.pid, signal.SIGKILL)
                    self.process.wait()
        self.reader.join(timeout=1)


class Runner:
    def __init__(self, args, module, state_root):
        self.args, self.module = args, module
        self.guide = Guide(module)
        self.steps = build_steps(module, self.guide)
        self.directory = state_root / f"module{module:02d}"
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.variables = self.directory / "variables.bash"
        self.progress = self.directory / "progress.json"
        self.inflight = self.directory / "inflight.json"
        self.completed = set(json.loads(self.progress.read_text())) if self.progress.exists() else set()
        stamp = datetime.datetime.now().strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:6]
        self.logfile = self.directory / f"run-{stamp}.log"
        self.log = self.logfile.open("w")
        self.sessions = {}
        self.security_ready = False
        self.executed = set()
        self.recover = None
        self.env = os.environ.copy()
        self.env.update(STUDENT_NO=args.student, PGUSER=f"student_{args.student}", PGDATABASE=f"claimsure_{args.student}",
                        PGHOST=args.host, PGPORT=str(args.port), PGCONNECT_TIMEOUT="5", PAGER="cat", PSQL_PAGER="cat")
        self.env["PATH"] = args.pg_bin + os.pathsep + self.env.get("PATH", "")
        self.env["PG_BIN"] = args.pg_bin
        self.env["PGAPPNAME"] = f"case-m{module}-runner"
        for name in ("PGOPTIONS", "PGSERVICE", "PGSERVICEFILE"):
            self.env.pop(name, None)

    def emit(self, message):
        print(message, flush=True)
        self.log.write(message + "\n")
        self.log.flush()

    def scalar(self, sql, session="A"):
        marker = "__VALUE_" + uuid.uuid4().hex
        text = self.session(session).run(f"SELECT '{marker}' || ({sql})::text;", quiet=True)
        match = re.search(r"^\s*" + marker + r"(.*?)\s*$", text, re.M)
        if not match:
            raise LabError("Could not read query result")
        return match[1]

    def assert_sql(self, expression, message, session="A"):
        if self.scalar(expression, session) != "true":
            raise LabError(message)

    def session(self, name):
        if name in self.sessions:
            return self.sessions[name]
        env = self.env.copy()
        options = ["-v", f"student_no={self.args.student}"]
        if name in ("P", "Q"):
            lab, port = self.bash_values("M6_LAB", "M6_PORT")
            if not lab or not port:
                raise LabError("Run 6D.1 first using this state directory")
            self.ensure_cluster('"${M6_LAB:?}/data"', '"${M6_LAB:?}/server.log"')
            options += ["-h", lab + "/socket", "-p", port, "-U", "labadmin", "-d", "claimsure"]
        elif name == "admin":
            if not self.args.instructor:
                raise LabError("Instructor step: use --instructor and INSTRUCTOR_* connection settings")
            options += ["-U", os.environ.get("INSTRUCTOR_USER", "postgres")]
            if "INSTRUCTOR_PASSWORD" in os.environ:
                env["PGPASSWORD"] = os.environ["INSTRUCTOR_PASSWORD"]
            else:
                env.pop("PGPASSWORD", None)
        role = {"A": "holder", "B": "waiter", "C": "observer", "P": "private-a", "Q": "private-b"}.get(name, name)
        if self.module == 9:
            env["PGAPPNAME"] = f"module09_{self.args.student}_{role}"
        else:
            env["PGAPPNAME"] = f"case-m{self.module}-{role}"
        current = Session(options, env, name, self.emit)
        self.sessions[name] = current
        if name == "admin":
            current.run("SELECT 'cs_reader_'||:'student_no' AS reader_role, 'cs_actor_'||:'student_no' AS actor_role, 'cs_api_'||:'student_no' AS api_role, 'student_'||:'student_no' AS student_role \\gset")
        return current

    def preflight(self):
        self.emit(f"Target: {self.args.host}:{self.args.port}/claimsure_{self.args.student} as student_{self.args.student}")
        self.assert_sql("current_database() = 'claimsure_" + self.args.student + "' AND session_user = 'student_" + self.args.student + "' AND current_setting('server_version_num')::int >= 180000", "Wrong database/login, or PostgreSQL older than 18")
        if self.module > 1:
            self.assert_sql("to_regclass('claimsure.claim') IS NOT NULL", "Complete Module 1 first")
        if self.module in (4, 5, 6, 7, 9, 10) and not self.completed:
            self.assert_sql("(SELECT count(*) FROM claimsure.claim WHERE claim_no LIKE 'CLM-L1-%') = 6", "The six original claims are incomplete; finish/reset the previous lab first")

    def bash_values(self, *names):
        if not self.variables.exists():
            return [""] * len(names)
        code = 'source "$1"\n' + "\n".join(f'printf \'%s\\0\' "${{{n}:-}}"' for n in names)
        result = subprocess.run(["bash", "-c", code, "state", str(self.variables)], capture_output=True, env=self.env, check=True)
        return result.stdout.decode().split("\0")[:-1]

    def bash(self, body, timeout=600):
        # Save only declared lab paths/arrays, never passwords or connection URLs.
        saved = str(self.variables)
        code = "set -Eeuo pipefail\numask 077\n"
        code += f"if test -f {shlex.quote(saved)}; then source {shlex.quote(saved)}; fi\n"
        code += "save_lab_state() {\n  {\n"
        code += "\n".join(f"    declare -p {name} 2>/dev/null || true" for name in STATE_VARS)
        code += f"\n  }} > {shlex.quote(saved + '.tmp')}\n  mv {shlex.quote(saved + '.tmp')} {shlex.quote(saved)}\n}}\ntrap save_lab_state EXIT\n"
        # M7 must use the selected host/port rather than a hidden second target.
        code += f"export LAB_DB_HOST={shlex.quote(self.args.host)} M7_DB_PORT={shlex.quote(str(self.args.port))}\n"
        code += body + "\n"
        script = self.directory / "current-step.sh"
        script.write_text(code)
        p = subprocess.Popen(["bash", str(script)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=self.env, start_new_session=True)
        timer = threading.Timer(timeout, lambda: self._terminate(p))
        timer.start()
        try:
            for line in p.stdout:
                self.emit("[bash] " + line.rstrip())
            if p.wait() != 0:
                raise LabError(f"Bash step failed; inspect {script} and {self.logfile}. Do not blindly replay committed steps.")
        except BaseException:
            self._terminate(p)
            p.wait()
            raise
        finally:
            timer.cancel()

    @staticmethod
    def _terminate(p):
        if p.poll() is None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(p.pid, signal.SIGTERM)

    def sql_block(self, section, index=0, session="A", expected=()):
        if self.module == 4 and session != "admin":
            self.security_setup()
        if self.module == 10 and section == "10F.1":
            self.assert_sql(f"EXISTS(SELECT FROM pg_roles WHERE rolname='cs_api_{self.args.student}')", "Instructor must run 10F.0 first")
        text = self.guide.block(section, "sql", index)
        if self.module in (1, 2, 3):
            self.session(session)
        self.session(session).run(text, expected)
        if expected:
            self.session(session).run("\\set ON_ERROR_STOP on")

    def security_setup(self):
        if self.security_ready:
            return
        self.assert_sql(f"EXISTS(SELECT FROM pg_roles WHERE rolname='cs_actor_{self.args.student}') AND EXISTS(SELECT FROM pg_roles WHERE rolname='cs_reader_{self.args.student}')", "Instructor must run 4.0 first")
        self.session("A").run(self.guide.block("4A"))
        self.security_ready = True

    def copy_out(self, table, file, session="A"):
        self.session(session).run(f"\\copy {table} TO {sql_literal(str(file))} WITH (FORMAT csv, HEADER true)")

    def copy_in(self, table, file, session="A"):
        if not file.exists():
            raise LabError(f"Missing saved data: {file}")
        self.session(session).run(f"\\copy {table} FROM {sql_literal(str(file))} WITH (FORMAT csv, HEADER true)")

    def snapshot5(self):
        text = self.guide.block("5A").replace("CREATE TABLE cs_m5_original", "CREATE TEMP TABLE cs_m5_original")
        self.session("A").run(text)
        self.copy_out("cs_m5_original", self.directory / "original.csv")
        self.recover = self.restore5

    def restore5(self):
        if self.scalar("to_regclass('pg_temp.cs_m5_original') IS NOT NULL") != "true":
            self.session("A").run("CREATE TEMP TABLE cs_m5_original AS SELECT * FROM claimsure.claim WITH NO DATA;")
            self.copy_in("cs_m5_original", self.directory / "original.csv")
        self.sql_block("5E")
        self.recover = None

    def memory(self):
        for phase in ("original", "64kB", "4MB", "32MB"):
            for sample in range(1, 4):
                self.emit(f"work_mem={phase}, sample={sample}")
                sql = self.guide.block("6B", index=0 if phase == "original" else 1)
                self.session("A").run(sql.replace("'64kB'", sql_literal(phase)))

    def wal_candidate(self):
        self.sql_block("6D.4", session="P")
        self.poll(lambda: self.scalar("current_setting('max_wal_size') = '256MB'", "P") == "true", 15, "max_wal_size did not reload")
        self.session("P").run("DROP TABLE IF EXISTS checkpoint_before;\n\\set phase 256MB")
        self.session("P").run(self.guide.block("6D.3").replace("\\set phase 64MB", "\\set phase 256MB"))
        self.sql_block("6D.4", 2, "P")
        self.bash(self.guide.block("6D.4", "bash"))

    @staticmethod
    def poll(condition, seconds, error):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(.2)
        raise LabError(error)

    def wait_for_lock(self, observer="C"):
        if self.module == 9:
            prefix = f"module09_{self.args.student}_"
            named = f"starts_with(application_name, '{prefix}')"
        else:
            named = "application_name LIKE 'case-m" + str(self.module) + "-%'"
        self.poll(lambda: self.scalar("EXISTS(SELECT FROM pg_stat_activity WHERE datname=current_database() AND usename=current_user AND " + named + " AND cardinality(pg_blocking_pids(pid))>0)", observer) == "true", 15, "Expected row-lock wait was not observed")

    def autovacuum(self):
        first = self.guide.block("6E")
        setup, rest = first.split("ALTER TABLE claimsure.claim SET(autovacuum_vacuum_insert_threshold=-1);", 1)
        self.session("A").run(setup)
        self.copy_out("cs_m6_options", self.directory / "options.csv")
        self.copy_out("cs_m6_rows", self.directory / "rows.csv")
        self.recover = self.restore_autovacuum
        self.session("A").run("ALTER TABLE claimsure.claim SET(autovacuum_vacuum_insert_threshold=-1);" + rest.replace("\\watch 5", ""))
        # Bounded observation replaces the manual Ctrl+C; always report measured results.
        deadline = time.monotonic() + self.args.autovacuum_wait
        while time.monotonic() < deadline:
            self.session("A").run("SELECT pg_stat_clear_snapshot();")
            if self.scalar("(SELECT s.n_dead_tup=0 AND s.autovacuum_count>b.autovacuum_count FROM pg_stat_user_tables s CROSS JOIN cs_m6_before b WHERE s.relid='claimsure.claim'::regclass)") == "true":
                break
            time.sleep(min(5, max(0, deadline-time.monotonic())))
        else:
            self.emit("OBSERVATION: no completed autovacuum within the sample; report this outcome, not a fabricated success.")
        self.session("A").run(self.guide.block("6E", index=1))
        self.recover = None

    def restore_autovacuum(self):
        self.discard_session("A")
        self.session("A").run("CREATE TEMP TABLE cs_m6_options(reloptions text[]); CREATE TEMP TABLE cs_m6_rows(claim_id bigint,status text);")
        self.copy_in("cs_m6_options", self.directory / "options.csv")
        self.copy_in("cs_m6_rows", self.directory / "rows.csv")
        reset = self.guide.block("6E", index=1).split("ALTER TABLE claimsure.claim RESET", 1)[1]
        self.session("A").run("ALTER TABLE claimsure.claim RESET" + reset)

    def logging(self, candidate):
        section = "6F.2" if candidate else "6F.1"
        self.sql_block(section, session="P")
        self.sql_block("6F.1", 1, "Q")
        self.session("P").send(self.guide.block("6F.1", index=2))
        # This observer must connect to the private instance, not shared.
        observer = self.session("Q")
        app = "case-m6-f-after" if candidate else "case-m6-f-before"
        self.poll(lambda: "Lock" in observer.run(f"SELECT wait_event_type FROM pg_stat_activity WHERE application_name='{app}';"), 10, "Private UPDATE did not wait for row lock")
        self.sql_block("6F.1", 3, "Q")
        self.session("P").finish()
        self.sql_block(section, 1 if candidate else 4, "P")
        if candidate:
            body = self.guide.block("6F.2", "bash")
            body = "\n".join(line + " || test $? -eq 1" if line.startswith("grep ") else line for line in body.splitlines())
            self.discard_session("P")
            self.discard_session("Q")
            self.bash(body)

    def module7(self, id):
        blocks = [s for lang, s in self.guide.sections[id]["blocks"] if lang == "bash"]
        if id == "7.1a":
            body = re.sub(r"^STUDENT_NO=.*\n", "", blocks[0], flags=re.M)
            body = re.sub(r"^read .*\n", "", body, flags=re.M)
            self.bash(body)
            return
        if id in ("7.3a", "7.3b", "7.4a", "7.4b", "7.4c", "7.4d", "7.4e"):
            self.ensure_cluster('"${PRIMARY:?}"', '"${LAB:?}/primary.log"')
        if id in ("7.4g", "7.4h"):
            self.ensure_cluster('"${D_RECOVERY:?}"', '"${LAB:?}/d-recovery.log"')
        if id == "7.3a":
            blocks = blocks[2:]
        self.bash("\n".join(blocks))
        if id == "7.2d":
            self.assert_sql("NOT EXISTS(SELECT FROM claimsure.claim WHERE claim_no='CLM-L1-002')", "Deleted claim is still present")
        if id in ("7.2g", "7.3e"):
            self.assert_sql("EXISTS(SELECT FROM claimsure.claim WHERE claim_no='CLM-L1-002' AND estimated_amount=22000)", "Restored original claim is missing/wrong")
        if id == "7.4h":
            self.assert_sql("EXISTS(SELECT FROM claimsure.claim WHERE claim_no='CLM-L7-AFTER-BASE' AND estimated_amount=400) AND NOT EXISTS(SELECT FROM claimsure.claim WHERE claim_no='CLM-L7-LOSS')", "PITR did not recover the expected target")

    def ensure_cluster(self, directory, log):
        self.bash(f'pg_ctl -D {directory} status || {{ code=$?; if test "$code" -eq 3; then pg_ctl -D {directory} -l {log} -w start; else exit "$code"; fi; }}')

    def workload(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(self.bash, self.guide.block("9C", "bash"))
            while not future.done():
                self.sql_block("9B", session="C")
                time.sleep(2)
            future.result()
        self.sql_block("9C", session="C")

    def blocking(self):
        self.sql_block("9D")
        self.session("B").send(self.guide.block("9D", index=1))
        try:
            self.wait_for_lock()
            self.sql_block("9D", 2, "C")
        finally:
            self.session("A").run("ROLLBACK;")
        self.session("B").finish()
        self.session("B").run("ROLLBACK;")

    def deadlock(self):
        self.sql_block("9E")
        self.sql_block("9E", 1, "B")
        self.session("A").send(self.guide.block("9E", index=2))
        self.wait_for_lock()
        self.session("B").send(self.guide.block("9E", index=3))
        # Exactly one victim is required; which session loses is intentionally unspecified.
        states = []
        for name in ("A", "B"):
            try:
                self.session(name).finish()
            except LabError as exc:
                if "observed ['40P01']" not in str(exc):
                    raise
                states.append("40P01")
            self.sql_block("9E", 4, name)
        if states != ["40P01"]:
            raise LabError(f"Expected one deadlock victim, got {states}")
        self.sql_block("9E", 5, "C")

    def snapshot10(self):
        text = self.guide.block("10A")
        before, mutation = text.split("UPDATE claimsure.claim", 1)
        self.session("A").run(before)
        self.copy_out("cs_m10_before", self.directory / "before.csv")
        self.recover = self.restore10
        self.session("A").run("UPDATE claimsure.claim" + mutation)

    def restore10(self):
        if self.sessions.get("A") and self.sessions["A"].process.poll() is not None:
            self.discard_session("A")
        if self.scalar("to_regclass('pg_temp.cs_m10_before') IS NOT NULL") != "true":
            self.session("A").run("CREATE TEMP TABLE cs_m10_before AS SELECT claim_id,description,metadata FROM claimsure.claim WITH NO DATA;")
            self.copy_in("cs_m10_before", self.directory / "before.csv")
        text = self.guide.block("10H").replace("DROP COLUMN search_document", "DROP COLUMN IF EXISTS search_document")
        self.session("A").run(text)
        self.recover = None

    def supabase(self):
        required = ("SUPABASE_DB_URL", "REAL_USER_ID", "SUPABASE_URL", "SUPABASE_PUBLIC_KEY", "SUPABASE_ACCESS_TOKEN")
        if any(not os.environ.get(name) for name in required):
            raise LabError("10G needs environment variables: " + ", ".join(required) + "; values are never saved in runner state")
        # Explicit opt-in only; never selected by `run all`.
        import urllib.request
        import urllib.parse
        csv = self.directory / "claims-api.csv"
        self.copy_out("(SELECT claim_no,status,estimated_amount FROM claimsure.claim WHERE claim_no LIKE 'CLM-L1-%' ORDER BY claim_no)", csv)
        project = Session([os.environ["SUPABASE_DB_URL"], "-v", "real_user_id=" + os.environ["REAL_USER_ID"]], self.env, "project", self.emit)
        try:
            project.run(self.guide.block("10G"))
            project.run("CREATE TEMP TABLE staged_claim(claim_no text,status text,estimated_amount numeric);\n" + f"\\copy staged_claim FROM {sql_literal(str(csv))} WITH (FORMAT csv, HEADER true)\n" + "INSERT INTO public.course_claim(claim_no,owner_id,status,estimated_amount) SELECT claim_no,:'real_user_id'::uuid,status,estimated_amount FROM staged_claim;")
            url = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1/course_claim?select=claim_no,status,estimated_amount&order=claim_no"
            req = urllib.request.Request(url, headers={"apikey": os.environ["SUPABASE_PUBLIC_KEY"], "Authorization": "Bearer " + os.environ["SUPABASE_ACCESS_TOKEN"]})
            with urllib.request.urlopen(req, timeout=30) as response:
                data = json.load(response)
            self.emit(json.dumps(data, ensure_ascii=False))
            if len(data) != 6:
                raise LabError("10G expected six claims visible to the assigned authenticated user")
            project.run("DROP TABLE public.course_claim;")
        finally:
            project.close()

    def discard_session(self, name):
        if name in self.sessions:
            self.sessions.pop(name).close()

    def action(self, action):
        kind, *values = action
        if kind == "sql":
            self.sql_block(*values)
        elif kind == "bash":
            body = self.guide.block(values[0], "bash", values[1])
            if self.module == 6 and values[0] == "6D.1":
                body = body.replace('export PATH="/usr/lib/postgresql/18/bin:$PATH"', "")
                body = body.replace('psql -X -v ON_ERROR_STOP=1 "${PRIVATE[@]}"\n', "")
            self.bash(body)
        elif kind == "security_setup": self.security_setup()
        elif kind == "m5_snapshot": self.snapshot5()
        elif kind == "m5_restore": self.restore5()
        elif kind == "memory": self.memory()
        elif kind == "wal_candidate": self.wal_candidate()
        elif kind == "autovacuum": self.autovacuum()
        elif kind == "logging": self.logging(*values)
        elif kind == "module7": self.module7(*values)
        elif kind == "workload": self.workload()
        elif kind == "blocking": self.blocking()
        elif kind == "deadlock": self.deadlock()
        elif kind == "statements":
            if self.scalar("EXISTS(SELECT FROM pg_extension WHERE extname='pg_stat_statements')") == "true":
                self.sql_block("9F", 1)
            else:
                self.emit("SKIPPED 9F: pg_stat_statements is not installed/prepared")
        elif kind == "m10_snapshot": self.snapshot10()
        elif kind == "m10_restore": self.restore10()
        elif kind == "supabase": self.supabase()
        elif kind == "verify":
            self.assert_sql(f"(SELECT count(*) FROM claimsure.claim)={values[0]}", "Unexpected claim count")
        elif kind == "note":
            self.emit(self.guide.sections[values[0]]["text"])
        else:
            raise LabError("Unknown recipe action: " + kind)

    def run(self, steps):
        if self.inflight.exists() and not self.args.retry_failed:
            failed = json.loads(self.inflight.read_text())["step"]
            raise LabError(f"Previous invocation stopped inside {failed}. Inspect data/logs first; use --retry-failed only after deciding that this step can be repeated.")
        self.preflight()
        if self.module in (1, 2):
            for kind, text in self.guide.sections["intro"]["blocks"]:
                if kind == "sql":
                    self.session("A").run(text)
        if self.module == 5 and any(s.id == "5B" for s in steps) and not any(s.id == "5C" for s in steps):
            raise LabError("5B leaves a transaction open. Select 5B 5C together, or run the whole module.")
        for step in steps:
            if self.args.resume and step.id in self.completed:
                self.emit("RESUME: skip completed " + step.id)
                continue
            if self.module == 5 and step.id == "5C" and "5B" not in self.executed:
                raise LabError("5C needs 5B in this invocation to keep transaction A open")
            missing = set(step.requires) - self.completed - self.executed
            if missing:
                raise LabError(f"{step.id} needs earlier steps: {', '.join(sorted(missing))}")
            if step.id in self.completed and not self.args.replay:
                raise LabError(f"{step.id} already completed. Use --resume to skip it, or --replay only after inspecting existing data.")
            self.emit(f"\n=== {step.id} — {step.title} ===")
            if self.args.pause:
                input("Enter to run this step (Ctrl+C to stop): ")
            self.inflight.write_text(json.dumps({"step": step.id, "log": str(self.logfile)}) + "\n")
            for action in step.actions:
                self.action(action)
            # An uncommitted 5B must never appear as resumable completed work.
            if step.id != "5B":
                self.completed.add(step.id)
            if step.id == "5C":
                self.completed.add("5B")
            self.executed.add(step.id)
            self.progress.write_text(json.dumps(sorted(self.completed), indent=2) + "\n")
            self.inflight.unlink()
            self.emit("DONE " + step.id)

    def close(self, failed=False):
        # Closing SQL connections rolls back any incomplete transaction first.
        if failed:
            for name in list(self.sessions):
                self.discard_session(name)
            if self.recover:
                try:
                    self.emit("Restoring saved lab rows/options after failure...")
                    self.recover()
                except Exception as exc:
                    self.emit(f"RESET REQUIRED: {exc}. Saved data: {self.directory}")
        for name in list(self.sessions):
            self.discard_session(name)
        self.emit("Evidence log: " + str(self.logfile))
        self.log.close()


def sql_literal(value):
    return "'" + value.replace("'", "''") + "'"


def select_steps(steps, selectors, instructor=False, optional=False):
    if not selectors:
        return [s for s in steps if (not s.optional or optional) and (not s.instructor or instructor) and s.id not in ("1Z", "2Z", "10G")]
    picked = []
    for selector in selectors:
        matches = [s for s in steps if s.id.casefold() == selector.casefold()]
        if not matches:
            # Only real submodule groups, never a broad "10" prefix that would
            # accidentally include the external Supabase/destructive reset steps.
            if re.fullmatch(r"\d+\.\d+", selector):
                matches = [s for s in steps if re.fullmatch(re.escape(selector.casefold()) + r"[a-z]+", s.id.casefold())]
            elif re.fullmatch(r"\d+[A-Za-z]", selector):
                matches = [s for s in steps if s.id.casefold().startswith(selector.casefold() + ".")]
        if not matches:
            raise LabError(f"Unknown step/group: {selector}")
        picked.extend(matches)
    ids = {s.id for s in picked}
    # Execution follows guide order even when selectors are entered out of order.
    return [s for s in steps if s.id in ids]


def main():
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(prog="run-labs.sh", description="ClaimSure continuous labs: module/submodule runner (Thai guides, English commands)")
    parser.add_argument("command", choices=("list", "show", "run", "status", "check"))
    parser.add_argument("module", nargs="?", default="all", help="1–7, 9, 10 or all")
    parser.add_argument("steps", nargs="*", help="e.g. 1A 1B, 6D.3, 7.2, 7.4b")
    parser.add_argument("--student", default=os.environ.get("STUDENT_NO", ""), help="Assigned two-digit number (01–20); required for run/status")
    parser.add_argument("--host", default=os.environ.get("PGHOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PGPORT", "5432")))
    parser.add_argument("--pg-bin", default=os.environ.get("PG_BIN", "/usr/lib/postgresql/18/bin"))
    parser.add_argument("--state-dir", type=Path, default=Path.home() / "case-labs" / "continuous-runner")
    parser.add_argument("--resume", action="store_true", help="Skip completed steps; no automatic replay of a partially committed step")
    parser.add_argument("--replay", action="store_true", help="Explicitly repeat selected completed steps")
    parser.add_argument("--retry-failed", action="store_true", help="Explicitly retry a failed step after inspecting partial commits")
    parser.add_argument("--pause", action="store_true", help="Wait for Enter before each step, retaining SQL connections")
    parser.add_argument("--instructor", action="store_true", help="Include instructor role preparation/cleanup using INSTRUCTOR_USER/PASSWORD")
    parser.add_argument("--optional", action="store_true", help="Include local optional vector/monitoring steps (Supabase requires explicit 10G)")
    parser.add_argument("--autovacuum-wait", type=int, default=90, help="Bounded observation time in seconds")
    args = parser.parse_args()
    try:
        if args.command in ("run", "status") and not args.student:
            raise LabError("Set STUDENT_NO or --student to your assigned number (01–20); xx is a placeholder")
        if args.student and not re.fullmatch(r"(?:0[1-9]|1[0-9]|20)", args.student):
            raise LabError("--student must be 01–20")
        if args.module != "all" and (not args.module.isdigit() or int(args.module) not in MODULES):
            raise LabError("Modules supported: 1–7, 9, 10")
        if args.module == "all" and args.steps:
            raise LabError("Specify a module when selecting submodules")
        if not 1 <= args.autovacuum_wait <= 600:
            raise LabError("--autovacuum-wait must be 1–600 seconds")
        modules = MODULES if args.module == "all" else (int(args.module),)
        plans = []
        for module in modules:
            guide = Guide(module)
            steps = build_steps(module, guide)
            selected = select_steps(steps, args.steps, args.instructor, args.optional)
            if args.instructor and not args.steps and module in (4, 10):
                admin_ids = ("4.0", "4Z") if module == 4 else ("10F.0", "10Z")
                selected = [steps[0]] + selected if module == 4 and steps[0] not in selected else selected
                for s in steps:
                    if s.id in admin_ids and s not in selected:
                        selected.append(s)
                if module == 10:
                    selected.sort(key=lambda s: steps.index(s))
            plans.append((module, guide, selected))
        if args.command in ("list", "show", "check"):
            for module, guide, selected in plans:
                print(f"\nModule {module}: {guide.path.name}")
                if args.command in ("list", "check") and not args.steps:
                    selected = build_steps(module, guide)
                for step in selected:
                    print(f"  {step.id:7} {step.title}" + (" [instructor]" if step.instructor else " [optional]" if step.optional else ""))
                    if args.command == "show":
                        print("  Recipe: " + ", ".join(a[0] for a in step.actions))
                        section = step.id if step.id in guide.sections else None
                        if section:
                            for lang, text in guide.sections[section]["blocks"]:
                                print(f"```{lang}\n{text}```")
                    if args.command == "check":
                        for action in step.actions:
                            if action[0] in ("sql", "bash"):
                                guide.block(action[1], "sql" if action[0] == "sql" else "bash", action[2])
                if args.command == "check":
                    for data in guide.sections.values():
                        for lang, text in data["blocks"]:
                            if lang == "bash":
                                subprocess.run(["bash", "-n"], input=text, text=True, check=True)
            return 0
        os.umask(0o077)
        root = args.state_dir.expanduser().resolve() / ("student" + args.student)
        root.mkdir(parents=True, exist_ok=True, mode=0o700)
        binding = {"host": args.host, "port": args.port, "student": args.student}
        binding_file = root / "connection.json"
        lock = (root / ".lock").open("a")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise LabError("Another runner is using this student's state directory") from exc
        if binding_file.exists() and json.loads(binding_file.read_text()) != binding:
            raise LabError("State belongs to a different server/student; choose a different --state-dir")
        if args.command == "status":
            for module, _, selected in plans:
                p = root / f"module{module:02d}" / "progress.json"
                done = set(json.loads(p.read_text())) if p.exists() else set()
                for step in selected:
                    print(("DONE " if step.id in done else "TODO ") + step.id + " " + step.title)
            return 0
        if os.geteuid() == 0:
            raise LabError("Run as the student OS account, not root (initdb/pg_ctl require it)")
        if not re.fullmatch(r"[A-Za-z0-9_./-]+", str(Path.home())):
            raise LabError("This lab's archive_command requires a home path without spaces/shell punctuation")
        binding_file.write_text(json.dumps(binding, indent=2) + "\n")
        if "PGPASSWORD" not in os.environ and sys.stdin.isatty():
            password = getpass.getpass(f"Database password for student_{args.student} (blank to use .pgpass): ")
            if password:
                os.environ["PGPASSWORD"] = password
        for module, guide, selected in plans:
            runner = Runner(args, module, root)
            failed = True
            try:
                runner.run(selected)
                failed = False
            finally:
                runner.close(failed)
        return 0
    except (LabError, subprocess.CalledProcessError, OSError) as exc:
        print(f"STOP: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nStopped; open SQL transactions were rolled back. Inspect the log before resuming.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
