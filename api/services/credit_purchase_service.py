import base64
import hashlib
import hmac
import json
import os
import uuid
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


PACKAGES = (
    {'id': 'starter', 'name': 'Starter', 'credits': 100, 'amount_minor': 4900, 'currency': 'INR', 'popular': False},
    {'id': 'popular', 'name': 'Popular', 'credits': 250, 'amount_minor': 9900, 'currency': 'INR', 'popular': True},
    {'id': 'value', 'name': 'Value', 'credits': 500, 'amount_minor': 17900, 'currency': 'INR', 'popular': False},
    {'id': 'premium', 'name': 'Premium', 'credits': 1000, 'amount_minor': 29900, 'currency': 'INR', 'popular': False},
)


class PaymentUnavailable(Exception):
    pass


def get_packages():
    raw = os.getenv('CREDIT_PACKAGES_JSON')
    if not raw:
        return [dict(package) for package in PACKAGES]
    try:
        packages = json.loads(raw)
        if not isinstance(packages, list):
            raise ValueError
        validated = []
        for item in packages:
            package = {
                'id': str(item['id']),
                'name': str(item['name']),
                'credits': int(item['credits']),
                'amount_minor': int(item['amount_minor']),
                'currency': str(item['currency']).upper(),
                'popular': bool(item.get('popular', False)),
            }
            if not package['id'] or package['credits'] < 1 or package['amount_minor'] < 1:
                raise ValueError
            validated.append(package)
        if len({item['id'] for item in validated}) != len(validated):
            raise ValueError
        return validated
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        raise ValueError('CREDIT_PACKAGES_JSON must contain valid package definitions.') from error


def payment_is_configured():
    key_id = os.getenv('RAZORPAY_KEY_ID', '').strip()
    key_secret = os.getenv('RAZORPAY_KEY_SECRET', '').strip()
    webhook_secret = os.getenv('RAZORPAY_WEBHOOK_SECRET', '').strip()
    return key_id.startswith('rzp_test_') and bool(key_secret) and bool(webhook_secret)


def get_package(package_id):
    return next((item for item in get_packages() if item['id'] == package_id), None)


def list_purchases(conn, user_id):
    cur = conn.cursor()
    cur.execute(
        'SELECT id, package_id, credits, amount_minor, currency, payment_provider, '
        'payment_reference, status, created_at, completed_at '
        'FROM credit_purchases WHERE user_id = %s ORDER BY created_at DESC LIMIT 100',
        (user_id,),
    )
    purchases = cur.fetchall()
    cur.close()
    for purchase in purchases:
        package = get_package(purchase['package_id'])
        purchase['package_name'] = package['name'] if package else purchase['package_id'].title()
        purchase['checkout_key_id'] = (
            os.getenv('RAZORPAY_KEY_ID')
            if purchase['payment_provider'] == 'razorpay'
            and purchase['status'] == 'processing'
            and payment_is_configured()
            else None
        )
    return purchases


def get_purchase(conn, user_id, purchase_id):
    cur = conn.cursor()
    cur.execute(
        'SELECT id, package_id, credits, amount_minor, currency, payment_provider, '
        'payment_reference, status, created_at, completed_at '
        'FROM credit_purchases WHERE id = %s AND user_id = %s',
        (purchase_id, user_id),
    )
    purchase = cur.fetchone()
    cur.close()
    if purchase:
        package = get_package(purchase['package_id'])
        purchase['package_name'] = package['name'] if package else purchase['package_id'].title()
        purchase['checkout_key_id'] = (
            os.getenv('RAZORPAY_KEY_ID')
            if purchase['payment_provider'] == 'razorpay'
            and purchase['status'] == 'processing'
            and payment_is_configured()
            else None
        )
    return purchase


def _existing_request(conn, user_id, request_id):
    cur = conn.cursor()
    cur.execute(
        'SELECT id, package_id, credits, amount_minor, currency, payment_provider, '
        'status, payment_reference FROM credit_purchases '
        'WHERE user_id = %s AND client_request_id = %s',
        (user_id, request_id),
    )
    purchase = cur.fetchone()
    cur.close()
    return purchase


def _create_pending_purchase(conn, user_id, package, request_id):
    purchase_id = str(uuid.uuid4())
    cur = conn.cursor()
    cur.execute(
        'INSERT INTO credit_purchases '
        '(id, user_id, client_request_id, package_id, credits, amount_minor, currency, payment_provider, status) '
        "VALUES (%s, %s, %s, %s, %s, %s, %s, 'razorpay', 'pending')",
        (purchase_id, user_id, request_id, package['id'], package['credits'],
         package['amount_minor'], package['currency']),
    )
    conn.commit()
    cur.close()
    return purchase_id


def _set_purchase_status(conn, purchase_id, status, payment_reference=None, checkout_url=None):
    cur = conn.cursor()
    if payment_reference is None:
        cur.execute(
            'UPDATE credit_purchases SET status = %s WHERE id = %s AND status = %s',
            (status, purchase_id, 'pending'),
        )
    else:
        cur.execute(
            'UPDATE credit_purchases SET status = %s, payment_reference = %s, checkout_url = %s '
            'WHERE id = %s AND status = %s',
            (status, payment_reference, checkout_url, purchase_id, 'pending'),
        )
    conn.commit()
    cur.close()


