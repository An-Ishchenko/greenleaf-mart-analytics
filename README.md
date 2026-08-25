# greenleaf-mart-analytics
GreenLeaf Mart - Retail Chain SQL Analysis

SQL portfolio project analyzing store performance, profitability, and customer
loyalty for a fictional 8-store retail chain ("GreenLeaf Mart") over a
2-year period (2024-2025). Built as a self-directed practice case using a
synthetic dataset (no real company or customer data).

Dataset

Five tables, ~130K rows total:

- `stores` - 8 store locations, opening dates, formats, sizes
- `customers` - loyalty program members only (not every shopper)
- `cogs` - product cost history (cost changes over time, effective-dated)
- `receipts` - 124K+ line-item transactions
- `expenses` - monthly expenses, store-level and network-level (HQ)

What this analysis covers

1. Monthly P&L per store, with product cost matched to the price in effect
   on the sale date (effective-dated JOIN)
2. Allocation of shared network-level (HQ) expenses to stores by revenue
   share, to get a fair per-store profitability view
3. Revenue per square meter by store
4. Loyalty members vs. anonymous shoppers - basket size and frequency
5. RFM segmentation of loyalty members (Recency / Frequency / Monetary)
6. Loyalty members who signed up but never purchased
7. Ramp-up trajectory of the two newest stores
8. Category ranking by gross margin (not just revenue)
9. Monthly revenue trend and month-over-month growth
10. Cohort retention of loyalty members by sign-up month

Techniques used

CTEs, an effective-dated ("as of") JOIN via correlated subquery, window
functions (`LAG`, `NTILE`), proportional cost allocation, `CASE`-based
business segmentation, and careful handling of `NULL`/optional foreign keys
(not every receipt is tied to a loyalty customer).

Tools

DuckDB (SQL syntax is standard and portable to PostgreSQL/MySQL with minor
adjustments - noted inline in the query file).

Key findings

- Network gross margin has eroded from ~23% to ~16% over two years as
  product costs rose faster than retail prices.
- The top 25% of loyalty members (by RFM) generate 48% of loyalty revenue;
  a further 156 previously high-value members have gone quiet.
- 12% of loyalty sign-ups have never made a purchase.
- Revenue grew ~3.7x over two years, with a strong, consistent November
  seasonal peak.

