import json
import io
import os
import sys
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(__file__))

from services import book_catalog_service


books = book_catalog_service._normalize_books({
    'docs': [
        {'key': '/works/1', 'title': 'A Covered Book', 'author_name': ['A. Writer'], 'cover_i': 123},
        {'key': '/works/2', 'title': 'No cover'},
        {'key': '/works/3', 'title': '   ', 'cover_i': 456},
        {'key': '/works/1', 'title': 'Duplicate', 'cover_i': 789},
    ],
})
assert books == [{
    'key': '/works/1',
    'title': 'A Covered Book',
    'author': 'A. Writer',
    'cover_url': 'https://covers.openlibrary.org/b/id/123-L.jpg',
    'first_publish_year': None,
}]
assert isinstance(json.dumps(books), str)
expanded_books = book_catalog_service._normalize_books({
    'docs': [
        {
            'key': f'/works/{index}',
            'title': f'Book {index}',
            'author_name': ['Writer'],
            'cover_i': index,
        }
        for index in range(40)
    ],
})
assert len(expanded_books) == 24
book_catalog_service._cached_books = []
book_catalog_service._cached_at = 0.0
payload = json.dumps({
    'docs': [
        {'key': '/works/4', 'title': 'Catalog Test', 'author_name': ['Writer'], 'cover_i': 42},
    ],
}).encode()
with patch.object(book_catalog_service, 'urlopen', return_value=io.BytesIO(payload)) as fetch:
    first_result = book_catalog_service.get_featured_books()
    second_result = book_catalog_service.get_featured_books()
assert first_result == second_result
fetch.assert_called_once()
print('Book catalog normalization and cover filtering passed.')
