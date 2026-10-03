-- Who stays after the first purchase: the SQL I submitted in Atterna
-- Data: the fictional marketplace Meridian (schema `meridian`, DuckDB).

-- 1. How many new customers arrive each month: By month, April to November: how many customers made their first paid purchase that month.
WITH first_purchase AS (
    SELECT customer_id, MIN(created_at) AS first_at
    FROM meridian.order_history
    WHERE status = 'paid'
    GROUP BY customer_id
)
SELECT date_trunc('month', first_at) AS cohort_month,
       COUNT(*)                      AS customers
FROM first_purchase
WHERE first_at >= TIMESTAMP '2026-04-01' AND first_at < TIMESTAMP '2026-12-01'
GROUP BY cohort_month
ORDER BY cohort_month;

-- 2. Retention by cohort: For the cohorts from April onwards (today is 1 December): how many customers are in the cohort, how many of them paid for another order in the next calendar month, and what percentage that is. The report includes only the cohorts whose retention can already be calculated fairly.
WITH first_purchase AS (
    SELECT customer_id, MIN(created_at) AS first_at
    FROM meridian.order_history
    WHERE status = 'paid'
    GROUP BY customer_id
),
returned_next_month AS (
    SELECT DISTINCT f.customer_id
    FROM first_purchase AS f
    JOIN meridian.order_history AS o
      ON o.customer_id = f.customer_id
     AND o.status = 'paid'
     AND date_trunc('month', o.created_at) = date_trunc('month', f.first_at) + INTERVAL 1 MONTH
)
SELECT date_trunc('month', f.first_at)                AS cohort_month,
       COUNT(*)                                       AS customers,
       COUNT(r.customer_id)                           AS retained_m1,
       100.0 * COUNT(r.customer_id) / COUNT(*)        AS retention_m1_pct
FROM first_purchase AS f
LEFT JOIN returned_next_month AS r ON r.customer_id = f.customer_id
WHERE f.first_at >= TIMESTAMP '2026-04-01'
  AND f.first_at <  TIMESTAMP '2026-11-01'      -- today is 1 December: November's next month has barely started
GROUP BY cohort_month
ORDER BY cohort_month;

-- 3. Who really didn't come back: For the April–October cohorts, split customers into those whose first paid purchase had the AUTUMN20 code ('promo') and everyone else ('regular'). For each cohort–type pair: how many customers and the month-1 retention.
WITH
paid AS (
    SELECT customer_id, created_at, promo_code,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created_at) AS order_no
    FROM meridian.order_history
    WHERE status = 'paid'
),
first_order AS (
    SELECT customer_id,
           created_at AS first_at,
           CASE WHEN promo_code = 'AUTUMN20' THEN 'promo' ELSE 'regular' END AS first_type
    FROM paid
    WHERE order_no = 1
),
came_back AS (
    SELECT DISTINCT f.customer_id
    FROM first_order AS f
    JOIN meridian.order_history AS o
      ON o.customer_id = f.customer_id
     AND o.status = 'paid'
     AND date_trunc('month', o.created_at) = date_trunc('month', f.first_at) + INTERVAL 1 MONTH
)
SELECT date_trunc('month', f.first_at)         AS cohort_month,
       f.first_type,
       COUNT(*)                                AS customers,
       100.0 * COUNT(c.customer_id) / COUNT(*) AS retention_m1_pct
FROM first_order AS f
LEFT JOIN came_back AS c ON c.customer_id = f.customer_id
WHERE f.first_at >= TIMESTAMP '2026-04-01' AND f.first_at < TIMESTAMP '2026-11-01'
GROUP BY cohort_month, f.first_type
ORDER BY cohort_month, f.first_type;

-- 4. Came back, or stocked up?: For the September cohort, by type of first purchase: how many customers, what share paid for at least one more order within 60 days of the first (as in Tomás's report), and what share placed another order without a promo code in those same 60 days (the first order doesn’t count).
WITH
paid AS (
    SELECT customer_id, created_at, promo_code,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created_at) AS order_no
    FROM meridian.order_history
    WHERE status = 'paid'
),
first_order AS (
    SELECT customer_id,
           created_at AS first_at,
           CASE WHEN promo_code = 'AUTUMN20' THEN 'promo' ELSE 'regular' END AS first_type
    FROM paid
    WHERE order_no = 1
),
within_60_days AS (
    SELECT f.customer_id,
           COUNT(*)                                       AS later_orders,
           COUNT(*) FILTER (WHERE o.promo_code IS NULL)   AS later_full_price_orders
    FROM first_order AS f
    JOIN meridian.order_history AS o
      ON o.customer_id = f.customer_id
     AND o.status = 'paid'
     AND o.created_at >  f.first_at
     AND o.created_at <  f.first_at + INTERVAL 60 DAY
    GROUP BY f.customer_id
)
SELECT f.first_type,
       COUNT(*)                                                           AS customers,
       100.0 * COUNT(w.customer_id) / COUNT(*)                            AS repeat_pct,
       100.0 * COUNT(*) FILTER (WHERE w.later_full_price_orders > 0) / COUNT(*) AS full_price_pct
FROM first_order AS f
LEFT JOIN within_60_days AS w ON w.customer_id = f.customer_id
WHERE f.first_at >= TIMESTAMP '2026-09-01' AND f.first_at < TIMESTAMP '2026-10-01'
GROUP BY f.first_type
ORDER BY f.first_type;

-- 5. How much the platform earned on them: For the September cohort, by type of first purchase: how many customers, and GMV and platform contribution per customer over the first 60 days, including the first purchase. An order's contribution is commission_eur minus platform_discount_eur.
WITH
paid AS (
    SELECT customer_id, created_at, promo_code,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created_at) AS order_no
    FROM meridian.order_history
    WHERE status = 'paid'
),
first_order AS (
    SELECT customer_id,
           created_at AS first_at,
           CASE WHEN promo_code = 'AUTUMN20' THEN 'promo' ELSE 'regular' END AS first_type
    FROM paid
    WHERE order_no = 1
),
first_60_days AS (
    SELECT f.customer_id,
           f.first_type,
           SUM(o.items_total_eur)                           AS gmv_eur,
           SUM(o.commission_eur - o.platform_discount_eur)  AS contribution_eur
    FROM first_order AS f
    JOIN meridian.order_history AS o
      ON o.customer_id = f.customer_id
     AND o.status = 'paid'
     AND o.created_at >= f.first_at
     AND o.created_at <  f.first_at + INTERVAL 60 DAY
    WHERE f.first_at >= TIMESTAMP '2026-09-01' AND f.first_at < TIMESTAMP '2026-10-01'
    GROUP BY f.customer_id, f.first_type
)
SELECT first_type,
       COUNT(*)              AS customers,
       AVG(gmv_eur)          AS gmv_per_customer_eur,
       AVG(contribution_eur) AS margin_per_customer_eur
FROM first_60_days
GROUP BY first_type
ORDER BY first_type;
