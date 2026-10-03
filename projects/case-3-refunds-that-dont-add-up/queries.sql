-- Refunds that don’t add up: the SQL I submitted in Atterna
-- Data: the fictional marketplace Meridian (schema `meridian`, DuckDB).

-- Step 1: Refunds in euros for each product. Refunds are stored per order, so join them to the order items by order.
WITH order_value AS (
    SELECT order_id, SUM(qty * unit_price_eur) AS value_eur
    FROM meridian.order_items
    GROUP BY order_id
)
SELECT i.product_title,
       SUM(r.amount_eur * (i.qty * i.unit_price_eur) / v.value_eur) AS refund_eur
FROM meridian.refunds AS r
JOIN meridian.order_items AS i ON i.order_id = r.order_id
JOIN order_value          AS v ON v.order_id = r.order_id
GROUP BY i.product_title
ORDER BY refund_eur DESC, i.product_title;

-- Step 2: One number: refunds on orders with at least one item priced over €20 per unit, each refund counted once. The AI's draft is in the editor — fix what's wrong, then send it.
-- The AI draft joined refunds to order_items, so an order with several lines over 20 euros was counted once per line.
-- EXISTS keeps one row per refund.
SELECT SUM(r.amount_eur) AS refunded_eur
FROM meridian.refunds AS r
WHERE EXISTS (
    SELECT 1
    FROM meridian.order_items AS i
    WHERE i.order_id = r.order_id
      AND i.unit_price_eur > 20
);

-- Step 3: For each product: paid orders that contain it, how many of them were refunded, and that share in per cent to one decimal. Count orders, not item lines.
WITH paid_products AS (
    SELECT DISTINCT i.product_title, i.order_id
    FROM meridian.order_items AS i
    JOIN meridian.orders      AS o ON o.order_id = i.order_id
    WHERE o.status = 'paid'
),
refunded_orders AS (
    SELECT DISTINCT order_id FROM meridian.refunds
)
SELECT p.product_title,
       COUNT(*)                                       AS orders,
       COUNT(r.order_id)                              AS refunded_orders,
       ROUND(100.0 * COUNT(r.order_id) / COUNT(*), 1) AS refund_rate_pct
FROM paid_products AS p
LEFT JOIN refunded_orders AS r ON r.order_id = p.order_id
GROUP BY p.product_title
ORDER BY refund_rate_pct DESC, p.product_title;

-- Step 4: The same, but only paid orders with exactly one item line: how many, how many were refunded, and the share in per cent to one decimal.
-- Completed from a template the task gave me.
WITH single_line_orders AS (
    SELECT order_id
    FROM meridian.order_items
    GROUP BY order_id
    HAVING COUNT(*) = 1        -- only here does a refund name the item
)
SELECT i.product_title,
       COUNT(*)                                       AS orders,
       COUNT(r.order_id)                              AS refunded_orders,
       ROUND(100.0 * COUNT(r.order_id) / COUNT(*), 1) AS refund_rate_pct
FROM meridian.order_items AS i
JOIN single_line_orders   AS s ON s.order_id = i.order_id
JOIN meridian.orders      AS o ON o.order_id = i.order_id AND o.status = 'paid'
LEFT JOIN meridian.refunds AS r ON r.order_id = i.order_id
GROUP BY i.product_title
ORDER BY refund_rate_pct DESC, i.product_title;
