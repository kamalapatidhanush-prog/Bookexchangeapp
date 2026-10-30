import re
import uuid

from services.community_service import log_activity, notify


_ADDRESS_FIELDS = {
    'recipient_name': (100, True),
    'recipient_phone': (40, True),
    'address_line1': (255, True),
    'address_line2': (255, False),
    'city': (100, True),
    'region': (100, True),
    'postal_code': (32, True),
    'country': (100, True),
}
MAX_BOOK_PRICE_CREDITS = 20


def _begin_mutation(conn):
    if conn.db_type == 'sqlite':
        conn.begin(immediate=True)


def _validated_address(address):
    if not isinstance(address, dict):
        raise ValueError('A shipping address is required.')

    result = {}
    for field, (max_length, required) in _ADDRESS_FIELDS.items():
        value = address.get(field, '')
        if not isinstance(value, str):
            raise ValueError('Shipping address fields must be text.')
        value = value.strip()
        if required and not value:
            raise ValueError('Please complete all required shipping address fields.')
        if len(value) > max_length:
            raise ValueError(f'{field.replace("_", " ").title()} is too long.')
        result[field] = value or None

    phone = result['recipient_phone']
    phone_digits = re.sub(r'\D', '', phone)
    if (
        not re.fullmatch(r'[+()\d\s.-]+', phone)
        or not 7 <= len(phone_digits) <= 15
    ):
        raise ValueError('Enter a valid phone number for delivery.')
    return result


def create_marketplace_order(conn, buyer_id, listing_id, address, idempotency_key):
    if not isinstance(listing_id, str) or not listing_id.strip():
        raise ValueError('A book listing is required.')
    if not isinstance(idempotency_key, str) or not idempotency_key.strip():
        raise ValueError('An order request key is required.')
    idempotency_key = idempotency_key.strip()
    if len(idempotency_key) > 128:
        raise ValueError('Invalid order request key.')
    address = _validated_address(address)

    _begin_mutation(conn)
    cur = conn.cursor()
    try:
        cur.execute(
            'SELECT * FROM marketplace_orders '
            'WHERE buyer_id = %s AND idempotency_key = %s',
            (buyer_id, idempotency_key),
        )
        existing = cur.fetchone()
        if existing:
            if existing['listing_id'] != listing_id.strip() or any(
                existing[field] != address[field]
                for field in _ADDRESS_FIELDS
            ):
                raise ValueError(
                    'This order request key was already used for different details.'
                )
            conn.commit()
            return existing['id']

        cur.execute(
            'SELECT * FROM exchange_listings WHERE id = %s FOR UPDATE',
            (listing_id.strip(),),
        )
        listing = cur.fetchone()
        if not listing:
            raise ValueError('Book listing not found.')
        if listing['status'] != 'available':
            raise ValueError('This book has already been sold or is unavailable.')
        if listing['owner_id'] == buyer_id:
            raise ValueError('You cannot buy your own book.')

        order_id = str(uuid.uuid4())
        credits = listing['credit_value']
        if (
            isinstance(credits, bool)
            or not isinstance(credits, int)
            or not 1 <= credits <= MAX_BOOK_PRICE_CREDITS
        ):
            raise ValueError(
                f'This listing must be priced between 1 and '
                f'{MAX_BOOK_PRICE_CREDITS} credits.'
            )

        for account_id in sorted((buyer_id, listing['owner_id'])):
            cur.execute(
                'SELECT balance FROM credit_accounts WHERE user_id = %s FOR UPDATE',
                (account_id,),
            )
            if not cur.fetchone():
                raise ValueError('A buyer or seller credit account is unavailable.')

        cur.execute(
            'UPDATE credit_accounts SET balance = balance - %s '
            'WHERE user_id = %s AND balance >= %s',
            (credits, buyer_id, credits),
        )
        if cur.rowcount != 1:
            raise ValueError('You do not have enough credits to buy this book.')
        cur.execute(
            'UPDATE credit_accounts SET balance = balance + %s WHERE user_id = %s',
            (credits, listing['owner_id']),
        )
        if cur.rowcount != 1:
            raise ValueError('The seller credit account is unavailable.')

        cur.execute(
            "INSERT INTO credit_ledger "
            "(id, user_id, amount, type, reference_id, description) "
            "VALUES (%s, %s, %s, 'spent', %s, %s)",
            (
                str(uuid.uuid4()),
                buyer_id,
                -credits,
                order_id,
                f"Purchased '{listing['title']}'",
            ),
        )
        cur.execute(
            "INSERT INTO credit_ledger "
            "(id, user_id, amount, type, reference_id, description) "
            "VALUES (%s, %s, %s, 'earned', %s, %s)",
            (
                str(uuid.uuid4()),
                listing['owner_id'],
                credits,
                order_id,
                f"Sold '{listing['title']}'",
            ),
        )
        cur.execute(
            "INSERT INTO marketplace_orders "
            "(id, listing_id, buyer_id, seller_id, idempotency_key, credits, "
            "status, recipient_name, recipient_phone, address_line1, address_line2, "
            "city, region, postal_code, country) "
            "VALUES (%s, %s, %s, %s, %s, %s, 'paid', %s, %s, %s, %s, %s, %s, %s, %s)",
            (
                order_id,
                listing['id'],
                buyer_id,
                listing['owner_id'],
                idempotency_key,
                credits,
                address['recipient_name'],
                address['recipient_phone'],
                address['address_line1'],
                address['address_line2'],
                address['city'],
                address['region'],
                address['postal_code'],
                address['country'],
            ),
        )
        cur.execute(
            "UPDATE exchange_listings SET status = 'sold' "
            "WHERE id = %s AND status = 'available'",
            (listing['id'],),
        )
        if cur.rowcount != 1:
            raise ValueError('This book is no longer available.')

        cur.execute(
            'SELECT display_name FROM profiles WHERE id = %s',
            (buyer_id,),
        )
        buyer = cur.fetchone()
        buyer_name = buyer['display_name'] if buyer else 'A reader'
        notify(
            cur,
            listing['owner_id'],
            'Book sold',
            f"{buyer_name} purchased '{listing['title']}'. Ship it to the address in your orders.",
            'marketplace_order',
            order_id,
        )
        notify(
            cur,
            buyer_id,
            'Order placed',
            f"Your order for '{listing['title']}' is paid. The seller will ship it to you.",
            'marketplace_order',
            order_id,
        )
        log_activity(
            cur,
            buyer_id,
            'marketplace_purchase',
            f"Bought '{listing['title']}'",
            f'{credits} credits transferred to the seller.',
            order_id,
        )
        log_activity(
            cur,
            listing['owner_id'],
            'marketplace_sale',
            f"Sold '{listing['title']}'",
            f'Earned {credits} credits from a marketplace order.',
            order_id,
        )
        conn.commit()
        return order_id
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()


