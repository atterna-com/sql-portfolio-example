-- The seller who drags things down: the SQL I submitted in Atterna
-- Data: the fictional marketplace Meridian (schema `meridian`, DuckDB).

-- 1. Cancellations by the shop: For each shop over the eight weeks: total orders, how many of them the shop cancelled itself, and what share that is in per cent.
SELECT shop_id,
       COUNT(*) AS orders,
       SUM(CASE WHEN status = 'cancelled_by_seller' THEN 1 ELSE 0 END) AS seller_cancels,
       ROUND(100.0 * SUM(CASE WHEN status = 'cancelled_by_seller' THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancel_pct
FROM meridian.shop_orders
GROUP BY shop_id
ORDER BY cancel_pct DESC, shop_id;

-- 2. Late shipments: For each shop: how many orders should already have shipped (the ship_by deadline has passed and the order wasn't cancelled), how many of those were late — shipped after the deadline or still not shipped — and the late-shipment rate. It's now 14 December, 10:00.
WITH due AS (
    SELECT shop_id,
           (shipped_at > ship_by OR shipped_at IS NULL) AS is_late
    FROM meridian.shop_orders
    WHERE status IN ('shipped', 'awaiting_shipment')
      AND ship_by <= TIMESTAMP '2026-12-14 10:00:00'          -- the deadline has passed (it is 14 December, 10:00)
)
SELECT shop_id,
       COUNT(*)                                                                AS due_orders,
       SUM(CASE WHEN is_late THEN 1 ELSE 0 END)                                AS late_orders,
       ROUND(100.0 * SUM(CASE WHEN is_late THEN 1 ELSE 0 END) / COUNT(*), 2)   AS late_pct
FROM due
GROUP BY shop_id
ORDER BY late_pct DESC, shop_id;

-- 3. Who really lets customers down: Shops with at least 30 orders over the eight weeks that break at least one rule: a rate of cancellations by the shop above 5% or a late-shipment rate above 15%. For each — the number of orders and both rates.
WITH
cancels AS (
    SELECT shop_id,
           COUNT(*) AS orders,
           100.0 * COUNT(*) FILTER (WHERE status = 'cancelled_by_seller') / COUNT(*) AS cancel_pct
    FROM meridian.shop_orders
    GROUP BY shop_id
    HAVING COUNT(*) >= 30           -- fewer orders say nothing about a shop
),
lateness AS (
    SELECT shop_id,
           100.0 * COUNT(*) FILTER (WHERE shipped_at > ship_by OR shipped_at IS NULL) / COUNT(*) AS late_pct
    FROM meridian.shop_orders
    WHERE status IN ('shipped', 'awaiting_shipment')
      AND ship_by <= TIMESTAMP '2026-12-14 10:00:00'
    GROUP BY shop_id
)
SELECT c.shop_id, c.orders, c.cancel_pct, l.late_pct
FROM cancels AS c
LEFT JOIN lateness AS l ON l.shop_id = c.shop_id
WHERE c.cancel_pct > 5 OR l.late_pct > 15
ORDER BY c.cancel_pct DESC, c.shop_id;

-- 4. Who the rating would catch: For shops with 30+ orders: the average review score, and a “behaves normally” flag (cancellations by the shop no higher than 5% and late shipments no higher than 15%). How many shops fall into each of the four combinations.
WITH
cancels AS (
    SELECT shop_id,
           COUNT(*) AS orders,
           100.0 * COUNT(*) FILTER (WHERE status = 'cancelled_by_seller') / COUNT(*) AS cancel_pct
    FROM meridian.shop_orders
    GROUP BY shop_id
    HAVING COUNT(*) >= 30           -- fewer orders say nothing about a shop
),
lateness AS (
    SELECT shop_id,
           100.0 * COUNT(*) FILTER (WHERE shipped_at > ship_by OR shipped_at IS NULL) / COUNT(*) AS late_pct
    FROM meridian.shop_orders
    WHERE status IN ('shipped', 'awaiting_shipment')
      AND ship_by <= TIMESTAMP '2026-12-14 10:00:00'
    GROUP BY shop_id
),
ratings AS (
    SELECT o.shop_id, AVG(v.rating) AS avg_rating
    FROM meridian.shop_orders  AS o
    JOIN meridian.shop_reviews AS v ON v.order_id = o.order_id
    GROUP BY o.shop_id
)
SELECT r.avg_rating >= 4.5                              AS rating_ok,
       NOT (c.cancel_pct > 5 OR l.late_pct > 15)        AS behavior_ok,
       COUNT(*)                                         AS shops
FROM cancels AS c
LEFT JOIN lateness AS l ON l.shop_id = c.shop_id
JOIN ratings       AS r ON r.shop_id = c.shop_id
GROUP BY rating_ok, behavior_ok
ORDER BY rating_ok DESC, behavior_ok DESC;

-- 5. How much of the problem sits with them: One row. Flagged shops have 30+ orders and break at least one rule, as in the task “Who really lets customers down”. How many there are, their share of the platform's GMV (items_total_eur of shipped orders), their share of all late shipments and their share of all cancellations by shops — as a percentage of the totals across all shops.
WITH per_shop AS (
    SELECT shop_id,
           COUNT(*)                                                                          AS orders,
           COUNT(*) FILTER (WHERE status = 'cancelled_by_seller')                            AS cancels,
           COUNT(*) FILTER (WHERE status IN ('shipped', 'awaiting_shipment') AND ship_by <= TIMESTAMP '2026-12-14 10:00:00') AS due,
           COUNT(*) FILTER (WHERE status IN ('shipped', 'awaiting_shipment') AND ship_by <= TIMESTAMP '2026-12-14 10:00:00'
                              AND (shipped_at > ship_by OR shipped_at IS NULL))              AS late,
           SUM(items_total_eur) FILTER (WHERE status = 'shipped')                            AS gmv
    FROM meridian.shop_orders
    GROUP BY shop_id
),
flagged AS (
    SELECT *,
           orders >= 30 AND (100.0 * cancels / orders > 5 OR 100.0 * late / NULLIF(due, 0) > 15) AS is_problem
    FROM per_shop
)
SELECT COUNT(*) FILTER (WHERE is_problem)                              AS problem_shops,
       100.0 * SUM(gmv)     FILTER (WHERE is_problem) / SUM(gmv)       AS gmv_share_pct,
       100.0 * SUM(late)    FILTER (WHERE is_problem) / SUM(late)      AS late_share_pct,
       100.0 * SUM(cancels) FILTER (WHERE is_problem) / SUM(cancels)   AS cancel_share_pct
FROM flagged;
