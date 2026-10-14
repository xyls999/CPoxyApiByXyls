"""End-to-end welcome quota check against an isolated new-api SQLite copy only."""

import argparse
import json
import secrets
import sqlite3
import urllib.request


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--expected', type=int, required=True)
    args = parser.parse_args()
    if args.port != 13000 or 'station-registration-trial.db' not in args.db:
        raise ValueError('Refusing to register a test user outside the isolated staging service')

    conn = sqlite3.connect(args.db)
    before = dict(conn.execute('select id,quota from users'))
    username = 'giftprobe' + secrets.token_hex(5)
    data = json.dumps({'username': username, 'password': secrets.token_urlsafe(22)}).encode()
    request = urllib.request.Request(
        f'http://127.0.0.1:{args.port}/api/user/register',
        data=data,
        headers={'Content-Type': 'application/json'},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        result = json.load(response)
    assert result.get('success'), 'Staging account creation must succeed'
    actual = conn.execute('select quota from users where username=?', (username,)).fetchone()[0]
    assert actual == args.expected, f'Welcome quota expected {args.expected}, received {actual}'
    with urllib.request.urlopen(request, timeout=15) as response:
        duplicate = json.load(response)
    assert not duplicate.get('success'), 'Same username must not register twice'
    assert conn.execute('select quota from users where username=?', (username,)).fetchone()[0] == args.expected
    after = dict(conn.execute('select id,quota from users where id in (' + ','.join('?' for _ in before) + ')', tuple(before)))
    assert before == after, 'Existing account balances must stay unchanged'
    print('PASS: single new account receives expected quota; duplicate denied; existing balances unchanged')


if __name__ == '__main__':
    main()
