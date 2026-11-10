import json
import threading
import time
from urllib.error import URLError
from urllib.request import Request, urlopen


_CACHE_SECONDS = 1800
_FEATURED_BOOK_LIMIT = 24
_cache_lock = threading.Lock()
_cached_books = []
_cached_at = 0.0


def _normalize_books(payload):
    books = []
    seen = set()
    for entry in payload.get('docs', []):
        title = entry.get('title')
        cover_id = entry.get('cover_i')
        if not isinstance(title, str) or not title.strip():
            continue
        if isinstance(cover_id, bool) or not isinstance(cover_id, int):
            continue
        key = entry.get('key') or f'{title.strip().casefold()}:{cover_id}'
        if key in seen:
            continue
        seen.add(key)
        authors = entry.get('author_name') or []
        books.append({
            'key': key,
            'title': title.strip(),
            'author': authors[0] if authors else 'Unknown author',
            'cover_url': f'https://covers.openlibrary.org/b/id/{cover_id}-L.jpg',
            'first_publish_year': entry.get('first_publish_year'),
        })
        if len(books) == _FEATURED_BOOK_LIMIT:
            break
    return books


def get_featured_books():
    global _cached_books, _cached_at
    now = time.monotonic()
    with _cache_lock:
        if _cached_books and now - _cached_at < _CACHE_SECONDS:
            return list(_cached_books)

    url = (
        'https://openlibrary.org/search.json?subject=fiction&limit=80'
        '&fields=key,title,author_name,cover_i,first_publish_year'
    )
    request = Request(url, headers={'User-Agent': 'LeafAndLore/1.0'})
    try:
        with urlopen(request, timeout=8) as response:
            payload = json.loads(response.read().decode('utf-8'))
    except (OSError, URLError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError('The book catalog is temporarily unavailable.') from error

    books = _normalize_books(payload)
    if not books:
        raise RuntimeError('The book catalog returned no books with cover images.')
    with _cache_lock:
        _cached_books = books
        _cached_at = time.monotonic()
    return list(books)
