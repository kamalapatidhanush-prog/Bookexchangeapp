import hashlib
import json
import os
import sys
import tempfile
import threading
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

_test_database = tempfile.TemporaryDirectory(prefix='leaf-lore-upload-test-')
os.environ['DB_TYPE'] = 'sqlite'
os.environ['BOOKEXCHANGE_DB_PATH'] = os.path.join(
    _test_database.name, 'upload-test.db'
)
os.environ['API_TOKEN_SECRET'] = 'upload-test-token-secret-at-least-32-chars'
os.environ.pop('CLOUDINARY_CLOUD_NAME', None)
os.environ.pop('CLOUDINARY_API_KEY', None)
os.environ.pop('CLOUDINARY_API_SECRET', None)
sys.path.insert(0, os.path.dirname(__file__))

from db import ensure_schema
from server import APIHandler

ensure_schema()
http_server = ThreadingHTTPServer(('127.0.0.1', 0), APIHandler)
server_thread = threading.Thread(target=http_server.serve_forever, daemon=True)
server_thread.start()
base_url = f'http://127.0.0.1:{http_server.server_address[1]}'


def request(method, path, body=None, token=None):
    data = None if body is None else json.dumps(body).encode('utf-8')
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    req = urllib.request.Request(
        base_url + path, data=data, headers=headers, method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode('utf-8'))


status, unauthorized = request('POST', '/uploads/signature')
assert status == 401, unauthorized

status, account = request('POST', '/auth/register', {
    'name': 'Upload Test User',
    'email': 'upload-test@example.test',
    'password': 'SecurePassword123!',
})
assert status == 201, account
token = account['token']

status, unavailable = request('POST', '/uploads/signature', token=token)
assert status == 503 and 'not configured' in unavailable['message'].lower()

os.environ['CLOUDINARY_CLOUD_NAME'] = 'leaf-lore-test'
os.environ['CLOUDINARY_API_KEY'] = 'test-api-key'
os.environ['CLOUDINARY_API_SECRET'] = 'test-api-secret'
status, signature = request('POST', '/uploads/signature', token=token)
assert status == 200, signature
assert signature['folder'].startswith(
    f"leaf-lore/users/{account['user']['id']}/book-covers"
)
assert signature['api_key'] == 'test-api-key'
assert signature['cloud_name'] == 'leaf-lore-test'
signed_params = {
    key: signature[key]
    for key in ('folder', 'public_id', 'timestamp')
}
canonical = '&'.join(
    f'{key}={signed_params[key]}' for key in sorted(signed_params)
)
expected = hashlib.sha1(
    f'{canonical}test-api-secret'.encode('utf-8')
).hexdigest()
assert signature['signature'] == expected, 'Cloudinary upload signature is invalid'

http_server.shutdown()
http_server.server_close()
_test_database.cleanup()
print('Cloudinary signing auth, unavailable state, and signature tests passed.')