def set_shipping(conn, seller_id, order_id, carrier, tracking_number):
    if not isinstance(carrier, str) or not carrier.strip() or len(carrier.strip()) > 100:
        raise ValueError('Enter a valid shipping carrier.')
    if (
        not isinstance(tracking_number, str)
        or not tracking_number.strip()
        or len(tracking_number.strip()) > 128
    ):
        raise ValueError('Enter a valid tracking number.')

    _begin_mutation(conn)
    cur = conn.cursor()
    try:
        cur.execute(
            'SELECT o.*, l.title FROM marketplace_orders o '
            'JOIN exchange_listings l ON l.id = o.listing_id '
            'WHERE o.id = %s FOR UPDATE',
            (order_id,),
        )
        order = cur.fetchone()
        if not order:
            raise ValueError('Order not found.')
        if order['seller_id'] != seller_id:
            raise PermissionError('Only the seller can add shipping details.')
        if order['status'] not in ('paid', 'shipped'):
            raise ValueError('Shipping details cannot be changed for this order.')

        cur.execute(
            "UPDATE marketplace_orders SET status = 'shipped', shipping_carrier = %s, "
            "tracking_number = %s, shipped_at = COALESCE(shipped_at, CURRENT_TIMESTAMP) "
            'WHERE id = %s',
            (carrier.strip(), tracking_number.strip(), order_id),
        )
        notify(
            cur,
            order['buyer_id'],
            'Your book has shipped',
            f"'{order['title']}' was marked as shipped with {carrier.strip()}.",
            'marketplace_shipped',
            order_id,
        )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()


def confirm_delivery(conn, buyer_id, order_id):
    _begin_mutation(conn)
    cur = conn.cursor()
    try:
        cur.execute(
            'SELECT o.*, l.title FROM marketplace_orders o '
            'JOIN exchange_listings l ON l.id = o.listing_id '
            'WHERE o.id = %s FOR UPDATE',
            (order_id,),
        )
        order = cur.fetchone()
        if not order:
            raise ValueError('Order not found.')
        if order['buyer_id'] != buyer_id:
            raise PermissionError('Only the buyer can confirm delivery.')
        if order['status'] != 'shipped':
            raise ValueError('Only shipped orders can be marked delivered.')

        cur.execute(
            "UPDATE marketplace_orders SET status = 'delivered', "
            'delivered_at = CURRENT_TIMESTAMP WHERE id = %s',
            (order_id,),
        )
        notify(
            cur,
            order['seller_id'],
            'Order delivered',
            f"The buyer confirmed delivery of '{order['title']}'.",
            'marketplace_delivered',
            order_id,
        )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
