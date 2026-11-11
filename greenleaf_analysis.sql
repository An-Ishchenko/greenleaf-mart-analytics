
--Store-level P&L - Network-wide gross margin averages 17.5%, and it's been steadily eroding: 
--from ~22-24% in early 2024 down to ~15-17% by late 2025, across every store at the same time. 
--Product costs kept rising while retail prices barely moved - 
--the chain has been quietly losing margin to cost inflation it never passed on to customers
WITH priced_lines AS (
    SELECT
        r.store_id, r.receipt_date, r.line_amount,
        r.quantity * c.cost_price AS line_cogs
    FROM receipts r
    JOIN cogs c
      ON c.product_id = r.product_id
     AND c.effective_from = (
            SELECT MAX(c2.effective_from)
            FROM cogs c2
            WHERE c2.product_id = r.product_id
              AND c2.effective_from <= r.receipt_date
        )
)
SELECT
    s.store_name,
    strftime(p.receipt_date, '%Y-%m') AS month,
    ROUND(SUM(p.line_amount), 2) AS revenue,
    ROUND(SUM(p.line_cogs), 2) AS cogs,
    ROUND(SUM(p.line_amount) - SUM(p.line_cogs), 2) AS gross_profit,
    ROUND((SUM(p.line_amount) - SUM(p.line_cogs)) * 100.0 / SUM(p.line_amount), 1) AS gross_margin_pct
FROM priced_lines p
JOIN stores s ON s.store_id = p.store_id
GROUP BY s.store_name, month
ORDER BY s.store_name, month;


--HQ expense allocation - Even after allocating marketing/admin costs proportionally to revenue, 
--Dnipro Central remains the most profitable store (2.39M UAH in profit before COGS), 
--while the two new stores rank lowest - expected for locations under a year old
WITH monthly_revenue AS (
    SELECT store_id, strftime(receipt_date, '%Y-%m') AS month, SUM(line_amount) AS revenue
    FROM receipts GROUP BY 1, 2
),
total_revenue AS (
    SELECT month, SUM(revenue) AS total_revenue FROM monthly_revenue GROUP BY month
),
store_expenses AS (
    SELECT store_id, year_month AS month, SUM(amount) AS direct_expenses
    FROM expenses WHERE store_id <> 'HQ' GROUP BY store_id, year_month
),
hq_expenses AS (
    SELECT year_month AS month, SUM(amount) AS hq_total
    FROM expenses WHERE store_id = 'HQ' GROUP BY year_month
)
SELECT
    s.store_name,
    mr.month,
    ROUND(mr.revenue, 2) AS revenue,
    ROUND(COALESCE(se.direct_expenses, 0), 2) AS direct_expenses,
    ROUND(mr.revenue / t.total_revenue * h.hq_total, 2) AS allocated_hq_expenses,
    ROUND(mr.revenue - COALESCE(se.direct_expenses, 0) - mr.revenue / t.total_revenue * h.hq_total, 2) AS profit_before_cogs
FROM monthly_revenue mr
JOIN total_revenue t ON t.month = mr.month
JOIN hq_expenses h ON h.month = mr.month
JOIN stores s ON s.store_id = mr.store_id
LEFT JOIN store_expenses se ON se.store_id = mr.store_id AND se.month = mr.month
ORDER BY s.store_name, mr.month;


--Revenue per sqm — Kyiv Osokorky (the newest store, largest format) generates just 12,775 UAH/sqm - 
--roughly half the network average (~28-31K UAH/sqm). Poltava (opened earlier) has already nearly caught up 
--to mature stores (23,856 UAH/sqm) - ramping a large-format store simply takes longer than a small one
WITH store_revenue AS (
    SELECT store_id, SUM(line_amount) AS total_revenue
    FROM receipts GROUP BY store_id
)
SELECT s.store_name, s.format, s.size_sqm,
       ROUND(sr.total_revenue, 2) AS total_revenue,
       ROUND(sr.total_revenue / s.size_sqm, 2) AS revenue_per_sqm
