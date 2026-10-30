# Leaf & Lore — Credit-Based Book Marketplace

Leaf & Lore is a credit-based marketplace for buying and selling physical books. Buyers place orders with credits and provide a delivery address; sellers ship the book and add carrier/tracking details. The Flutter app is backed by a Python REST API and MySQL, with SQLite for local development.

The marketplace operates around the order loop:
**DISCOVER → BUY WITH CREDITS → SELLER SHIPS → TRACK → CONFIRM DELIVERY**

---

## Key Features

1. **Shipped Book Marketplace**:
   - Buyers select an available listing, enter a delivery address, and place an order using credits.
   - Sellers choose a listing price from 1 to 20 credits; the API enforces the same maximum on listing creation and checkout.
   - A listing can only be purchased once; the API checks availability, debits the buyer, credits the seller, records both ledger entries, and creates the order in one database transaction.
   - Credits transfer to the seller immediately at checkout, as configured for this product.
   - The seller pays shipping; no separate shipping charge is collected in the app.
   - Sellers see the buyer's order address and submit carrier and tracking details. Buyers can confirm delivery.
   - Orders move through `PAID` → `SHIPPED` → `DELIVERED`. Order changes are refreshed in the app periodically and on pull-to-refresh.

2. **Atomic Credit Ledger & Economy**:
   - Append-only transactional credit ledger with full audit history (`welcome`, `spent`, `earned`, `refund`).
   - New members receive 15 welcome credits upon account registration.
   - Sellers receive credits at marketplace checkout; creating a listing does not mint credits.
   - Balance changes are performed strictly inside database transactions; client code never modifies balances locally.
   - Credit purchases use backend-priced Razorpay orders; credits are granted only after backend verification and a signed provider webhook.

3. **Marketplace Discovery & Trust**:
   - Search and filter listings by title, author, category, and condition.
   - Readers can save books, post wanted-book requests, and view seller ratings and order history.

4. **Professional Material 3 Visual Identity**:
   - Custom **Leaf & Lore** color palette (Deep Forest Pine `#1B3B2B`, Leaf Sage `#52796F`, Warm Amber Gold `#D4A359`, Parchment `#FBF9F5`).
   - 5-tab core navigation: **Home**, **Discover**, **Orders**, **Activity**, **Profile**.
   - Accessible Dark and Light mode support with Material 3 tokens.
   - Professional loading skeletons, empty states with clear calls to action, and network error handling.
5. **Book discovery catalog**:
   - Home and Discover display real book titles and cover thumbnails from Open Library, separately labeled from books listed for sale by community members.

---

## Architecture

```
Flutter Client (Material 3 Mobile App)
       │
       ▼ HTTP REST (Bearer Token Authentication)
Python API Server (api/server.py)
   ├── auth.py (Scrypt Password Hashing & HMAC Session Tokens)
   ├── db.py (MySQL 8+ with Transparent SQLite Development Fallback)
   ├── services/credit_service.py (Credit balances, purchases & ledger)
   ├── services/credit_purchase_service.py (Server-priced checkout & verified purchase settlement)
   └── services/marketplace_service.py (Atomic purchase, seller shipping & delivery confirmation)
       │
       ▼
Relational Database (MySQL `bookexchange` or SQLite `api/bookexchange.db`)
```

Marketplace order addresses are stored with the order and visible only to the
buyer and seller. Shipping carrier/tracking details are entered manually by the seller;
the app does not currently integrate carrier APIs or verify delivery
independently. Since credits are transferred immediately, order disputes,
automatic refunds, and payment reversals require an operational support process
before public production launch.

---

## Marketplace Order API

`POST /marketplace/orders` requires authentication, a complete shipping address,
and an `Idempotency-Key` header. The API locks the listing, verifies the buyer's
balance, transfers credits, stores the order, and marks the listing sold in one
transaction. Repeated requests with the same key and payload return the original
order without charging again.

`GET /marketplace/orders` returns only orders where the authenticated user is
the buyer or seller. Sellers add carrier and tracking details with
`POST /marketplace/orders/<id>/ship`; buyers confirm delivery with
`POST /marketplace/orders/<id>/delivered`. Delivered participants can leave one
review per order. Legacy in-person exchange endpoints return HTTP 410 and are
not used by the app.

