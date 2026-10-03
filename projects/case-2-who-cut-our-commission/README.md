# Who cut our commission?

`SQL` · `DuckDB` · `Case study` · `Fictional marketplace data`

[← All projects](../../README.md)

> **Finding:** The platform paid €21,516 in discounts; after them, commission fell from €18,206 to €4,961
>
> **Key numbers:** **€52,614.13** Electronics GMV, the week before the promo (W37) · **€110,078.61** Electronics GMV, the promo week (W38) · **€21,516.17** Discounts the platform paid in the promo week (W38)
>
> **My call:** No reversal: the mix explains the drop. Show the €21,516 of discounts beside it; payback is still open

## Business question

> Take rate fell by more than a point in the promo week. Finance wants a name.

**What I set out to find out:** Find what moved the take rate and what the promo cost, before reversing anything

_Assembled from the options I selected in the exercise; not free text._

## Definition

- Commission is: goods value × the seller's commission rate
- Divided by: GMV of paid orders
- Across sellers: total commission ÷ total GMV
- Weeks by: the date the order was created
- Platform discounts: kept out of take rate, shown as a separate line

_Assembled from the options I selected in the exercise; not free text._

## Approach

3 SQL queries, each checked automatically.

### Step 1

**Task.** Take rate for each of the three weeks: GMV of paid orders, commission and take rate in per cent, to two decimals. Commission is the goods value times the seller's rate.

_Completed from a template the task gave me._

```sql
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
ORDER BY w.week_id
```

**Result** (3 rows) · [CSV](results/01-weekly.csv)

| week_id | gmv_eur | commission_eur | take_rate_pct |
| :--- | ---: | ---: | ---: |
| W36 | 149811.85 | 18830.3864 | 12.57 |
| W37 | 150502.86 | 18970.5755 | 12.6 |
| W38 | 230967.18 | 26477.5428 | 11.46 |

### Step 2

**Task.** For each week and seller category: GMV of paid orders and its share of that week's GMV, in per cent to one decimal.

_Completed from a template the task gave me._

```sql
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
ORDER BY week_id, share_pct DESC, category
```

**Result** (first 10 of 18 rows) · [CSV](results/02-mix.csv)

| week_id | category | gmv_eur | share_pct |
| :--- | :--- | ---: | ---: |
| W36 | Electronics | 52275.51 | 34.9 |
| W36 | Clothing | 30495.62 | 20.4 |
| W36 | Home & Kitchen | 26672.19 | 17.8 |
| W36 | Sports | 18465.47 | 12.3 |
| W36 | Beauty | 11688.19 | 7.8 |
| W36 | Kids | 10214.87 | 6.8 |
| W37 | Electronics | 52614.13 | 35 |
| W37 | Clothing | 32454.08 | 21.6 |
| W37 | Home & Kitchen | 27268.16 | 18.1 |
| W37 | Sports | 17189.84 | 11.4 |

### Step 3

**Task.** For each week: commission on paid orders, the discounts the platform paid on those orders, and commission after the discounts.

_Completed from a template the task gave me._

```sql
SELECT w.week_id,
       SUM(o.items_total_eur * s.commission_rate)                            AS commission_eur,
       SUM(o.platform_discount_eur)                                          AS discount_eur,
       SUM(o.items_total_eur * s.commission_rate - o.platform_discount_eur)  AS net_eur
FROM meridian.orders  AS o
JOIN meridian.sellers AS s ON s.seller_id = o.seller_id
JOIN meridian.weeks   AS w ON o.created_at >= w.week_start AND o.created_at < w.week_end
WHERE o.status = 'paid'
GROUP BY w.week_id
ORDER BY w.week_id
```

**Result** (3 rows) · [CSV](results/03-net.csv)

| week_id | commission_eur | discount_eur | net_eur |
| :--- | ---: | ---: | ---: |
| W36 | 18830.3864 | 1005 | 17825.3864 |
| W37 | 18970.5755 | 765 | 18205.5755 |
| W38 | 26477.5428 | 21516.17 | 4961.3728 |

## Numbers I reported

_Typed by me; the checker accepted each one within its tolerance._

| Number | My value |
| :--- | ---: |
| Electronics GMV, the week before the promo (W37) | €52,614.13 |
| Electronics GMV, the promo week (W38) | €110,078.61 |
| Discounts the platform paid in the promo week (W38) | €21,516.17 |

**Checked numbers in my decision memo:** Take rate: 12.6% in W37, 11.5% in the promo week. At the rates in the sellers table, Electronics (7%) went from 35% to 48% of GMV. Commission before discounts: €18,971, then €26,478. Platform discounts: €765, then €21,516. Commission after discounts: €18,206, then €4,961.

_Assembled from the options I selected in the exercise; not free text._

## Decision and recommendation

**Option I chose:** No reversal: the mix explains the drop. Show the €21,516 of discounts beside it; payback is still open

_Selected from the options the exercise offered._

**Evidence I relied on:**

- Electronics went from 35% to 48% of GMV
- The platform paid €21,516 in discounts; after them, commission fell from €18,206 to €4,961

## Limits and what I’d check next

**What the data don't show:** whether the promo paid back: its full cost and how many extra orders the code brought

**What would change the call:** a contract or rate history showing that a seller's rate was changed

_Assembled from the options I selected in the exercise; not free text._

## How it was checked

- 3 SQL queries were checked automatically against a hidden reference, on two versions of the data.
- 3 of 3 passed on the first try.
- No hints used.
- 3 attempts in total.
- Whole case: 9 of 9 graded steps done on my own.
- Data version: 2026-09-26.en1.
- Result tables for course and case steps were re-run on the practice dataset when this repository was built; episode results are the rows stored when the query was accepted.
- Completed 3 October 2026.

---

<sub>Sample generated by Atterna from synthetic progress on fictional Meridian data. Task and data: Atterna. SQL and decisions: the sample learner’s.</sub>
