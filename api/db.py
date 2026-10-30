import os
import sqlite3
import datetime

# Database configuration
DB_HOST = os.getenv('DB_HOST', '127.0.0.1')
DB_PORT = int(os.getenv('DB_PORT', '3306'))
DB_USER = os.getenv('DB_USER', 'root')
DB_PASSWORD = os.getenv('DB_PASSWORD')
DB_NAME = os.getenv('DB_NAME', 'bookexchange')
DB_TYPE = os.getenv('DB_TYPE', 'auto')  # 'mysql', 'sqlite', or 'auto'

_ACTIVE_DB_TYPE = None


def get_db_type():
    global _ACTIVE_DB_TYPE
    if _ACTIVE_DB_TYPE:
        return _ACTIVE_DB_TYPE

    if DB_TYPE not in ('auto', 'mysql', 'sqlite'):
        raise RuntimeError("DB_TYPE must be 'auto', 'mysql', or 'sqlite'.")

    if DB_TYPE == 'sqlite':
        _ACTIVE_DB_TYPE = 'sqlite'
        return _ACTIVE_DB_TYPE

    if (
        DB_TYPE == 'mysql'
        and os.getenv('MYSQL_AUTO_CREATE_DATABASE', '').strip().lower() == 'false'
    ):
        if not DB_NAME.replace('_', '').isalnum():
            raise RuntimeError('DB_NAME contains unsupported characters.')
        try:
            import mysql.connector
            conn = mysql.connector.connect(
                host=DB_HOST,
                port=DB_PORT,
                user=DB_USER,
                password=DB_PASSWORD or '',
                database=DB_NAME,
            )
            conn.close()
            _ACTIVE_DB_TYPE = 'mysql'
            return _ACTIVE_DB_TYPE
        except Exception as error:
            raise RuntimeError(
                'Unable to connect to the configured MySQL database.'
            ) from error

    if DB_PASSWORD or DB_TYPE == 'mysql':
        try:
            import mysql.connector
            conn = mysql.connector.connect(
                host=DB_HOST,
                port=DB_PORT,
                user=DB_USER,
                password=DB_PASSWORD or '',
            )
            cursor = conn.cursor()
            cursor.execute(f"CREATE DATABASE IF NOT EXISTS {DB_NAME} CHARACTER SET utf8mb4")
            cursor.close()
            conn.close()
            _ACTIVE_DB_TYPE = 'mysql'
            return _ACTIVE_DB_TYPE
        except Exception as error:
            if DB_TYPE == 'mysql' or DB_PASSWORD:
                raise RuntimeError(
                    'Unable to connect to the configured MySQL database.'
                ) from error

    _ACTIVE_DB_TYPE = 'sqlite'
    return _ACTIVE_DB_TYPE


class DatabaseConnection:
    """Unified wrapper around MySQL and SQLite connections."""
    def __init__(self, db_type, raw_conn):
        self.db_type = db_type
        self.raw_conn = raw_conn

    def cursor(self):
        if self.db_type == 'mysql':
            return MySQLCursorWrapper(self.raw_conn.cursor(dictionary=True))
        else:
            return SQLiteCursorWrapper(self.raw_conn.cursor())

    def begin(self, immediate=False):
        if self.db_type == 'mysql':
            self.raw_conn.start_transaction()
        else:
            self.raw_conn.execute('BEGIN IMMEDIATE' if immediate else 'BEGIN')

    def commit(self):
        self.raw_conn.commit()

    def rollback(self):
        self.raw_conn.rollback()

    def close(self):
        self.raw_conn.close()


