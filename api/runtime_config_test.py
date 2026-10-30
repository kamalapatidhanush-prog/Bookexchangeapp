import os
import sys
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(__file__))

import server

_production_environment = {
    'API_TOKEN_SECRET': 'runtime-config-test-secret-at-least-32-characters',
    'DB_TYPE': 'mysql',
    'MYSQL_AUTO_CREATE_DATABASE': 'false',
    'DB_HOST': 'mysql.internal',
    'DB_USER': 'leaf_lore_api',
    'DB_PASSWORD': 'test-only-password',
    'DB_NAME': 'bookexchange',
    'CORS_ALLOWED_ORIGINS': 'https://books.example.com',
}

with patch.dict(os.environ, _production_environment, clear=False):
    with patch.object(server, 'APP_ENV', 'production'):
        with patch.object(server, 'HOST', '0.0.0.0'):
            with patch.object(server, 'CORS_ALLOWED_ORIGINS', {'*'}):
                try:
                    server.run_server()
                except RuntimeError as error:
                    assert 'exact trusted origins' in str(error)
                else:
                    raise AssertionError('Wildcard CORS was accepted in production')


class FakeServer:
    def __init__(self, address, handler):
        self.address = address
        self.handler = handler
        self.served = False

    def serve_forever(self):
        self.served = True


with patch.dict(os.environ, _production_environment, clear=False):
    with patch.object(server, 'APP_ENV', 'production'):
        with patch.object(server, 'HOST', '0.0.0.0'):
            with patch.object(
                server, 'CORS_ALLOWED_ORIGINS', {'https://books.example.com'}
            ):
                with patch.object(server, 'ensure_schema') as ensure_schema:
                    with patch.object(server, 'get_db_type', return_value='mysql'):
                        with patch.object(server, 'ThreadingHTTPServer', FakeServer):
                            server.run_server()
                            ensure_schema.assert_called_once()

print('Production startup validation and valid MySQL configuration passed.')
