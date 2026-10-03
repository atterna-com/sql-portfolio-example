-- Windows and the final report: the SQL I submitted in Atterna
-- Data: the fictional marketplace Meridian (schema `meridian`, DuckDB).

-- Step 1: For each category: GMV of paid orders and its share of total GMV in per cent, rounded to one decimal place.
-- Completed from a template the task gave me.
SELECT s.category,
       SUM(o.items_total_eur) AS gmv_eur,
       ROUND(100.0 * SUM(o.items_total_eur) / SUM(SUM(o.items_total_eur)) OVER (), 1) AS share_pct
FROM meridian.orders  AS o
JOIN meridian.sellers AS s ON s.seller_id = o.seller_id
WHERE o.status = 'paid'
GROUP BY s.category
ORDER BY gmv_eur DESC;

-- Step 2: Every shop with its place by GMV within its category, 1 being the biggest. Step g with the GMV figures is ready: add the window ROW_NUMBER() OVER (PARTITION BY … ORDER BY …).
-- Completed from a template the task gave me.
SELECT s.category,
       s.seller_name,
       SUM(o.items_total_eur) AS gmv_eur,
       ROW_NUMBER() OVER (PARTITION BY s.category ORDER BY SUM(o.items_total_eur) DESC) AS place
FROM meridian.orders  AS o
JOIN meridian.sellers AS s ON s.seller_id = o.seller_id
WHERE o.status = 'paid'
GROUP BY s.category, s.seller_name
ORDER BY s.category, place;

-- Step 3: For each category, the one shop with the highest GMV from paid orders, and that GMV.
-- Completed from a template the task gave me.
WITH shop_gmv AS (
    SELECT s.category, s.seller_name, SUM(o.items_total_eur) AS gmv_eur
    FROM meridian.orders  AS o
    JOIN meridian.sellers AS s ON s.seller_id = o.seller_id
    WHERE o.status = 'paid'
    GROUP BY s.category, s.seller_name
)
SELECT category, seller_name, gmv_eur
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY category ORDER BY gmv_eur DESC) AS place
    FROM shop_gmv
) AS ranked
WHERE place = 1
ORDER BY gmv_eur DESC;

-- Step 4: For each day: GMV of the day's paid orders and the running total from the first day. Sorted by day.
-- Completed from a template the task gave me.
SELECT date_trunc('day', created_at)                                         AS day,
       SUM(items_total_eur)                                                  AS gmv_eur,
       SUM(SUM(items_total_eur)) OVER (ORDER BY date_trunc('day', created_at)) AS running_gmv_eur
FROM meridian.orders
WHERE status = 'paid'
GROUP BY date_trunc('day', created_at)
ORDER BY day;

-- Step 5: For each catalogue category, the three products with the most units ordered (all orders, cancelled ones too — we're measuring demand). Only products that are in stock and were added before 1 September 2026.
WITH demand AS (
    SELECT c.category, i.product_title, SUM(i.qty) AS units
    FROM meridian.order_items AS i
    JOIN meridian.catalog     AS c ON c.title = i.product_title
    WHERE c.in_stock AND c.added_at < DATE '2026-09-01'      -- new products have not had time to sell
    GROUP BY c.category, i.product_title
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY category ORDER BY units DESC) AS place
    FROM demand
)
SELECT category, product_title, units
FROM ranked
WHERE place <= 3
ORDER BY category, units DESC, product_title;

-- Step 6: For each city: how many people registered, and how many of them made at least one paid order. Write it from an empty editor.
SELECT b.city,
       COUNT(*)                   AS registered,
       COUNT(DISTINCT p.buyer_id) AS paying
FROM meridian.buyers AS b
LEFT JOIN (
    SELECT DISTINCT buyer_id
    FROM meridian.orders
    WHERE status = 'paid'
) AS p ON p.buyer_id = b.buyer_id
GROUP BY b.city
ORDER BY registered DESC, b.city;

-- Step 7: For each category: paid orders, GMV, average order value to the cent and share of GMV in per cent to one decimal place. Sorted by GMV, from largest to smallest.
SELECT s.category,
       COUNT(*)                         AS orders,
       SUM(o.items_total_eur)           AS gmv_eur,
       ROUND(AVG(o.items_total_eur), 2) AS aov_eur,
       ROUND(100.0 * SUM(o.items_total_eur) / SUM(SUM(o.items_total_eur)) OVER (), 1) AS share_pct
FROM meridian.orders  AS o
JOIN meridian.sellers AS s ON s.seller_id = o.seller_id
WHERE o.status = 'paid'
GROUP BY s.category
ORDER BY gmv_eur DESC;

-- Step 8: One row: the report's orders added up across categories, all paid orders counted straight from orders, and the report's shares added up, to one decimal place. Steps c and r are ready: that's the report itself.
-- Completed from a template the task gave me.
WITH by_category AS (
    SELECT s.category, COUNT(*) AS orders, SUM(o.items_total_eur) AS gmv_eur
    FROM meridian.orders  AS o
    JOIN meridian.sellers AS s ON s.seller_id = o.seller_id
    WHERE o.status = 'paid'
    GROUP BY s.category
),
shares AS (
    SELECT orders, ROUND(100.0 * gmv_eur / SUM(gmv_eur) OVER (), 1) AS share_pct
    FROM by_category
)
SELECT SUM(orders)                                                    AS orders_in_report,
       (SELECT COUNT(*) FROM meridian.orders WHERE status = 'paid')   AS paid_orders,
       ROUND(SUM(share_pct), 1)                                       AS shares_sum
FROM shares;