def _migrate_legacy_columns(conn, cur):
    migrations = {
        'profiles': {
            'bio': 'TEXT NULL',
            'avatar_url': 'TEXT NULL',
        },
        'credit_ledger': {
            'description': 'TEXT NULL',
        },
        'exchange_listings': {
            'category': "VARCHAR(100) NOT NULL DEFAULT 'Fiction'",
            'book_condition': "VARCHAR(50) NOT NULL DEFAULT 'Very Good'",
            'lending_days': 'INT NOT NULL DEFAULT 21',
            'cover_image_url': 'TEXT NULL',
        },
        'exchange_orders': {
            'notes': 'TEXT NULL',
            'due_date': 'DATETIME NULL',
            'returned_at': 'DATETIME NULL',
        },
        'notifications': {
            'reference_id': 'CHAR(36) NULL',
        },
    }
    if conn.db_type == 'sqlite':
        for table, columns in migrations.items():
            cur.execute(f'PRAGMA table_info({table})')
            existing = {row['name'] for row in cur.fetchall()}
            for column, definition in columns.items():
                if column not in existing:
                    cur.execute(
                        f'ALTER TABLE {table} ADD COLUMN {column} {definition}'
                    )
        return

    for table, columns in migrations.items():
        cur.execute(
            'SELECT COLUMN_NAME FROM information_schema.COLUMNS '
            'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s',
            (table,),
        )
        existing = {row['COLUMN_NAME'] for row in cur.fetchall()}
        for column, definition in columns.items():
            if column not in existing:
                cur.execute(
                    f'ALTER TABLE {table} ADD COLUMN {column} {definition}'
                )

    if conn.db_type == 'sqlite':
        cur.execute('PRAGMA index_list(credit_ledger)')
        existing_indexes = {row['name'] for row in cur.fetchall()}
    else:
        cur.execute('SHOW INDEX FROM credit_ledger')
        existing_indexes = {row['Key_name'] for row in cur.fetchall()}
    if 'credit_ledger_page_idx' not in existing_indexes:
        cur.execute(
            'CREATE INDEX credit_ledger_page_idx '
            'ON credit_ledger (user_id, created_at, id)'
        )

    enum_updates = (
        (
            'exchange_listings',
            'available', 'requested', 'borrowed', 'completed', 'cancelled', 'sold',
            'available',
        ),
        (
            'exchange_orders',
            'requested', 'accepted', 'rejected', 'handoff_pending', 'borrowed',
            'return_requested', 'returned', 'completed', 'cancelled',
            'requested',
        ),
    )
    for table, *states, default in enum_updates:
        cur.execute(
            'SELECT COLUMN_TYPE FROM information_schema.COLUMNS '
            'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s '
            "AND COLUMN_NAME = 'status'",
            (table,),
        )
        row = cur.fetchone()
        if row and any(state not in row['COLUMN_TYPE'] for state in states):
            enum_values = ', '.join(f"'{state}'" for state in states)
            cur.execute(
                f'ALTER TABLE {table} MODIFY status ENUM({enum_values}) '
                f"NOT NULL DEFAULT '{default}'"
            )


class MySQLCursorWrapper:
    def __init__(self, raw_cursor):
        self.raw = raw_cursor

    def execute(self, query, params=None):
        params = params or ()
        return self.raw.execute(query, params)

    def fetchone(self):
        return self.raw.fetchone()

    def fetchall(self):
        return self.raw.fetchall()

    @property
    def rowcount(self):
        return self.raw.rowcount

    def close(self):
        self.raw.close()


class SQLiteCursorWrapper:
    def __init__(self, raw_cursor):
        self.raw = raw_cursor

    def execute(self, query, params=None):
        # Convert %s placeholders to ? for sqlite
        sqlite_query = query.replace('%s', '?')
        # Replace NOW() and CURRENT_TIMESTAMP functions if needed
        sqlite_query = sqlite_query.replace('NOW()', "datetime('now')")
        sqlite_query = sqlite_query.replace('DATE_ADD(datetime(\'now\'), INTERVAL 21 DAY)', "datetime('now', '+21 days')")
        sqlite_query = sqlite_query.replace('DATE_ADD(NOW(), INTERVAL 21 DAY)', "datetime('now', '+21 days')")
        # Remove FOR UPDATE locks (SQLite locks database automatically in transaction)
        if ' FOR UPDATE' in sqlite_query:
            sqlite_query = sqlite_query.replace(' FOR UPDATE', '')
        params = params or ()
        # Convert bools to int for sqlite
        converted_params = []
        for p in params:
            if isinstance(p, bool):
                converted_params.append(1 if p else 0)
            else:
                converted_params.append(p)
        return self.raw.execute(sqlite_query, tuple(converted_params))

    def fetchone(self):
        row = self.raw.fetchone()
        if row is None:
            return None
        cols = [d[0] for d in self.raw.description]
        return dict(zip(cols, row))

    def fetchall(self):
        rows = self.raw.fetchall()
        if not rows:
            return []
        cols = [d[0] for d in self.raw.description]
        return [dict(zip(cols, row)) for row in rows]

    @property
    def rowcount(self):
        return self.raw.rowcount

    def close(self):
        self.raw.close()


