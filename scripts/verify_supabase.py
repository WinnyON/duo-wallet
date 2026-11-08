#!/usr/bin/env python3
"""Exercise real Auth, PostgREST/RLS and Storage with disposable test identities.
Credentials are read from a private status JSON, never printed or committed.
"""
import argparse
import json
import secrets
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--status-file', required=True)
parser.add_argument('--allow-live', action='store_true')
parser.add_argument('--cli', help='Supabase CLI path for read-only live password-hash metadata verification')
args = parser.parse_args()
config = json.loads(Path(args.status_file).read_text())
base = config['API_URL'].rstrip('/')
if urllib.parse.urlparse(base).hostname not in ('127.0.0.1', 'localhost') and not args.allow_live:
    raise SystemExit('Live tests require --allow-live and create disposable test users/households.')
public = config.get('PUBLISHABLE_KEY') or config['ANON_KEY']
admin = config.get('SECRET_KEY') or config['SERVICE_ROLE_KEY']
results = []
users = []
households = []
password = secrets.token_hex(8)
run = uuid.uuid4().hex[:12]


def request(path, data=None, token=None, method=None, admin_request=False, raw=False, expect=(200, 201, 204)):
    key = admin if admin_request else public
    headers = {'apikey': key}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    elif admin_request and not admin.startswith('sb_secret_'):
        headers['Authorization'] = 'Bearer ' + admin
    if data is not None:
        headers['Content-Type'] = 'application/json'
    if '/storage/v1/object/' in path and data is not None:
        headers['x-upsert'] = 'true'
    payload = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(base + path, data=payload, headers=headers, method=method or ('POST' if data is not None else 'GET'))
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            status, body = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, body = error.code, error.read()
    if expect is not None and status not in expect:
        # API bodies can contain supplied data; never print passwords or tokens.
        parsed = json.loads(body) if body else {}
        raise AssertionError(f'{method or req.method} {path.split("?")[0]} status {status}; code={parsed.get("code", parsed.get("error_code", "unknown"))}; message={parsed.get("message", "") if path.startswith("/rest/") else "redacted"}')
    if raw:
        return status, body
    return status, json.loads(body) if body else None


def check(name, condition):
    if not condition:
        raise AssertionError(name)
    results.append(name)


def denied(path, data=None, token=None, method=None):
    status, _ = request(path, data, token, method, expect=None)
    return status >= 400


def signup_user(index):
    email = f'duo-security-{run}-{index}@example.com'
    _, user = request('/auth/v1/admin/users', {'email': email, 'password': password, 'email_confirm': True}, admin_request=True)
    users.append(user['id'])
    _, session = request('/auth/v1/token?grant_type=password', {'email': email, 'password': password})
    check(f'User {index}: confirmed email/password login succeeds', session['user']['id'] == user['id'])
    return user['id'], session['access_token']


def snapshot(token):
    return request('/rest/v1/rpc/duo_snapshot', {}, token)[1]


def transaction(uid, household, account, scope='individual', common=False):
    now = datetime.now(timezone.utc).isoformat()
    return {'id': str(uuid.uuid4()), 'household_id': household, 'kind': 'expense', 'scope': scope,
        'visibility': 'shared' if scope == 'together' else 'private', 'occurred_on': now[:10],
        'amount_minor': 10000, 'currency': 'HUF', 'fx_rate_to_base': 1, 'fx_source': 'manual',
        'base_amount_minor': 10000, 'paid_by': uid, 'paid_from_common': common,
        'account_id': account, 'account_amount_minor': 10000, 'is_contribution': False,
        'created_by': uid, 'created_at': now, 'updated_at': now, 'tags': []}


def save_txn(token, row, shares):
    return request('/rest/v1/rpc/duo_save_transaction', {'p_transaction': row, 'p_shares': shares, 'p_base_shares': shares}, token)


