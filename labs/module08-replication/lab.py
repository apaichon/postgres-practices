#!/usr/bin/env python3
"""Module 8A–8E: primary, optional replicas, logical subscriber and PgBouncer."""
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
ENV = Path(os.environ.get('M8_ENV_FILE', LAB / '.env')).resolve()
NODES = ('primary', 'replica', 'replica2', 'subscriber')


def init():
    if ENV.exists():
        print('Kept existing Lab 8 .env; no secrets changed.')
        return
    text = (LAB / '.env.example').read_text()
    for key in ('M8_ADMIN_PASSWORD', 'M8_REPLICATION_PASSWORD', 'M8_APP_PASSWORD'):
        text = re.sub(r'^' + key + r'=.*$', key + '=' + secrets.token_hex(24), text, flags=re.M)
    fd = os.open(ENV, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as file:
        file.write(text)
    print('Created private Lab 8 .env (0600). Set unused host ports before up.')


def config():
    if not ENV.exists():
        raise RuntimeError('Run make lab8-init first.')
    values = dict(line.split('=', 1) for line in ENV.read_text().splitlines()
                  if line.strip() and not line.lstrip().startswith('#'))
    if 'M8_PG1_PORT' in values:
        raise RuntimeError('This .env belongs to the previous pg1/pg2/pg3 lab. Keep it with its '
                           'old volumes; use M8_ENV_FILE with a new project and new .env for 8A–8E.')
    if not re.fullmatch(r'[a-z0-9][a-z0-9_-]+', values.get('COMPOSE_PROJECT_NAME', '')):
        raise RuntimeError('Use a lowercase COMPOSE_PROJECT_NAME without spaces.')
    for key in ('M8_ADMIN_PASSWORD', 'M8_REPLICATION_PASSWORD', 'M8_APP_PASSWORD'):
        if not re.fullmatch(r'[a-zA-Z0-9_-]{16,}', values.get(key, '')) or values[key].startswith('replace_'):
            raise RuntimeError('Set a random secret of at least 16 characters for ' + key)
    ports = [values.get('M8_' + name + '_PORT', '')
             for name in ('PRIMARY', 'REPLICA', 'REPLICA2', 'SUBSCRIBER', 'POOL')]
    if len(set(ports)) != 5 or not all(p.isdigit() and 1024 <= int(p) <= 65535 for p in ports):
        raise RuntimeError('Configure five distinct host ports between 1024 and 65535.')
    return values


def compose(*args, capture=False, input=None):
    values = config()
    return subprocess.run(['docker', 'compose', '--project-directory', str(LAB),
                           '--env-file', str(ENV), '-p', values['COMPOSE_PROJECT_NAME'],
                           '-f', str(LAB / 'compose.yaml'), '--profile', 'ha-lab',
                           '--profile', 'logical-lab', *args], input=input, text=True,
                          check=True, capture_output=capture, env={**os.environ, **values})


def sql(node, query):
    return compose('exec', '-T', node, 'psql', '-XqAt', '-U', 'postgres', '-d', 'claimsure',
                   '-v', 'ON_ERROR_STOP=1', input=query, capture=True).stdout.strip()


def wait_ready(node, timeout=120):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = compose('ps', '-q', node, capture=True).stdout.strip()
        if result:
            state = json.loads(subprocess.run(['docker', 'inspect', result], check=True,
                                             capture_output=True, text=True).stdout)[0]['State']
            if state.get('Health', {}).get('Status') == 'healthy':
                return
            if state['Status'] in ('exited', 'dead'):
                raise RuntimeError(node + ' exited; inspect its Compose logs.')
        time.sleep(1)
    raise RuntimeError(node + ' did not become healthy; inspect its Compose logs.')


def wait_value(node, query, expected, timeout=45):
    deadline = time.monotonic() + timeout
    while sql(node, query) != expected:
        if time.monotonic() >= deadline:
            raise RuntimeError(node + ' did not reach the expected replay state within 45 seconds.')
        time.sleep(1)


def running():
    return set(compose('ps', '--services', '--status', 'running', capture=True).stdout.split())


def up():
    compose('up', '-d', 'primary', 'replica', 'pgbouncer')
    for node in ('primary', 'replica', 'pgbouncer'):
        wait_ready(node)
    if sql('primary', 'SELECT pg_is_in_recovery();') != 'f':
        raise RuntimeError('The configured primary is in recovery. Follow the failover runbook.')
    print('Ready: primary + replica + PgBouncer. Add replica2 with make node-add.')


def inspect():
    compose('exec', '-T', 'primary', 'psql', '-X', '-U', 'postgres', '-d', 'claimsure',
            '-v', 'ON_ERROR_STOP=1', '-f', '/lab/sql/status.sql')


def verify():
    standbys = [node for node in ('replica', 'replica2') if node in running()]
    if 'replica' not in standbys:
        raise RuntimeError('Start the baseline replica with make up first.')
    if sql('primary', 'SELECT pg_is_in_recovery();') != 'f':
        raise RuntimeError('Expected primary to be writable.')
    cluster_id = sql('primary', 'SELECT system_identifier FROM pg_control_system();')
    sql('primary', 'CREATE TABLE IF NOT EXISTS lab_m8.replication_probe (id text PRIMARY KEY);')
    probe = uuid.uuid4().hex
    try:
        sql('primary', "INSERT INTO lab_m8.replication_probe VALUES ('" + probe + "');")
        lsn = sql('primary', 'SELECT pg_current_wal_lsn();')
        for node in standbys:
            if sql(node, 'SELECT pg_is_in_recovery();') != 't':
                raise RuntimeError(node + ' must remain a read-only standby.')
            if sql(node, 'SELECT system_identifier FROM pg_control_system();') != cluster_id:
                raise RuntimeError(node + ' has a different physical cluster identifier.')
            wait_value(node, "SELECT coalesce(pg_last_wal_replay_lsn() >= '" + lsn + "'::pg_lsn, false);", 't')
            if sql(node, "SELECT count(*) FROM lab_m8.replication_probe WHERE id='" + probe + "';") != '1':
                raise RuntimeError(node + ' is missing the committed probe.')
            try:
                sql(node, "BEGIN; INSERT INTO lab_m8.replication_probe VALUES ('readonly-test'); ROLLBACK;")
            except subprocess.CalledProcessError as error:
                if 'read-only transaction' not in error.stderr:
                    raise
            else:
                raise RuntimeError(node + ' unexpectedly accepted a write.')
    finally:
        sql('primary', "DELETE FROM lab_m8.replication_probe WHERE id='" + probe + "';")
    print('PASS: primary + ' + str(len(standbys)) + ' physical standbys, shared cluster ID, replay and read-only checks.')


def wal():
    batch = uuid.uuid4().hex
    sql('primary', "INSERT INTO insurance.audit_event(tenant_id,actor,action,entity_type,entity_id,details) "
        "SELECT 1,'ha_lab','NODE_DOWN_WAL','replica2',g::text,"
        "jsonb_build_object('lab','8C','batch','" + batch + "') FROM generate_series(1,1000) g;")
    print('Committed 1000 audit events on primary. Compare replica2_slot before/after restart.')
    inspect()


def logical_up():
    sql('primary', "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_publication WHERE pubname='claims_reporting') "
        "THEN CREATE PUBLICATION claims_reporting FOR TABLE insurance.claim, insurance.claim_payment; "
        "END IF; END $$;")
    compose('up', '-d', 'subscriber')
    wait_ready('subscriber')
    compose('exec', '-T', 'subscriber', 'psql', '-X', '-U', 'postgres', '-d', 'claimsure',
            '-v', 'ON_ERROR_STOP=1', '-f', '/lab/sql/schema.sql')
    if sql('subscriber', "SELECT count(*) FROM pg_subscription WHERE subname='claims_reporting_sub';") == '0':
        sql('subscriber', "CREATE SUBSCRIPTION claims_reporting_sub CONNECTION "
            "'host=primary port=5432 user=replicator dbname=claimsure "
            "passfile=/var/lib/postgresql/replication.pgpass application_name=logical_subscriber' "
            "PUBLICATION claims_reporting;")
    wait_value('subscriber', "SELECT count(*) FROM pg_subscription_rel WHERE srsubstate = 'r';", '2')
    print('Ready: independent subscriber, publication claims_reporting, subscription claims_reporting_sub.')


def logical_verify():
    if 'subscriber' not in running():
        raise RuntimeError('Run make logical-up first.')
    if sql('subscriber', 'SELECT pg_is_in_recovery();') != 'f':
        raise RuntimeError('Logical subscriber should be an independent writable database.')
    if sql('primary', 'SELECT system_identifier FROM pg_control_system();') == sql('subscriber', 'SELECT system_identifier FROM pg_control_system();'):
        raise RuntimeError('Logical subscriber must have its own cluster identifier.')
    for table, key in (('claim', 'claim_id'), ('claim_payment', 'payment_id')):
        query = 'SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY ' + key + ")::text, '[]')) FROM insurance." + table + ' t;'
        wait_value('subscriber', query, sql('primary', query))
    probe = 'M8-LOGICAL-' + uuid.uuid4().hex
    try:
        sql('primary', "INSERT INTO insurance.claim(tenant_id,claim_no,status,amount) VALUES (1,'" + probe + "','NEW',1);")
        wait_value('subscriber', "SELECT count(*) FROM insurance.claim WHERE claim_no='" + probe + "';", '1')
        sql('primary', "UPDATE insurance.claim SET status='REVIEW' WHERE claim_no='" + probe + "';")
        wait_value('subscriber', "SELECT status FROM insurance.claim WHERE claim_no='" + probe + "';", 'REVIEW')
        if sql('subscriber', "SELECT to_regclass('insurance.audit_event') IS NULL;") != 't':
            raise RuntimeError('Unpublished audit_event should not be created on subscriber.')
    finally:
        sql('primary', "DELETE FROM insurance.claim WHERE claim_no='" + probe + "';")
        wait_value('subscriber', "SELECT count(*) FROM insurance.claim WHERE claim_no='" + probe + "';", '0')
    print('PASS: logical initial copy/INSERT/UPDATE/DELETE on an independent subscriber; unpublished audit table absent.')


def pool_query(query, admin=False):
    user, database, secret = ('postgres', 'pgbouncer', 'POSTGRES_PASSWORD') if admin else ('claim_app', 'claimsure', 'M8_APP_PASSWORD')
    return compose('exec', '-T', 'primary', '/bin/bash', '-c',
                   'export PGPASSWORD="$' + secret + '"; exec psql -XqAt -h pgbouncer -p 6432 -U ' + user + ' -d ' + database + ' -v ON_ERROR_STOP=1',
                   input=query, capture=True).stdout.strip()


def pool_verify():
    config_rows = pool_query('SHOW CONFIG;', admin=True).splitlines()
    if not any(row.startswith('pool_mode|transaction|') for row in config_rows):
        raise RuntimeError('PgBouncer must use transaction pooling.')
    identity = pool_query('SELECT session_user, current_user, pg_is_in_recovery();')
    if identity != 'claim_app|claim_app|f':
        raise RuntimeError('Pool must connect claim_app to the writable primary.')
    for tenant in ('1', '2'):
        expected = sql('primary', 'SELECT count(*) FROM insurance.claim WHERE tenant_id=' + tenant + ';')
        rows = pool_query("BEGIN; SET LOCAL app.tenant_id='" + tenant + "'; SELECT count(*) FROM insurance.claim; COMMIT; "
                          'SELECT count(*) FROM insurance.claim;').splitlines()
        if rows != [expected, '0']:
            raise RuntimeError('Expected tenant rows inside transaction and zero rows without context.')
    print('PASS: PgBouncer transaction mode, real claim_app login and transaction-local tenant RLS for tenants 1/2.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['init', 'config', 'pull', 'up', 'verify', 'status',
        'node-status', 'node-add', 'node-down', 'node-up', 'wal', 'inspect', 'logical-up',
        'logical-verify', 'pool-verify', 'stop', 'down', 'psql', 'pgbouncer'])
    parser.add_argument('node', choices=NODES, nargs='?')
    args = parser.parse_args()
    command = args.command
    if args.node and command not in ('node-up', 'node-down', 'psql'):
        parser.error('A node argument applies only to psql, node-up and node-down.')
    if command == 'init':
        init()
        return
    if command == 'up' and not ENV.exists():
        init()
    if command == 'config':
        compose('config', '--quiet')
        print('Compose configuration valid; secrets hidden.')
    elif command == 'up':
        up()
    elif command == 'verify':
        verify()
    elif command == 'inspect':
        inspect()
    elif command in ('node-add', 'node-up', 'node-down'):
        node = args.node or 'replica2'
        if node not in ('replica', 'replica2'):
            raise RuntimeError('Node drills target replica or replica2 only; primary/subscriber are not accepted.')
        if command == 'node-down':
            compose('stop', node)
        else:
            compose('up', '-d', node)
            wait_ready(node)
    elif command == 'wal':
        wal()
    elif command == 'logical-up':
        logical_up()
    elif command == 'logical-verify':
        logical_verify()
    elif command == 'pool-verify':
        pool_verify()
    elif command == 'psql':
        compose('exec', args.node or 'primary', 'psql', '-X', '-U', 'postgres', '-d', 'claimsure')
    elif command == 'pgbouncer':
        compose('exec', 'primary', '/bin/bash', '-c',
                'export PGPASSWORD="$M8_APP_PASSWORD"; exec psql -X -h pgbouncer -p 6432 -U claim_app -d claimsure')
    else:
        compose('ps' if command in ('status', 'node-status') else command)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, OSError, KeyError, ValueError) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
