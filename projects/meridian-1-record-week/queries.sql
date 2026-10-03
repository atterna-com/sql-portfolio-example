-- Record week: the SQL I submitted in Atterna
-- Data: the fictional marketplace Meridian (schema `meridian`, DuckDB).

-- 1. GMV by week: One row per week from the weeks table, with the number of paid orders and GMV.
SELECT w.week_start,
       COUNT(*)               AS orders,
       SUM(o.items_total_eur) AS gmv_eur
FROM meridian.orders AS o
JOIN meridian.weeks  AS w ON o.created_at >= w.week_start AND o.created_at < w.week_end
WHERE o.status = 'paid'
GROUP BY w.week_start
ORDER BY w.week_start;

-- 2. Where the record came from: For each of the three weeks: GMV the way the dashboard query calculates it, the correct GMV, and the average number of line items in a paid order.
WITH line_counts AS (
    SELECT order_id, COUNT(*) AS n_lines
    FROM meridian.order_items
    GROUP BY order_id
),
paid AS (
    SELECT o.created_at, o.items_total_eur, lc.n_lines
    FROM meridian.orders AS o
    JOIN line_counts     AS lc ON lc.order_id = o.order_id
    WHERE o.status = 'paid'
)
SELECT w.week_start,
       SUM(p.items_total_eur * p.n_lines) AS dashboard_gmv_eur,  -- the dashboard joins order_items: an order counts once per line
       SUM(p.items_total_eur)             AS gmv_eur,
       AVG(p.n_lines)                     AS avg_lines
FROM meridian.weeks AS w
JOIN paid AS p ON p.created_at >= w.week_start AND p.created_at < w.week_end
GROUP BY w.week_start
ORDER BY w.week_start;

-- 3. Reconciling with finance: Calculate weekly GMV, commission and take rate. Compare the totals with Olga's attachment and explain any difference.
SELECT w.week_start,
       SUM(o.items_total_eur)                                                          AS gmv_eur,
       SUM(o.items_total_eur * s.commission_rate)                                      AS commission_eur,
       100.0 * SUM(o.items_total_eur * s.commission_rate) / SUM(o.items_total_eur)     AS take_rate_pct
FROM meridian.orders  AS o
JOIN meridian.sellers AS s ON s.seller_id = o.seller_id
JOIN meridian.weeks   AS w ON o.created_at >= w.week_start AND o.created_at < w.week_end
WHERE o.status = 'paid'
GROUP BY w.week_start
ORDER BY w.week_start;

-- 4. Where the difference with finance comes from: For each week in the weeks table: our GMV of paid orders, GMV the way the finance system calculates it, and the difference “finance minus us”.
WITH paid AS (
    SELECT items_total_eur,
           created_at,
           created_at + INTERVAL 3 HOUR AS created_tallinn   -- finance books on Tallinn time, UTC+3 in September
    FROM meridian.orders
    WHERE status = 'paid'
)
SELECT w.week_start,
       SUM(p.items_total_eur) FILTER (WHERE p.created_at      >= w.week_start AND p.created_at      < w.week_end) AS gmv_eur,
       SUM(p.items_total_eur) FILTER (WHERE p.created_tallinn >= w.week_start AND p.created_tallinn < w.week_end) AS finance_gmv_eur,
       SUM(p.items_total_eur) FILTER (WHERE p.created_tallinn >= w.week_start AND p.created_tallinn < w.week_end)
     - SUM(p.items_total_eur) FILTER (WHERE p.created_at      >= w.week_start AND p.created_at      < w.week_end) AS diff_eur
FROM meridian.weeks AS w
CROSS JOIN paid AS p
GROUP BY w.week_start
ORDER BY w.week_start;

-- 5. What the platform really earned: By week: the parts of platform contribution and the total, following Olga's rules in the attachment.
WITH paid_orders AS (
    SELECT w.week_id, w.week_start, o.order_id, o.items_total_eur, o.platform_discount_eur, o.paid_eur, s.commission_rate
    FROM meridian.orders  AS o
    JOIN meridian.sellers AS s ON s.seller_id = o.seller_id
    JOIN meridian.weeks   AS w ON o.created_at >= w.week_start AND o.created_at < w.week_end
    WHERE o.status = 'paid'
),
completed_refunds AS (            -- pending refunds have not left the bank yet: they do not count
    SELECT order_id, SUM(amount_eur) AS refunded_eur
    FROM meridian.refunds
    WHERE status = 'completed'
    GROUP BY order_id
),
weekly AS (
    SELECT p.week_id,
           p.week_start,
           SUM(p.items_total_eur)                                                    AS gmv_eur,
           SUM(p.items_total_eur * p.commission_rate)
             - SUM(COALESCE(cr.refunded_eur, 0) * p.commission_rate)                 AS commission_net_eur,
           SUM(p.platform_discount_eur)                                              AS platform_discount_eur,
           SUM(p.paid_eur) * 0.018                                                   AS card_fees_eur
    FROM paid_orders AS p
    LEFT JOIN completed_refunds AS cr ON cr.order_id = p.order_id
    GROUP BY p.week_id, p.week_start
),
marketing AS (
    SELECT week_id, SUM(spend_eur) AS marketing_eur
    FROM meridian.marketing_spend
    GROUP BY week_id
)
SELECT k.week_start,
       k.gmv_eur,
       k.commission_net_eur,
       k.platform_discount_eur,
       k.card_fees_eur,
       m.marketing_eur,
       k.commission_net_eur - k.platform_discount_eur - k.card_fees_eur - m.marketing_eur AS contribution_eur
FROM weekly AS k
JOIN marketing AS m ON m.week_id = k.week_id
ORDER BY k.week_start;

-- 6. Who came for the discount: Split the promo week's paid orders into orders from new and returning customers: how many orders and how much platform discount went to each group.
WITH promo_week AS (
    SELECT o.buyer_id, o.platform_discount_eur
    FROM meridian.orders AS o
    JOIN meridian.weeks  AS w ON o.created_at >= w.week_start AND o.created_at < w.week_end
    WHERE w.is_promo AND o.status = 'paid'
),
paid_before AS (
    SELECT DISTINCT buyer_id
    FROM meridian.orders
    WHERE status = 'paid' AND created_at < TIMESTAMP '2026-09-14'
)
SELECT CASE WHEN b.buyer_id IS NULL THEN 'new' ELSE 'returning' END AS buyer_type,
       COUNT(*)                     AS orders,
       SUM(p.platform_discount_eur) AS discount_eur
FROM promo_week AS p
LEFT JOIN paid_before AS b ON b.buyer_id = p.buyer_id
GROUP BY buyer_type
ORDER BY orders DESC;