try:
    check('Anonymous database snapshot denied', denied('/rest/v1/rpc/duo_snapshot', {}))
    check('Email is required by Auth', denied('/auth/v1/signup', {'email': '', 'password': password}))
    check('Weak passwords rejected server-side', denied('/auth/v1/signup', {'email': f'weak-{run}@example.com', 'password': 'weak'}))
    check('Seven-character passwords rejected server-side', denied('/auth/v1/signup', {'email': f'weak2-{run}@example.com', 'password': 'seven77'}))
    unconfirmed_email = f'unconfirmed-{run}@example.com'
    _, unconfirmed = request('/auth/v1/admin/users', {'email': unconfirmed_email, 'password': password, 'email_confirm': False}, admin_request=True)
    users.append(unconfirmed['id'])
    check('Unconfirmed email cannot sign in', denied('/auth/v1/token?grant_type=password', {'email': unconfirmed_email, 'password': password}))
    a, at = signup_user('a')
    b, bt = signup_user('b')
    c, ct = signup_user('c')
    _, household = request('/rest/v1/rpc/create_household', {'p_name': 'Duo security test ' + run, 'p_display_name': 'A', 'p_color': '#4F46E5'}, at)
    households.append(household)
    sa = snapshot(at)
    code = sa['household']['invite_code']
    check('New invite codes have 128-bit entropy', len(code) >= 32)
    _, same = request('/rest/v1/rpc/create_household', {'p_name': 'Duplicate', 'p_display_name': 'A', 'p_color': '#4F46E5'}, at)
    check('Household creation is idempotent', same == household)
    request('/rest/v1/rpc/join_household', {'p_invite_code': code, 'p_display_name': 'B', 'p_color': '#EC4899'}, bt)
    check('Third member cannot join a full household', denied('/rest/v1/rpc/join_household', {'p_invite_code': code, 'p_display_name': 'C', 'p_color': '#EF4444'}, ct))
    _, other = request('/rest/v1/rpc/create_household', {'p_name': 'Other test ' + run, 'p_display_name': 'C', 'p_color': '#EF4444'}, ct)
    households.append(other)
    sb = snapshot(bt)
    aa = next(x['id'] for x in sa['accounts'] if x['owner_id'] == a)
    ba = next(x['id'] for x in sb['accounts'] if x['owner_id'] == b)
    check('Partner private account is absent from snapshot', not any(x['id'] == ba for x in snapshot(at)['accounts']))
    private = transaction(b, household, ba)
    save_txn(bt, private, {b: 10000})
    shared = transaction(b, household, ba, 'together')
    save_txn(bt, shared, {a: 6000, b: 4000})
    visible = snapshot(at)
    check('Partner private transaction is absent', not any(x['id'] == private['id'] for x in visible['transactions']))
    check('Shared transaction and exact shares are visible', next(x for x in visible['transactions'] if x['id'] == shared['id'])['transaction_shares'] != [])
    check('Unrelated household sees no victim transaction', not any(x['household_id'] == household for x in snapshot(ct)['transactions']))
    check('Direct household-membership hijack blocked', denied(f'/rest/v1/profiles?id=eq.{a}', {'household_id': other}, at, 'PATCH'))
    forged = transaction(a, household, ba, 'together')
    check('Partner source account cannot be spent', denied('/rest/v1/rpc/duo_save_transaction', {'p_transaction': forged, 'p_shares': {a: 10000}, 'p_base_shares': {a: 10000}}, at))
    forged = transaction(a, household, aa, 'together')
    forged['created_by'] = b
    check('Transaction actor impersonation blocked', denied('/rest/v1/rpc/duo_save_transaction', {'p_transaction': forged, 'p_shares': {a: 10000}, 'p_base_shares': {a: 10000}}, at))
    invalid = transaction(a, household, aa, 'together')
    check('Cross-household share participant blocked atomically', denied('/rest/v1/rpc/duo_save_transaction', {'p_transaction': invalid, 'p_shares': {c: 10000}, 'p_base_shares': {c: 10000}}, at))
    check('Rejected atomic transaction leaves no row', not any(x['id'] == invalid['id'] for x in snapshot(at)['transactions']))
    invalid_sum = transaction(a, household, aa)
    check('Share totals enforced by database', denied('/rest/v1/rpc/duo_save_transaction', {'p_transaction': invalid_sum, 'p_shares': {a: 1}, 'p_base_shares': {a: 1}}, at))
    check('Global recurring job cannot be invoked by a user', denied('/rest/v1/rpc/generate_recurring', {}, at))
    check('Client cannot publish forged private activity', denied('/rest/v1/activity', {'id': str(uuid.uuid4()), 'household_id': household, 'actor_id': a, 'event_type': 'expense_added', 'payload': {'summary_en': 'private leak'}}, at))
    check('Only actual shared writes generate activity', not any(x.get('entity_id') == private['id'] for x in snapshot(at)['activity']) and any(x.get('entity_id') == shared['id'] for x in snapshot(at)['activity']))
    data = {'marker': run, 'owner': a}
    path = f'/storage/v1/object/backups/{a}/latest.json'
    request(path, data, at)
    _, restored = request(path, token=at)
    check('Private Storage upload/download round trip works', restored == data)
    check('Partner cannot read private backup', denied(path, token=bt))
    check('Partner cannot overwrite private backup', denied(path, {'owner': b}, bt))
    check('Anonymous backup download denied', denied(path))
    request(f'/storage/v1/object/backups', {'prefixes': [f'{a}/latest.json']}, at, 'DELETE')
    # Check salted bcrypt in local Auth without returning hashes to the terminal.
    if urllib.parse.urlparse(base).hostname in ('127.0.0.1', 'localhost'):
        sql = f"select (select encrypted_password from auth.users where id='{a}') <> (select encrypted_password from auth.users where id='{b}') and (select encrypted_password like '$2%' from auth.users where id='{a}');"
        result = subprocess.run(['docker', 'exec', '-i', 'supabase_db_duo-wallet', 'psql', '-U', 'postgres', '-d', 'postgres', '-Atc', sql], capture_output=True, text=True, check=True)
        check('Equal passwords use distinct salted bcrypt hashes', result.stdout.strip() == 't')
    elif args.cli:
        sql = f"select (select encrypted_password from auth.users where id='{a}') <> (select encrypted_password from auth.users where id='{b}') and (select encrypted_password like '$2%' from auth.users where id='{a}') as salted_bcrypt_verified;"
        result = subprocess.run([args.cli, 'db', 'query', '--remote', '--read-only', sql, '--output', 'json'], capture_output=True, text=True, check=True)
        metadata = json.loads(result.stdout)
        check('Equal passwords use distinct salted bcrypt hashes on the live project', metadata['rows'][0]['salted_bcrypt_verified'] is True)
    print(json.dumps({'result': 'PASS', 'checks': len(results), 'passed': results}, indent=2))