def db_connection():
    db_type = get_db_type()
    if db_type == 'mysql':
        import mysql.connector
        conn = mysql.connector.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD or '',
            database=DB_NAME,
        )
        return DatabaseConnection('mysql', conn)
    else:
        db_path = os.getenv('BOOKEXCHANGE_DB_PATH', os.path.join(os.path.dirname(__file__), 'bookexchange.db'))
        conn = sqlite3.connect(db_path, timeout=30.0)
        return DatabaseConnection('sqlite', conn)


def ensure_schema():
    conn = db_connection()
    cur = conn.cursor()

    if conn.db_type == 'mysql':
        # MySQL tables
        cur.execute("""
            CREATE TABLE IF NOT EXISTS profiles (
                id CHAR(36) PRIMARY KEY,
                display_name VARCHAR(100) NOT NULL,
                email VARCHAR(255) NOT NULL UNIQUE,
                password_hash TEXT NULL,
                location VARCHAR(255) NULL,
                bio TEXT NULL,
                role ENUM('member','admin') NOT NULL DEFAULT 'member',
                avatar_url TEXT NULL,
                is_active BOOLEAN NOT NULL DEFAULT TRUE,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS auth_sessions (
                token_hash CHAR(64) PRIMARY KEY,
                user_id CHAR(36) NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                revoked_at TIMESTAMP NULL,
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
                INDEX auth_sessions_user_idx (user_id)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS credit_accounts (
                user_id CHAR(36) PRIMARY KEY,
                balance INT NOT NULL DEFAULT 10,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS credit_ledger (
                id CHAR(36) PRIMARY KEY,
                user_id CHAR(36) NOT NULL,
                amount INT NOT NULL,
                type VARCHAR(64) NOT NULL,
                reference_id CHAR(36) NULL,
                description TEXT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
                INDEX credit_ledger_user_idx (user_id, created_at),
                INDEX credit_ledger_page_idx (user_id, created_at, id)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS credit_purchases (
                id CHAR(36) PRIMARY KEY,
                user_id CHAR(36) NOT NULL,
                client_request_id VARCHAR(128) NOT NULL,
                package_id VARCHAR(80) NOT NULL,
                credits INT NOT NULL,
                amount_minor INT NOT NULL,
                currency CHAR(3) NOT NULL,
                payment_provider VARCHAR(32) NOT NULL,
                payment_reference VARCHAR(255) NULL UNIQUE,
                checkout_url TEXT NULL,
                status VARCHAR(24) NOT NULL DEFAULT 'pending',
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                completed_at TIMESTAMP NULL,
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
                UNIQUE KEY credit_purchase_request_idx (user_id, client_request_id),
                INDEX credit_purchases_user_idx (user_id, created_at)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS books (
                id CHAR(36) PRIMARY KEY,
                title VARCHAR(255) NOT NULL,
                author VARCHAR(255) NOT NULL,
                category VARCHAR(100) NOT NULL,
                description TEXT NOT NULL,
                isbn VARCHAR(32) NOT NULL,
                publisher VARCHAR(255) NULL,
                publication_year SMALLINT NULL,
                total_copies INT NOT NULL DEFAULT 1,
                available_copies INT NOT NULL DEFAULT 1,
                cover_image_url TEXT NULL,
                is_active BOOLEAN NOT NULL DEFAULT TRUE,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS exchange_listings (
                id CHAR(36) PRIMARY KEY,
                owner_id CHAR(36) NOT NULL,
                title VARCHAR(255) NOT NULL,
                author VARCHAR(255) NOT NULL,
                category VARCHAR(100) NOT NULL DEFAULT 'Fiction',
                book_condition VARCHAR(50) NOT NULL DEFAULT 'Very Good',
                description TEXT NOT NULL,
                credit_value INT NOT NULL DEFAULT 10,
                lending_days INT NOT NULL DEFAULT 21,
                cover_image_url TEXT NULL,
                status ENUM('available','requested','borrowed','completed','cancelled','sold') NOT NULL DEFAULT 'available',
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE,
                INDEX listings_status_idx (status)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS exchange_orders (
                id CHAR(36) PRIMARY KEY,
                listing_id CHAR(36) NOT NULL,
                buyer_id CHAR(36) NOT NULL,
                seller_id CHAR(36) NOT NULL,
                credits INT NOT NULL,
                status ENUM('requested','accepted','rejected','handoff_pending','borrowed','return_requested','returned','completed','cancelled') NOT NULL DEFAULT 'requested',
                notes TEXT NULL,
                due_date DATETIME NULL,
                returned_at DATETIME NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                FOREIGN KEY (listing_id) REFERENCES exchange_listings(id) ON DELETE CASCADE,
                FOREIGN KEY (buyer_id) REFERENCES profiles(id) ON DELETE CASCADE,
                FOREIGN KEY (seller_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS marketplace_orders (
                id CHAR(36) PRIMARY KEY,
                listing_id CHAR(36) NOT NULL,
                buyer_id CHAR(36) NOT NULL,
                seller_id CHAR(36) NOT NULL,
                idempotency_key VARCHAR(128) NOT NULL,
                credits INT NOT NULL,
                status VARCHAR(24) NOT NULL DEFAULT 'paid',
                recipient_name VARCHAR(100) NOT NULL,
                recipient_phone VARCHAR(40) NOT NULL,
                address_line1 VARCHAR(255) NOT NULL,
                address_line2 VARCHAR(255) NULL,
                city VARCHAR(100) NOT NULL,
                region VARCHAR(100) NOT NULL,
                postal_code VARCHAR(32) NOT NULL,
                country VARCHAR(100) NOT NULL,
                shipping_carrier VARCHAR(100) NULL,
                tracking_number VARCHAR(128) NULL,
                shipped_at TIMESTAMP NULL,
                delivered_at TIMESTAMP NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                FOREIGN KEY (listing_id) REFERENCES exchange_listings(id),
                FOREIGN KEY (buyer_id) REFERENCES profiles(id) ON DELETE CASCADE,
                FOREIGN KEY (seller_id) REFERENCES profiles(id) ON DELETE CASCADE,
                UNIQUE KEY marketplace_order_request_idx (buyer_id, idempotency_key),
                INDEX marketplace_order_buyer_idx (buyer_id, created_at),
                INDEX marketplace_order_seller_idx (seller_id, created_at)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS wanted_books (
                id CHAR(36) PRIMARY KEY,
                user_id CHAR(36) NOT NULL,
                title VARCHAR(255) NOT NULL,
                author VARCHAR(255) NOT NULL,
                category VARCHAR(100) NOT NULL DEFAULT 'Fiction',
                max_credits INT NOT NULL DEFAULT 10,
                notes TEXT NULL,
                status ENUM('open','fulfilled','cancelled') NOT NULL DEFAULT 'open',
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS reviews (
                id CHAR(36) PRIMARY KEY,
                exchange_id CHAR(36) NOT NULL,
                reviewer_id CHAR(36) NOT NULL,
                reviewee_id CHAR(36) NOT NULL,
                rating TINYINT NOT NULL,
                review TEXT NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY review_exchange_user (exchange_id, reviewer_id),
                FOREIGN KEY (reviewer_id) REFERENCES profiles(id) ON DELETE CASCADE,
                FOREIGN KEY (reviewee_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS notifications (
                id CHAR(36) PRIMARY KEY,
                user_id CHAR(36) NOT NULL,
                title VARCHAR(255) NOT NULL,
                body TEXT NOT NULL,
                type VARCHAR(64) NOT NULL DEFAULT 'system',
                is_read BOOLEAN NOT NULL DEFAULT FALSE,
                reference_id CHAR(36) NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
                INDEX notification_user_idx (user_id, created_at)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS activities (
                id CHAR(36) PRIMARY KEY,
                user_id CHAR(36) NOT NULL,
                action_type VARCHAR(64) NOT NULL,
                title VARCHAR(255) NOT NULL,
                description TEXT NOT NULL,
                reference_id CHAR(36) NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
                INDEX activity_user_idx (user_id, created_at)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS exchange_messages (
                id CHAR(36) PRIMARY KEY,
                exchange_id CHAR(36) NOT NULL,
                sender_id CHAR(36) NOT NULL,
                body TEXT NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (exchange_id) REFERENCES exchange_orders(id) ON DELETE CASCADE,
                FOREIGN KEY (sender_id) REFERENCES profiles(id) ON DELETE CASCADE,
                INDEX exchange_messages_page_idx (exchange_id, created_at, id)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS saved_books (
                id CHAR(36) PRIMARY KEY,
                user_id CHAR(36) NOT NULL,
                title VARCHAR(255) NOT NULL,
                author VARCHAR(255) NOT NULL,
                category VARCHAR(100) NOT NULL,
                cover_url TEXT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY saved_book_user_title (user_id, title),
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS reading_progress (
                id CHAR(36) PRIMARY KEY,
                user_id CHAR(36) NOT NULL,
                book_title VARCHAR(255) NOT NULL,
                page INT NOT NULL DEFAULT 1,
                completed BOOLEAN NOT NULL DEFAULT FALSE,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                UNIQUE KEY reading_progress_user_title (user_id, book_title),
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

    else:
        # SQLite tables
        cur.execute("""
            CREATE TABLE IF NOT EXISTS profiles (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                email TEXT NOT NULL UNIQUE,
                password_hash TEXT,
                location TEXT,
                bio TEXT,
                role TEXT NOT NULL DEFAULT 'member',
                avatar_url TEXT,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS auth_sessions (
                token_hash TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                revoked_at TEXT,
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)
        cur.execute("CREATE INDEX IF NOT EXISTS auth_sessions_user_idx ON auth_sessions (user_id)")

        cur.execute("""
            CREATE TABLE IF NOT EXISTS credit_accounts (
                user_id TEXT PRIMARY KEY,
                balance INTEGER NOT NULL DEFAULT 10,
                updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS credit_ledger (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                amount INTEGER NOT NULL,
                type TEXT NOT NULL,
                reference_id TEXT,
                description TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)
        cur.execute(
            "CREATE INDEX IF NOT EXISTS credit_ledger_page_idx "
            "ON credit_ledger (user_id, created_at, id)"
        )

        cur.execute("""
            CREATE TABLE IF NOT EXISTS credit_purchases (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                client_request_id TEXT NOT NULL,
                package_id TEXT NOT NULL,
                credits INTEGER NOT NULL,
                amount_minor INTEGER NOT NULL,
                currency TEXT NOT NULL,
                payment_provider TEXT NOT NULL,
                payment_reference TEXT UNIQUE,
                checkout_url TEXT,
                status TEXT NOT NULL DEFAULT 'pending',
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                completed_at TEXT,
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
                UNIQUE (user_id, client_request_id)
            )
        """)
        cur.execute("CREATE INDEX IF NOT EXISTS credit_purchases_user_idx ON credit_purchases (user_id, created_at)")

        cur.execute("""
            CREATE TABLE IF NOT EXISTS books (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                author TEXT NOT NULL,
                category TEXT NOT NULL,
                description TEXT NOT NULL,
                isbn TEXT NOT NULL,
                publisher TEXT,
                publication_year INTEGER,
                total_copies INTEGER NOT NULL DEFAULT 1,
                available_copies INTEGER NOT NULL DEFAULT 1,
                cover_image_url TEXT,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS exchange_listings (
                id TEXT PRIMARY KEY,
                owner_id TEXT NOT NULL,
                title TEXT NOT NULL,
                author TEXT NOT NULL,
                category TEXT NOT NULL DEFAULT 'Fiction',
                book_condition TEXT NOT NULL DEFAULT 'Very Good',
                description TEXT NOT NULL,
                credit_value INTEGER NOT NULL DEFAULT 10,
                lending_days INTEGER NOT NULL DEFAULT 21,
                cover_image_url TEXT,
                status TEXT NOT NULL DEFAULT 'available',
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS exchange_orders (
                id TEXT PRIMARY KEY,
                listing_id TEXT NOT NULL,
                buyer_id TEXT NOT NULL,
                seller_id TEXT NOT NULL,
                credits INTEGER NOT NULL,
                status TEXT NOT NULL DEFAULT 'requested',
                notes TEXT,
                due_date TEXT,
                returned_at TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY (listing_id) REFERENCES exchange_listings(id) ON DELETE CASCADE,
                FOREIGN KEY (buyer_id) REFERENCES profiles(id) ON DELETE CASCADE,
                FOREIGN KEY (seller_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS marketplace_orders (
                id TEXT PRIMARY KEY,
                listing_id TEXT NOT NULL,
                buyer_id TEXT NOT NULL,
                seller_id TEXT NOT NULL,
                idempotency_key TEXT NOT NULL,
                credits INTEGER NOT NULL,
                status TEXT NOT NULL DEFAULT 'paid',
                recipient_name TEXT NOT NULL,
                recipient_phone TEXT NOT NULL,
                address_line1 TEXT NOT NULL,
                address_line2 TEXT,
                city TEXT NOT NULL,
                region TEXT NOT NULL,
                postal_code TEXT NOT NULL,
                country TEXT NOT NULL,
                shipping_carrier TEXT,
                tracking_number TEXT,
                shipped_at TEXT,
                delivered_at TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY (listing_id) REFERENCES exchange_listings(id),
                FOREIGN KEY (buyer_id) REFERENCES profiles(id) ON DELETE CASCADE,
                FOREIGN KEY (seller_id) REFERENCES profiles(id) ON DELETE CASCADE,
                UNIQUE (buyer_id, idempotency_key)
            )
        """)
        cur.execute(
            "CREATE INDEX IF NOT EXISTS marketplace_order_buyer_idx "
            "ON marketplace_orders (buyer_id, created_at)"
        )
        cur.execute(
            "CREATE INDEX IF NOT EXISTS marketplace_order_seller_idx "
            "ON marketplace_orders (seller_id, created_at)"
        )

        cur.execute("""
            CREATE TABLE IF NOT EXISTS wanted_books (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                title TEXT NOT NULL,
                author TEXT NOT NULL,
                category TEXT NOT NULL DEFAULT 'Fiction',
                max_credits INTEGER NOT NULL DEFAULT 10,
                notes TEXT,
                status TEXT NOT NULL DEFAULT 'open',
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS reviews (
                id TEXT PRIMARY KEY,
                exchange_id TEXT NOT NULL,
                reviewer_id TEXT NOT NULL,
                reviewee_id TEXT NOT NULL,
                rating INTEGER NOT NULL,
                review TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                UNIQUE (exchange_id, reviewer_id),
                FOREIGN KEY (reviewer_id) REFERENCES profiles(id) ON DELETE CASCADE,
                FOREIGN KEY (reviewee_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS notifications (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                type TEXT NOT NULL DEFAULT 'system',
                is_read INTEGER NOT NULL DEFAULT 0,
                reference_id TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS activities (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                action_type TEXT NOT NULL,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                reference_id TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS exchange_messages (
                id TEXT PRIMARY KEY,
                exchange_id TEXT NOT NULL,
                sender_id TEXT NOT NULL,
                body TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY (exchange_id) REFERENCES exchange_orders(id) ON DELETE CASCADE,
                FOREIGN KEY (sender_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)
        cur.execute(
            "CREATE INDEX IF NOT EXISTS exchange_messages_page_idx "
            "ON exchange_messages (exchange_id, created_at, id)"
        )

        cur.execute("""
            CREATE TABLE IF NOT EXISTS saved_books (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                title TEXT NOT NULL,
                author TEXT NOT NULL,
                category TEXT NOT NULL,
                cover_url TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                UNIQUE (user_id, title),
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS reading_progress (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                book_title TEXT NOT NULL,
                page INTEGER NOT NULL DEFAULT 1,
                completed INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                UNIQUE (user_id, book_title),
                FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
            )
        """)

    _migrate_legacy_columns(conn, cur)

    conn.commit()

    cur.close()
    conn.close()