FROM store_revenue sr
JOIN stores s ON s.store_id = sr.store_id
ORDER BY revenue_per_sqm DESC;



--Loyalty members vs. anonymous shoppers - Loyalty members' average receipt is only ~2.7% higher than anonymous 
--purchases (634.97 UAH vs. 618.47 UAH). The real difference isn't basket size - it's frequency: 
--a loyalty member returns 8.3 times on average over 2 years
SELECT
    CASE WHEN customer_id IS NULL OR customer_id = '' THEN 'Anonymous' ELSE 'Loyalty member' END AS buyer_type,
    COUNT(DISTINCT receipt_id) AS receipts_count,
    ROUND(SUM(line_amount), 2) AS total_revenue,
    ROUND(SUM(line_amount) / COUNT(DISTINCT receipt_id), 2) AS avg_receipt_value
FROM receipts
GROUP BY buyer_type

SELECT ROUND(AVG(order_count), 2) AS avg_orders_per_loyalty_customer
FROM (
    SELECT customer_id, COUNT(DISTINCT receipt_id) AS order_count
    FROM receipts
    WHERE customer_id IS NOT NULL AND customer_id <> ''
    GROUP BY customer_id
) t;



--RFM segmentation - 285 "Champions" (25% of active members) generate 2.57M UAH - 48% of all loyalty-member revenue. 
--A further 156 customers in the "At Risk (high value)" segment have historically spent 1.26M UAH but have gone quiet -
--a ready-made, high-value win-back target list
WITH customer_orders AS (
    SELECT customer_id, MAX(receipt_date) AS last_order_date,
           COUNT(DISTINCT receipt_id) AS frequency, SUM(line_amount) AS monetary
    FROM receipts
    WHERE customer_id IS NOT NULL AND customer_id <> ''
    GROUP BY customer_id
),
scored AS (
    SELECT *,
        date_diff('day', last_order_date, DATE '2025-12-31') AS recency_days,
        NTILE(4) OVER (ORDER BY date_diff('day', last_order_date, DATE '2025-12-31') DESC) AS r_score,
        NTILE(4) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(4) OVER (ORDER BY monetary ASC) AS m_score
    FROM customer_orders
)
SELECT customer_id, recency_days, frequency, ROUND(monetary,2) AS monetary,
    r_score, f_score, m_score,
    CASE
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions'
        WHEN r_score >= 3 AND f_score <= 2 THEN 'New / Promising'
        WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN 'At Risk (high value)'
        WHEN r_score = 1 AND f_score <= 2 THEN 'Lost'
        ELSE 'Needs Attention'
    END AS segment
FROM scored
ORDER BY monetary DESC;



--Silent loyalty members - 139 of 1,150 program members (12%) have never made a single purchase - 
--a sign the loyalty program's onboarding isn't converting signups into first purchases
SELECT c.customer_id, c.full_name, c.registration_date, c.home_city, c.loyalty_tier
FROM customers c
LEFT JOIN receipts r ON r.customer_id = c.customer_id
WHERE r.receipt_id IS NULL
ORDER BY c.registration_date;



--New-store ramp-up - Poltava grew from ~51K to ~149K UAH/month in its first 3 months (nearly 3x); 
--Kyiv Osokorky grew from 115K to 315K UAH/month over the same window (nearly 2.7x). 
--A fair comparison to older stores' own launch period isn't possible - their first months of operation predate the dataset -
-- so the better benchmark is the network's average revenue per store per month (~185K UAH), 
--which Kyiv Osokorky had already surpassed by the end of 2025
WITH monthly AS (
    SELECT store_id, strftime(receipt_date, '%Y-%m') AS month, SUM(line_amount) AS revenue
    FROM receipts GROUP BY 1, 2
)
SELECT s.store_name, m.month,
    date_diff('month', s.open_date, CAST(m.month || '-01' AS DATE)) AS months_since_open,
    ROUND(m.revenue, 2) AS revenue