`GET /book-catalog` returns cached featured book metadata from Open Library
with cover-image URLs. Catalog books are recommendations only, not seller
inventory; only member listings in Discover can be purchased.

---

## Wallet & Ledger API

`GET /credits` is an authenticated, read-only wallet endpoint. The server derives
the account from the authenticated session; clients cannot request another
user's wallet. `limit` is optional (default `50`, allowed range `1`–`100`), and
`cursor` is an opaque continuation token returned by the previous page:

```text
GET /credits?limit=50
GET /credits?limit=50&cursor=<next_cursor>
```

Each response includes the current `balance`, aggregate `summary`, the current
page of `ledger` entries, `has_more`, and `next_cursor` (null when there is no
next page). Entries are ordered newest first, with a stable ID tie-breaker.
Invalid limits or cursors return HTTP 400. The wallet screen loads older
entries on demand and supports pull-to-refresh; failed page requests can be
retried without discarding already loaded entries. Purchase callbacks do not
award credits in the client: the app re-queries the backend purchase status and
wallet after verification, and offers an explicit status check for purchases
still pending or processing.

## Running the Application

### Quick start on Windows

Run the app and its local API together from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_local.ps1
```

The launcher reuses a healthy API on port 8081 or starts one, waits for its
`/health` check to pass, then runs Flutter in Chrome with the matching API URL.
Override the local API port by setting `API_PORT` before launching. It creates
and reuses a local API signing secret under `%LOCALAPPDATA%\LeafAndLore`; the
secret is not stored in the repository. Press Ctrl+C to stop the app and any
API process started by the launcher. If the Flutter web app is already running,
start just the API with
`powershell -NoProfile -ExecutionPolicy Bypass -File .\run_local.ps1 -ApiOnly`.

### 1. Start the Backend API

To start with MySQL:
```powershell
$env:API_TOKEN_SECRET = (python -c "import secrets; print(secrets.token_urlsafe(48))")
$env:API_PORT = '8081'
$env:DB_USER = 'root'
$env:DB_PASSWORD = '<your-mysql-password>'
$env:DB_NAME = 'bookexchange'
python api/server.py
```

For SQLite development, set `API_TOKEN_SECRET` and `API_PORT=8081` in the
same way before starting `python api/server.py`. Keep the same secret across
restarts; generating a new one invalidates existing sessions. The API refuses
to start without a sufficiently long `API_TOKEN_SECRET`. The first start after
enabling server-side session tracking requires users to sign in again. Never
put this secret in the Flutter app or commit its value.

*Note: A clean database starts empty; the API does not insert fictional community members, books, or exchanges. If no MySQL credentials are provided, the API uses the local SQLite database (`api/bookexchange.db`) with schema initialization. If MySQL credentials are configured but the connection fails, startup fails instead of silently writing to a different SQLite database. Set `DB_TYPE=sqlite` explicitly to force local development storage.*

### Production deployment baseline

The API container is built from the repository `Dockerfile`. Production startup
refuses SQLite, wildcard or non-HTTPS browser origins, MySQL database-creation
privileges, missing database credentials, and the local-only bind address.
Provision an empty MySQL database first and give the API a database-scoped user;
the API applies its schema migrations at startup. Put the container behind a
managed HTTPS reverse proxy and set `API_HOST=0.0.0.0`.

Configure these server-side values in the hosting provider (do not commit them
or put secrets in Flutter build arguments):

```text
APP_ENV=production
API_HOST=0.0.0.0
API_PORT=8080
API_TOKEN_SECRET=<long random secret>
DB_TYPE=mysql
MYSQL_AUTO_CREATE_DATABASE=false
DB_HOST=<managed MySQL host>
DB_PORT=3306
DB_USER=<database-scoped user>
DB_PASSWORD=<database password>
DB_NAME=bookexchange
CORS_ALLOWED_ORIGINS=https://<your-app-domain>
CLOUDINARY_CLOUD_NAME=<cloud name>
CLOUDINARY_API_KEY=<server-side API key>
CLOUDINARY_API_SECRET=<server-side API secret>
```

The checked-in `.env.example` is a variable-name template only; the API does not
load `.env` files automatically. Use the hosting provider's secret manager or
set environment variables in the process environment. Flutter must be built
with the deployed API base URL using
`--dart-define=API_BASE_URL=https://<your-api-domain>`.