def _razorpay_create_order(package, purchase_id):
    payload = {
        'amount': package['amount_minor'],
        'currency': package['currency'],
        'receipt': purchase_id[:40],
        'notes': {'purchase_id': purchase_id, 'package_id': package['id']},
    }
    credentials = base64.b64encode(
        f"{os.environ['RAZORPAY_KEY_ID']}:{os.environ['RAZORPAY_KEY_SECRET']}".encode()
    ).decode()
    request = Request(
        'https://api.razorpay.com/v1/orders',
        data=json.dumps(payload).encode(),
        headers={
            'Authorization': f'Basic {credentials}',
            'Content-Type': 'application/json',
        },
        method='POST',
    )
    try:
        with urlopen(request, timeout=20) as response:
            result = json.loads(response.read().decode())
    except (HTTPError, URLError, TimeoutError, OSError, ValueError) as error:
        raise RuntimeError('Unable to create a Razorpay order.') from error
    if (not result.get('id') or result.get('amount') != package['amount_minor']
            or result.get('currency') != package['currency'] or result.get('status') != 'created'):
        raise RuntimeError('Razorpay returned an invalid order.')
    return result


def create_purchase(conn, user_id, package_id, request_id):
    if not request_id or len(request_id) > 128:
        raise ValueError('A valid idempotency key is required.')

    existing = _existing_request(conn, user_id, request_id)
    if existing:
        if existing['package_id'] != package_id:
            raise ValueError('This idempotency key was already used for another package.')
        if existing['status'] == 'processing' and existing['payment_reference']:
            if existing['payment_provider'] != 'razorpay':
                raise ValueError('This pending purchase belongs to another payment provider.')
            if not payment_is_configured():
                raise PaymentUnavailable('Razorpay TEST MODE is not configured on the backend.')
            return {
                'id': existing['id'],
                'status': existing['status'],
                'order_id': existing['payment_reference'],
                'key_id': os.getenv('RAZORPAY_KEY_ID'),
                'credits': existing['credits'],
                'amount': existing['amount_minor'],
                'amount_minor': existing['amount_minor'],
                'currency': existing['currency'],
                'package_name': (get_package(package_id) or {}).get('name', package_id.title()),
                'idempotent': True,
            }
        if existing['status'] == 'completed':
            return {
                'id': existing['id'],
                'status': 'completed',
                'credits': existing['credits'],
                'amount_minor': existing['amount_minor'],
                'currency': existing['currency'],
                'package_name': (get_package(package_id) or {}).get('name', package_id.title()),
                'idempotent': True,
            }
        raise ValueError(f"This purchase request is already {existing['status']}.")

    package = get_package(package_id)
    if not package:
        raise ValueError('Credit package not found or no longer available.')
    if not payment_is_configured():
        raise PaymentUnavailable('Payments are unavailable. Configure Razorpay TEST MODE keys on the backend.')

    purchase_id = _create_pending_purchase(conn, user_id, package, request_id)
    try:
        order = _razorpay_create_order(package, purchase_id)
        _set_purchase_status(conn, purchase_id, 'processing', order['id'])
    except Exception:
        _set_purchase_status(conn, purchase_id, 'failed')
        raise

    return {
        'id': purchase_id,
        'status': 'processing',
        'order_id': order['id'],
        'key_id': os.environ['RAZORPAY_KEY_ID'],
        'credits': package['credits'],
        'amount': package['amount_minor'],
        'amount_minor': package['amount_minor'],
        'currency': package['currency'],
        'package_name': package['name'],
    }


def _razorpay_fetch_payment(payment_id):
    credentials = base64.b64encode(
        f"{os.environ['RAZORPAY_KEY_ID']}:{os.environ['RAZORPAY_KEY_SECRET']}".encode()
    ).decode()
    request = Request(
        f'https://api.razorpay.com/v1/payments/{payment_id}',
        headers={'Authorization': f'Basic {credentials}', 'Accept': 'application/json'},
    )
    try:
        with urlopen(request, timeout=20) as response:
            return json.loads(response.read().decode())
    except (HTTPError, URLError, TimeoutError, OSError, ValueError) as error:
        raise RuntimeError('Unable to verify payment with Razorpay.') from error


