import json
import logging
import os
import sqlite3
import sys
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

# Ensure local api folder is on sys.path
sys.path.insert(0, os.path.dirname(__file__))

from auth import (
    hash_password,
    session_token_hash,
    token_for,
    token_from_headers,
    user_from_token,
    validate_token_secret,
    verify_password,
)
from db import db_connection, ensure_schema, get_db_type
from services.credit_service import get_credit_account
from services.credit_purchase_service import (
    PaymentUnavailable,
    create_purchase,
    get_purchase,
    get_packages,
    list_purchases,
    payment_is_configured,
    process_razorpay_webhook,
    verify_razorpay_payment,
)
from services.community_service import (
    log_activity,
    notify,
)
from services.marketplace_service import (
    MAX_BOOK_PRICE_CREDITS,
    confirm_delivery,
    create_marketplace_order,
    set_shipping,
)
from services.book_catalog_service import get_featured_books
from services.upload_service import UploadUnavailable, create_book_cover_signature

HOST = os.getenv('API_HOST', '127.0.0.1')
PORT = int(os.getenv('API_PORT', '8080'))
APP_ENV = os.getenv('APP_ENV', 'development').strip().lower()
CORS_ALLOWED_ORIGINS = {
    origin.strip().rstrip('/')
    for origin in os.getenv('CORS_ALLOWED_ORIGINS', '').split(',')
    if origin.strip()
}


def _is_unique_conflict(error):
    if getattr(error, 'errno', None) == 1062:
        return True
    return (
        isinstance(error, sqlite3.IntegrityError)
        and 'UNIQUE constraint failed' in str(error)
    )


