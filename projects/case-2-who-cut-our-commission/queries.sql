-- Who cut our commission?: the SQL I submitted in Atterna
-- Data: the fictional marketplace Meridian (schema `meridian`, DuckDB).

-- Step 1: Take rate for each of the three weeks: GMV of paid orders, commission and take rate in per cent, to two decimals. Commission is the goods value times the seller's rate.
-- Completed from a template the task gave me.
WITH paid AS (
    SELECT o.created_at, o.items_total_eur, s.commission_rate
    FROM meridian.orders AS o
    JOIN meridian.sellers AS s ON s.seller_id = o.seller_id
    WHERE o.status = 'paid'
)
SELECT w.week_id,
       SUM(p.items_total_eur)                                                           AS gmv_eur,
       SUM(p.items_total_eur * p.commission_rate)                                       AS commission_eur,
       ROUND(100.0 * SUM(p.items_total_eur * p.commission_rate) / SUM(p.items_total_eur), 2) AS take_rate_pct
FROM meridian.weeks AS w
JOIN paid AS p ON p.created_at >= w.week_start AND p.created_at < w.week_end
GROUP BY w.week_id
ORDER BY w.week_id;

-- Step 2: For each week and seller category: GMV of paid orders and its share of that week's GMV, in per cent to one decimal.
-- Completed from a template the task gave me.
WITH weekly_category AS (
    SELECT w.week_id, s.category, SUM(o.items_total_eur) AS gmv_eur
    FROM meridian.orders  AS o
    JOIN meridian.weeks   AS w ON o.created_at >= w.week_start AND o.created_at < w.week_end
    JOIN meridian.sellers AS s ON s.seller_id = o.seller_id
    WHERE o.status = 'paid'
    GROUP BY w.week_id, s.category
)
SELECT week_id,
       category,
       gmv_eur,
       ROUND(100.0 * gmv_eur / SUM(gmv_eur) OVER (PARTITION BY week_id), 1) AS share_pct
FROM weekly_category
ORDER BY week_id, share_pct DESC, category;

-- Step 3: For each week: commission on paid orders, the discounts the platform paid on those orders, and commission after the discounts.
-- Completed from a template the task gave me.
SELECT w.week_id,
       SUM(o.items_total_eur * s.commission_rate)                            AS commission_eur,
       SUM(o.platform_discount_eur)                                          AS discount_eur,
       SUM(o.items_total_eur * s.commission_rate - o.platform_discount_eur)  AS net_eur
FROM meridian.orders  AS o
JOIN meridian.sellers AS s ON s.seller_id = o.seller_id
JOIN meridian.weeks   AS w ON o.created_at >= w.week_start AND o.created_at < w.week_end
WHERE o.status = 'paid'
GROUP BY w.week_id
ORDER BY w.week_id;
