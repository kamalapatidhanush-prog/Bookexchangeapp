import hashlib
import os
import re
import time
import uuid


class UploadUnavailable(RuntimeError):
    pass


def create_book_cover_signature(user_id):
    cloud_name = os.getenv('CLOUDINARY_CLOUD_NAME', '').strip()
    api_key = os.getenv('CLOUDINARY_API_KEY', '').strip()
    api_secret = os.getenv('CLOUDINARY_API_SECRET', '').strip()
    if not cloud_name or not api_key or not api_secret:
        raise UploadUnavailable(
            'Book image uploads are not configured. Contact the administrator.'
        )
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', cloud_name):
        raise RuntimeError('CLOUDINARY_CLOUD_NAME is invalid.')

    params = {
        'folder': f'leaf-lore/users/{user_id}/book-covers',
        'public_id': str(uuid.uuid4()),
        'timestamp': str(int(time.time())),
    }
    canonical = '&'.join(
        f'{key}={params[key]}' for key in sorted(params)
    )
    signature = hashlib.sha1(
        f'{canonical}{api_secret}'.encode('utf-8')
    ).hexdigest()
    return {
        **params,
        'signature': signature,
        'api_key': api_key,
        'cloud_name': cloud_name,
    }
