import hashlib
import hmac
import json
import os
import tempfile
import threading
import time
import urllib.error
import urllib.request


_temp_dir = tempfile.TemporaryDirectory(prefix='leaf-lore-credit-test-')
os.environ['DB_TYPE'] = 'sqlite'
os.environ['BOOKEXCHANGE_DB_PATH'] = os.path.join(_temp_dir.name, 'credit-test.db')
os.environ['API_TOKEN_SECRET'] = 'credit-purchase-test-token-secret'
os.environ['RAZORPAY_KEY_ID'] = 'rzp_test_example'
os.environ['RAZORPAY_KEY_SECRET'] = 'test-key-secret-placeholder'
os.environ['RAZORPAY_WEBHOOK_SECRET'] = 'webhook-secret-placeholder'

import sys
sys.path.insert(0, os.path.dirname(__file__))

import services.credit_purchase_service as purchase_service
from db import db_connection, ensure_schema
from http.server import ThreadingHTTPServer
from server import APIHandler


ensure_schema()
_orders = {}
_payments = {}
_order_counter = 0


def fake_create_order(package, purchase_id):
    global _order_counter
    _order_counter += 1
    order = {
        'id': f'order_test_{_order_counter}',
        'amount': package['amount_minor'],
        'currency': package['currency'],
        'receipt': purchase_id,
        'status': 'created',
        'notes': {'purchase_id': purchase_id, 'package_id': package['id']},
    }
    _orders[order['id']] = order
    return order


def fake_fetch_payment(payment_id):
    return _payments[payment_id]


purchase_service._razorpay_create_order = fake_create_order
purchase_service._razorpay_fetch_payment = fake_fetch_payment
http_server = ThreadingHTTPServer(('127.0.0.1', 0), APIHandler)
thread = threading.Thread(target=http_server.serve_forever, daemon=True)
thread.start()
base_url = f'http://127.0.0.1:{http_server.server_address[1]}'


def request(method, path, body=None, token=None, idempotency_key=None):
    data = None if body is None else json.dumps(body).encode('utf-8')
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    if idempotency_key:
        headers['Idempotency-Key'] = idempotency_key
    req = urllib.request.Request(base_url + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode('utf-8'))


def register(label):
    status, result = request('POST', '/auth/register', {
        'name': label,
        'email': f'{label.lower()}-{time.time_ns()}@example.test',
        'password': 'SecurePassword123!',
    })
    assert status == 201, result
    return result['token'], result['user']


def signed_webhook(event):
    payload = json.dumps(event, separators=(',', ':')).encode('utf-8')
    signature = hmac.new(
        b'webhook-secret-placeholder', payload, hashlib.sha256
    ).hexdigest()
    return payload, signature


def post_webhook(event, forged=False):
    payload, signature = signed_webhook(event)
    if forged:
        signature = 'forged-signature'
    req = urllib.request.Request(
        base_url + '/webhooks/razorpay',
        data=payload,
        headers={
            'Content-Type': 'application/json',
            'X-Razorpay-Signature': signature,
        },
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode('utf-8'))


def paid_event(order, payment):
    paid_order = {**order, 'status': 'paid'}
    captured_payment = {
        **payment,
        'order_id': order['id'],
        'amount': order['amount'],
        'currency': order['currency'],
        'status': 'captured',
        'captured': True,
    }
    return {
        'event': 'order.paid',
        'payload': {
            'order': {'entity': paid_order},
            'payment': {'entity': captured_payment},
        },
    }


def create_order(token, package_id, request_id=None, **client_fields):
    return request(
        'POST',
        '/credit-purchases',
        {'package_id': package_id, **client_fields},
        token=token,
        idempotency_key=request_id or f'test-{time.time_ns()}',
    )


def assert_balance(token, expected):
    status, account = request('GET', '/credits', token=token)
    assert status == 200 and account['balance'] == expected, account
    return account


