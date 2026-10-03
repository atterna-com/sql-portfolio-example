# The fast-delivery badge

`SQL` · `DuckDB` · `Meridian episode 2` · `Fictional marketplace data`

[← All projects](../../README.md)

## Context

Vera needs a recommendation for Wednesday's product committee: whether to roll out the fast-delivery badge and charge sellers for it.

## Why it’s not obvious

Missing participants in one app version distort the overall conversion comparison. A bigger-looking gain can reflect a broken experiment as well as the badge.

_Scenario context supplied by Atterna._

> **Finding:** On the fair part the badge probably raises conversion: +1.5 pp, 95% interval +0.2 pp to +2.9 pp.
>
> **Key numbers:** **48.60%** Badge group's share of all participants · **0.20 pp** Lower bound of the 95% interval on the fair part
>
> **My call:** Turn the badge on now for web and app 5.1 and 5.3, keeping 20% of those users without it as a holdout, and fix the event so 5.2 joins the same way. Switch the badge off if the holdout does clearly better; open the paid programme only when…

## Business question

> Product's report says conversion went up. On Wednesday they decide whether to roll the badge out and charge sellers for it.

## Approach

5 SQL queries, each checked automatically.

### 1. Did the groups split fairly?

**Task.** For each group: how many users were assigned to it and what share of all participants that is.

```sql
SELECT variant,
       COUNT(*) AS users,
       100.0 * COUNT(*) / (SELECT COUNT(*) FROM meridian.ab_assignments) AS share_pct
FROM meridian.ab_assignments
GROUP BY variant
ORDER BY variant
```

**Result** (2 rows) · [CSV](results/01-did-the-groups-split-fairly.csv)

| variant | users | share_pct |
| :--- | ---: | ---: |
| badge | 5663 | 48.647 |
| control | 5978 | 51.353 |

### 2. Where users go missing

**Task.** For each device, app version and group: how many users, and what share that is within its own device–version pair. The website has no version, so it's empty there.

```sql
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
ORDER BY device, app_version, variant
```

**Result** (8 rows) · [CSV](results/02-where-users-go-missing.csv)

| device | app_version | variant | users | share_pct |
| :--- | :--- | :--- | ---: | ---: |
| app | 5.1 | badge | 804 | 50.3759 |
| app | 5.1 | control | 792 | 49.6241 |
| app | 5.2 | badge | 1247 | 43.9239 |
| app | 5.2 | control | 1592 | 56.0761 |
| app | 5.3 | badge | 1162 | 49.7858 |
| app | 5.3 | control | 1172 | 50.2142 |
| web | NULL | badge | 2450 | 50.2874 |
| web | NULL | control | 2422 | 49.7126 |

### 3. Conversion where the split is fair

**Task.** Leave out app version 5.2. For each remaining segment (web, 5.1, 5.3) and each group: how many users were assigned, how many of them bought at least once, and the resulting conversion.

```sql
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
ORDER BY a.segment, a.variant
```

**Result** (6 rows) · [CSV](results/03-conversion-where-the-split-is-fair.csv)

| segment | variant | users | buyers | conversion_pct |
| :--- | :--- | ---: | ---: | ---: |
| 5.1 | badge | 804 | 127 | 15.796 |
| 5.1 | control | 792 | 96 | 12.1212 |
| 5.3 | badge | 1162 | 183 | 15.7487 |
| 5.3 | control | 1172 | 165 | 14.0785 |
| web | badge | 2450 | 228 | 9.3061 |
| web | control | 2422 | 206 | 8.5054 |

### 4. Money per user

**Task.** The fair part of the test (everything except app version 5.2), by group: users, revenue, revenue per assigned user and average order value.

```sql
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
ORDER BY a.variant
```

**Result** (2 rows) · [CSV](results/04-money-per-user.csv)

| variant | users | revenue_eur | arpu_eur | aov_eur |
| :--- | ---: | ---: | ---: | ---: |
| badge | 4416 | 28691.74 | 6.4972 | 43.5383 |
| control | 4386 | 24719.66 | 5.636 | 43.2919 |

### 5. Effect or noise

**Task.** One row: the conversion difference on the fair part (everything except app version 5.2), “badge minus control”, and the bounds of its 95% interval, in percentage points.

```sql
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
FROM gap
```

**Result** (1 row) · [CSV](results/05-effect-or-noise.csv)

| diff_pp | ci_low_pp | ci_high_pp |
| ---: | ---: | ---: |
| 1.5355 | 0.2073 | 2.8636 |

## Numbers I reported

_Typed by me; the checker accepted each one within its tolerance._

| Number | My value |
| :--- | ---: |
| Badge group's share of all participants | 48.60% |
| Lower bound of the 95% interval on the fair part | 0.20 pp |

## Decision and recommendation

**Option I chose:** Turn the badge on now for web and app 5.1 and 5.3, keeping 20% of those users without it as a holdout, and fix the event so 5.2 joins the same way. Switch the badge off if the holdout does clearly better; open the paid programme only when the holdout gives a clear number (Vera's proposal)

_Selected from the options the exercise offered._

**What I claimed from the numbers:** On the fair part the badge probably raises conversion: +1.5 pp, 95% interval +0.2 pp to +2.9 pp. A small gain of uncertain size from a test whose first week ran under AUTUMN20, and the test says nothing about app 5.2.

## What I’d check next

In the next test, check the test/control split within each app version and compare conversion and revenue per assigned user.

_Suggested by the exercise; review and adapt before publishing._

## How it was checked

- 5 SQL queries were checked automatically against a hidden reference, on two versions of the data.
- 4 of 5 passed on the first try.
- No hints used.
- 6 attempts in total.
- Data version: 2026-09-26.en1.
- Completed 3 October 2026.

---

<sub>Sample generated by Atterna from synthetic progress on fictional Meridian data. Task and data: Atterna. SQL and decisions: the sample learner’s.</sub>
