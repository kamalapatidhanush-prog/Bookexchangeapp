import os
import sys
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(__file__))

import db


def test_cloud_sql_socket_options():
    with patch.object(db, 'DB_UNIX_SOCKET', '/cloudsql/project:region:instance'):
        assert db._mysql_connection_options() == {
            'user': db.DB_USER,
            'password': db.DB_PASSWORD or '',
            'unix_socket': '/cloudsql/project:region:instance',
            'database': db.DB_NAME,
        }


def test_tcp_mysql_options():
    with patch.object(db, 'DB_UNIX_SOCKET', None):
        assert db._mysql_connection_options() == {
            'user': db.DB_USER,
            'password': db.DB_PASSWORD or '',
            'host': db.DB_HOST,
            'port': db.DB_PORT,
            'database': db.DB_NAME,
        }


test_cloud_sql_socket_options()
test_tcp_mysql_options()
print('Cloud SQL socket and regular MySQL connection options passed.')
