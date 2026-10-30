import os
import sys
import tempfile

_test_database = tempfile.TemporaryDirectory(prefix='leaf-lore-marketplace-test-')
os.environ['DB_TYPE'] = 'sqlite'
os.environ['BOOKEXCHANGE_DB_PATH'] = os.path.join(
    _test_database.name, 'marketplace-test.db'
)
sys.path.insert(0, os.path.dirname(__file__))

from db import db_connection, ensure_schema
from services.marketplace_service import (
    confirm_delivery,
    create_marketplace_order,
    set_shipping,
)

ensure_schema()

buyer_id = 'buyer-1'
seller_id = 'seller-1'
other_buyer_id = 'buyer-2'
listing_id = 'listing-1'
insufficient_listing_id = 'listing-2'
overpriced_listing_id = 'listing-3'
conn = db_connection()
cur = conn.cursor()
for user_id, email in (
    (buyer_id, 'buyer@example.com'),
    (seller_id, 'seller@example.com'),
    (other_buyer_id, 'other@example.com'),
):
    cur.execute(
        'INSERT INTO profiles (id, display_name, email) VALUES (%s, %s, %s)',
        (user_id, user_id, email),
    )
for user_id, balance in ((buyer_id, 20), (seller_id, 0), (other_buyer_id, 5)):
    cur.execute(
        'INSERT INTO credit_accounts (user_id, balance) VALUES (%s, %s)',
        (user_id, balance),
    )
for book_id, owner_id, title, price in (
    (listing_id, seller_id, 'A Marketplace Book', 10),
    (insufficient_listing_id, seller_id, 'A Book Beyond Budget', 10),
    (overpriced_listing_id, seller_id, 'An Overpriced Book', 21),
):
    cur.execute(
        "INSERT INTO exchange_listings "
        "(id, owner_id, title, author, category, book_condition, description, "
        "credit_value, status) "
        "VALUES (%s, %s, %s, 'A. Author', 'Fiction', 'Good', 'Book details here', %s, 'available')",
        (book_id, owner_id, title, price),
    )
conn.commit()
cur.close()
conn.close()

address = {
    'recipient_name': 'Reader One',
    'recipient_phone': '+1 555 555 0123',
    'address_line1': '123 Book Street',
    'address_line2': '',
    'city': 'Reading',
    'region': 'CA',
    'postal_code': '90210',
    'country': 'US',
}
conn = db_connection()
order_id = create_marketplace_order(
    conn, buyer_id, listing_id, address, 'request-key-1'
)
assert create_marketplace_order(
    conn, buyer_id, listing_id, address, 'request-key-1'
) == order_id, 'Retrying the same request must not create another order.'
try:
    create_marketplace_order(
        conn,
        buyer_id,
        listing_id,
        {**address, 'city': 'Different City'},
        'request-key-1',
    )
except ValueError as error:
    assert 'already used' in str(error)
else:
    raise AssertionError('Reusing an idempotency key with different data must fail.')

cur = conn.cursor()
cur.execute('SELECT balance FROM credit_accounts WHERE user_id = %s', (buyer_id,))
assert cur.fetchone()['balance'] == 10
cur.execute('SELECT balance FROM credit_accounts WHERE user_id = %s', (seller_id,))
assert cur.fetchone()['balance'] == 10
cur.execute('SELECT status FROM exchange_listings WHERE id = %s', (listing_id,))
assert cur.fetchone()['status'] == 'sold'
cur.close()

try:
    create_marketplace_order(
        conn,
        other_buyer_id,
        insufficient_listing_id,
        address,
        'request-key-2',
    )
except ValueError as error:
    assert 'enough credits' in str(error)
else:
    raise AssertionError('A buyer with insufficient credits must not place an order.')
cur = conn.cursor()
cur.execute(
    'SELECT status FROM exchange_listings WHERE id = %s',
    (insufficient_listing_id,),
)
assert cur.fetchone()['status'] == 'available'
cur.close()

try:
    create_marketplace_order(
        conn,
        buyer_id,
        overpriced_listing_id,
        address,
        'request-key-3',
    )
except ValueError as error:
    assert 'between 1 and 20 credits' in str(error)
else:
    raise AssertionError('A book priced above 20 credits must not be purchased.')

try:
    set_shipping(conn, buyer_id, order_id, 'Postal Service', 'TRACK123')
except PermissionError:
    pass
else:
    raise AssertionError('Only the seller may update shipping details.')

set_shipping(conn, seller_id, order_id, 'Postal Service', 'TRACK123')
try:
    confirm_delivery(conn, seller_id, order_id)
except PermissionError:
    pass
else:
    raise AssertionError('Only the buyer may confirm delivery.')

confirm_delivery(conn, buyer_id, order_id)
cur = conn.cursor()
cur.execute(
    'SELECT status, shipping_carrier, tracking_number FROM marketplace_orders '
    'WHERE id = %s',
    (order_id,),
)
order = cur.fetchone()
assert order['status'] == 'delivered'
assert order['shipping_carrier'] == 'Postal Service'
assert order['tracking_number'] == 'TRACK123'
cur.close()
conn.close()
_test_database.cleanup()

print('Marketplace order and credit transfer tests passed.')