Provider recommendations compatible with this stack:

- **Railway** for a straightforward Docker API deployment and managed MySQL;
  Render or another Docker host plus managed MySQL is also suitable.
- **Cloudinary** for signed book-cover uploads. Upload signing is implemented;
  it remains intentionally unavailable until all three Cloudinary variables
  are configured.
- **Razorpay** for credit purchases. Payment processing is implemented and
  stays disabled until the server-side test/live credentials and webhook are
  configured.
- **Firebase Cloud Messaging** for push notifications is a future integration;
  the current app uses persisted in-app notifications and does not claim push
  delivery.

### Railway deployment (API + managed MySQL)

The API and database must both run in the cloud for the phone app to work while
your PC is off. MySQL Workbench is a desktop client; a MySQL server reachable
only from your PC is not a hosted database. Do not send database passwords or
API signing secrets in chat, source control, or Flutter build arguments.

1. Create a Railway account and a new project. Add a MySQL service and a
   service deployed from this GitHub repository. Railway detects the root
   `Dockerfile` automatically; the Docker image starts `api/server.py`.
2. In the API service's Variables, configure the following. Select the
   generated Railway MySQL service in variable references (name it `MySQL` to
   use the examples below). Set secrets directly in Railway's private variable
   editor:

   ```text
   APP_ENV=production
   API_HOST=0.0.0.0
   API_PORT=8080
   API_TOKEN_SECRET=<generate a unique random value of at least 32 characters>
   DB_TYPE=mysql
   MYSQL_AUTO_CREATE_DATABASE=false
   DB_HOST=${{MySQL.MYSQLHOST}}
   DB_PORT=${{MySQL.MYSQLPORT}}
   DB_USER=${{MySQL.MYSQLUSER}}
   DB_PASSWORD=${{MySQL.MYSQLPASSWORD}}
   DB_NAME=${{MySQL.MYSQLDATABASE}}
   CORS_ALLOWED_ORIGINS=https://<your-api-domain>
   ```

   Generate the signing secret locally with
   `python -c "import secrets; print(secrets.token_urlsafe(48))"` and paste it
   directly into Railway. Do not share the value. The API initializes its
   schema in the managed database on startup. If preserving data from a
   separate local MySQL server, export and import that data using MySQL
   Workbench; deploying the API does not transfer local data automatically.
3. Deploy the API service. In its Networking settings, generate a public
   HTTPS domain and configure the service's target port as `8080`. Replace the
   `CORS_ALLOWED_ORIGINS` placeholder with the generated HTTPS origin (scheme
   and host only), then redeploy. Open `https://<your-api-domain>/health`;
   continue only when it returns `{"status":"ok","database":"mysql"}`.
4. From the repository root, build and install an Android APK that points to
   the deployed API:

   ```powershell
   flutter build apk --release --dart-define=API_BASE_URL=https://<your-api-domain>
   adb install -r .\build\app\outputs\flutter-apk\app-release.apk
   ```

   Replace the placeholder with the exact Railway HTTPS domain. No PC API
   process or USB port forwarding is needed after this installation. The app
   still needs internet access and the Railway API and database must remain
   available; hosting does not prevent errors caused by outages, network loss,
   or invalid server configuration. Configure database backups before relying
   on production data.

## Razorpay Test Payment Setup

Razorpay is used for the India-oriented native Flutter checkout. The Credit Store stays disabled unless the backend has a Razorpay test key ID, test key secret, and webhook secret. The API rejects key IDs that do not begin with `rzp_test_`. `.env.example` lists variable names only; the API reads process environment variables. Keep both key secrets on the backend only, never in Flutter source, Git, README, screenshots, or APK assets.

