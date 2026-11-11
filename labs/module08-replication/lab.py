#!/usr/bin/env python3
"""Bootstrap the isolated Lab 8 primary and two physical streaming replicas."""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time
import uuid

LAB = Path(__file__).resolve().parent
ENV = LAB / '.env'
NODES = ('pg1', 'pg2', 'pg3')


def init():
    if ENV.exists():
        print('Kept existing Lab 8 .env; no secrets changed.')
        return
    text = (LAB / '.env.example').read_text()
    for key in ('M8_ADMIN_PASSWORD', 'M8_REPLICATION_PASSWORD'):
        text = re.sub(r'^' + key + r'=.*$', key + '=' + secrets.token_hex(24), text, flags=re.M)
    fd = os.open(ENV, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as file:
        file.write(text)
    print('Created labs/module08-replication/.env (0600).')


def compose(*args, capture=False, input=None):
    if not ENV.exists():
        raise RuntimeError('Run: bash labs/docker-labs.sh 8 init')
    values = dict(line.split('=', 1) for line in ENV.read_text().splitlines()
                  if line.strip() and not line.lstrip().startswith('#'))
    if re.search(r'(?:^|[-_])xx(?:$|[-_])', values.get('COMPOSE_PROJECT_NAME', ''), re.I):
        raise RuntimeError('Replace xx in COMPOSE_PROJECT_NAME with your assigned number (01-20) before starting the lab')
    for key in ('M8_ADMIN_PASSWORD', 'M8_REPLICATION_PASSWORD'):
        if not re.fullmatch(r'[a-zA-Z0-9_-]{16,}', values.get(key, '')) or values[key].startswith('replace_'):
            raise RuntimeError('Set a random secret of at least 16 characters for ' + key)
    return subprocess.run(['docker', 'compose', '--project-directory', str(LAB),
                           '--env-file', str(ENV), '-p', values['COMPOSE_PROJECT_NAME'],
                           '-f', str(LAB / 'compose.yaml'), *args],
                          input=input, text=True, check=True, capture_output=capture,
                          env={**os.environ, **values})


def sql(node, query):
    return compose('exec', '-T', node, 'psql', '-XAt', '-U', 'postgres', '-d', 'claimsure_m8',
                   '-v', 'ON_ERROR_STOP=1', input=query, capture=True).stdout.strip()


def wait_ready(node, timeout=90):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = compose('ps', '-q', node, capture=True).stdout.strip()
        if result:
            state = json.loads(subprocess.run(['docker', 'inspect', result], check=True,
                                             capture_output=True, text=True).stdout)[0]['State']
            if state.get('Health', {}).get('Status') == 'healthy':
                return
            if state['Status'] in ('exited', 'dead'):
                raise RuntimeError(node + ' exited during startup; inspect docker compose logs ' + node)
        time.sleep(2)
    raise RuntimeError(node + ' did not become healthy; inspect docker compose logs ' + node)


def disk_role(node):
    # Read only: do not invoke the node entrypoint or start stopped databases here.
    return compose('run', '--rm', '--no-deps', '--entrypoint', '/bin/bash', node, '-ec',
                   'if [[ ! -f "$PGDATA/PG_VERSION" ]]; then echo empty; '
                   'elif [[ -f "$PGDATA/standby.signal" ]]; then echo standby; '
                   'else echo primary; fi', capture=True).stdout.strip()


def up():
    roles = {node: disk_role(node) for node in NODES}
    if roles['pg1'] == 'standby' or any(roles[node] == 'primary' for node in NODES[1:]):
        raise RuntimeError('Roles changed after failover. Use the README rejoin procedure; '
                           'up only bootstraps/resumes the original pg1-primary topology.')
    compose('up', '-d', 'pg1')
    wait_ready('pg1')
    for node in NODES[1:]:
        if roles[node] == 'empty':
            sql('pg1', "SELECT pg_create_physical_replication_slot('m8_" + node + "') "
                "WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name='m8_" + node + "');")
            compose('run', '--rm', '--no-deps', node, 'clone', 'pg1')
        compose('up', '-d', node)
        wait_ready(node)
    print('Ready: pg1 primary, pg2 + pg3 standbys. Run verify to prove WAL replay.')


def verify():
    roles = {node: sql(node, 'SELECT pg_is_in_recovery();') for node in NODES}
    primaries = [node for node, recovery in roles.items() if recovery == 'f']
    if len(primaries) != 1 or any(role not in ('t', 'f') for role in roles.values()):
        raise RuntimeError('Expected exactly one writable primary: ' + str(roles))
    primary = primaries[0]
    identifiers = {sql(node, 'SELECT system_identifier FROM pg_control_system();') for node in NODES}
    if len(identifiers) != 1:
        raise RuntimeError('Nodes do not share a physical cluster system identifier.')
    sql(primary, 'CREATE TABLE IF NOT EXISTS lab_m8.replication_probe '
        '(id text PRIMARY KEY, created_at timestamptz NOT NULL DEFAULT clock_timestamp());')
    probe = uuid.uuid4().hex
    try:
        sql(primary, "INSERT INTO lab_m8.replication_probe(id) VALUES ('" + probe + "');")
        target_lsn = sql(primary, 'SELECT pg_current_wal_lsn();')
        for node in NODES:
            deadline = time.monotonic() + 30
            while node != primary and sql(node, "SELECT coalesce(pg_last_wal_replay_lsn() >= '" +
                                              target_lsn + "'::pg_lsn, false);") != 't':
                if time.monotonic() >= deadline:
                    raise RuntimeError(node + ' did not replay the probe within 30 seconds.')
                time.sleep(1)
            if sql(node, "SELECT count(*) FROM lab_m8.replication_probe WHERE id='" + probe + "';") != '1':
                raise RuntimeError(node + ' is missing the committed probe.')
            if node != primary:
                # A transaction guarantees that even an unexpectedly writable node keeps no row.
                try:
                    sql(node, "BEGIN; INSERT INTO lab_m8.replication_probe(id) VALUES ('readonly-test'); ROLLBACK;")
                except subprocess.CalledProcessError as error:
                    if 'read-only transaction' not in error.stderr:
                        raise
                else:
                    raise RuntimeError(node + ' unexpectedly accepted a write.')
    finally:
        sql(primary, "DELETE FROM lab_m8.replication_probe WHERE id='" + probe + "';")
    print('PASS: one primary (' + primary + '), shared cluster ID, WAL replay on both standbys, '
          'and standby writes rejected.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['init', 'config', 'pull', 'up', 'verify',
                                           'status', 'stop', 'down', 'psql'])
    parser.add_argument('node', choices=NODES, nargs='?', default='pg1')
    args = parser.parse_args()
    if args.command == 'init':
        init()
    elif args.command == 'config':
        compose('config', '--quiet')
        print('Compose configuration is valid (secrets not displayed).')
    elif args.command == 'up':
        up()
    elif args.command == 'verify':
        verify()
    elif args.command == 'psql':
        compose('exec', args.node, 'psql', '-X', '-U', 'postgres', '-d', 'claimsure_m8')
    else:
        compose('ps' if args.command == 'status' else args.command)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, OSError, KeyError, ValueError) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
