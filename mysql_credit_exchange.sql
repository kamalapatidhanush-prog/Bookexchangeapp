USE bookexchange;

-- Requires the profiles table from mysql_schema.sql or api/db.py.
CREATE TABLE IF NOT EXISTS credit_accounts (
  user_id CHAR(36) PRIMARY KEY,
  balance INT NOT NULL DEFAULT 10,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT credit_accounts_user_fk FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS credit_ledger (
  id CHAR(36) PRIMARY KEY,
  user_id CHAR(36) NOT NULL,
  amount INT NOT NULL,
  type VARCHAR(64) NOT NULL,
  reference_id CHAR(36) NULL,
  description TEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT credit_ledger_user_fk FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  INDEX credit_ledger_user_idx (user_id, created_at),
  INDEX credit_ledger_page_idx (user_id, created_at, id)
);

CREATE TABLE IF NOT EXISTS credit_purchases (
  id CHAR(36) PRIMARY KEY,
  user_id CHAR(36) NOT NULL,
  client_request_id VARCHAR(128) NOT NULL,
  package_id VARCHAR(80) NOT NULL,
  credits INT NOT NULL,
  amount_minor INT NOT NULL,
  currency CHAR(3) NOT NULL,
  payment_provider VARCHAR(32) NOT NULL,
  payment_reference VARCHAR(255) NULL UNIQUE,
  checkout_url TEXT NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMP NULL,
  CONSTRAINT credit_purchases_user_fk FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  UNIQUE KEY credit_purchase_request_idx (user_id, client_request_id),
  INDEX credit_purchases_user_idx (user_id, created_at)
);

CREATE TABLE IF NOT EXISTS exchange_listings (
  id CHAR(36) PRIMARY KEY,
  owner_id CHAR(36) NOT NULL,
  title VARCHAR(255) NOT NULL,
  author VARCHAR(255) NOT NULL,
  category VARCHAR(100) NOT NULL DEFAULT 'Fiction',
  book_condition VARCHAR(50) NOT NULL DEFAULT 'Very Good',
  description TEXT NOT NULL,
  credit_value INT NOT NULL DEFAULT 10,
  lending_days INT NOT NULL DEFAULT 21,
  cover_image_url TEXT NULL,
  status ENUM('available','requested','borrowed','completed','cancelled','sold') NOT NULL DEFAULT 'available',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT exchange_listings_owner_fk FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE,
  INDEX listings_status_idx (status)
);
ALTER TABLE exchange_listings
  MODIFY status ENUM('available','requested','borrowed','completed','cancelled','sold')
  NOT NULL DEFAULT 'available';

CREATE TABLE IF NOT EXISTS exchange_orders (
  id CHAR(36) PRIMARY KEY,
  listing_id CHAR(36) NOT NULL,
  buyer_id CHAR(36) NOT NULL,
  seller_id CHAR(36) NOT NULL,
  credits INT NOT NULL,
  status ENUM('requested','accepted','rejected','handoff_pending','borrowed','return_requested','returned','completed','cancelled') NOT NULL DEFAULT 'requested',
  notes TEXT NULL,
  due_date DATETIME NULL,
  returned_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT exchange_orders_listing_fk FOREIGN KEY (listing_id) REFERENCES exchange_listings(id) ON DELETE CASCADE,
  CONSTRAINT exchange_orders_buyer_fk FOREIGN KEY (buyer_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT exchange_orders_seller_fk FOREIGN KEY (seller_id) REFERENCES profiles(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS marketplace_orders (
  id CHAR(36) PRIMARY KEY,
  listing_id CHAR(36) NOT NULL,
  buyer_id CHAR(36) NOT NULL,
  seller_id CHAR(36) NOT NULL,
  idempotency_key VARCHAR(128) NOT NULL,
  credits INT NOT NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'paid',
  recipient_name VARCHAR(100) NOT NULL,
  recipient_phone VARCHAR(40) NOT NULL,
  address_line1 VARCHAR(255) NOT NULL,
  address_line2 VARCHAR(255) NULL,
  city VARCHAR(100) NOT NULL,
  region VARCHAR(100) NOT NULL,
  postal_code VARCHAR(32) NOT NULL,
  country VARCHAR(100) NOT NULL,
  shipping_carrier VARCHAR(100) NULL,
  tracking_number VARCHAR(128) NULL,
  shipped_at TIMESTAMP NULL,
  delivered_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (listing_id) REFERENCES exchange_listings(id),
  FOREIGN KEY (buyer_id) REFERENCES profiles(id) ON DELETE CASCADE,
  FOREIGN KEY (seller_id) REFERENCES profiles(id) ON DELETE CASCADE,
  UNIQUE KEY marketplace_order_request_idx (buyer_id, idempotency_key),
  INDEX marketplace_order_buyer_idx (buyer_id, created_at),
  INDEX marketplace_order_seller_idx (seller_id, created_at)
);
