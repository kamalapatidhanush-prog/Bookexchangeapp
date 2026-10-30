import os
import sqlite3
import tempfile
from unittest.mock import patch


_temp_dir = tempfile.TemporaryDirectory(prefix='leaf-lore-schema-test-')
os.environ['DB_TYPE'] = 'sqlite'
os.environ['BOOKEXCHANGE_DB_PATH'] = os.path.join(_temp_dir.name, 'legacy.db')

import sys
sys.path.insert(0, os.path.dirname(__file__))

from db import db_connection, ensure_schema
import db as database_module
import mysql.connector


previous_db_type = database_module.DB_TYPE
previous_db_password = database_module.DB_PASSWORD
try:
    database_module.DB_TYPE = 'mysql'
    database_module.DB_PASSWORD = 'test-only-unavailable-password'
    database_module._ACTIVE_DB_TYPE = None
    with patch.object(mysql.connector, 'connect', side_effect=OSError('test connection failure')):
        try:
            database_module.get_db_type()
        except RuntimeError as error:
            assert 'configured MySQL database' in str(error)
        else:
            raise AssertionError('Failed MySQL configuration silently fell back to SQLite')
finally:
    database_module.DB_TYPE = previous_db_type
    database_module.DB_PASSWORD = previous_db_password
    database_module._ACTIVE_DB_TYPE = None


legacy_user_id = 'legacy-reader'
legacy_listing_id = 'legacy-listing'
legacy_order_id = 'legacy-order'
legacy_db = sqlite3.connect(os.environ['BOOKEXCHANGE_DB_PATH'])
legacy_db.executescript("""
CREATE TABLE profiles (
  id TEXT PRIMARY KEY, display_name TEXT NOT NULL, email TEXT NOT NULL UNIQUE,
  password_hash TEXT, location TEXT, role TEXT NOT NULL DEFAULT 'member',
  is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT, updated_at TEXT
);
CREATE TABLE auth_sessions (
  token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL,
  created_at TEXT, revoked_at TEXT
);
CREATE TABLE books (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL,
  category TEXT NOT NULL, description TEXT NOT NULL, isbn TEXT NOT NULL,
  publisher TEXT, publication_year INTEGER, total_copies INTEGER NOT NULL,
  available_copies INTEGER NOT NULL, cover_image_url TEXT, is_active INTEGER NOT NULL,
  created_at TEXT, updated_at TEXT
);
CREATE TABLE credit_accounts (
  user_id TEXT PRIMARY KEY, balance INTEGER NOT NULL DEFAULT 10, updated_at TEXT
);
CREATE TABLE credit_ledger (
  id TEXT PRIMARY KEY, user_id TEXT NOT NULL, amount INTEGER NOT NULL,
  type TEXT NOT NULL, reference_id TEXT, created_at TEXT
);
CREATE TABLE exchange_listings (
  id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, title TEXT NOT NULL,
  author TEXT NOT NULL, description TEXT NOT NULL, credit_value INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'available', created_at TEXT, updated_at TEXT
);
CREATE TABLE exchange_orders (
  id TEXT PRIMARY KEY, listing_id TEXT NOT NULL, buyer_id TEXT NOT NULL,
  seller_id TEXT NOT NULL, credits INTEGER NOT NULL, status TEXT NOT NULL,
  created_at TEXT, updated_at TEXT
);
CREATE TABLE notifications (
  id TEXT PRIMARY KEY, user_id TEXT NOT NULL, title TEXT NOT NULL,
  body TEXT NOT NULL, type TEXT NOT NULL, is_read INTEGER NOT NULL DEFAULT 0,
  created_at TEXT
);
""")
legacy_db.execute(
    "INSERT INTO profiles (id, display_name, email, role) VALUES (?, ?, ?, ?)",
    (legacy_user_id, 'Legacy Reader', 'legacy@example.test', 'member'),
)
legacy_db.execute(
    "INSERT INTO books (id, title, author, category, description, isbn, "
    "total_copies, available_copies, is_active) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    ('legacy-book', 'Legacy Book', 'Legacy Author', 'Fiction', 'Existing record', '1', 1, 1, 1),
)
legacy_db.execute(
    "INSERT INTO credit_accounts (user_id, balance) VALUES (?, ?)",
    (legacy_user_id, 15),
)
legacy_db.execute(
    "INSERT INTO credit_ledger (id, user_id, amount, type) VALUES (?, ?, ?, ?)",
    ('legacy-ledger', legacy_user_id, 15, 'welcome'),
)
legacy_db.execute(
    "INSERT INTO exchange_listings "
    "(id, owner_id, title, author, description, credit_value) VALUES (?, ?, ?, ?, ?, ?)",
    (legacy_listing_id, legacy_user_id, 'Legacy Listing', 'Legacy Author', 'Keep this row', 10),
)
legacy_db.execute(
    "INSERT INTO exchange_orders "
    "(id, listing_id, buyer_id, seller_id, credits, status) VALUES (?, ?, ?, ?, ?, ?)",
    (legacy_order_id, legacy_listing_id, legacy_user_id, legacy_user_id, 10, 'requested'),
)
legacy_db.execute(
    "INSERT INTO notifications (id, user_id, title, body, type) VALUES (?, ?, ?, ?, ?)",
    ('legacy-notification', legacy_user_id, 'Existing notice', 'Keep this row', 'system'),
)
legacy_db.commit()
legacy_db.close()

ensure_schema()
ensure_schema()

conn = db_connection()
cur = conn.cursor()
cur.execute("SELECT balance FROM credit_accounts WHERE user_id = %s", (legacy_user_id,))
assert cur.fetchone()['balance'] == 15
cur.execute("SELECT type FROM credit_ledger WHERE id = %s", ('legacy-ledger',))
assert cur.fetchone()['type'] == 'welcome'
cur.execute('PRAGMA index_list(credit_ledger)')
assert any(index['name'] == 'credit_ledger_page_idx' for index in cur.fetchall())
cur.execute("SELECT title, category, book_condition, lending_days FROM exchange_listings WHERE id = %s", (legacy_listing_id,))
listing = cur.fetchone()
assert listing == {
    'title': 'Legacy Listing',
    'category': 'Fiction',
    'book_condition': 'Very Good',
    'lending_days': 21,
}
cur.execute("SELECT status, notes, due_date, returned_at FROM exchange_orders WHERE id = %s", (legacy_order_id,))
order = cur.fetchone()
assert order['status'] == 'requested' and order['notes'] is None
cur.execute("SELECT title, reference_id FROM notifications WHERE id = %s", ('legacy-notification',))
notification = cur.fetchone()
assert notification['title'] == 'Existing notice' and notification['reference_id'] is None
cur.execute("SELECT bio, avatar_url FROM profiles WHERE id = %s", (legacy_user_id,))
profile = cur.fetchone()
assert profile == {'bio': None, 'avatar_url': None}
cur.execute("SELECT COUNT(*) AS count FROM profiles")
assert cur.fetchone()['count'] == 1
cur.execute("SELECT COUNT(*) AS count FROM books")
assert cur.fetchone()['count'] == 1
cur.close()
conn.close()

print('SQLite legacy-schema migration passed; existing records were preserved.')
