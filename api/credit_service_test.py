import json
from decimal import Decimal

from services.credit_service import get_credit_account


class CreditAccountConnection:
    def __init__(self):
        self.rows = iter(
            [
                {'balance': 10},
                [],
                {
                    'earned': Decimal('10'),
                    'purchased': Decimal('0'),
                    'refunded': Decimal('0'),
                },
                {'spent': Decimal('0'), 'held': Decimal('0')},
                {'spent': Decimal('0')},
            ]
        )

    def cursor(self):
        return CreditAccountCursor(self.rows)


class CreditAccountCursor:
    def __init__(self, rows):
        self.rows = rows
        self.result = None

    def execute(self, *_args):
        self.result = next(self.rows)

    def fetchone(self):
        return self.result

    def fetchall(self):
        return self.result

    def close(self):
        pass


account = get_credit_account(CreditAccountConnection(), 'user-1')
response = json.loads(json.dumps(account, default=str))
assert response['summary'] == {
    'earned': 10,
    'purchased': 0,
    'spent': 0,
    'held': 0,
    'refunded': 0,
}
assert all(type(value) is int for value in response['summary'].values())
print('Credit summary aggregates are returned as JSON numbers.')
