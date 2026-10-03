-- The fast-delivery badge: the SQL I submitted in Atterna
-- Data: the fictional marketplace Meridian (schema `meridian`, DuckDB).

-- 1. Did the groups split fairly?: For each group: how many users were assigned to it and what share of all participants that is.
SELECT variant,
       COUNT(*) AS users,
       100.0 * COUNT(*) / (SELECT COUNT(*) FROM meridian.ab_assignments) AS share_pct
FROM meridian.ab_assignments
GROUP BY variant
ORDER BY variant;

-- 2. Where users go missing: For each device, app version and group: how many users, and what share that is within its own device–version pair. The website has no version, so it's empty there.
WITH per_group AS (
    SELECT device, app_version, variant, COUNT(*) AS users
    FROM meridian.ab_assignments
    GROUP BY device, app_version, variant
)
SELECT device,
       app_version,
       variant,
       users,
       100.0 * users / SUM(users) OVER (PARTITION BY device, app_version) AS share_pct
FROM per_group
ORDER BY device, app_version, variant;

-- 3. Conversion where the split is fair: Leave out app version 5.2. For each remaining segment (web, 5.1, 5.3) and each group: how many users were assigned, how many of them bought at least once, and the resulting conversion.
WITH buyers AS (
    SELECT DISTINCT user_id FROM meridian.ab_orders
),
assigned AS (
    SELECT user_id, variant, COALESCE(app_version, 'web') AS segment
    FROM meridian.ab_assignments
)
SELECT a.segment,
       a.variant,
       COUNT(*)                            AS users,
       COUNT(b.user_id)                    AS buyers,
       100.0 * COUNT(b.user_id) / COUNT(*) AS conversion_pct
FROM assigned AS a
LEFT JOIN buyers AS b ON b.user_id = a.user_id
WHERE a.segment <> '5.2'      -- the split is not fair in app 5.2, so it stays out of the comparison
GROUP BY a.segment, a.variant
ORDER BY a.segment, a.variant;

-- 4. Money per user: The fair part of the test (everything except app version 5.2), by group: users, revenue, revenue per assigned user and average order value.
WITH revenue AS (
    SELECT user_id, SUM(items_total_eur) AS revenue_eur, COUNT(*) AS n_orders
    FROM meridian.ab_orders
    GROUP BY user_id
)
SELECT a.variant,
       COUNT(*)                                    AS users,
       COALESCE(SUM(r.revenue_eur), 0)             AS revenue_eur,
       COALESCE(SUM(r.revenue_eur), 0) / COUNT(*)  AS arpu_eur,
       SUM(r.revenue_eur) / SUM(r.n_orders)        AS aov_eur
FROM meridian.ab_assignments AS a
LEFT JOIN revenue AS r ON r.user_id = a.user_id
WHERE NOT (a.device = 'app' AND a.app_version = '5.2')
GROUP BY a.variant
ORDER BY a.variant;

-- 5. Effect or noise: One row: the conversion difference on the fair part (everything except app version 5.2), “badge minus control”, and the bounds of its 95% interval, in percentage points.
WITH buyers AS (
    SELECT DISTINCT user_id FROM meridian.ab_orders
),
by_group AS (
    SELECT a.variant,
           COUNT(*) AS n,
           AVG(CASE WHEN b.user_id IS NOT NULL THEN 1.0 ELSE 0.0 END) AS p
    FROM meridian.ab_assignments AS a
    LEFT JOIN buyers AS b ON b.user_id = a.user_id
    WHERE NOT (a.device = 'app' AND a.app_version = '5.2')
    GROUP BY a.variant
),
gap AS (
    SELECT t.p - c.p AS diff,
           1.96 * SQRT(t.p * (1 - t.p) / t.n + c.p * (1 - c.p) / c.n) AS margin   -- 95% interval, difference of two proportions
    FROM by_group AS t, by_group AS c
    WHERE t.variant = 'badge' AND c.variant = 'control'
)
SELECT 100 * diff             AS diff_pp,
       100 * (diff - margin)  AS ci_low_pp,
       100 * (diff + margin)  AS ci_high_pp
FROM gap;