finally:
    # Legacy hosted foreign keys are not all CASCADE. Clean only the identities
    # and households created by this run, in dependency order.
    failures = []
    for household in households:
        _, txs = request(f'/rest/v1/transactions?household_id=eq.{household}&select=id', admin_request=True)
        _, accounts = request(f'/rest/v1/accounts?household_id=eq.{household}&select=id', admin_request=True)
        _, goals = request(f'/rest/v1/goals?household_id=eq.{household}&select=id', admin_request=True)
        _, settlements = request(f'/rest/v1/settlements?household_id=eq.{household}&select=id', admin_request=True)
        request(f'/rest/v1/transactions?household_id=eq.{household}', {'deleted_at': datetime.now(timezone.utc).isoformat()}, method='PATCH', admin_request=True, expect=None)
        children = [('transaction_tags', 'transaction_id', txs), ('transaction_shares', 'transaction_id', txs),
            ('goal_accounts', 'goal_id', goals), ('goal_contributions', 'goal_id', goals),
            ('settlement_postings', 'settlement_id', settlements), ('account_valuations', 'account_id', accounts)]
        for table, key, records in children:
            if records:
                ids = ','.join(r['id'] for r in records)
                status, _ = request(f'/rest/v1/{table}?{key}=in.({ids})', method='DELETE', admin_request=True, expect=None)
                if status >= 400: failures.append(table)
        for table in ['activity', 'transactions', 'recurring_rules', 'settlements', 'budgets', 'goals', 'accounts', 'categories', 'tags']:
            status, _ = request(f'/rest/v1/{table}?household_id=eq.{household}', method='DELETE', admin_request=True, expect=None)
            if status >= 400: failures.append(table)
        for uid in users:
            status, _ = request(f'/rest/v1/profiles?id=eq.{uid}&household_id=eq.{household}', method='DELETE', admin_request=True, expect=None)
            if status >= 400: failures.append('profile')
        status, _ = request(f'/rest/v1/households?id=eq.{household}', method='DELETE', admin_request=True, expect=None)
        if status >= 400: failures.append('household')
    for uid in users:
        status, _ = request(f'/auth/v1/admin/users/{uid}', method='DELETE', admin_request=True, expect=None)
        if status >= 400: failures.append('auth user')
    if failures:
        raise AssertionError('Disposable test cleanup failed for: ' + ', '.join(failures))