def _settle_purchase(conn, purchase_id):
    if conn.db_type == 'sqlite':
        conn.begin(immediate=True)
    cur = conn.cursor()
    cur.execute('SELECT * FROM credit_purchases WHERE id = %s FOR UPDATE', (purchase_id,))
    purchase = cur.fetchone()
    if not purchase:
        cur.close()
        raise ValueError('Purchase not found.')
    if purchase['status'] == 'completed':
        cur.close()
        return {'status': 'completed', 'idempotent': True}
    if purchase['status'] not in ('pending', 'processing'):
        cur.close()
        return {'status': purchase['status'], 'idempotent': True}

    cur.execute(
        'UPDATE credit_purchases SET status = %s WHERE id = %s AND status IN (%s, %s)',
        ('completed', purchase_id, 'pending', 'processing'),
    )
    if cur.rowcount != 1:
        conn.rollback()
        cur.close()
        return {'status': 'completed', 'idempotent': True}
    cur.execute(
        'UPDATE credit_accounts SET balance = balance + %s WHERE user_id = %s',
        (purchase['credits'], purchase['user_id']),
    )
    if cur.rowcount != 1:
        conn.rollback()
        cur.close()
        raise ValueError('Credit account not found for purchase.')
    cur.execute(
        'INSERT INTO credit_ledger (id, user_id, amount, type, reference_id, description) '
        'VALUES (%s, %s, %s, %s, %s, %s)',
        (str(uuid.uuid4()), purchase['user_id'], purchase['credits'], 'credit_purchase',
         purchase_id, f"Purchased {purchase['credits']} Leaf & Lore Credits"),
    )
    if conn.db_type == 'mysql':
        cur.execute('UPDATE credit_purchases SET completed_at = NOW() WHERE id = %s', (purchase_id,))
    else:
        cur.execute("UPDATE credit_purchases SET completed_at = datetime('now') WHERE id = %s", (purchase_id,))
    conn.commit()
    cur.close()
    return {'status': 'completed', 'idempotent': False}


def verify_razorpay_payment(conn, user_id, purchase_id, order_id, payment_id, signature):
    if not payment_is_configured():
        raise PaymentUnavailable('Razorpay TEST MODE is not configured on the backend.')
    cur = conn.cursor()
    cur.execute(
        'SELECT * FROM credit_purchases WHERE id = %s AND user_id = %s',
        (purchase_id, user_id),
    )
    purchase = cur.fetchone()
    cur.close()
    if not purchase or purchase['payment_provider'] != 'razorpay':
        raise ValueError('Purchase not found.')
    if purchase['payment_reference'] != order_id:
        raise ValueError('Razorpay order does not match this purchase.')
    signed_data = f'{order_id}|{payment_id}'.encode()
    expected = hmac.new(
        os.environ['RAZORPAY_KEY_SECRET'].encode(), signed_data, hashlib.sha256
    ).hexdigest()
    if not signature or not hmac.compare_digest(expected, signature):
        raise PermissionError('Invalid Razorpay payment signature.')

    payment = _razorpay_fetch_payment(payment_id)
    if (payment.get('order_id') != order_id
            or payment.get('status') != 'captured'
            or int(payment.get('amount', -1)) != purchase['amount_minor']
            or str(payment.get('currency', '')).upper() != purchase['currency'].upper()):
        raise ValueError('Razorpay payment could not be verified against the purchase.')
    result = _settle_purchase(conn, purchase_id)
    result['purchase_id'] = purchase_id
    return result


def process_razorpay_webhook(conn, payload, signature_header, secret=None):
    if not payment_is_configured():
        raise PermissionError('Razorpay TEST MODE configuration is unavailable.')
    webhook_secret = secret or os.getenv('RAZORPAY_WEBHOOK_SECRET', '')
    expected = hmac.new(webhook_secret.encode(), payload, hashlib.sha256).hexdigest()
    if not signature_header or not hmac.compare_digest(expected, signature_header):
        raise PermissionError('Invalid Razorpay webhook signature.')
    try:
        event = json.loads(payload.decode('utf-8'))
        event_type = event['event']
    except (ValueError, KeyError, TypeError) as error:
        raise ValueError('Invalid Razorpay webhook event.') from error
    if event_type != 'order.paid':
        return {'status': 'ignored'}
    try:
        order = event['payload']['order']['entity']
        payment = event['payload']['payment']['entity']
        order_id = order['id']
    except (KeyError, TypeError) as error:
        raise ValueError('Razorpay order.paid event is incomplete.') from error

    cur = conn.cursor()
    cur.execute(
        'SELECT * FROM credit_purchases '
        'WHERE payment_provider = %s AND payment_reference = %s FOR UPDATE',
        ('razorpay', order_id),
    )
    purchase = cur.fetchone()
    cur.close()
    if not purchase:
        raise ValueError('Razorpay order not found.')
    notes = order.get('notes') or {}
    if (order.get('receipt') != purchase['id']
            or notes.get('purchase_id') != purchase['id']
            or notes.get('package_id') != purchase['package_id']):
        raise ValueError('Razorpay order does not match this purchase.')
    try:
        amounts_match = (
            int(order.get('amount', -1)) == purchase['amount_minor']
            and int(payment.get('amount', -1)) == purchase['amount_minor']
        )
    except (TypeError, ValueError):
        amounts_match = False
    currencies_match = (
        str(order.get('currency', '')).upper() == purchase['currency'].upper()
        and str(payment.get('currency', '')).upper() == purchase['currency'].upper()
    )
    if (order.get('status') != 'paid'
            or payment.get('order_id') != order_id
            or payment.get('status') != 'captured'
            or not amounts_match
            or not currencies_match):
        raise ValueError('Razorpay payment does not match the stored purchase amount/currency.')
    result = _settle_purchase(conn, purchase['id'])
    result['purchase_id'] = purchase['id']
    return result