try:
    token_a, user_a = register('Credit Buyer')
    token_b, _ = register('Other Reader')

    status, login_result = request('POST', '/auth/login', {
        'email': user_a['email'],
        'password': 'SecurePassword123!',
    })
    assert status == 200 and login_result['token'] != token_a

    conn = db_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT COUNT(*) AS total FROM profiles "
        "WHERE id IN (%s, %s)",
        ('user-community-steward-1', 'user-marcus-vance-2'),
    )
    removed_seed_accounts = cur.fetchone()['total']
    cur.close()
    conn.close()
    assert removed_seed_accounts == 0, 'Bundled starter accounts were created'

    logout_token, _ = register('Logout Reader')
    status, _ = request('POST', '/auth/logout', token=logout_token)
    assert status == 200
    status, _ = request('GET', '/credits', token=logout_token)
    assert status == 401, 'A revoked session still accessed a protected endpoint'

    inactive_token, inactive_user = register('Inactive Reader')
    conn = db_connection()
    cur = conn.cursor()
    cur.execute("UPDATE profiles SET is_active = 0 WHERE id = %s", (inactive_user['id'],))
    conn.commit()
    cur.close()
    conn.close()
    status, _ = request('GET', '/credits', token=inactive_token)
    assert status == 401, 'A disabled account still accessed a protected endpoint'

    status, catalog = request('GET', '/credit-packages')
    assert status == 200 and catalog['payments_enabled'] is True
    package = next(item for item in catalog['packages'] if item['id'] == 'popular')
    assert package['credits'] == 250 and package['amount_minor'] == 9900
    status, _ = create_order('', 'popular')
    assert status == 401, 'Unauthenticated purchase was accepted'
    status, invalid = create_order(token_a, 'does-not-exist')
    assert status == 400 and 'package' in invalid['message'].lower()

    status, order_response = create_order(
        token_a,
        'popular',
        request_id='popular-order-retry-key',
        credits=999999,
        amount_minor=1,
        currency='USD',
    )
    assert status == 201, order_response
    assert order_response['credits'] == 250
    assert order_response['amount'] == 9900
    assert order_response['currency'] == 'INR'
    assert order_response['key_id'] == 'rzp_test_example'
    assert 'key_secret' not in order_response
    purchase_id = order_response['id']
    provider_order = _orders[order_response['order_id']]

    status, retry = create_order(token_a, 'popular', request_id='popular-order-retry-key')
    assert status == 201 and retry['id'] == purchase_id and retry['idempotent'] is True
    assert retry['order_id'] == order_response['order_id']
    status, mismatch = create_order(token_a, 'starter', request_id='popular-order-retry-key')
    assert status == 400 and 'another package' in mismatch['message']
    assert_balance(token_a, 15)

    payment = {'id': 'pay_test_1'}
    event = paid_event(provider_order, payment)
    status, _ = post_webhook(event, forged=True)
    assert status == 400
    bad_amount = json.loads(json.dumps(event))
    bad_amount['payload']['payment']['entity']['amount'] = 1
    status, _ = post_webhook(bad_amount)
    assert status == 400
    bad_currency = json.loads(json.dumps(event))
    bad_currency['payload']['order']['entity']['currency'] = 'USD'
    status, _ = post_webhook(bad_currency)
    assert status == 400
    bad_package = json.loads(json.dumps(event))
    bad_package['payload']['order']['entity']['notes']['package_id'] = 'starter'
    status, _ = post_webhook(bad_package)
    assert status == 400
    assert_balance(token_a, 15)

    status, result = post_webhook(event)
    assert status == 200 and result['status'] == 'completed'
    account = assert_balance(token_a, 265)
    assert account['summary']['purchased'] == 250
    status, result = post_webhook(event)
    assert status == 200 and result['idempotent'] is True
    assert_balance(token_a, 265)

    callback_signature = hmac.new(
        b'test-key-secret-placeholder',
        f"{provider_order['id']}|{payment['id']}".encode(),
        hashlib.sha256,
    ).hexdigest()
    _payments[payment['id']] = {
        'id': payment['id'],
        'order_id': provider_order['id'],
        'amount': 9900,
        'currency': 'INR',
        'status': 'captured',
    }
    status, callback_result = request('POST', '/credit-purchases/verify', {
        'purchase_id': purchase_id,
        'razorpay_order_id': provider_order['id'],
        'razorpay_payment_id': payment['id'],
        'razorpay_signature': callback_signature,
    }, token=token_a)
    assert status == 200 and callback_result['idempotent'] is True
    status, _ = request('POST', '/credit-purchases/verify', {
        'purchase_id': purchase_id,
        'razorpay_order_id': provider_order['id'],
        'razorpay_payment_id': payment['id'],
        'razorpay_signature': 'forged',
    }, token=token_a)
    assert status == 400
    assert_balance(token_a, 265)

    conn = db_connection()
    cur = conn.cursor()
    cur.execute(
        'SELECT COUNT(*) AS total FROM credit_ledger '
        'WHERE user_id = %s AND type = %s AND reference_id = %s',
        (user_a['id'], 'credit_purchase', purchase_id),
    )
    assert cur.fetchone()['total'] == 1, 'Purchase must create exactly one ledger record'
    cur.close()
    conn.close()

    status, first_page = request('GET', '/credits?limit=1', token=token_a)
    assert status == 200 and len(first_page['ledger']) == 1
    assert first_page['has_more'] is True and first_page['next_cursor']
    status, second_page = request(
        'GET',
        f"/credits?limit=1&cursor={first_page['next_cursor']}",
        token=token_a,
    )
    assert status == 200 and len(second_page['ledger']) == 1
    assert first_page['ledger'][0]['id'] != second_page['ledger'][0]['id']
    assert second_page['has_more'] is False
    status, _ = request('GET', '/credits?limit=101', token=token_a)
    assert status == 400
    status, _ = request('GET', f"/credits?limit={'9' * 5000}", token=token_a)
    assert status == 400
    status, _ = request('GET', '/credits?cursor=invalid-cursor', token=token_a)
    assert status == 400

    failed_status = {
        'event': 'payment.failed',
        'payload': {'order': {'entity': {}}, 'payment': {'entity': {}}},
    }
    status, result = post_webhook(failed_status)
    assert status == 200 and result['status'] == 'ignored'
    assert_balance(token_a, 265)

    status, history = request('GET', '/credit-purchases', token=token_a)
    assert status == 200 and len(history['purchases']) == 1
    status, _ = request('GET', f'/credit-purchases/{purchase_id}', token=token_b)
    assert status == 404
    status, other_history = request('GET', '/credit-purchases', token=token_b)
    assert status == 200 and other_history['purchases'] == []

    config_names = ('RAZORPAY_KEY_ID', 'RAZORPAY_KEY_SECRET', 'RAZORPAY_WEBHOOK_SECRET')
    saved_config = {name: os.environ.pop(name) for name in config_names}
    status, _ = create_order(token_a, 'starter')
    assert status == 503
    for name, value in saved_config.items():
        os.environ[name] = value
    os.environ['RAZORPAY_KEY_ID'] = 'rzp_live_not_allowed'
    assert purchase_service.payment_is_configured() is False
    status, _ = create_order(token_a, 'starter')
    assert status == 503
    assert_balance(token_a, 265)

    print('SUCCESS: Razorpay purchase security and lifecycle tests passed.')
    print('Verified test-key gating, auth, server pricing, signed webhook, callback verification, mismatches, idempotency, one ledger award, and purchase ownership.')
finally:
    http_server.shutdown()
    http_server.server_close()
    thread.join(timeout=5)
    _temp_dir.cleanup()