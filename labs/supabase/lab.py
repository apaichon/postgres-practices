#!/usr/bin/env python3
"""Supabase Data API + Authentication lab. Standard library only; hides secrets."""
import argparse
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

LAB = Path(__file__).resolve().parent
REPO = LAB.parent.parent
ENV = LAB / '.env'
REPORT = REPO / 'docs/tutorials/supabase-self-hosted/verification.json'


def read_env(path=ENV):
    if not path.exists():
        raise RuntimeError('Run: python3 labs/supabase/lab.py init')
    values = {}
    for line in path.read_text().splitlines():
        if line.strip() and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=').decode()


def init():
    if ENV.exists():
        print('Kept existing labs/supabase/.env; no secrets were changed.')
        return
    values = {
        'POSTGRES_PASSWORD': secrets.token_hex(24),
        'JWT_SECRET': secrets.token_hex(32),
        'DASHBOARD_PASSWORD': secrets.token_hex(16),
        'SECRET_KEY_BASE': secrets.token_hex(48),
        'REALTIME_DB_ENC_KEY': secrets.token_hex(8),
        'VAULT_ENC_KEY': secrets.token_hex(16),
        'PG_META_CRYPTO_KEY': secrets.token_hex(32),
        'S3_PROTOCOL_ACCESS_KEY_ID': secrets.token_hex(16),
        'S3_PROTOCOL_ACCESS_KEY_SECRET': secrets.token_hex(32),
        'DEMO_PASSWORD': secrets.token_hex(16),
    }
    now = int(time.time())
    for key, role in [('ANON_KEY', 'anon'), ('SERVICE_ROLE_KEY', 'service_role')]:
        header = b64(json.dumps({'alg': 'HS256', 'typ': 'JWT'}, separators=(',', ':')).encode())
        payload = b64(json.dumps({'role': role, 'iss': 'supabase', 'iat': now,
                                 'exp': now + 365 * 86400}, separators=(',', ':')).encode())
        message = header + '.' + payload
        signature = hmac.new(values['JWT_SECRET'].encode(), message.encode(), hashlib.sha256).digest()
        values[key] = message + '.' + b64(signature)
    text = (LAB / '.env.example').read_text()
    for key, value in values.items():
        text = re.sub(r'^' + re.escape(key) + r'=.*$', key + '=' + value, text, flags=re.M)
    # Exclusive creation prevents concurrent init from replacing a configured stack.
    fd = os.open(ENV, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as file:
        file.write(text)
    print('Created labs/supabase/.env (0600), with unique secrets and matching HS256 keys.')
    print('API keys expire in 365 days. Keep this file with your private backups.')


def config():
    values = read_env()
    for key in ['POSTGRES_PASSWORD', 'JWT_SECRET', 'ANON_KEY', 'SERVICE_ROLE_KEY',
                'DASHBOARD_PASSWORD', 'SECRET_KEY_BASE', 'REALTIME_DB_ENC_KEY',
                'VAULT_ENC_KEY', 'PG_META_CRYPTO_KEY', 'DEMO_PASSWORD']:
        if not values.get(key) or values[key].startswith('change-me-'):
            raise RuntimeError('Unconfigured ' + key + '; initialize your private .env first.')
    return values


def compose(*args, input=None, capture=False):
    values = config()
    command = ['docker', 'compose', '--project-directory', str(LAB),
               '--env-file', str(ENV), '--project-name', values['COMPOSE_PROJECT_NAME'],
               '-f', str(LAB / 'compose.yaml'), *args]
    return subprocess.run(command, input=input, text=True, check=True,
                          capture_output=capture, env={**os.environ, **values})


def sql(filename):
    text = (LAB / 'sql' / filename).read_text()
    if filename == '02-demo-claims.sql':
        values = config()
        for source, key in [('adjuster.bkk@claimsure.example.com', 'DEMO_BKK_EMAIL'),
                            ('adjuster.cm@claimsure.example.com', 'DEMO_CM_EMAIL')]:
            text = text.replace(source, values[key].replace("'", "''"))
    return compose('exec', '-T', 'db', 'psql', '-X', '-U', 'postgres', '-d', 'postgres',
                   '-v', 'ON_ERROR_STOP=1', input=text)


def api(path, method='GET', body=None, token=None, admin=False, raw=None, extra=None):
    values = config()
    key = values['SERVICE_ROLE_KEY'] if admin else values['ANON_KEY']
    headers = {'apikey': key, 'Authorization': 'Bearer ' + (token or key)}
    if raw is not None:
        data = raw
    elif body is not None:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(body).encode()
    else:
        data = None
    headers.update(extra or {})
    req = urllib.request.Request(values['SUPABASE_PUBLIC_URL'].rstrip('/') + path,
                                 data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            status, content = res.status, res.read()
    except urllib.error.HTTPError as err:
        status, content = err.code, err.read()
    try:
        result = json.loads(content)
    except (ValueError, UnicodeDecodeError):
        result = content.decode(errors='replace')
    return status, result


def require(status, expected, message):
    if status not in expected:
        raise RuntimeError(message + ': HTTP ' + str(status) + ' (check service health/logs)')


def seed(extended=False):
    values = config()
    sql('01-claims-schema.sql')
    status, result = api('/auth/v1/admin/users?page=1&per_page=1000', admin=True)
    require(status, [200], 'List Auth users')
    existing = {user['email']: user['id'] for user in result['users']}
    for key, branch in [('DEMO_BKK_EMAIL', 'BKK'), ('DEMO_CM_EMAIL', 'CM')]:
        email = values[key]
        payload = {'password': values['DEMO_PASSWORD'], 'email_confirm': True,
                   'user_metadata': {'display_name': 'ClaimSure ' + branch + ' Demo'}}
        if email in existing:
            status, _ = api('/auth/v1/admin/users/' + existing[email], 'PUT', payload, admin=True)
        else:
            payload['email'] = email
            status, _ = api('/auth/v1/admin/users', 'POST', payload, admin=True)
        require(status, [200, 201], 'Create/update synthetic Auth user')
    sql('02-demo-claims.sql')
    print('API seed complete: 2 confirmed Auth users + 4 claims with owner-based RLS.')
    if not extended:
        return
    status, _ = api('/storage/v1/bucket', 'POST',
                    {'id': 'claim-documents', 'name': 'claim-documents', 'public': False}, admin=True)
    require(status, [200, 201, 400, 409], 'Create private bucket')
    # A 400 may mean "already exists". Confirm bucket identity and privacy separately.
    status, bucket = api('/storage/v1/bucket/claim-documents', admin=True)
    require(status, [200], 'Inspect private bucket')
    if bucket.get('public') is not False:
        raise RuntimeError('claim-documents must remain a private bucket.')
    status, _ = api('/storage/v1/object/claim-documents/example-claim.txt', 'POST', admin=True,
                    raw=(LAB / 'fixtures/example-claim.txt').read_bytes(),
                    extra={'Content-Type': 'text/plain', 'x-upsert': 'true'})
    require(status, [200, 201], 'Upload synthetic example file')
    print('Optional seed complete: 1 private bucket and 1 example file.')


def verify(extended=False, demo=False):
    values = config()
    checks = []
    users = {}

    def record(label, method, path, status, result=None):
        row = {'check': label, 'method': method, 'path': path, 'status': status, 'pass': True}
        if result is not None:
            row['rows'] = result
        checks.append(row)
        if demo:
            print('\n' + label + '\n' + method + ' ' + path + '\nHTTP ' + str(status))
            if result is not None:
                print(json.dumps(result, ensure_ascii=False, indent=2))

    login_path = '/auth/v1/token?grant_type=password'
    if demo:
        print('Same Data API endpoint; change the caller to see role + RLS in action.')
        print('Login responses show only the email and role; passwords/tokens are hidden.')
    for branch, key in [('BKK', 'DEMO_BKK_EMAIL'), ('CM', 'DEMO_CM_EMAIL')]:
        status, result = api(login_path, 'POST',
                             {'email': values[key], 'password': values['DEMO_PASSWORD']})
        require(status, [200], 'Password sign-in ' + branch)
        users[branch] = {'token': result['access_token'], 'id': result['user']['id']}
        record(branch + ' sign-in: Auth issues a user JWT', 'POST', login_path, status)
        if demo:
            print(json.dumps({'email': values[key], 'role': 'authenticated',
                              'access_token': '[hidden]'}, indent=2))
    status, _ = api(login_path, 'POST',
                    {'email': values['DEMO_BKK_EMAIL'], 'password': secrets.token_hex(24)})
    require(status, [400, 401], 'Wrong password must fail')
    record('Wrong password rejected', 'POST', login_path, status)
    query = '/rest/v1/claimsure_claims?select=claim_no,branch,amount,status&order=claim_no'
    status, _ = api(query, token='invalid-token')
    require(status, [401], 'Invalid bearer token must fail')
    record('Invalid bearer token rejected', 'GET', query, status)
    status, rows = api(query)
    assert status == 200 and rows == [], 'Anonymous SELECT must see no claims'
    record('anon SELECT: no user signed in', 'GET', query, status, rows)
    for branch in users:
        status, rows = api(query, token=users[branch]['token'])
        assert status == 200 and {r['claim_no'] for r in rows} == {
            'CLM-' + branch + '-001', 'CLM-' + branch + '-002'}, branch + ' row isolation failed'
        record('authenticated / ' + branch + ' SELECT own claims', 'GET', query, status, rows)
    status, rows = api(query, admin=True)
    assert status == 200 and {row['claim_no'] for row in rows} == {
        'CLM-BKK-001', 'CLM-BKK-002', 'CLM-CM-001', 'CLM-CM-002'}, 'Admin must see all demo claims'
    record('service_role SELECT: instructor/backend only; bypasses RLS', 'GET', query, status, rows)
    status, rows = api(query + '&branch=eq.CM', token=users['BKK']['token'])
    assert status == 200 and rows == [], 'Cross-user SELECT must be filtered out'
    record('BKK filters for CM: RLS still hides other owners', 'GET', query + '&branch=eq.CM', status, rows)
    status, _ = api('/rest/v1/claimsure_claims', 'POST',
                    {'claim_no': 'CLM-REJECT-' + uuid.uuid4().hex, 'branch': 'CM',
                     'adjuster_id': users['CM']['id'], 'amount': 1}, token=users['BKK']['token'])
    assert status == 403, 'Cross-user INSERT must fail WITH CHECK'
    record('BKK INSERT for CM rejected', 'POST', '/rest/v1/claimsure_claims', status)
    test_id = str(uuid.uuid4())
    try:
        status, _ = api('/rest/v1/claimsure_claims', 'POST',
                        {'id': test_id, 'claim_no': 'CLM-API-' + uuid.uuid4().hex,
                         'branch': 'BKK', 'adjuster_id': users['BKK']['id'], 'amount': 10},
                        token=users['BKK']['token'])
        assert status == 201, 'Own-user INSERT must succeed'
        record('BKK INSERT own claim', 'POST', '/rest/v1/claimsure_claims', status)
        own_query = query + '&id=eq.' + test_id
        status, rows = api(own_query, token=users['BKK']['token'])
        assert status == 200 and len(rows) == 1 and rows[0]['claim_no'].startswith('CLM-API-'), 'Owner must see inserted claim'
        record('BKK reads the newly inserted claim', 'GET', own_query, status, rows)
        status, rows = api(own_query, token=users['CM']['token'])
        assert status == 200 and rows == [], 'Other user must not see inserted claim'
        record('CM cannot see the BKK inserted claim', 'GET', own_query, status, rows)
        update_path = '/rest/v1/claimsure_claims?id=eq.' + test_id
        status, rows = api(update_path, 'PATCH', {'status': 'REVIEW'}, token=users['BKK']['token'],
                           extra={'Prefer': 'return=representation'})
        assert status == 200 and len(rows) == 1 and rows[0]['status'] == 'REVIEW', 'Own-user UPDATE must succeed'
        record('BKK UPDATE own claim status', 'PATCH', update_path, status,
               [{'claim_no': row['claim_no'], 'status': row['status']} for row in rows])
        status, _ = api('/rest/v1/claimsure_claims?id=eq.' + test_id, 'PATCH',
                        {'adjuster_id': users['CM']['id']}, token=users['BKK']['token'])
        assert status == 403, 'Cannot transfer an own claim to another user'
        record('BKK UPDATE owner to CM rejected', 'PATCH', update_path, status)
    finally:
        cleanup, _ = api('/rest/v1/claimsure_claims?id=eq.' + test_id, 'DELETE', admin=True)
        require(cleanup, [204], 'Clean up only the temporary verification row')
    if extended:
        status, content = api('/storage/v1/object/claim-documents/example-claim.txt', admin=True)
        assert status == 200 and content == (LAB / 'fixtures/example-claim.txt').read_text(), 'Seed object must exist'
        record('Optional: admin reads private object', 'GET', '/storage/v1/object/claim-documents/example-claim.txt', status)
        status, _ = api('/storage/v1/object/claim-documents/example-claim.txt')
        assert status in [400, 401, 403, 404], 'Anonymous must not download the private file'
        record('Optional: anon download private object rejected', 'GET', '/storage/v1/object/claim-documents/example-claim.txt', status)
        status, result = api('/functions/v1/claimsure-health')
        assert status == 200 and result.get('edge_runtime') == 'ready', 'Edge Function must execute with the signed JWT'
        record('Optional: JWT-protected Edge Function', 'GET', '/functions/v1/claimsure-health', status)
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps({'captured_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                                  'base_url': values['SUPABASE_PUBLIC_URL'],
                                  'checks': checks}, indent=2) + '\n')
    print('\nPASS: ' + str(len(checks)) + ' ' + ('extended' if extended else 'Auth / Data API / RLS') +
          ' checks. No tokens in report.')
    print('Report: ' + str(REPORT.relative_to(REPO)))


def wait_ready(timeout=300):
    deadline = time.monotonic() + timeout
    expected = compose('config', '--services', capture=True).stdout.split()
    while time.monotonic() < deadline:
        ids = compose('ps', '-q', capture=True).stdout.split()
        if ids:
            rows = json.loads(subprocess.run(['docker', 'inspect', *ids], capture_output=True,
                                            text=True, check=True).stdout)
            states = {r['Config']['Labels']['com.docker.compose.service']:
                      r['State'].get('Health', {}).get('Status', r['State']['Status']) for r in rows}
            if all(states.get(service) in ['healthy', 'running'] for service in expected):
                print('Ready: ' + ', '.join(expected))
                return
        time.sleep(3)
    raise RuntimeError('Startup timed out; run status, then inspect logs for the affected service.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['init', 'config', 'pull', 'up', 'wait', 'status',
                                           'stop', 'down', 'psql', 'seed', 'verify', 'api-demo'])
    parser.add_argument('--extended', action='store_true', help='Include optional Storage/Edge exercises (seed/verify only).')
    args = parser.parse_args()
    command = args.command
    if args.extended and command not in ('seed', 'verify'):
        parser.error('--extended applies only to seed or verify')
    if command == 'init':
        init()
    elif command == 'config':
        compose('config', '--quiet')
        print('Compose configuration is valid (secrets not displayed).')
    elif command == 'up':
        compose('up', '-d')
        wait_ready()
        print('Studio: ' + config()['SUPABASE_PUBLIC_URL'])
        print('Dashboard credentials: DASHBOARD_USERNAME / DASHBOARD_PASSWORD in labs/supabase/.env')
    elif command == 'wait':
        wait_ready()
    elif command == 'seed':
        seed(extended=args.extended)
    elif command == 'verify':
        verify(extended=args.extended)
    elif command == 'api-demo':
        verify(demo=True)
    elif command == 'psql':
        compose('exec', 'db', 'psql', '-X', '-U', 'postgres', '-d', 'postgres')
    elif command == 'status':
        compose('ps')
    else:
        compose(command)  # pull, stop, down; down never passes --volumes.


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, AssertionError, subprocess.CalledProcessError,
            urllib.error.URLError, KeyError, ValueError) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
