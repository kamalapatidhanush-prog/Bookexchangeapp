import json
import os
import sys
import tempfile
import time
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from threading import Thread

_test_database = tempfile.TemporaryDirectory(prefix='leaf-lore-marketplace-api-test-')
os.environ['DB_TYPE'] = 'sqlite'
os.environ['BOOKEXCHANGE_DB_PATH'] = os.path.join(
    _test_database.name, 'marketplace-api-test.db'
)
os.environ['API_TOKEN_SECRET'] = 'marketplace-api-test-secret-at-least-32-chars'
sys.path.insert(0, os.path.dirname(__file__))

from db import ensure_schema
from server import APIHandler

ensure_schema()
http_server = ThreadingHTTPServer(('127.0.0.1', 0), APIHandler)
Thread(target=http_server.serve_forever, daemon=True).start()
BASE_URL = f'http://127.0.0.1:{http_server.server_address[1]}'


def request(method, path, body=None, token=None, extra_headers=None):
    data = None if body is None else json.dumps(body).encode('utf-8')
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    if extra_headers:
        headers.update(extra_headers)
    req = urllib.request.Request(
        BASE_URL + path,
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status, json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode('utf-8'))


def register(name):
    email = f'{name.lower().replace(" ", "")}-{time.time_ns()}@example.test'
    status, result = request('POST', '/auth/register', {
        'name': name,
        'email': email,
        'password': 'SecurePassword123!',
        'location': 'Greenwich Circle',
    })
    assert status == 201, f'Failed to register {name}: {result}'
    return result['token'], result['user']


def get_balance(token):
    status, result = request('GET', '/credits', token=token)
    assert status == 200, result
    return result['balance']


print('--- Running Leaf & Lore Marketplace API Integration Test ---')

seller_token, seller = register('Alice Seller')
buyer_token, buyer = register('Bob Buyer')
outsider_token, _ = register('Casey Reader')

status, duplicate = request('POST', '/auth/register', {
    'name': 'Duplicate Alice',
    'email': seller['email'],
    'password': 'SecurePassword123!',
})
assert status == 409, f'Duplicate registration was not rejected: {status}'
status, _ = request('POST', '/auth/login', body=['not', 'an', 'object'])
assert status == 400, f'Non-object JSON body was not rejected: {status}'
status, _ = request('GET', '/credits')
assert status == 401, f'Unauthenticated wallet request was accepted: {status}'
status, _ = request('GET', '/admin/stats', token=seller_token)
assert status == 403, f'Member accessed the admin endpoint: {status}'

status, legacy = request(
    'POST',
    '/exchanges/request',
    {'listing_id': 'legacy-listing'},
    token=buyer_token,
)
assert status == 410, f'In-person exchange endpoint was not retired: {legacy}'
status, legacy = request('GET', '/exchanges', token=buyer_token)
assert status == 410, f'In-person exchange history was not retired: {legacy}'
status, legacy = request(
    'POST',
    '/borrow',
    {'book_id': 'legacy-book'},
    token=buyer_token,
)
assert status == 410, f'Library borrowing endpoint was not retired: {legacy}'

status, listing_error = request('POST', '/listings', {
    'title': 'Invalid price',
    'author': 'Test Author',
    'description': 'Invalid prices must be rejected.',
    'credit_value': '10',
}, token=seller_token)
assert status == 400, f'Invalid listing price was accepted: {listing_error}'
status, listing_error = request('POST', '/listings', {
    'title': 'Overpriced listing',
    'author': 'Test Author',
    'description': 'Listings must stay within the 20-credit maximum.',
    'credit_value': 21,
}, token=seller_token)
assert status == 400, f'A listing over 20 credits was accepted: {listing_error}'
status, maximum_price_listing = request('POST', '/listings', {
    'title': 'Maximum price listing',
    'author': 'Test Author',
    'description': 'A listing at the allowed 20-credit maximum.',
    'credit_value': 20,
}, token=seller_token)
assert status == 201, f'A listing at 20 credits was rejected: {maximum_price_listing}'

listing_title = f'The Marketplace Book {time.time_ns()}'
status, listing = request('POST', '/listings', {
    'title': listing_title,
    'author': 'A. Author',
    'category': 'Fiction',
    'condition': 'Like New',
    'description': 'A well-kept copy ready for its next reader.',
    'credit_value': 10,
}, token=seller_token)
assert status == 201, f'Listing failed: {listing}'
listing_id = listing['id']
assert get_balance(seller_token) == 15, 'Creating a listing must not mint credits.'

