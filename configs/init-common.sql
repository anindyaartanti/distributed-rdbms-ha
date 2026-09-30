CREATE DATABASE IF NOT EXISTS shop;
USE shop;

CREATE TABLE IF NOT EXISTS customers (
  customer_id BIGINT       NOT NULL,
  name        VARCHAR(100) NOT NULL,
  email       VARCHAR(150) NOT NULL,
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (customer_id)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS orders (
  order_id    BIGINT        NOT NULL,
  customer_id BIGINT        NOT NULL,
  order_date  DATE          NOT NULL,
  amount      DECIMAL(12,2) NOT NULL,
  PRIMARY KEY (order_id, order_date),
  KEY idx_customer (customer_id)
) ENGINE = InnoDB
PARTITION BY RANGE (YEAR(order_date)) (
  PARTITION p2024 VALUES LESS THAN (2025),
  PARTITION p2025 VALUES LESS THAN (2026),
  PARTITION p2026 VALUES LESS THAN (2027),
  PARTITION pmax  VALUES LESS THAN MAXVALUE
);

CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'replpass';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'repl'@'%';

CREATE USER IF NOT EXISTS 'haproxy_check'@'%' IDENTIFIED WITH mysql_native_password BY '';
GRANT USAGE ON *.* TO 'haproxy_check'@'%';

CREATE USER IF NOT EXISTS 'orchestrator'@'%' IDENTIFIED WITH mysql_native_password BY 'orchpass';
GRANT PROCESS, REPLICATION SLAVE, REPLICATION CLIENT, RELOAD, SUPER, SHOW DATABASES ON *.* TO 'orchestrator'@'%';

CREATE USER IF NOT EXISTS 'app'@'%' IDENTIFIED WITH mysql_native_password BY 'apppass';
GRANT SELECT, INSERT, UPDATE, DELETE ON shop.* TO 'app'@'%';

FLUSH PRIVILEGES;
