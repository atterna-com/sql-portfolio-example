# Refunds that don’t add up

`SQL` · `DuckDB` · `Case study` · `Fictional marketplace data`

[← All projects](../../README.md)

> **Finding:** Product totals add up to €36,095; finance booked €16,073
>
> **Key numbers:** **€16,072.94** Refunds booked for the three weeks (all requests) · **323** Refund requests in the three weeks
>
> **My call:** No defensible cut yet: the ranking moves and item-level evidence is thin. Agree the rule first

## Business question

> Vera wants to drop the most-refunded products from the December promo. Finance is about to check the numbers.

**What I set out to find out:** Find out whether some products really come back more, with numbers finance accepts

_Assembled from the options I selected in the exercise; not free text._

## Definition

- A refund is worth: the refund amount (amount_eur)
- Which refunds: every request, pending or completed
- Period: all refunds in the data (the three weeks)

_Assembled from the options I selected in the exercise; not free text._

## Approach

4 SQL queries, each checked automatically.

### Step 1

**Task.** Refunds in euros for each product. Refunds are stored per order, so join them to the order items by order.

```sql
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
ORDER BY refund_eur DESC, i.product_title
```

**Result** (first 10 of 38 rows) · [CSV](results/01-products.csv)

| product_title | refund_eur |
| :--- | ---: |
| Smart speaker | 1411.4575 |
| Webcam | 1263.5084 |
| Power bank | 957.7077 |
| Wireless headphones | 908.7327 |
| USB-C cable | 829.872 |
| 65W charger | 813.7936 |
| Basic T-shirt | 629.78 |
| Fitness band | 608.0981 |
| Desk lamp | 521.0064 |
| Linen scarf | 518.4473 |

### Step 2

**Task.** One number: refunds on orders with at least one item priced over €20 per unit, each refund counted once. The AI's draft is in the editor — fix what's wrong, then send it.

```sql
-- The AI draft joined refunds to order_items, so an order with several lines over 20 euros was counted once per line.
-- EXISTS keeps one row per refund.
SELECT SUM(r.amount_eur) AS refunded_eur
FROM meridian.refunds AS r
WHERE EXISTS (
    SELECT 1
    FROM meridian.order_items AS i
    WHERE i.order_id = r.order_id
      AND i.unit_price_eur > 20
)
```

**Result** (1 row) · [CSV](results/02-ai-refund-total.csv)

| refunded_eur |
| ---: |
| 13098.4 |

### Step 3

**Task.** For each product: paid orders that contain it, how many of them were refunded, and that share in per cent to one decimal. Count orders, not item lines.

```sql
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
ORDER BY refund_rate_pct DESC, p.product_title
```

**Result** (first 10 of 38 rows) · [CSV](results/03-rates.csv)

| product_title | orders | refunded_orders | refund_rate_pct |
| :--- | ---: | ---: | ---: |
| Smart speaker | 544 | 28 | 5.1 |
| Yoga mat | 313 | 16 | 5.1 |
| Webcam | 561 | 28 | 5 |
| Wireless headphones | 542 | 27 | 5 |
| 2 kg dumbbells | 306 | 15 | 4.9 |
| Face serum | 387 | 18 | 4.7 |
| Set of wine glasses | 507 | 24 | 4.7 |
| Basic T-shirt | 526 | 24 | 4.6 |
| Cast-iron pan | 561 | 26 | 4.6 |
| Desk lamp | 551 | 25 | 4.5 |

### Step 4

**Task.** The same, but only paid orders with exactly one item line: how many, how many were refunded, and the share in per cent to one decimal.

_Completed from a template the task gave me._

```sql
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
ORDER BY refund_rate_pct DESC, i.product_title
```

**Result** (first 10 of 38 rows) · [CSV](results/04-single.csv)

| product_title | orders | refunded_orders | refund_rate_pct |
| :--- | ---: | ---: | ---: |
| Solid shampoo | 99 | 7 | 7.1 |
| Webcam | 142 | 10 | 7 |
| Desk lamp | 178 | 11 | 6.2 |
| Cast-iron pan | 159 | 9 | 5.7 |
| Set of wine glasses | 146 | 8 | 5.5 |
| Face serum | 102 | 5 | 4.9 |
| Terry towel | 124 | 6 | 4.8 |
| Wireless headphones | 145 | 7 | 4.8 |
| Book with stickers | 87 | 4 | 4.6 |
| Basic T-shirt | 155 | 7 | 4.5 |

## Numbers I reported

_Typed by me; the checker accepted each one within its tolerance._

| Number | My value |
| :--- | ---: |
| Refunds booked for the three weeks (all requests) | €16,072.94 |
| Refund requests in the three weeks | 323 |

**Checked numbers in my decision memo:** Refunds booked: €16,073 on 323 refunds. Joined to order items they become 596 rows and add up to €36,095. Share of orders refunded, by product: 1.5% to 5.1%. On single-line orders (44% of refunds): 0.0% to 7.1%, on 0 to 11 refunded orders per product. Of the five highest rates before the promo, 0 are in the top five in the promo week.

_Assembled from the options I selected in the exercise; not free text._

## Decision and recommendation

**Option I chose:** No defensible cut yet: the ranking moves and item-level evidence is thin. Agree the rule first

_Selected from the options the exercise offered._

**Evidence I relied on:**

- Product totals add up to €36,095; finance booked €16,073
- Of the five products with the highest refund rate before the promo, 0 are in the top five in the promo week

## Limits and what I’d check next

**What the data don't show:** which item in a multi-line order came back: the refunds table doesn't say

**What would change the call:** returns logged per item, and a product whose rate stays high in two separate months

_Assembled from the options I selected in the exercise; not free text._

## How it was checked

- 4 SQL queries were checked automatically against a hidden reference, on two versions of the data.
- 3 of 4 passed on the first try.
- Hints used on 1 query.
- 5 attempts in total.
- Whole case: 9 of 10 graded steps done on my own, 1 with a hint.
- Data version: 2026-09-26.en1.
- Result tables for course and case steps were re-run on the practice dataset when this repository was built; episode results are the rows stored when the query was accepted.
- Completed 3 October 2026.

---

<sub>Sample generated by Atterna from synthetic progress on fictional Meridian data. Task and data: Atterna. SQL and decisions: the sample learner’s.</sub>
