#!/usr/bin/env python3
"""Run the Supabase data-api.http collection using only Python's standard library."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

HERE = Path(__file__).resolve().parent
SEED_CLAIMS = {"CLM-BKK-001", "CLM-BKK-002", "CLM-CM-001", "CLM-CM-002"}


class CheckError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def read_env(path):
    require(path.is_file(), f"Missing {path}; prepare your lab .env first")
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        require("=" in line, "Invalid .env assignment")
        key, value = line.split("=", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key.strip()] = value
    for key in ("SUPABASE_PUBLIC_URL", "ANON_KEY", "SERVICE_ROLE_KEY",
                "DEMO_BKK_EMAIL", "DEMO_CM_EMAIL", "DEMO_PASSWORD"):
        require(bool(values.get(key)), f"Missing .env value: {key}")
    values["SUPABASE_PUBLIC_URL"] = values["SUPABASE_PUBLIC_URL"].rstrip("/")
    return values


def read_collection(path):
    text = path.read_text(encoding="utf-8")
    variables = dict(re.findall(r"^@(\w+)\s*=\s*(.+)$", text, re.M))
    requests = []
    names = set()
    for part in re.split(r"(?m)^###\s+", text)[1:]:
        number = re.match(r"(\d+)", part)
        name = re.search(r"^# @name (\w+)\s*$", part, re.M)
        expected = re.search(r"^# EXPECT: HTTP ([0-9/]+)", part, re.M)
        require(number and name and expected, "Every request needs a number, @name and EXPECT: HTTP")
        name = name[1]
        require(name not in names, f"Duplicate request name: {name}")
        names.add(name)
        lines = part.splitlines()
        at = next((i for i, line in enumerate(lines)
                   if re.match(r"^(GET|POST|PATCH|DELETE) ", line)), None)
        require(at is not None, f"Missing HTTP method: {name}")
        method, url = lines[at].split(" ", 1)
        headers = {}
        i = at + 1
        while i < len(lines) and lines[i].strip():
            require(":" in lines[i], f"Invalid header: {name}")
            key, value = lines[i].split(":", 1)
            headers[key] = value.strip()
            i += 1
        raw_body = "\n".join(lines[i + 1:]).strip()
        body = json.loads(raw_body) if raw_body else None
        requests.append({"number": int(number[1]), "name": name, "method": method,
                         "url": url, "headers": headers, "body": body,
                         "expected": {int(x) for x in expected[1].split("/")}})
    require(requests, "No requests found in the HTTP file")
    return variables, requests


class ApiRunner:
    def __init__(self, env, variables, student, timeout):
        self.env = env
        self.variables = {**variables, "studentNo": student}
        self.student = student
        self.timeout = timeout
        self.responses = {}
        self.rows = set()
        self.baseline = None
        self.base_url = env["SUPABASE_PUBLIC_URL"]
        self.origin = urllib.parse.urlsplit(self.base_url)
        require(self.origin.scheme in ("http", "https") and bool(self.origin.netloc),
                "SUPABASE_PUBLIC_URL must be an HTTP(S) URL")
        self.table_url = self.base_url + "/rest/v1/claimsure_claims"
        self.admin = {"apikey": env["SERVICE_ROLE_KEY"],
                      "Authorization": "Bearer " + env["SERVICE_ROLE_KEY"]}

    def resolve(self, text, stack=()):
        def value(match):
            key = match[1].strip()
            if key.startswith("$dotenv "):
                field = key.split()[1]
                require(field in self.env, f"Missing .env value: {field}")
                return self.env[field]
            if key == "$guid":
                return str(uuid.uuid4())
            if key in self.variables:
                require(key not in stack, "Circular file variable")
                return self.resolve(self.variables[key], (*stack, key))
            reference = re.fullmatch(r"(\w+)\.response\.body\.(\$(?:\.\w+|\[\d+\])*)", key)
            require(reference is not None, "Unsupported HTTP variable expression")
            name, path = reference.groups()
            require(name in self.responses, f"Missing response dependency: {name}")
            data = self.responses[name]
            try:
                for field, index in re.findall(r"\.(\w+)|\[(\d+)\]", path):
                    data = data[int(index)] if index else data[field]
            except (KeyError, IndexError, TypeError):
                raise CheckError(f"Missing response field in {name}") from None
            return str(data)
        return re.sub(r"\{\{(.*?)\}\}", value, text)

    def resolve_body(self, value):
        # Resolve JSON values before encoding so quotes in passwords remain valid JSON.
        if isinstance(value, str):
            return self.resolve(value)
        if isinstance(value, dict):
            return {k: self.resolve_body(v) for k, v in value.items()}
        if isinstance(value, list):
            return [self.resolve_body(v) for v in value]
        return value

    def send(self, method, url, headers, body=None):
        target = urllib.parse.urlsplit(url)
        require((target.scheme, target.netloc) == (self.origin.scheme, self.origin.netloc),
                "Request target differs from the configured Supabase server")
        payload = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=payload, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                status, raw = response.status, response.read()
        except urllib.error.HTTPError as error:
            status, raw = error.code, error.read()
        except (urllib.error.URLError, TimeoutError, OSError):
            raise CheckError("API connection failed or timed out; check the configured stack") from None
        try:
            data = json.loads(raw) if raw else None
        except (ValueError, UnicodeDecodeError):
            raise CheckError(f"HTTP {status}: expected a JSON response") from None
        return status, data

    def snapshot(self):
        status, rows = self.send("GET", self.table_url + "?select=*&order=claim_no", self.admin)
        require(status == 200 and isinstance(rows, list), "Cannot read lab baseline with service role")
        return rows

    def preflight(self):
        self.baseline = self.snapshot()
        require(len(self.baseline) == 4 and {r.get("claim_no") for r in self.baseline} == SEED_CLAIMS,
                "Expected four seed claims. Finish prior lab cleanup before running; no automatic reset is performed")

    def track_insert(self, body):
        # Register BEFORE sending: cleanup also works if the POST response is lost.
        require(isinstance(body, dict), "Expected a claim JSON object")
        claim = body.get("claim_no", "")
        prefix = rf"CLM-REST(?:-REJECT)?_{self.student}-"
        require(re.fullmatch(prefix + r"[0-9a-fA-F-]{36}", claim), "Only temporary REST lab claims may be inserted")
        owner = str(uuid.UUID(body["adjuster_id"]))
        self.rows.add((claim, owner))

    def check_result(self, name, data):
        if name in ("loginBkk", "loginCm"):
            require(isinstance(data, dict) and bool(data.get("access_token")), "Login response has no access token")
            uuid.UUID(data["user"]["id"])
            if name == "loginCm":
                require(data["user"]["id"] != self.responses["loginBkk"]["user"]["id"], "Demo users must be different")
        elif name in ("readAnonymous", "readOtherOwner", "cmReadsBkkClaim", "cmUpdatesBkkClaim"):
            require(data == [], f"{name}: expected no visible rows")
        elif name in ("readBkk", "readCm"):
            branch = "BKK" if name == "readBkk" else "CM"
            require(isinstance(data, list) and len(data) == 2
                    and {r["claim_no"] for r in data} == {f"CLM-{branch}-001", f"CLM-{branch}-002"},
                    f"{name}: owner row isolation failed")
        elif name in ("createClaim", "readCreatedClaim", "updateOwnClaim", "confirmClaimUnchanged", "cleanupClaim"):
            require(isinstance(data, list) and len(data) == 1, f"{name}: expected one lab row")
            created = data[0] if name == "createClaim" else self.responses["createClaim"][0]
            require(data[0]["id"] == created["id"], f"{name}: incorrect lab row")
            if name == "createClaim":
                require((data[0]["claim_no"], data[0]["adjuster_id"]) in self.rows, "INSERT returned an unexpected owner/claim")
            if name in ("createClaim", "readCreatedClaim", "updateOwnClaim", "confirmClaimUnchanged"):
                expected = "NEW" if name in ("createClaim", "readCreatedClaim") else "REVIEW"
                require(data[0]["status"] == expected, f"{name}: unexpected claim status")
            if name == "confirmClaimUnchanged":
                require(data[0]["adjuster_id"] == self.responses["loginBkk"]["user"]["id"], "Claim owner changed")
        elif name in ("rejectOwnerTransfer", "rejectOtherOwnerInsert"):
            require(isinstance(data, dict) and data.get("code") == "42501", f"{name}: expected RLS SQLSTATE 42501")
        elif name == "readServiceRole":
            require(isinstance(data, list) and len(data) == 4
                    and {r["claim_no"] for r in data} == SEED_CLAIMS, "Seed claims did not return to baseline")

    def execute(self, request):
        method = request["method"]
        url = self.resolve(request["url"])
        headers = {k: self.resolve(v) for k, v in request["headers"].items()}
        body = self.resolve_body(request["body"])
        if method == "POST" and urllib.parse.urlsplit(url).path.endswith("/rest/v1/claimsure_claims"):
            self.track_insert(body)
        if request["name"] == "rejectOwnerTransfer" and "createClaim" in self.responses:
            # Even a broken WITH CHECK policy must not leave our row under its new owner.
            claim = self.responses["createClaim"][0]["claim_no"]
            self.rows.add((claim, str(uuid.UUID(body["adjuster_id"]))))
        status, data = self.send(method, url, headers, body)
        require(status in request["expected"], f"HTTP {status}; expected " + "/".join(map(str, sorted(request["expected"]))))
        self.check_result(request["name"], data)
        self.responses[request["name"]] = data
        return status

    def cleanup(self):
        errors = []
        for claim, owner in sorted(self.rows):
            filters = urllib.parse.urlencode({"claim_no": "eq." + claim, "adjuster_id": "eq." + owner})
            try:
                status, _ = self.send("DELETE", self.table_url + "?" + filters, self.admin)
                require(status in (200, 204), "Temporary row cleanup failed")
            except CheckError:
                errors.append("Could not remove a temporary row; inspect the lab before retrying")
        if self.baseline is not None:
            try:
                require(self.snapshot() == self.baseline, "Baseline data differs after cleanup")
            except CheckError as error:
                errors.append(str(error))
        require(not errors, "; ".join(errors))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--student", help="Assigned two-digit number (01–20); overrides STUDENT_NO and @studentNo")
    parser.add_argument("--env", type=Path, default=HERE / ".env")
    parser.add_argument("--http-file", type=Path, default=HERE / "data-api.http")
    parser.add_argument("--report", type=Path, default=HERE / "artifacts/api-results.json")
    parser.add_argument("--timeout", type=float, default=20, help="Seconds per HTTP request")
    parser.add_argument("--list", action="store_true", help="List requests without reading secrets or connecting")
    args = parser.parse_args(argv)
    report = {"started_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "passed": False, "requests": [], "cleanup": "not-needed"}
    runner = None
    current = None
    exit_code = 1
    try:
        variables, requests = read_collection(args.http_file)
        if args.list:
            for request in requests:
                print(f'{request["number"]:02} {request["method"]:6} {request["name"]}')
            return 0
        student = args.student or os.environ.get("STUDENT_NO") or variables.get("studentNo", "")
        require(re.fullmatch(r"(?:0[1-9]|1[0-9]|20)", student),
                "Set --student, STUDENT_NO or @studentNo to your assigned number (01–20); xx is a placeholder")
        require(0 < args.timeout <= 120, "--timeout must be greater than 0 and at most 120 seconds")
        runner = ApiRunner(read_env(args.env), variables, student, args.timeout)
        runner.preflight()
        print(f"Running {len(requests)} API requests for student {student}; credentials hidden", flush=True)
        for current in requests:
            status = runner.execute(current)
            report["requests"].append({"number": current["number"], "name": current["name"],
                                       "method": current["method"], "status": status, "passed": True})
            print(f'PASS {current["number"]:02} {current["name"]}: HTTP {status}', flush=True)
        report["passed"] = True
        exit_code = 0
    except KeyboardInterrupt:
        report["passed"] = False
        report["error"] = "Interrupted; remaining requests were not sent"
        print("STOP: interrupted; cleaning up temporary rows", file=sys.stderr)
        exit_code = 130
    except (CheckError, OSError, ValueError, KeyError, TypeError) as error:
        report["passed"] = False
        # Never include HTTP bodies, headers, raw environment values or login responses.
        message = str(error) if isinstance(error, CheckError) else "Invalid collection/configuration or unexpected API response"
        report["error"] = message
        if current:
            report["requests"].append({"number": current["number"], "name": current["name"],
                                       "passed": False, "error": message})
        print("FAIL: " + message, file=sys.stderr)
    finally:
        if runner and runner.rows:
            try:
                runner.cleanup()
                report["cleanup"] = "passed"
                print("CLEANUP: temporary rows removed; original four claims unchanged", flush=True)
            except (CheckError, ValueError, KeyError, TypeError):
                report["cleanup"] = "failed"
                report["passed"] = False
                exit_code = 1
                print("FAIL: cleanup/baseline check failed; inspect your lab before retrying", file=sys.stderr)
        if not args.list:
            try:
                args.report.parent.mkdir(parents=True, exist_ok=True)
                args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                print("Report: " + str(args.report), flush=True)
            except OSError:
                exit_code = 1
                print("FAIL: cannot write report", file=sys.stderr)
    if exit_code == 0:
        print(f'PASS: {len(report["requests"])}/{len(report["requests"])} API requests')
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
