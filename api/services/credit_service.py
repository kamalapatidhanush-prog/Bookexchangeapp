import base64
import binascii
import uuid


def _decode_ledger_cursor(cursor):
    if not cursor:
        return None
    if len(cursor) > 2048:
        raise ValueError('Invalid ledger cursor.')
    try:
        decoded = base64.urlsafe_b64decode(cursor.encode()).decode()
        created_at, entry_id = decoded.split('\n', 1)
    except (binascii.Error, UnicodeDecodeError, ValueError) as error:
        raise ValueError('Invalid ledger cursor.') from error
    if not created_at or not entry_id:
        raise ValueError('Invalid ledger cursor.')
    return created_at, entry_id


def get_credit_account(conn, user_id, limit=50, cursor=None):
    decoded_cursor = _decode_ledger_cursor(cursor)
    cur = conn.cursor()
    cur.execute("SELECT balance, updated_at FROM credit_accounts WHERE user_id = %s", (user_id,))
    row = cur.fetchone()
    if not row:
        cur.execute("INSERT INTO credit_accounts (user_id, balance) VALUES (%s, 10)", (user_id,))
        cur.execute(
            "INSERT INTO credit_ledger (id, user_id, amount, type, description) VALUES (%s, %s, 10, 'welcome', 'Welcome bonus')",
            (str(uuid.uuid4()), user_id)
        )
        conn.commit()
        balance = 10
    else:
        balance = row['balance']

    if decoded_cursor:
        created_at, entry_id = decoded_cursor
        cur.execute(
            "SELECT * FROM credit_ledger WHERE user_id = %s "
            "AND (created_at < %s OR (created_at = %s AND id < %s)) "
            "ORDER BY created_at DESC, id DESC LIMIT %s",
            (user_id, created_at, created_at, entry_id, limit + 1),
        )
    else:
        cur.execute(
            "SELECT * FROM credit_ledger WHERE user_id = %s "
            "ORDER BY created_at DESC, id DESC LIMIT %s",
            (user_id, limit + 1),
        )
    ledger_page = cur.fetchall()
    has_more = len(ledger_page) > limit
    ledger = ledger_page[:limit]
    next_cursor = None
    if has_more and ledger:
        last_entry = ledger[-1]
        created_at = last_entry['created_at']
        if hasattr(created_at, 'isoformat'):
            created_at = created_at.isoformat(sep=' ')
        next_cursor = base64.urlsafe_b64encode(
            f'{created_at}\n{last_entry["id"]}'.encode()
        ).decode()
    cur.execute(
        "SELECT "
        "COALESCE(SUM(CASE WHEN type IN ('welcome', 'listing_reward', 'earned') THEN amount ELSE 0 END), 0) AS earned, "
        "COALESCE(SUM(CASE WHEN type = 'credit_purchase' THEN amount ELSE 0 END), 0) AS purchased, "
        "COALESCE(SUM(CASE WHEN type = 'refund' THEN amount ELSE 0 END), 0) AS refunded "
        "FROM credit_ledger WHERE user_id = %s",
        (user_id,),
    )
    totals = cur.fetchone()
    cur.execute(
        "SELECT "
        "COALESCE(SUM(CASE WHEN status = 'completed' THEN credits ELSE 0 END), 0) AS spent, "
        "COALESCE(SUM(CASE WHEN status IN ('requested', 'accepted', 'handoff_pending', 'borrowed', 'return_requested') "
        "THEN credits ELSE 0 END), 0) AS held "
        "FROM exchange_orders WHERE buyer_id = %s",
        (user_id,),
    )
    exchange_totals = cur.fetchone()
    cur.execute(
        "SELECT COALESCE(SUM(credits), 0) AS spent "
        "FROM marketplace_orders WHERE buyer_id = %s",
        (user_id,),
    )
    marketplace_totals = cur.fetchone()
    cur.close()
    return {
        'balance': balance,
        'ledger': ledger,
        'has_more': has_more,
        'next_cursor': next_cursor,
        'summary': {
            'earned': totals['earned'],
            'purchased': totals['purchased'],
            'spent': exchange_totals['spent'] + marketplace_totals['spent'],
            'held': exchange_totals['held'],
            'refunded': totals['refunded'],
        },
    }
