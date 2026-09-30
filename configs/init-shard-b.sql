USE shop;

INSERT INTO customers (customer_id, name, email) VALUES
  (101, 'Cici Ganjil', 'cici@example.com'),
  (103, 'Dewi Ganjil', 'dewi@example.com'),
  (105, 'Fajar Ganjil','fajar@example.com');

INSERT INTO orders (order_id, customer_id, order_date, amount) VALUES
  (201, 101, '2025-06-01', 320000.00),
  (202, 103, '2026-03-11', 185000.00),
  (203, 101, '2026-04-05',  75000.00);