1. Create or sign in to your account at the [Razorpay Dashboard](https://dashboard.razorpay.com/).
2. Switch the Dashboard to **Test Mode**.
3. Open **Account & Settings → API Keys** and generate test keys. Keep the `rzp_test_...` Key ID and matching Key Secret for the backend environment.
4. In the PowerShell terminal that will run the API, set the test credentials:

   ```powershell
   $env:API_PORT = '8081'
   $env:RAZORPAY_KEY_ID = 'rzp_test_<your-test-key-id>'
   $env:RAZORPAY_KEY_SECRET = '<your-test-key-secret>'
   $env:RAZORPAY_WEBHOOK_SECRET = '<your-webhook-signing-secret>'
   ```

5. Razorpay webhooks require a publicly reachable HTTPS URL on port 80 or 443. For local testing with the Windows launcher, run an HTTPS tunnel to port 8081 (for example, `ngrok http 8081`) and configure the resulting HTTPS URL plus `/webhooks/razorpay` in **Account & Settings → Webhooks**. Subscribe to `order.paid`. Copy the webhook secret configured in the Dashboard into `RAZORPAY_WEBHOOK_SECRET`, then restart the API. Do not disable signature verification or expose an unsigned endpoint.
6. Start the API in the same PowerShell session that has the three environment variables:

   ```powershell
   python api/server.py
   ```

7. Connect the Android phone over USB, keep the API running, and forward its local API port:

   ```powershell
   adb reverse tcp:8081 tcp:8081
   ```

   Run/reopen Leaf & Lore, sign in, and navigate to **Profile → Wallet → Buy Credits**. Checkout is enabled only when the API reports configured Razorpay TEST MODE credentials.
8. Choose a package and confirm. The backend resolves the price and creates the Razorpay order; Flutter receives only the public test Key ID and order details. The Key Secret never leaves the backend.
9. Complete a payment using Razorpay’s official [test-mode payment details](https://razorpay.com/docs/payments/payment-gateway/flutter-integration/standard/integration-steps/#2-test-integration). Test mode simulates success/failure and does not charge a real card.
10. Confirm the Razorpay Dashboard shows the test order/payment and the webhook listener/tunnel receives the signed `order.paid` event. The backend checks the signature, order, package, amount, currency, and captured status before settlement. A Flutter callback alone cannot award credits.
11. Return to the app. The server verifies the SDK callback with Razorpay and refreshes the purchase status; the webhook is also independently verified. Confirm **Credit Store → Purchase History** shows `completed`, the backend balance has increased once, and the credit ledger has one `credit_purchase` entry. Replaying the event must not add credits again.

Use only the test API keys for this flow. Switch to Live Mode only after account approval and a separately reviewed production go-live; this README does not configure live payments.

The Credit Store also displays the supplied static PhonePe UPI QR for manual
transfers. It is not a Razorpay order QR, does not encode a package amount, and
is not connected to payment verification or automatic credit settlement.
Verify the recipient in PhonePe; use verified Razorpay checkout for credit
top-ups. Do not treat a static-QR transfer as an in-app purchase.

Default package definitions and example prices are centralized in `api/services/credit_purchase_service.py`. Deployments can override them with server-side `CREDIT_PACKAGES_JSON`, a JSON array of `{ "id", "name", "credits", "amount_minor", "currency", "popular" }` records; amounts use the currency's minor unit. Review package pricing and applicable payment/legal requirements before enabling any live environment.

### 2. Run the Flutter Mobile App

In another terminal:
```powershell
flutter run
```
Or specify the API host:
```powershell
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8081
```

The app does not show a simulated checkout. Credit purchases are available only after real Razorpay credentials are configured on the API; until then the store explains that payment is unavailable and does not create fake orders or credits.

---

## Automated Verification & Testing

Verify both the frontend and backend with automated test suites:

```powershell
# 1. Run Flutter static analysis (0 errors guaranteed)
flutter analyze

# 2. Run Flutter widget and component tests
flutter test

# 3. Run Backend API smoke test
python api/smoke_test.py

# 4. Run multi-user API regression tests
python api/multi_user_test.py

# 5. Run atomic marketplace purchase and shipping tests
python api/marketplace_test.py

# 6. Run isolated credit purchase/webhook security tests
python api/credit_purchase_test.py

# 7. Verify non-destructive SQLite schema upgrades
python api/schema_migration_test.py

# 8. Verify authenticated Cloudinary signature behavior and unconfigured response
python api/upload_test.py

# 9. Verify production startup rejects unsafe configuration
python api/runtime_config_test.py
```

The backend integration tests start their own temporary SQLite database and
ephemeral HTTP server; they do not need the local API running and do not modify
`api/bookexchange.db`.
