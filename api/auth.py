import base64
import hashlib
import hmac
import os
import secrets
import time


def validate_token_secret():
    secret = os.environ.get('API_TOKEN_SECRET', '').strip()
    if len(secret) < 32:
        raise RuntimeError('API_TOKEN_SECRET must be configured with at least 32 characters.')
    return secret


def session_token_hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


def hash_password(password, salt=None):
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1)
    return base64.urlsafe_b64encode(salt + digest).decode()


def verify_password(password, encoded):
    if not encoded:
        return False
    try:
        raw = base64.urlsafe_b64decode(encoded.encode())
        salt, expected = raw[:16], raw[16:]
        actual = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1)
        return hmac.compare_digest(actual, expected)
    except Exception:
        return False


def token_for(user_id):
    # Valid for 30 days
    payload = f'{user_id}:{int(time.time()) + (86400 * 30)}:{secrets.token_urlsafe(16)}'
    signature = hmac.new(validate_token_secret().encode(), payload.encode(), hashlib.sha256).hexdigest()
    return base64.urlsafe_b64encode(f'{payload}:{signature}'.encode()).decode()


def user_from_token(token):
    try:
        payload, signature = base64.urlsafe_b64decode(token.encode()).decode().rsplit(':', 1)
        expected = hmac.new(validate_token_secret().encode(), payload.encode(), hashlib.sha256).hexdigest()
        user_id, expiry, _token_id = payload.split(':')
        if not hmac.compare_digest(signature, expected) or int(expiry) < time.time():
            return None
        return user_id
    except (ValueError, TypeError, UnicodeError, RuntimeError):
        return None


def token_from_headers(headers):
    header = headers.get('Authorization', '')
    if not header:
        return None
    return header.removeprefix('Bearer ').strip() or None


def get_auth_user_from_headers(headers):
    token = token_from_headers(headers)
    return user_from_token(token) if token else None
