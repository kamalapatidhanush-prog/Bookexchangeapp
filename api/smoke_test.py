import os
import sys
import tempfile
import json
from http.server import ThreadingHTTPServer
from threading import Thread
from urllib.request import urlopen

_test_database = tempfile.TemporaryDirectory(prefix='leaf-lore-smoke-test-')
os.environ['DB_TYPE'] = 'sqlite'
os.environ['BOOKEXCHANGE_DB_PATH'] = os.path.join(
    _test_database.name, 'smoke-test.db'
)
os.environ['API_TOKEN_SECRET'] = 'smoke-test-token-secret-at-least-32-chars'
sys.path.insert(0, os.path.dirname(__file__))

from db import ensure_schema
from server import APIHandler

ensure_schema()
_http_server = ThreadingHTTPServer(('127.0.0.1', 0), APIHandler)
_server_thread = Thread(target=_http_server.serve_forever, daemon=True)
_server_thread.start()
BASE_URL = f'http://127.0.0.1:{_http_server.server_address[1]}'


def get_json(path):
    with urlopen(BASE_URL + path, timeout=5) as response:
        assert response.status == 200, response.status
        return json.loads(response.read().decode('utf-8'))


health = get_json('/health')
assert health['status'] == 'ok'

books = get_json('/books')
assert isinstance(books.get('books'), list)

listings = get_json('/listings')
assert isinstance(listings.get('listings'), list)

wanted = get_json('/wanted-books')
assert isinstance(wanted.get('wanted_books'), list)

activity = get_json('/activity')
assert isinstance(activity.get('activities'), list)

assert books['books'] == [], 'A new local database must not contain sample books'
assert listings['listings'] == [], 'A new local database must not contain sample listings'
assert wanted['wanted_books'] == [], 'A new local database must not contain sample requests'
print("API smoke test passed with an empty, sample-free database.")