address = {
    'recipient_name': 'Bob Buyer',
    'recipient_phone': '+1 555 555 0123',
    'address_line1': '123 Book Street',
    'address_line2': '',
    'city': 'Reading',
    'region': 'CA',
    'postal_code': '90210',
    'country': 'US',
}
status, missing_key = request(
    'POST',
    '/marketplace/orders',
    {'listing_id': listing_id, 'shipping_address': address},
    token=buyer_token,
)
assert status == 409, f'An order without an idempotency key was accepted: {missing_key}'

request_key = 'marketplace-purchase-test-1'
status, order = request(
    'POST',
    '/marketplace/orders',
    {'listing_id': listing_id, 'shipping_address': address},
    token=buyer_token,
    extra_headers={'Idempotency-Key': request_key},
)
assert status == 201 and order['status'] == 'paid', f'Purchase failed: {order}'
order_id = order['id']
assert get_balance(buyer_token) == 5
assert get_balance(seller_token) == 25

status, retry = request(
    'POST',
    '/marketplace/orders',
    {'listing_id': listing_id, 'shipping_address': address},
    token=buyer_token,
    extra_headers={'Idempotency-Key': request_key},
)
assert status == 201 and retry['id'] == order_id, 'Order retry created a duplicate.'
assert get_balance(buyer_token) == 5 and get_balance(seller_token) == 25

status, second_purchase = request(
    'POST',
    '/marketplace/orders',
    {'listing_id': listing_id, 'shipping_address': address},
    token=outsider_token,
    extra_headers={'Idempotency-Key': 'second-purchase-test'},
)
assert status == 409, f'A sold listing was purchased twice: {second_purchase}'

status, buyer_orders = request('GET', '/marketplace/orders', token=buyer_token)
assert status == 200 and len(buyer_orders['orders']) == 1
assert buyer_orders['orders'][0]['address_line1'] == address['address_line1']
status, outsider_orders = request('GET', '/marketplace/orders', token=outsider_token)
assert status == 200 and outsider_orders['orders'] == []

status, _ = request(
    'POST',
    f'/marketplace/orders/{order_id}/ship',
    {'shipping_carrier': 'Postal Service', 'tracking_number': 'TRACK123'},
    token=buyer_token,
)
assert status == 403, 'A buyer was allowed to ship the order.'
status, _ = request(
    'POST',
    f'/marketplace/orders/{order_id}/delivered',
    token=seller_token,
)
assert status == 403, 'A seller was allowed to confirm delivery.'

status, shipped = request(
    'POST',
    f'/marketplace/orders/{order_id}/ship',
    {'shipping_carrier': 'Postal Service', 'tracking_number': 'TRACK123'},
    token=seller_token,
)
assert status == 200 and shipped['status'] == 'shipped'
status, delivered = request(
    'POST',
    f'/marketplace/orders/{order_id}/delivered',
    token=buyer_token,
)
assert status == 200 and delivered['status'] == 'delivered'
status, buyer_orders = request('GET', '/marketplace/orders', token=buyer_token)
assert status == 200 and buyer_orders['orders'][0]['status'] == 'delivered'
assert buyer_orders['orders'][0]['tracking_number'] == 'TRACK123'
assert buyer_orders['orders'][0]['user_review_id'] is None
status, review = request('POST', '/reviews', {
    'exchange_id': order_id,
    'rating': 5,
    'review': 'The book arrived as described and was shipped promptly.',
}, token=buyer_token)
assert status == 201, f'Order review failed: {review}'
status, duplicate_review = request('POST', '/reviews', {
    'exchange_id': order_id,
    'rating': 5,
    'review': 'A second review should not be allowed.',
}, token=buyer_token)
assert status == 409, f'Duplicate order review was accepted: {duplicate_review}'
status, buyer_orders = request('GET', '/marketplace/orders', token=buyer_token)
assert status == 200 and buyer_orders['orders'][0]['user_review_id'] == review['id']

http_server.shutdown()
http_server.server_close()
_test_database.cleanup()
print('Marketplace API permissions, checkout, credits, and shipping tests passed.')