class APIHandler(BaseHTTPRequestHandler):
    def _add_cors_headers(self):
        origin = self.headers.get('Origin', '').rstrip('/')
        if origin and (
            origin in CORS_ALLOWED_ORIGINS
            or (
                APP_ENV != 'production'
                and urlparse(origin).hostname in ('localhost', '127.0.0.1')
            )
        ):
            self.send_header('Access-Control-Allow-Origin', origin)
            self.send_header('Vary', 'Origin')

    def _json(self, status, body):
        data = json.dumps(
            body,
            default=lambda v: v.isoformat() if hasattr(v, 'isoformat') else str(v),
        ).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self._add_cors_headers()
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, Idempotency-Key')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.end_headers()
        self.wfile.write(data)

    def _body(self):
        self._body_error = None
        self._body_error_status = 400
        try:
            length = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            self._body_error = 'Invalid Content-Length header.'
            self._raw_request_body = b''
            return {}
        if length < 0:
            self._body_error = 'Invalid request body length.'
            self._raw_request_body = b''
            return {}
        if length > 1024 * 1024:
            self._body_error = 'Request body exceeds the 1 MB limit.'
            self._body_error_status = 413
            self._raw_request_body = b''
            self.close_connection = True
            return {}
        if length == 0:
            self._raw_request_body = b''
            return {}
        try:
            self._raw_request_body = self.rfile.read(length)
            body = json.loads(self._raw_request_body.decode('utf-8') or '{}')
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._raw_request_body = b''
            self._body_error = 'Request body must contain valid JSON.'
            return {}
        if not isinstance(body, dict):
            self._body_error = 'Request body must be a JSON object.'
            return {}
        return body

    def _auth_user(self):
        token = token_from_headers(self.headers)
        user_id = user_from_token(token) if token else None
        if not user_id:
            return None

        conn = db_connection()
        cur = conn.cursor()
        cur.execute(
            "SELECT p.id FROM profiles p "
            "JOIN auth_sessions s ON s.user_id = p.id "
            "WHERE s.token_hash = %s AND s.revoked_at IS NULL AND p.is_active = 1",
            (session_token_hash(token),),
        )
        row = cur.fetchone()
        cur.close()
        conn.close()
        return row['id'] if row else None

    def _is_admin(self, user_id):
        conn = db_connection()
        cur = conn.cursor()
        cur.execute("SELECT role FROM profiles WHERE id = %s AND is_active = 1", (user_id,))
        row = cur.fetchone()
        cur.close()
        conn.close()
        return row is not None and row.get('role') == 'admin'

    def do_OPTIONS(self):
        self.send_response(204)
        self._add_cors_headers()
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, Idempotency-Key')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip('/') or '/'
        # Normalize /api/xyz -> /xyz
        if path.startswith('/api/'):
            path = path[4:]
        query = parse_qs(parsed.query)

        # Health
        if path == '/health':
            return self._json(200, {'status': 'ok', 'database': get_db_type()})

        if path == '/book-catalog':
            try:
                return self._json(200, {'books': get_featured_books()})
            except RuntimeError as error:
                return self._json(502, {'message': str(error)})

        if path == '/credit-packages':
            try:
                packages = get_packages()
            except ValueError as error:
                return self._json(500, {'message': str(error)})
            return self._json(200, {
                'packages': packages,
                'payments_enabled': payment_is_configured(),
            })

        # Books (Catalog)
        if path == '/books':
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("SELECT * FROM books WHERE is_active = 1 ORDER BY created_at DESC")
            books = cur.fetchall()
            cur.close()
            conn.close()
            return self._json(200, {'books': books})

        # Listings (Peer-to-Peer)
        if path == '/listings':
            conn = db_connection()
            cur = conn.cursor()
            sql = """
                SELECT l.*, p.display_name AS owner_name, p.location AS owner_location,
                       (SELECT AVG(rating) FROM reviews WHERE reviewee_id = l.owner_id) AS owner_rating
                FROM exchange_listings l
                JOIN profiles p ON p.id = l.owner_id
                WHERE 1=1
            """
            params = []
            owner_filter = query.get('owner_id', [None])[0]
            if owner_filter:
                sql += " AND l.owner_id = %s"
                params.append(owner_filter)
            else:
                status_filter = query.get('status', ['available'])[0]
                if status_filter != 'all':
                    sql += " AND l.status = %s"
                    params.append(status_filter)
                sql += " AND l.credit_value BETWEEN 1 AND %s"
                params.append(MAX_BOOK_PRICE_CREDITS)

            cat = query.get('category', [None])[0]
            if cat and cat != 'All':
                sql += " AND l.category = %s"
                params.append(cat)

            search = query.get('q', [None])[0]
            if search:
                sql += " AND (l.title LIKE %s OR l.author LIKE %s)"
                params.extend([f"%{search}%", f"%{search}%"])

            sql += " ORDER BY l.created_at DESC"
            cur.execute(sql, tuple(params))
            listings = cur.fetchall()
            cur.close()
            conn.close()
            return self._json(200, {'listings': listings})

        # Single Listing
        if path.startswith('/listings/'):
            listing_id = path.split('/')[-1]
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("""
                SELECT l.*, p.display_name AS owner_name, p.location AS owner_location, p.bio AS owner_bio,
                       (SELECT AVG(rating) FROM reviews WHERE reviewee_id = l.owner_id) AS owner_rating
                FROM exchange_listings l
                JOIN profiles p ON p.id = l.owner_id
                WHERE l.id = %s
            """, (listing_id,))
            listing = cur.fetchone()
            cur.close()
            conn.close()
            if not listing:
                return self._json(404, {'message': 'Listing not found'})
            return self._json(200, {'listing': listing})

        # Wanted Books
        if path == '/wanted-books':
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("""
                SELECT w.*, p.display_name AS user_name, p.location AS user_location
                FROM wanted_books w
                JOIN profiles p ON p.id = w.user_id
                WHERE w.status = 'open'
                ORDER BY w.created_at DESC
            """)
            wanted = cur.fetchall()
            cur.close()
            conn.close()
            return self._json(200, {'wanted_books': wanted})

        # Community Activity
        if path == '/activity':
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("""
                SELECT a.*, p.display_name AS user_name
                FROM activities a
                JOIN profiles p ON p.id = a.user_id
                ORDER BY a.created_at DESC
                LIMIT 40
            """)
            activities = cur.fetchall()
            cur.close()
            conn.close()
            return self._json(200, {'activities': activities})

        # Public Profile & Reviews for any user
        if path.startswith('/users/') and not path.startswith('/users/me'):
            target_id = path.split('/')[-1]
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("SELECT id, display_name, location, bio, created_at FROM profiles WHERE id = %s", (target_id,))
            profile = cur.fetchone()
            if not profile:
                cur.close()
                conn.close()
                return self._json(404, {'message': 'User not found'})

            cur.execute("SELECT COUNT(*) AS total FROM marketplace_orders WHERE seller_id = %s", (target_id,))
            sold_count = cur.fetchone()['total']
            cur.execute("SELECT COUNT(*) AS total FROM marketplace_orders WHERE buyer_id = %s", (target_id,))
            purchased_count = cur.fetchone()['total']
            cur.execute("SELECT COUNT(*) AS total FROM exchange_listings WHERE owner_id = %s AND status = 'available'", (target_id,))
            listed_count = cur.fetchone()['total']

            cur.execute("""
                SELECT r.*, p.display_name AS reviewer_name
                FROM reviews r
                JOIN profiles p ON p.id = r.reviewer_id
                WHERE r.reviewee_id = %s
                ORDER BY r.created_at DESC
            """, (target_id,))
            reviews = cur.fetchall()
            cur.close()
            conn.close()

            avg_rating = sum(r['rating'] for r in reviews) / len(reviews) if reviews else None
            return self._json(200, {
                'profile': {
                    **profile,
                    'sold_count': sold_count,
                    'purchased_count': purchased_count,
                    'listed_count': listed_count,
                    'rating': round(avg_rating, 1),
                    'review_count': len(reviews),
                    'reviews': reviews,
                }
            })

        # Authenticated routes below
        user_id = self._auth_user()
        if not user_id:
            return self._json(401, {'message': 'Authentication required. Please sign in.'})

        if (
            path in ('/exchanges', '/exchange-orders')
            or path.startswith('/exchanges/')
            or path.startswith('/exchange-orders/')
        ):
            return self._json(
                410,
                {'message': 'In-person exchanges are no longer supported. Use marketplace orders.'},
            )

        if path == '/marketplace/orders':
            conn = db_connection()
            cur = conn.cursor()
            cur.execute(
                "SELECT o.*, l.title, l.author, l.category, l.cover_image_url, "
                "buyer.display_name AS buyer_name, seller.display_name AS seller_name, "
                "(SELECT id FROM reviews WHERE exchange_id = o.id AND reviewer_id = %s) "
                "AS user_review_id "
                "FROM marketplace_orders o "
                "JOIN exchange_listings l ON l.id = o.listing_id "
                "JOIN profiles buyer ON buyer.id = o.buyer_id "
                "JOIN profiles seller ON seller.id = o.seller_id "
                "WHERE o.buyer_id = %s OR o.seller_id = %s "
                "ORDER BY o.updated_at DESC, o.id DESC",
                (user_id, user_id, user_id),
            )
            orders = cur.fetchall()
            cur.close()
            conn.close()
            return self._json(200, {'orders': orders})

        # Current User Profile
        if path in ('/profile', '/users/me'):
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("SELECT id, display_name, email, location, bio, role, created_at FROM profiles WHERE id = %s", (user_id,))
            profile = cur.fetchone()
            if not profile:
                cur.close()
                conn.close()
                return self._json(404, {'message': 'Profile not found'})

            cur.execute("SELECT balance FROM credit_accounts WHERE user_id = %s", (user_id,))
            c_row = cur.fetchone()
            balance = c_row['balance'] if c_row else 0

            cur.execute("SELECT COUNT(*) AS total FROM marketplace_orders WHERE seller_id = %s", (user_id,))
            sold_count = cur.fetchone()['total']
            cur.execute("SELECT COUNT(*) AS total FROM marketplace_orders WHERE buyer_id = %s", (user_id,))
            purchased_count = cur.fetchone()['total']
            cur.execute("SELECT COUNT(*) AS total FROM exchange_listings WHERE owner_id = %s AND status = 'available'", (user_id,))
            listed_count = cur.fetchone()['total']

            cur.execute("SELECT AVG(rating) AS avg_r, COUNT(*) AS count_r FROM reviews WHERE reviewee_id = %s", (user_id,))
            r_stats = cur.fetchone()
            rating = round(r_stats['avg_r'], 1) if r_stats and r_stats['avg_r'] is not None else None
            review_count = r_stats['count_r'] if r_stats else 0

            cur.close()
            conn.close()
            return self._json(200, {
                'profile': {
                    **profile,
                    'credits': balance,
                    'sold_count': sold_count,
                    'purchased_count': purchased_count,
                    'listed_count': listed_count,
                    'rating': rating,
                    'review_count': review_count,
                }
            })

        # Credits & Ledger
        if path == '/credits':
            raw_limit = query.get('limit', ['50'])[0]
            if (
                len(raw_limit) > 3
                or not raw_limit.isascii()
                or not raw_limit.isdigit()
            ):
                return self._json(
                    400,
                    {'message': 'Ledger limit must be an integer between 1 and 100.'},
                )
            limit = int(raw_limit)
            if not 1 <= limit <= 100:
                return self._json(400, {'message': 'Ledger limit must be an integer between 1 and 100.'})
            cursor = query.get('cursor', [None])[0]
            if cursor is not None and not cursor:
                return self._json(400, {'message': 'Ledger cursor is invalid.'})
            conn = db_connection()
            try:
                account = get_credit_account(conn, user_id, limit=limit, cursor=cursor)
                return self._json(200, account)
            except ValueError as error:
                return self._json(400, {'message': str(error)})
            finally:
                conn.close()

        if path == '/credit-purchases':
            conn = db_connection()
            purchases = list_purchases(conn, user_id)
            conn.close()
            return self._json(200, {'purchases': purchases})

        if path.startswith('/credit-purchases/'):
            purchase_id = path.split('/')[-1]
            conn = db_connection()
            purchase = get_purchase(conn, user_id, purchase_id)
            conn.close()
            if not purchase:
                return self._json(404, {'message': 'Credit purchase not found.'})
            return self._json(200, {'purchase': purchase})

        # Notifications
        if path == '/notifications':
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("SELECT * FROM notifications WHERE user_id = %s ORDER BY created_at DESC LIMIT 50", (user_id,))
            notifs = cur.fetchall()
            cur.close()
            conn.close()
            return self._json(200, {'notifications': notifs})

        # Saved Books
        if path == '/saved-books':
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("SELECT * FROM saved_books WHERE user_id = %s ORDER BY created_at DESC", (user_id,))
            saved = cur.fetchall()
            cur.close()
            conn.close()
            return self._json(200, {'saved_books': saved})

        # Admin Endpoints
        if path == '/admin/stats':
            if not self._is_admin(user_id):
                return self._json(403, {'message': 'Admin access required'})
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) AS total_users FROM profiles")
            users_count = cur.fetchone()['total_users']
            cur.execute("SELECT COUNT(*) AS active_listings FROM exchange_listings WHERE status = 'available'")
            listings_count = cur.fetchone()['active_listings']
            cur.execute("SELECT COUNT(*) AS active_orders FROM marketplace_orders WHERE status IN ('paid','shipped')")
            active_orders = cur.fetchone()['active_orders']
            cur.execute("SELECT COUNT(*) AS completed_orders FROM marketplace_orders WHERE status = 'delivered'")
            completed_orders = cur.fetchone()['completed_orders']
            cur.close()
            conn.close()
            return self._json(200, {'stats': {
                'total_users': users_count,
                'active_listings': listings_count,
                'active_orders': active_orders,
                'completed_orders': completed_orders,
            }})

        return self._json(404, {'message': f'Not found: {path}'})

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip('/') or '/'
        if path.startswith('/api/'):
            path = path[4:]
        body = self._body()
        if self._body_error:
            status = getattr(self, '_body_error_status', 400)
            return self._json(status, {'message': self._body_error})

        # Registration
        if path == '/auth/register':
            name = body.get('name')
            email = body.get('email')
            password = body.get('password')
            location = body.get('location', '')

            if (
                not isinstance(name, str)
                or not isinstance(email, str)
                or not isinstance(password, str)
                or not isinstance(location, str)
                or not name.strip()
                or '@' not in email
                or len(password) < 8
                or len(name.strip()) > 100
                or len(email) > 255
                or len(location) > 255
            ):
                return self._json(400, {'message': 'Name, valid email, and at least 8-character password are required.'})
            name = name.strip()
            email = email.strip().lower()
            location = location.strip() or 'Local Community'

            user_id = str(uuid.uuid4())
            token = token_for(user_id)
            conn = db_connection()
            cur = conn.cursor()
            try:
                cur.execute(
                    "INSERT INTO profiles (id, display_name, email, password_hash, location) VALUES (%s, %s, %s, %s, %s)",
                    (user_id, name, email, hash_password(password), location)
                )
                cur.execute("INSERT INTO credit_accounts (user_id, balance) VALUES (%s, 15)", (user_id,))
                cur.execute(
                    "INSERT INTO credit_ledger (id, user_id, amount, type, description) VALUES (%s, %s, 15, 'welcome', 'Welcome bonus credits')",
                    (str(uuid.uuid4()), user_id)
                )
                cur.execute(
                    "INSERT INTO auth_sessions (token_hash, user_id) VALUES (%s, %s)",
                    (session_token_hash(token), user_id),
                )
                log_activity(cur, user_id, "user_joined", f"{name} joined Leaf & Lore", "Welcome to the reader community!")
                conn.commit()
            except Exception as error:
                conn.rollback()
                cur.close()
                conn.close()
                if _is_unique_conflict(error):
                    return self._json(409, {'message': 'An account with that email already exists.'})
                logging.error('Registration failed (%s).', type(error).__name__)
                return self._json(500, {'message': 'Unable to create the account right now.'})

            cur.close()
            conn.close()
            return self._json(201, {
                'token': token,
                'user': {'id': user_id, 'name': name, 'email': email, 'credits': 15, 'location': location}
            })

        if path == '/webhooks/razorpay':
            conn = db_connection()
            try:
                result = process_razorpay_webhook(
                    conn,
                    getattr(self, '_raw_request_body', b''),
                    self.headers.get('X-Razorpay-Signature', ''),
                )
                return self._json(200, result)
            except PermissionError as error:
                return self._json(400, {'message': str(error)})
            except ValueError as error:
                return self._json(400, {'message': str(error)})
            except Exception as error:
                conn.rollback()
                logging.error('Razorpay webhook processing failed (%s).', type(error).__name__)
                return self._json(500, {'message': 'Unable to process payment notification.'})
            finally:
                conn.close()

        # Login
        if path == '/auth/login':
            email = body.get('email')
            password = body.get('password')
            if not isinstance(email, str) or not isinstance(password, str):
                return self._json(400, {'message': 'Email and password are required.'})
            email = email.strip().lower()
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("SELECT id, display_name, email, password_hash, location, role, is_active FROM profiles WHERE email = %s", (email,))
            user = cur.fetchone()
            if not user or not user['is_active'] or not verify_password(password, user['password_hash']):
                cur.close()
                conn.close()
                return self._json(401, {'message': 'Invalid email or password.'})

            cur.execute("SELECT balance FROM credit_accounts WHERE user_id = %s", (user['id'],))
            c_row = cur.fetchone()
            credits = c_row['balance'] if c_row else 10
            token = token_for(user['id'])
            cur.execute(
                "INSERT INTO auth_sessions (token_hash, user_id) VALUES (%s, %s)",
                (session_token_hash(token), user['id']),
            )
            conn.commit()
            cur.close()
            conn.close()

            return self._json(200, {
                'token': token,
                'user': {
                    'id': user['id'],
                    'name': user['display_name'],
                    'email': user['email'],
                    'location': user['location'],
                    'role': user['role'],
                    'credits': credits,
                }
            })

        if path == '/auth/logout':
            user_id = self._auth_user()
            token = token_from_headers(self.headers)
            if not user_id or not token:
                return self._json(401, {'message': 'Authentication required. Please sign in.'})
            conn = db_connection()
            cur = conn.cursor()
            cur.execute(
                "UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP "
                "WHERE token_hash = %s AND user_id = %s AND revoked_at IS NULL",
                (session_token_hash(token), user_id),
            )
            conn.commit()
            cur.close()
            conn.close()
            return self._json(200, {'status': 'signed_out'})

        # Authenticated endpoints below
        user_id = self._auth_user()
        if not user_id:
            return self._json(401, {'message': 'Authentication required. Please sign in.'})

        if (
            path in ('/exchanges', '/exchange-orders')
            or path.startswith('/exchanges/')
            or path.startswith('/exchange-orders/')
        ):
            return self._json(
                410,
                {'message': 'In-person exchanges are no longer supported. Use marketplace orders.'},
            )

        if path == '/marketplace/orders':
            conn = db_connection()
            try:
                order_id = create_marketplace_order(
                    conn,
                    user_id,
                    body.get('listing_id'),
                    body.get('shipping_address'),
                    self.headers.get('Idempotency-Key', ''),
                )
                return self._json(201, {'id': order_id, 'status': 'paid'})
            except PermissionError as error:
                return self._json(403, {'message': str(error)})
            except ValueError as error:
                return self._json(409, {'message': str(error)})
            finally:
                conn.close()

        if path.startswith('/marketplace/orders/'):
            parts = path.split('/')
            if len(parts) != 5:
                return self._json(404, {'message': 'Marketplace order action not found.'})
            order_id, action = parts[3], parts[4]
            conn = db_connection()
            try:
                if action == 'ship':
                    set_shipping(
                        conn,
                        user_id,
                        order_id,
                        body.get('shipping_carrier'),
                        body.get('tracking_number'),
                    )
                    return self._json(200, {'status': 'shipped'})
                if action == 'delivered':
                    confirm_delivery(conn, user_id, order_id)
                    return self._json(200, {'status': 'delivered'})
                return self._json(404, {'message': 'Marketplace order action not found.'})
            except PermissionError as error:
                return self._json(403, {'message': str(error)})
            except ValueError as error:
                return self._json(409, {'message': str(error)})
            finally:
                conn.close()

        if path == '/uploads/signature':
            try:
                signature = create_book_cover_signature(user_id)
            except UploadUnavailable as error:
                return self._json(503, {'message': str(error)})
            except RuntimeError as error:
                logging.exception('Invalid image-upload configuration')
                return self._json(500, {'message': str(error)})
            return self._json(200, signature)

        if path == '/credit-purchases':
            package_id = body.get('package_id')
            if not isinstance(package_id, str) or not package_id:
                return self._json(400, {'message': 'A valid credit package is required.'})
            request_id = self.headers.get('Idempotency-Key', '').strip()
            if not request_id:
                return self._json(400, {'message': 'An Idempotency-Key header is required.'})
            conn = db_connection()
            try:
                result = create_purchase(conn, user_id, package_id, request_id)
                return self._json(201, result)
            except PaymentUnavailable as error:
                return self._json(503, {'message': str(error)})
            except ValueError as error:
                return self._json(400, {'message': str(error)})
            except RuntimeError as error:
                return self._json(502, {'message': str(error)})
            finally:
                conn.close()

        if path == '/credit-purchases/verify':
            purchase_id = body.get('purchase_id')
            order_id = body.get('razorpay_order_id')
            payment_id = body.get('razorpay_payment_id')
            signature = body.get('razorpay_signature')
            if not all(isinstance(value, str) and value for value in
                       (purchase_id, order_id, payment_id, signature)):
                return self._json(400, {'message': 'Razorpay payment verification fields are required.'})
            conn = db_connection()
            try:
                result = verify_razorpay_payment(
                    conn, user_id, purchase_id, order_id, payment_id, signature
                )
                return self._json(200, result)
            except PaymentUnavailable as error:
                return self._json(503, {'message': str(error)})
            except PermissionError as error:
                return self._json(400, {'message': str(error)})
            except ValueError as error:
                return self._json(400, {'message': str(error)})
            except RuntimeError as error:
                return self._json(502, {'message': str(error)})
            finally:
                conn.close()

        # Update Profile
        if path in ('/profile', '/users/me'):
            name = body.get('name', '').strip()
            location = body.get('location', '').strip()
            bio = body.get('bio', '').strip()
            if not name:
                return self._json(400, {'message': 'Name cannot be empty.'})
            conn = db_connection()
            cur = conn.cursor()
            cur.execute(
                "UPDATE profiles SET display_name = %s, location = %s, bio = %s WHERE id = %s",
                (name, location, bio, user_id)
            )
            conn.commit()
            cur.close()
            conn.close()
            return self._json(200, {'status': 'updated'})

        # Create Listing
        if path == '/listings':
            title = body.get('title')
            author = body.get('author')
            description = body.get('description')
            category = body.get('category', 'Fiction')
            condition = body.get('condition', 'Very Good')
            credits = body.get('credit_value', 10)
            cover_url = body.get('cover_image_url')

            if not all(isinstance(value, str) for value in (title, author, description, category, condition)):
                return self._json(400, {'message': 'Listing text fields must be strings.'})
            if (
                isinstance(credits, bool)
                or not isinstance(credits, int)
                or not 1 <= credits <= MAX_BOOK_PRICE_CREDITS
            ):
                return self._json(
                    400,
                    {
                        'message': (
                            f'Book price must be between 1 and '
                            f'{MAX_BOOK_PRICE_CREDITS} credits.'
                        )
                    },
                )
            title, author, description = title.strip(), author.strip(), description.strip()
            category, condition = category.strip(), condition.strip()
            if not title or not author or not description:
                return self._json(400, {'message': 'Title, author, and description are required.'})

            listing_id = str(uuid.uuid4())
            conn = db_connection()
            cur = conn.cursor()
            cur.execute(
                "INSERT INTO exchange_listings (id, owner_id, title, author, category, book_condition, description, credit_value, cover_image_url, status) "
                "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'available')",
                (listing_id, user_id, title, author, category, condition, description, credits, cover_url)
            )

            log_activity(cur, user_id, "book_listed", f"Listed '{title}'", f"Available for {credits} credits in {category}.", listing_id)
            notify(cur, user_id, "Book Listed Successfully", f"'{title}' is now available in the marketplace.", 'listing_created', listing_id)

            conn.commit()
            cur.close()
            conn.close()
            return self._json(201, {'id': listing_id, 'status': 'available'})

        # Delete Listing
        if path.startswith('/listings/') and path.endswith('/delete'):
            listing_id = path.split('/')[-2]
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("SELECT status FROM exchange_listings WHERE id = %s AND owner_id = %s", (listing_id, user_id))
            row = cur.fetchone()
            if not row:
                cur.close()
                conn.close()
                return self._json(404, {'message': 'Listing not found or unauthorized'})
            if row['status'] != 'available':
                cur.close()
                conn.close()
                return self._json(409, {'message': 'Only available marketplace listings can be removed.'})

            cur.execute("DELETE FROM exchange_listings WHERE id = %s", (listing_id,))
            conn.commit()
            cur.close()
            conn.close()
            return self._json(200, {'status': 'deleted'})

        # Post Wanted Book
        if path == '/wanted-books':
            title = body.get('title')
            author = body.get('author')
            category = body.get('category', 'Fiction')
            max_credits = body.get('max_credits', 10)
            notes = body.get('notes', '')

            if not all(isinstance(value, str) for value in (title, author, category, notes)):
                return self._json(400, {'message': 'Wanted-book text fields must be strings.'})
            if isinstance(max_credits, bool) or not isinstance(max_credits, int) or max_credits < 0:
                return self._json(400, {'message': 'Maximum credits must be a non-negative integer.'})
            title, author, category, notes = (
                title.strip(), author.strip(), category.strip(), notes.strip()
            )
            if not title or not author:
                return self._json(400, {'message': 'Title and author are required.'})

            wanted_id = str(uuid.uuid4())
            conn = db_connection()
            cur = conn.cursor()
            cur.execute(
                "INSERT INTO wanted_books (id, user_id, title, author, category, max_credits, notes, status) "
                "VALUES (%s, %s, %s, %s, %s, %s, %s, 'open')",
                (wanted_id, user_id, title, author, category, max_credits, notes)
            )
            log_activity(cur, user_id, "wanted_posted", f"Looking for '{title}'", f"Willing to offer up to {max_credits} credits.", wanted_id)
            conn.commit()
            cur.close()
            conn.close()
            return self._json(201, {'id': wanted_id, 'status': 'open'})

        # Submit Review
        if path == '/reviews':
            exchange_id = body.get('exchange_id')
            rating = body.get('rating', 5)
            review_text = body.get('review', '')

            if (
                not isinstance(exchange_id, str)
                or isinstance(rating, bool)
                or not isinstance(rating, int)
                or not isinstance(review_text, str)
                or rating not in range(1, 6)
                or not review_text.strip()
            ):
                return self._json(400, {'message': 'Exchange ID, 1-5 rating, and written review are required.'})
            review_text = review_text.strip()

            conn = db_connection()
            cur = conn.cursor()
            cur.execute(
                "SELECT buyer_id, seller_id, status FROM marketplace_orders "
                "WHERE id = %s",
                (exchange_id,),
            )
            order = cur.fetchone()
            is_marketplace_order = order is not None
            if not order:
                cur.execute(
                    "SELECT buyer_id, seller_id, status FROM exchange_orders "
                    "WHERE id = %s",
                    (exchange_id,),
                )
                order = cur.fetchone()
            completed_status = (
                'delivered' if is_marketplace_order else 'completed'
            )
            if not order or order['status'] != completed_status:
                cur.close()
                conn.close()
                return self._json(409, {'message': 'Reviews are only allowed after an order is delivered.'})

            if user_id not in (order['buyer_id'], order['seller_id']):
                cur.close()
                conn.close()
                return self._json(403, {'message': 'You were not a participant in this order.'})

            reviewee_id = order['seller_id'] if user_id == order['buyer_id'] else order['buyer_id']
            review_id = str(uuid.uuid4())
            try:
                cur.execute(
                    "INSERT INTO reviews (id, exchange_id, reviewer_id, reviewee_id, rating, review) "
                    "VALUES (%s, %s, %s, %s, %s, %s)",
                    (review_id, exchange_id, user_id, reviewee_id, rating, review_text)
                )
                notify(cur, reviewee_id, "New Review Received", f"A reader left you a {rating}-star review!", 'review', review_id)
                conn.commit()
            except Exception as error:
                conn.rollback()
                cur.close()
                conn.close()
                if _is_unique_conflict(error):
                    return self._json(409, {'message': 'You have already reviewed this order.'})
                logging.error('Review submission failed (%s).', type(error).__name__)
                return self._json(500, {'message': 'Unable to submit the review right now.'})

            cur.close()
            conn.close()
            return self._json(201, {'id': review_id, 'status': 'created'})

        # Mark Notification as Read
        if path == '/notifications/read':
            notif_id = body.get('notification_id')
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("UPDATE notifications SET is_read = 1 WHERE id = %s AND user_id = %s", (notif_id, user_id))
            conn.commit()
            cur.close()
            conn.close()
            return self._json(200, {'status': 'read'})

        # Mark All Notifications as Read
        if path == '/notifications/read-all':
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("UPDATE notifications SET is_read = 1 WHERE user_id = %s", (user_id,))
            conn.commit()
            cur.close()
            conn.close()
            return self._json(200, {'status': 'all_read'})

        # Saved Books
        if path == '/saved-books':
            title = body.get('title', '').strip()
            author = body.get('author', '').strip()
            category = body.get('category', 'Fiction').strip()
            cover_url = body.get('cover_url')
            if not title or not author:
                return self._json(400, {'message': 'Title and author are required.'})
            conn = db_connection()
            cur = conn.cursor()
            if conn.db_type == 'mysql':
                cur.execute(
                    "INSERT INTO saved_books (id, user_id, title, author, category, cover_url) VALUES (%s, %s, %s, %s, %s, %s) "
                    "ON DUPLICATE KEY UPDATE author = VALUES(author), category = VALUES(category), cover_url = VALUES(cover_url)",
                    (str(uuid.uuid4()), user_id, title, author, category, cover_url)
                )
            else:
                cur.execute(
                    "INSERT OR REPLACE INTO saved_books (id, user_id, title, author, category, cover_url) VALUES (%s, %s, %s, %s, %s, %s)",
                    (str(uuid.uuid4()), user_id, title, author, category, cover_url)
                )
            conn.commit()
            cur.close()
            conn.close()
            return self._json(201, {'status': 'saved'})

        if path == '/saved-books/remove':
            title = body.get('title', '').strip()
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("DELETE FROM saved_books WHERE user_id = %s AND title = %s", (user_id, title))
            conn.commit()
            cur.close()
            conn.close()
            return self._json(200, {'status': 'removed'})

        if path == '/borrow':
            return self._json(
                410,
                {'message': 'Borrowing is no longer supported. Buy physical books through marketplace listings.'},
            )

        return self._json(404, {'message': f'Not found: {path}'})

    def do_DELETE(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip('/') or '/'
        if path.startswith('/api/'):
            path = path[4:]
        user_id = self._auth_user()
        if not user_id:
            return self._json(401, {'message': 'Authentication required.'})

        if path.startswith('/listings/'):
            listing_id = path.split('/')[-1]
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("SELECT status FROM exchange_listings WHERE id = %s AND owner_id = %s", (listing_id, user_id))
            row = cur.fetchone()
            if not row:
                cur.close()
                conn.close()
                return self._json(404, {'message': 'Listing not found or unauthorized.'})
            if row['status'] != 'available':
                cur.close()
                conn.close()
                return self._json(409, {'message': 'Cannot remove a listing with an active exchange.'})
            cur.execute("DELETE FROM exchange_listings WHERE id = %s", (listing_id,))
            conn.commit()
            cur.close()
            conn.close()
            return self._json(200, {'status': 'deleted'})

        if path.startswith('/wanted-books/'):
            wanted_id = path.split('/')[-1]
            conn = db_connection()
            cur = conn.cursor()
            cur.execute("DELETE FROM wanted_books WHERE id = %s AND user_id = %s", (wanted_id, user_id))
            conn.commit()
            cur.close()
            conn.close()
            return self._json(200, {'status': 'deleted'})

        return self._json(404, {'message': 'Not found'})

    def log_message(self, format, *args):
        # Keep logs clean and readable
        pass


def run_server():
    validate_token_secret()
    if APP_ENV not in ('development', 'test', 'production'):
        raise RuntimeError('APP_ENV must be development, test, or production.')
    if APP_ENV == 'production':
        missing = [
            key for key in (
                'DB_USER',
                'DB_NAME',
                'DB_PASSWORD',
                'CORS_ALLOWED_ORIGINS',
            )
            if not os.getenv(key, '').strip()
        ]
        if not any(
            os.getenv(key, '').strip()
            for key in ('DB_HOST', 'DB_UNIX_SOCKET')
        ):
            missing.append('DB_HOST or DB_UNIX_SOCKET')
        if os.getenv('DB_TYPE', 'auto').strip().lower() != 'mysql':
            missing.append('DB_TYPE=mysql')
        if os.getenv('MYSQL_AUTO_CREATE_DATABASE', '').strip().lower() != 'false':
            missing.append('MYSQL_AUTO_CREATE_DATABASE=false')
        if '*' in CORS_ALLOWED_ORIGINS:
            missing.append('CORS_ALLOWED_ORIGINS must list exact trusted origins')
        if any(
            urlparse(origin).scheme != 'https'
            or not urlparse(origin).netloc
            or urlparse(origin).path
            or urlparse(origin).query
            or urlparse(origin).fragment
            or urlparse(origin).username
            or urlparse(origin).password
            or urlparse(origin).hostname in ('localhost', '127.0.0.1')
            for origin in CORS_ALLOWED_ORIGINS
        ):
            missing.append('CORS_ALLOWED_ORIGINS must use trusted HTTPS origins')
        if HOST not in ('0.0.0.0', '::'):
            missing.append('API_HOST=0.0.0.0 (behind a TLS-terminating proxy)')
        if missing:
            raise RuntimeError(
                'Production configuration is incomplete: ' + ', '.join(missing)
            )
    ensure_schema()
    server = ThreadingHTTPServer((HOST, PORT), APIHandler)
    print(f"Leaf & Lore API server running on {HOST}:{PORT} (DB: {get_db_type()})")
    server.serve_forever()


if __name__ == '__main__':
    run_server()