FROM monthly m
JOIN stores s ON s.store_id = m.store_id
WHERE s.store_id IN ('S08', 'S02')
ORDER BY s.store_name, m.month;

WITH monthly AS (
    SELECT store_id, strftime(receipt_date, '%Y-%m') AS month, SUM(line_amount) AS revenue
    FROM receipts GROUP BY 1, 2
),
tagged AS (
    SELECT m.*, date_diff('month', s.open_date, CAST(m.month || '-01' AS DATE)) AS months_since_open
    FROM monthly m
    JOIN stores s ON s.store_id = m.store_id
    WHERE s.store_id NOT IN ('S08', 'S02')
)
SELECT months_since_open, ROUND(AVG(revenue), 2) AS avg_revenue_mature_stores
FROM tagged
WHERE months_since_open BETWEEN 0 AND 6
GROUP BY months_since_open
ORDER BY months_since_open;



--Category margin ranking - Personal Care is the only category with margin below 13% (12.6%) 
--and also the lowest-revenue category of all six (2.68M UAH) - a candidate for a pricing or supplier review
WITH priced_lines AS (
    SELECT r.product_id, r.line_amount, c.category,
           r.quantity * c.cost_price AS line_cogs
    FROM receipts r
    JOIN cogs c
      ON c.product_id = r.product_id
     AND c.effective_from = (
            SELECT MAX(c2.effective_from) FROM cogs c2
            WHERE c2.product_id = r.product_id AND c2.effective_from <= r.receipt_date
        )
)
SELECT category,
    ROUND(SUM(line_amount), 2) AS revenue,
    ROUND(SUM(line_amount) - SUM(line_cogs), 2) AS gross_profit,
    ROUND((SUM(line_amount) - SUM(line_cogs)) * 100.0 / SUM(line_amount), 1) AS gross_margin_pct
FROM priced_lines
GROUP BY category
ORDER BY gross_margin_pct DESC;



--Monthly trend & MoM growth - Network revenue grew from 756K UAH (Jan 2024) to 2.82M UAH (Dec 2025) - almost 3.7x in two years.
--November delivers the sharpest jump both years (+62% and +61% MoM), while January is the deepest dip (−49% in 2025) -
--a clear seasonal pattern worth building into purchasing and staffing plans
WITH monthly AS (
    SELECT strftime(receipt_date, '%Y-%m') AS month, SUM(line_amount) AS revenue
    FROM receipts GROUP BY 1
)
SELECT month, ROUND(revenue, 2) AS revenue,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY month)) * 100.0 / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly
ORDER BY month;



--Cohort retention - Only 16% of new loyalty members make a purchase in their sign-up month, 
--but activity jumps to 33% the following month and settles into a ~27-30% plateau afterward. 
--Since joining the loyalty program doesn't always coincide with a purchase, the month-0 dip isn't a funnel failure -
--the plateau from month 2 onward is the number to watch
WITH cohort_size AS (
    SELECT strftime(registration_date, '%Y-%m') AS cohort_month, COUNT(*) AS cohort_customers
    FROM customers GROUP BY 1
),
activity AS (
    SELECT c.customer_id, strftime(c.registration_date, '%Y-%m') AS cohort_month,
        date_diff('month', c.registration_date, r.receipt_date) AS months_since_signup
    FROM customers c JOIN receipts r ON r.customer_id = c.customer_id
)
SELECT a.cohort_month, cs.cohort_customers, a.months_since_signup,
    COUNT(DISTINCT a.customer_id) AS active_customers,
    ROUND(COUNT(DISTINCT a.customer_id) * 100.0 / cs.cohort_customers, 1) AS pct_active
FROM activity a
JOIN cohort_size cs ON cs.cohort_month = a.cohort_month
WHERE a.months_since_signup BETWEEN 0 AND 6
GROUP BY a.cohort_month, cs.cohort_customers, a.months_since_signup
ORDER BY a.cohort_month, a.months_since_signup;
