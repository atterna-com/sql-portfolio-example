# The seller who drags things down

`SQL` · `DuckDB` · `Meridian episode 4` · `Fictional marketplace data`

[← All projects](../../README.md)

## Context

Vera needs defensible rules for January's Trusted Shop programme by Wednesday. Arthur proposes using ratings and disabling the ten shops with the worst cancellation rates.

## Why it’s not obvious

A shop with very few orders can look like one of the worst by chance. Ratings can miss operational problems, and looking only at shipped orders hides overdue orders that never shipped.

_Scenario context supplied by Atterna._

> **Finding:** The problem sits with a few shops: 17 shops break the rules, 9 also beyond chance; together they carry 11% of GMV and up to 40% of late shipments.
>
> **Key numbers:** **17** Shops with 30+ orders over a threshold · **9** Of them, shops beyond chance (probability under 2.5%)
>
> **My call:** Judge shops with 30+ orders on cancellations (≤5%) and late shipments (≤15%). Over the line and beyond chance: a month to fix it, then a recheck before any drop in search.

## Business question

> In January the platform launches the Trusted Shop programme. Arthur wants a rating-based criterion and has already drawn up a list of shops to switch off. The decision is on Wednesday.

## Approach

5 SQL queries, each checked automatically.

### 1. Cancellations by the shop

**Task.** For each shop over the eight weeks: total orders, how many of them the shop cancelled itself, and what share that is in per cent.

```sql
SELECT shop_id,
       COUNT(*) AS orders,
       SUM(CASE WHEN status = 'cancelled_by_seller' THEN 1 ELSE 0 END) AS seller_cancels,
       ROUND(100.0 * SUM(CASE WHEN status = 'cancelled_by_seller' THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancel_pct
FROM meridian.shop_orders
GROUP BY shop_id
ORDER BY cancel_pct DESC, shop_id
```

**Result** (first 10 of 190 rows) · [CSV](results/01-cancellations-by-the-shop.csv)

| shop_id | orders | seller_cancels | cancel_pct |
| :--- | ---: | ---: | ---: |
| M0040 | 3 | 1 | 33.33 |
| M0058 | 3 | 1 | 33.33 |
| M0181 | 12 | 2 | 16.67 |
| M0180 | 7 | 1 | 14.29 |
| M0045 | 279 | 33 | 11.83 |
| M0015 | 425 | 50 | 11.76 |
| M0051 | 361 | 38 | 10.53 |
| M0189 | 10 | 1 | 10 |
| M0132 | 201 | 20 | 9.95 |
| M0139 | 518 | 51 | 9.85 |

### 2. Late shipments

**Task.** For each shop: how many orders should already have shipped (the ship_by deadline has passed and the order wasn't cancelled), how many of those were late — shipped after the deadline or still not shipped — and the late-shipment rate. It's now 14 December, 10:00.

```sql
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
ORDER BY late_pct DESC, shop_id
```

**Result** (first 10 of 190 rows) · [CSV](results/02-late-shipments.csv)

| shop_id | due_orders | late_orders | late_pct |
| :--- | ---: | ---: | ---: |
| M0134 | 216 | 81 | 37.5 |
| M0170 | 3 | 1 | 33.33 |
| M0173 | 3 | 1 | 33.33 |
| M0015 | 344 | 110 | 31.98 |
| M0028 | 160 | 51 | 31.88 |
| M0139 | 430 | 136 | 31.63 |
| M0007 | 206 | 64 | 31.07 |
| M0051 | 296 | 86 | 29.05 |
| M0045 | 226 | 64 | 28.32 |
| M0142 | 4 | 1 | 25 |

### 3. Who really lets customers down

**Task.** Shops with at least 30 orders over the eight weeks that break at least one rule: a rate of cancellations by the shop above 5% or a late-shipment rate above 15%. For each — the number of orders and both rates.

```sql
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
ORDER BY c.cancel_pct DESC, c.shop_id
```

**Result** (first 10 of 17 rows) · [CSV](results/03-who-really-lets-customers-down.csv)

| shop_id | orders | cancel_pct | late_pct |
| :--- | ---: | ---: | ---: |
| M0045 | 279 | 11.828 | 28.3186 |
| M0015 | 425 | 11.7647 | 31.9767 |
| M0051 | 361 | 10.5263 | 29.0541 |
| M0132 | 201 | 9.9502 | 21.7391 |
| M0139 | 518 | 9.8456 | 31.6279 |
| M0067 | 31 | 9.6774 | 7.6923 |
| M0028 | 194 | 8.2474 | 31.875 |
| M0068 | 102 | 7.8431 | 7.5 |
| M0134 | 252 | 7.5397 | 37.5 |
| M0024 | 62 | 6.4516 | 7.1429 |

### 4. Who the rating would catch

**Task.** For shops with 30+ orders: the average review score, and a “behaves normally” flag (cancellations by the shop no higher than 5% and late shipments no higher than 15%). How many shops fall into each of the four combinations.

```sql
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
ORDER BY rating_ok DESC, behavior_ok DESC
```

**Result** (4 rows) · [CSV](results/04-who-the-rating-would-catch.csv)

| rating_ok | behavior_ok | shops |
| :--- | :--- | ---: |
| true | true | 52 |
| true | false | 9 |
| false | true | 35 |
| false | false | 8 |

### 5. How much of the problem sits with them

**Task.** One row. Flagged shops have 30+ orders and break at least one rule, as in the task “Who really lets customers down”. How many there are, their share of the platform's GMV (items_total_eur of shipped orders), their share of all late shipments and their share of all cancellations by shops — as a percentage of the totals across all shops.

```sql
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
FROM flagged
```

**Result** (1 row) · [CSV](results/05-how-much-of-the-problem-sits-with.csv)

| problem_shops | gmv_share_pct | late_share_pct | cancel_share_pct |
| ---: | ---: | ---: | ---: |
| 17 | 10.9469 | 40.0854 | 41.0448 |

## Numbers I reported

_Typed by me; the checker accepted each one within its tolerance._

| Number | My value |
| :--- | ---: |
| Shops with 30+ orders over a threshold | 17 |
| Of them, shops beyond chance (probability under 2.5%) | 9 |

## Decision and recommendation

**Option I chose:** Judge shops with 30+ orders on cancellations (≤5%) and late shipments (≤15%). Over the line and beyond chance: a month to fix it, then a recheck before any drop in search. (Luka's proposal)

_Selected from the options the exercise offered._

**What I claimed from the numbers:** The problem sits with a few shops: 17 shops break the rules, 9 also beyond chance; together they carry 11% of GMV and up to 40% of late shipments. The rating misses most.

## What I’d check next

Recheck cancellations and shipping delays as shops accumulate more orders, and review borderline cases before imposing penalties.

_Suggested by the exercise; review and adapt before publishing._

## How it was checked

- 5 SQL queries were checked automatically against a hidden reference, on two versions of the data.
- 5 of 5 passed on the first try.
- No hints used.
- 5 attempts in total.
- Data version: 2026-09-26.en1.
- Completed 3 October 2026.

---

<sub>Sample generated by Atterna from synthetic progress on fictional Meridian data. Task and data: Atterna. SQL and decisions: the sample learner’s.</sub>
