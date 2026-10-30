-- Leaf & Lore production schema (MySQL 8+).
CREATE DATABASE IF NOT EXISTS bookexchange CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE bookexchange;

CREATE TABLE IF NOT EXISTS profiles (
  id CHAR(36) PRIMARY KEY, display_name VARCHAR(100) NOT NULL, email VARCHAR(255) NOT NULL UNIQUE,
  password_hash TEXT NULL, location VARCHAR(255) NULL, bio TEXT NULL, avatar_url TEXT NULL,
  role ENUM('member','admin') NOT NULL DEFAULT 'member',
  is_active BOOLEAN NOT NULL DEFAULT TRUE, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS books (
  id CHAR(36) PRIMARY KEY, title VARCHAR(255) NOT NULL, author VARCHAR(255) NOT NULL, category VARCHAR(100) NOT NULL,
  description TEXT NOT NULL, isbn VARCHAR(32) NOT NULL, publisher VARCHAR(255), publication_year SMALLINT,
  total_copies INT NOT NULL, available_copies INT NOT NULL, cover_image_url TEXT, is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT book_copy_counts CHECK (total_copies >= 0 AND available_copies BETWEEN 0 AND total_copies)
);
CREATE TABLE IF NOT EXISTS borrowings (
  id CHAR(36) PRIMARY KEY, user_id CHAR(36) NOT NULL, book_id CHAR(36) NOT NULL, book_title VARCHAR(255) NOT NULL,
  borrowed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, due_date DATETIME NOT NULL, returned_at DATETIME NULL,
  status ENUM('active','returned') NOT NULL DEFAULT 'active', created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES profiles(id), FOREIGN KEY (book_id) REFERENCES books(id), INDEX borrowing_user_idx (user_id, status)
);
CREATE TABLE IF NOT EXISTS notifications (
  id CHAR(36) PRIMARY KEY, user_id CHAR(36) NOT NULL, title VARCHAR(255) NOT NULL, body TEXT NOT NULL,
  type VARCHAR(64) NOT NULL DEFAULT 'system', is_read BOOLEAN NOT NULL DEFAULT FALSE,
  reference_id CHAR(36) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES profiles(id), INDEX notification_user_idx (user_id, created_at)
);
CREATE TABLE IF NOT EXISTS transactions (
  id CHAR(36) PRIMARY KEY, buyer_id CHAR(36) NOT NULL, seller_id CHAR(36) NULL, book_title VARCHAR(255) NOT NULL,
  method ENUM('exchange','sale') NOT NULL, status ENUM('chatting','completed','cancelled') NOT NULL DEFAULT 'chatting',
  completed_at DATETIME NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (buyer_id) REFERENCES profiles(id), FOREIGN KEY (seller_id) REFERENCES profiles(id)
);
CREATE TABLE IF NOT EXISTS messages (
  id BIGINT AUTO_INCREMENT PRIMARY KEY, transaction_id CHAR(36) NOT NULL, sender_id CHAR(36) NOT NULL,
  message TEXT NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (transaction_id) REFERENCES transactions(id), FOREIGN KEY (sender_id) REFERENCES profiles(id)
);
CREATE TABLE IF NOT EXISTS payment_orders (
  id CHAR(36) PRIMARY KEY, buyer_id CHAR(36) NOT NULL, transaction_id CHAR(36) NULL, book_title VARCHAR(255) NOT NULL,
  amount DECIMAL(10,2) NOT NULL, payment_method ENUM('upi','card','pay_later','gift_card') NOT NULL,
  gift_card_code VARCHAR(100) NULL, status ENUM('pending','processing','paid','failed','cancelled') NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY (buyer_id) REFERENCES profiles(id),
  FOREIGN KEY (transaction_id) REFERENCES transactions(id)
);
CREATE TABLE IF NOT EXISTS gift_cards (
  id CHAR(36) PRIMARY KEY, code VARCHAR(100) NOT NULL UNIQUE, initial_amount DECIMAL(10,2) NOT NULL,
  remaining_amount DECIMAL(10,2) NOT NULL, expires_at DATETIME NULL, is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
