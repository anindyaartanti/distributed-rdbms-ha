USE shop;

INSERT INTO customers (customer_id, name, email) VALUES
  (102, 'Andi Genap',  'andi@example.com'),
  (104, 'Budi Genap',  'budi@example.com'),
  (106, 'Eka Genap',   'eka@example.com');

INSERT INTO orders (order_id, customer_id, order_date, amount) VALUES
  (101, 102, '2025-03-10', 150000.00),
  (102, 104, '2026-01-15', 275000.00),
  (103, 102, '2026-02-20',  99000.00);
