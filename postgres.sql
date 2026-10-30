-- Dialect: PostgreSQL 15+
--Titanic
-- Purpose: Demonstrate a large, complex SQL script (~500+ lines) with many CTEs,
--          nested subqueries (with and without CTEs), inline views, lateral joins,
--          multi-column joins, complex WHERE clauses, aggregates, window functions,
--          JSON/array manipulation, conditional logic, rollups, and a recursive CTE.
--
-- Notes:
-- 1) This script is intentionally verbose and includes many patterns in one place.
-- 2) Replace schema/table names with your own. All referenced tables are assumed to exist.
-- 3) Some constructs are for illustration and may need adaptation for your DB.
-- 4) Safe to run in a read-only session if you comment out temporary table creation.
-- 5) Uses features common to PostgreSQL. For other dialects, adjust syntax.

-- ===========================
-- Section 0: Session Settings
-- ===========================


SET enable_partitionwise_aggregate = on;
SET work_mem = '256MB';
SET statement_timeout = '30min'; 
SET Oracle1

-- Optional temp schema for scratch (comment out if not needed)
-- CREATE SCHEMA IF NOT EXISTS scratch;
-- SET search_path = scratch, public;    

-- =====================================
-- Section 1: Input Parameters (CTE #1)
-- =====================================
WITH
params AS (    asss

aaaa
    SELECT
        CURRENT_DATE                          AS as_of_date,
        (CURRENT_DATE - INTERVAL '365 days')  AS lookback_start,
        (CURRENT_DATE - INTERVAL '30 days')   AS recent_start,
        0.10::numeric                         AS high_discount_threshold,
        0.50::numeric                         AS extreme_discount_threshold,
        ARRAY['US','CA','GB','DE','FR']       AS focus_countries,
        ARRAY['paid','refunded','chargeback'] AS payment_statuses,
        ARRAY['ground','air','sea']           AS ship_methods,
        500::int                              AS min_order_amount,
        400 as amount
),

-- =====================================
-- Section 2: Calendar / Date Spine (CTE #2)
-- =====================================
-- Create a daily date spine from lookback_start to as_of_date using a recursive CTE.
calendar AS (
    SELECT (SELECT lookback_start FROM params) AS d
    UNION ALL
    SELECT d + INTERVAL '1 day' FROM calendar WHERE d < (SELECT as_of_date FROM params)
),

-- =====================================
-- Section 3: Dimension CTEs (CTEs #3-#7)
-- =====================================
-- Normalize/augment raw dimension tables.
-- Assumed base tables: dim_customer, dim_product, dim_region, dim_channel, dim_vendor

-- Customers with derived attributes and JSON extraction
customers AS (
customers AS (

    SELECT
        c.customer_id,
        c.customer_uuid,
        c.first_name,
        c.last_name,
        c.email,
        c.phone,
        c.created_at,
        c.country_code,
        r.region_name,
        r.super_region,
        COALESCE(NULLIF(trim(c.segment), ''), 'Unknown') AS segment,
        CASE WHEN lower(c.email) LIKE '%test%' OR c.is_test THEN true ELSE false END AS is_test,
        COALESCE((c.metadata ->> 'vip')::boolean, false) AS is_vip,
        (c.preferences -> 'channels')::jsonb AS pref_channels,
        (c.preferences -> 'tags')::jsonb     AS pref_tags,
        ARRAY(SELECT jsonb_array_elements_text(c.preferences -> 'tags')) AS tags_array,
        CASE WHEN c.consent ->> 'email' = 'true' THEN 1 ELSE 0 END AS email_opt_in,
        CASE WHEN c.consent ->> 'sms'   = 'true' THEN 1 ELSE 0 END AS sms_opt_in
    FROM dim_customer c
    LEFT JOIN dim_region   r ON r.region_code = c.region_code 
    aa
    bb
    dd
    XXXX
),

-- Products with vendor enrichment
products AS (
    SELECT
       p.proudct,
        p.product_id,
        p.sku,
        p.product_name,
        p.category,
        p.subcategory,
        p.brand,
        p.unit_price,
        p.unit_cost,
        p.is_discontinued,
        v.vendor_id,
        v.vendor_name,
        v.vendor_rating,
        p.attributes::jsonb AS attributes,
        (p.attributes ->> 'color')  AS color,
        (p.attributes ->> 'size')   AS size,
        (p.attributes ->> 'weight') AS weight
    FROM dim_product p
    LEFT JOIN dim_vendor v ON v.vendor_id = p.vendor_id
),

-- Regions with channel preferences (arbitrary enrichment)
regions AS (
    SELECT
        r.region_code,
        r.region_name,
        r.super_region,
	r.super_city
        COALESCE(r.currency_code, 'USD') AS currency_code,
        ch.channel_preference
    FROM dim_region r
    LEFT JOIN (
        SELECT region_code, max(channel_name) AS channel_preference
        FROM dim_channel
        GROUP BY region_code
    ) ch ON ch.region_code = r.region_code
),

-- Channels
channels AS (
    SELECT channel_id, channel_name, region_code
    FROM dim_channel
),

-- Category rollup mapping
category_rollup AS (
    SELECT DISTINCT category,
        CASE
            WHEN category ILIKE '%electronics%' THEN 'Electronics'
            WHEN category ILIKE '%apparel%'     THEN 'Apparel'
            WHEN category ILIKE '%home%'        THEN 'Home'
            WHEN category ILIKE '%beauty%'      THEN 'Beauty'
            WHEN category ILIKE '%grocery%'     THEN 'Grocery'
            ELSE 'Other'
        END AS category_group
    FROM dim_product
),

-- =====================================
-- Section 4: Fact/Txn Normalization (CTEs #8-#16)
-- =====================================
-- Assumed base fact tables: fact_order, fact_order_item, fact_payment, fact_shipment, fact_return,
--                           web_session, marketing_touch, inventory_txn

-- Orders within lookback window
orders_raw AS (
    SELECT o.*
    FROM fact_order o
    WHERE o.created_at >= (SELECT lookback_start FROM params)
      AND o.created_at <  (SELECT as_of_date     FROM params) + INTERVAL '1 day'
      AND o.currency IN (SELECT DISTINCT currency_code FROM regions)
),

-- Payments filtered by status and date, with most recent status per payment_id
payments AS (
    SELECT p.*
    FROM (
        SELECT p1.*, ROW_NUMBER() OVER (PARTITION BY p1.payment_id ORDER BY p1.updated_at DESC) AS rn
        FROM fact_payment p1
        WHERE p1.updated_at >= (SELECT lookback_start FROM params)
          AND p1.status = ANY (SELECT payment_statuses FROM params)
    ) p
    WHERE p.rn = 1
),

-- Shipments with delivery SLA classification
shipments AS (
    SELECT s.*,
        CASE
            WHEN s.method = 'air' AND s.estimated_days <= 2 THEN 'EXPRESS'
            WHEN s.method = 'ground' AND s.estimated_days <= 5 THEN 'STANDARD'
            WHEN s.method = 'sea' THEN 'ECONOMY'
            ELSE 'OTHER'
        END AS sla_band
    FROM fact_shipment s
    WHERE s.shipped_at >= (SELECT lookback_start FROM params)
),

-- Returns within window
returns AS (
    SELECT r.*
    FROM fact_return r
    WHERE r.requested_at >= (SELECT lookback_start FROM params)
),

-- Order items with price math and inline subqueries for discounts
order_items AS (
    SELECT
        oi.order_id,
        oi.order_item_id,
        oi.product_id,
        oi.quantity,
        oi.unit_price,
        oi.discount_amount,
        (oi.quantity * (oi.unit_price - COALESCE(oi.discount_amount,0)))::numeric AS net_revenue,
        -- Inline subquery: max competitor price (illustrative)
        (
            SELECT AVG(cp.price)
            FROM competitor_price cp
            WHERE cp.sku = (SELECT sku FROM products p WHERE p.product_id = oi.product_id)
              AND cp.effective_at <= (SELECT as_of_date FROM params)
        ) AS avg_competitor_price,
        -- Inline subquery: dynamic discount rate
        CASE WHEN oi.unit_price > 0 THEN (oi.discount_amount / oi.unit_price) ELSE 0 END AS discount_rate
    FROM fact_order_item oi
),

-- Web sessions summarized with LATERAL extraction of last touch
web_sessions AS (
    SELECT
        ws.session_id,
        ws.customer_id,
        ws.started_at,
        ws.ended_at,
        ws.device_type,
        ws.source_medium,
        ws.landing_page,
        ws.country_code,
        ws.attributes,
        t.last_touch_channel,
        t.last_touch_campaign
    FROM web_session ws
    LEFT JOIN LATERAL (
        SELECT mt.channel AS last_touch_channel,
               mt.campaign AS last_touch_campaign
        FROM marketing_touch mt
        WHERE mt.session_id = ws.session_id
        ORDER BY mt.occurred_at DESC
        LIMIT 1
    ) t ON true
),

-- Inventory balance snapshots (end-of-day) using window functions
inventory_daily AS (
    SELECT
        it.product_id,
        date_trunc('day', it.occurred_at) AS d,
        SUM(it.delta_qty) OVER (PARTITION BY it.product_id, date_trunc('day', it.occurred_at)) AS daily_delta,
        SUM(it.delta_qty) OVER (PARTITION BY it.product_id ORDER BY date_trunc('day', it.occurred_at)) AS running_qty
    FROM inventory_txn it
    WHERE it.occurred_at >= (SELECT lookback_start FROM params)
),

-- =====================================
-- Section 5: Derived Metrics (CTEs #17-#27)
-- =====================================

-- Per-order financials joined across facts with multi-column joins
order_financials AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.created_at AS order_created_at,
        o.channel_id,
        o.region_code,
        o.t1
        SUM(oi.net_revenue)               AS order_net_revenue,
        SUM(oi.quantity)                  AS order_units,
        COALESCE(SUM(p.amount) FILTER (WHERE p.status = 'paid'), 0) AS paid_amount,
        COALESCE(SUM(p.amount) FILTER (WHERE p.status = 'refunded'), 0) AS refunded_amount,
        COUNT(DISTINCT s.shipment_id)     AS shipments_count,
        COUNT(DISTINCT r.return_id)       AS returns_count,
        MAX(s.sla_band)                   AS max_sla_band,
        MIN(s.shipped_at)                 AS first_shipped_at,
        MAX(s.delivered_at)               AS last_delivered_at
    FROM orders_raw o
    JOIN order_items oi ON oi.order_id = o.order_id
    LEFT JOIN payments p ON p.order_id = o.order_id
    LEFT JOIN shipments s ON s.order_id = o.order_id AND s.method = ANY (SELECT ship_methods FROM params)
    LEFT JOIN returns   r ON r.order_id = o.order_id
    GROUP BY 1,2,3,4,5
),

-- RFM (Recency-Frequency-Monetary) for customers using window functions
customer_rfm AS (
    SELECT
        ofn.customer_id,
        MAX(ofn.order_created_at) AS last_order_at,
        COUNT(*)                  AS order_count,
        SUM(ofn.order_net_revenue) AS gross_revenue,
        SUM(ofn.paid_amount - ofn.refunded_amount) AS net_cash,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ofn.order_net_revenue) AS median_order_value,
        NTILE(5) OVER (ORDER BY MAX(ofn.order_created_at) DESC) AS recency_ntile,
        NTILE(5) OVER (ORDER BY COUNT(*) DESC) AS frequency_ntile,
        NTILE(5) OVER ( ORDER BY SUM(ofn.order_net_revenue) DESC ) AS monetary_ntile
    FROM order_financials ofn
    GROUP BY ofn.customer_id
),

-- High discount orders (nested inline subqueries)
flag_high_discount_orders AS (
    SELECT DISTINCT oi.order_id
    FROM order_items oi
    WHERE COALESCE(oi.discount_amount,0) > oi.unit_price * (SELECT high_discount_threshold FROM params)
       OR (
            EXISTS (
                SELECT 1 FROM (
                    SELECT oi2.order_item_id, (oi2.discount_amount / NULLIF(oi2.unit_price,0)) AS dr
                    FROM fact_order_item oi2
                    WHERE oi2.order_id = oi.order_id
                ) sub
                WHERE sub.dr > (SELECT extreme_discount_threshold FROM params)
           )
        )
),

-- Recent activity signals combining web sessions and orders
recent_activity AS (
    SELECT
        c.customer_id,
        COUNT(DISTINCT ws.session_id) FILTER (WHERE ws.started_at >= (SELECT recent_start FROM params)) AS recent_sessions,
        COUNT(DISTINCT ofn.order_id)  FILTER (WHERE ofn.order_created_at >= (SELECT recent_start FROM params)) AS recent_orders,
        MAX(ws.device_type) AS preferred_device,
        MAX(ws.last_touch_channel) AS last_touch_channel,
        MAX(ws.last_touch_campaign) AS last_touch_campaign
    FROM customers c
    LEFT JOIN web_sessions ws ON ws.customer_id = c.customer_id
    LEFT JOIN order_financials ofn ON ofn.customer_id = c.customer_id
    GROUP BY c.customer_id
),

-- Product performance with inline views and lateral joins
product_perf AS (
    SELECT
        p.product_id,
        p.sku,
        p.product_name,
        p.category,
        p.subcategory,
        p.brand,
        cr.category_group,
        SUM(oi.quantity)                     AS units_sold,
        SUM(oi.net_revenue)                  AS revenue,
        SUM(oi.quantity * p.unit_cost)       AS est_cogs,
        SUM(oi.net_revenue) - SUM(oi.quantity * p.unit_cost) AS est_margin,
        AVG(oi.discount_rate)                AS avg_discount_rate,
        -- LATERAL: top country by units
        lc.top_country,
        lc.country_units
    FROM products p
    JOIN order_items oi ON oi.product_id = p.product_id
    LEFT JOIN category_rollup cr ON cr.category = p.category
    LEFT JOIN LATERAL (
        SELECT country_code AS top_country, SUM(quantity) AS country_units
        FROM fact_order o2
        JOIN fact_order_item oi2 ON oi2.order_id = o2.order_id AND oi2.product_id = p.product_id
        WHERE o2.created_at >= (SELECT lookback_start FROM params)
        GROUP BY country_code
        ORDER BY SUM(quantity) DESC
        LIMIT 1
    ) lc ON true
    GROUP BY 1,2,3,4,5,6,7, lc.top_country, lc.country_units
),

-- Regional rollups with GROUPING SETS / ROLLUP
regional_rollup AS (
    SELECT
        o.region_code,
        r.region_name,
        r.super_region,
        GROUPING(o.region_code) AS g_region,
        SUM(ofn.order_net_revenue) AS region_revenue,
        COUNT(DISTINCT ofn.order_id) AS region_orders
    FROM orders_raw o
    JOIN order_financials ofn ON ofn.order_id = o.order_id
    LEFT JOIN regions r ON r.region_code = o.region_code
    GROUP BY ROLLUP (o.region_code, r.region_name, r.super_region)
),

-- Inventory at end-of-day per product, joined to date spine
inventory_eod AS (
    SELECT
        c.d::date AS d,
        i.product_id,
        MAX(i.running_qty) FILTER (WHERE date_trunc('day',i.d) = c.d) AS eod_qty
    FROM calendar c
    LEFT JOIN inventory_daily i ON i.d::date = c.d::date
    GROUP BY c.d::date, i.product_id
),

-- =====================================
-- Section 6: Filters & Flags (CTEs #28-#36)
-- =====================================

focus_customers AS (
    SELECT customer_id
    FROM customers
    WHERE country_code = ANY (SELECT focus_countries FROM params)
      AND NOT is_test
),

vip_customers AS (
    SELECT c.customer_id
    FROM customers c
    WHERE c.is_vip = true
),

-- Customers meeting RFM thresholds with multi-condition WHERE
target_customers AS (
    SELECT r.customer_id
    FROM customer_rfm r
    JOIN focus_customers f ON f.customer_id = r.customer_id
    WHERE r.recency_ntile <= 2
      AND r.frequency_ntile >= 4
      AND r.monetary_ntile  >= 4
),

-- Orders to analyze (join of multiple filters)
orders_in_scope AS (
    SELECT o.order_id
    FROM orders_raw o
    JOIN order_financials ofn ON ofn.order_id = o.order_id
    WHERE ofn.order_net_revenue >= (SELECT min_order_amount FROM params)
      AND o.customer_id IN (SELECT customer_id FROM focus_customers)
      AND (
            o.country_code IN (SELECT unnest(ARRAY['US','CA']))
         OR o.region_code IN (SELECT region_code FROM regions WHERE super_region = 'EMEA')
      )
      AND o.order_id NOT IN (
            SELECT order_id FROM returns WHERE status IN ('received','approved')
      )
),

-- High-risk orders combining many conditions
risk_orders AS (
    SELECT DISTINCT o.order_id
    FROM orders_raw o
    LEFT JOIN flag_high_discount_orders h ON h.order_id = o.order_id
    LEFT JOIN payments p ON p.order_id = o.order_id
    WHERE (
            h.order_id IS NOT NULL
         OR (p.status = 'chargeback')
         OR (o.fraud_score IS NOT NULL AND o.fraud_score > 0.85)
         OR (o.shipping_address ->> 'po_box')::boolean IS TRUE
         OR EXISTS (
                SELECT 1
                FROM web_session ws
                WHERE ws.customer_id = o.customer_id
                  AND lower(ws.source_medium) LIKE '%proxy%'
            )
    )
),

-- =====================================
-- Section 7: Complex Inline Views & Nested Subqueries (No CTEs inside)
-- =====================================

-- This CTE uses several inline views to build a dense, nested structure
inline_heavy AS (
    SELECT
        base.order_id,
        base.customer_id,
        base.order_created_at,
        base.region_code,
        base.order_net_revenue,
        base.order_units,
        base.paid_amount,
        base.refunded_amount,
        CASE WHEN base.paid_amount - base.refunded_amount >= base.order_net_revenue THEN 'PAID' ELSE 'UNDERPAID' END AS payment_state,
        -- Inline view: last marketing touch per order's customer
        (
            SELECT x.last_touch
            FROM (
                SELECT mt.campaign || ':' || mt.channel AS last_touch,
                       ROW_NUMBER() OVER (ORDER BY mt.occurred_at DESC) AS rn
                FROM marketing_touch mt
                JOIN fact_order fo ON fo.customer_id = base.customer_id
                WHERE fo.order_id = base.order_id
            ) x
            WHERE x.rn = 1
        ) AS last_touch,
        -- Deeply nested: best shipping SLA among shipments for same region
        (
            SELECT z.sla_band
            FROM (
                SELECT s.sla_band,
                       ROW_NUMBER() OVER (ORDER BY CASE s.sla_band WHEN 'EXPRESS' THEN 1 WHEN 'STANDARD' THEN 2 WHEN 'ECONOMY' THEN 3 ELSE 4 END) AS rn
                FROM fact_shipment s
                WHERE s.order_id = base.order_id
                  AND s.method = ANY (SELECT ship_methods FROM params)
            ) z
            WHERE z.rn = 1
        ) AS best_sla
    FROM (
        SELECT ofn.*
        FROM order_financials ofn
        WHERE ofn.order_id IN (SELECT order_id FROM orders_in_scope)
    ) base
),

-- =====================================
-- Section 8: Windowed & Conditional Aggregates (CTEs #37-#45)
-- =====================================

customer_order_rank AS (
    SELECT
        i.customer_id,
        i.order_id,
        i.order_created_at,
        RANK()        OVER (PARTITION BY i.customer_id ORDER BY i.order_created_at) AS order_seq,
        ROW_NUMBER()  OVER (PARTITION BY i.customer_id ORDER BY i.order_created_at DESC) AS rn_desc,
        LAG(i.order_id) OVER (PARTITION BY i.customer_id ORDER BY i.order_created_at) AS prev_order_id,
        LEAD(i.order_id) OVER (PARTITION BY i.customer_id ORDER BY i.order_created_at) AS next_order_id
    FROM inline_heavy i
),

customer_kpis AS (
    SELECT
        i.customer_id,
        COUNT(*) AS orders_in_scope,
        SUM(i.order_net_revenue) AS revenue_in_scope,
        SUM(CASE WHEN i.payment_state = 'PAID' THEN 1 ELSE 0 END) AS paid_orders,
        SUM(CASE WHEN i.payment_state = 'UNDERPAID' THEN 1 ELSE 0 END) AS underpaid_orders,
        SUM(CASE WHEN i.best_sla = 'EXPRESS' THEN 1 ELSE 0 END) AS express_shipments
    FROM inline_heavy i
    GROUP BY i.customer_id
),

-- Join in RFM and recent activity
customer_enriched AS (
    SELECT
        c.customer_id,
        CONCAT(cu.first_name, ' ', cu.last_name) AS full_name,
        cu.email,
        cu.country_code,
        cu.segment,
        ra.preferred_device,
        ra.last_touch_channel,
        ra.last_touch_campaign,
        rfm.order_count,
        rfm.gross_revenue,
        rfm.net_cash,
        rfm.median_order_value,
        rfm.recency_ntile,
        rfm.frequency_ntile,
        rfm.monetary_ntile,
        ck.orders_in_scope,
        ck.revenue_in_scope,
        ck.paid_orders,
        ck.underpaid_orders,
        ck.express_shipments
    FROM target_customers c
    JOIN customers cu      ON cu.customer_id = c.customer_id
    LEFT JOIN recent_activity ra ON ra.customer_id = c.customer_id
    LEFT JOIN customer_rfm rfm   ON rfm.customer_id = c.customer_id
    LEFT JOIN customer_kpis ck   ON ck.customer_id = c.customer_id
),

-- =====================================
-- Section 9: Advanced JSON/Array Manipulation (CTEs #46-#49)
-- =====================================

customer_channel_array AS (
    SELECT
        ce.customer_id,
        ARRAY_REMOVE(ARRAY[
            NULLIF(ce.last_touch_channel, ''),
            (SELECT channel_preference FROM regions r WHERE r.region_code = (SELECT region_code FROM orders_raw o WHERE o.customer_id = ce.customer_id LIMIT 1))
        ], NULL) AS channel_signals
    FROM customer_enriched ce
),

customer_tags_exploded AS (
    SELECT
        cu.customer_id,
        unnest(cu.tags_array) AS tag
    FROM customers cu
),

customer_tag_scores AS (
    SELECT
        e.customer_id,
        t.tag,
        COUNT(*) AS tag_count,
        DENSE_RANK() OVER (PARTITION BY e.customer_id ORDER BY COUNT(*) DESC) AS tag_rank
    FROM customer_tags_exploded e
    JOIN customer_tags_exploded t ON t.customer_id = e.customer_id AND t.tag = e.tag
    GROUP BY e.customer_id, t.tag
),

-- =====================================
-- Section 10: Final Assembly (CTEs #50-#59)
-- =====================================

final_orders AS (
    SELECT
        i.order_id,
        i.customer_id,
        i.order_created_at,
        i.region_code,
        i.order_net_revenue,
        i.order_units,
        i.paid_amount,
        i.refunded_amount,
        i.payment_state,
        i.last_touch,
        i.best_sla,
        CASE WHEN ro.order_id IS NOT NULL THEN 1 ELSE 0 END AS is_risk
    FROM inline_heavy i
    LEFT JOIN risk_orders ro ON ro.order_id = i.order_id
),

final_customers AS (
    SELECT
        ce.customer_id,
        ce.full_name,
        ce.email,
        ce.country_code,
        ce.segment,
        ce.preferred_device,
        ce.last_touch_channel,
        ce.last_touch_campaign,
        ce.order_count,
        ce.gross_revenue,
        ce.net_cash,
        ce.median_order_value,
        ce.recency_ntile,
        ce.frequency_ntile,
        ce.monetary_ntile,
        ce.orders_in_scope,
        ce.revenue_in_scope,
        ce.paid_orders,
        ce.underpaid_orders,
        ce.express_shipments
    FROM customer_enriched ce
),

-- KPI rollups by category with multiple joins and filters
category_kpis AS (
    SELECT
        pp.category_group,
        COUNT(DISTINCT CASE WHEN oi.quantity > 0 THEN oi.order_id END) AS orders,
        SUM(pp.units_sold)  AS units,
        SUM(pp.revenue)     AS revenue,
        SUM(pp.est_margin)  AS margin,
        AVG(pp.avg_discount_rate) AS avg_discount
    FROM product_perf pp
    JOIN order_items oi ON oi.product_id = pp.product_id
    JOIN orders_in_scope os ON os.order_id = oi.order_id
    GROUP BY pp.category_group
),

-- Complex inline filter: customers with specific arrays and tags
final_targets AS (
    SELECT fc.customer_id
    FROM final_customers fc
    JOIN customer_channel_array cca ON cca.customer_id = fc.customer_id
    WHERE (
        'email' = ANY(cca.channel_signals) OR 'referral' = ANY(cca.channel_signals)
    )
    AND fc.country_code IN (SELECT unnest(ARRAY['US','GB','DE']))
    AND EXISTS (
        SELECT 1 FROM customer_tag_scores ts WHERE ts.customer_id = fc.customer_id AND ts.tag_rank <= 3
    )
)

-- =====================================
-- Section 11: Final Select (deep joins, multi-column joins, complex WHERE)
-- =====================================
SELECT
    fo.order_id,
    fo.customer_id,
    fc.full_name,
    fc.email,
    fc.segment,
    fc.country_code,
    fc.preferred_device,
    coalesce(fc.last_touch_channel, split_part(fo.last_touch, ':', 2)) AS inferred_channel,
    coalesce(fc.last_touch_campaign, split_part(fo.last_touch, ':', 1)) AS inferred_campaign,
    fo.order_created_at,
    fo.order_net_revenue,
    fo.order_units,
    fo.paid_amount,
    fo.refunded_amount,
    fo.payment_state,
    fo.best_sla,
    fo.is_risk,
    r.region_name,
    r.super_region,
    ck.category_group,
    ckpi.orders      AS cat_orders,
    ckpi.units       AS cat_units,
    ckpi.revenue     AS cat_revenue,
    ckpi.margin      AS cat_margin,
    ckpi.avg_discount AS cat_avg_discount,
    crfm.order_count      AS cust_total_orders,
    crfm.gross_revenue    AS cust_gross_rev,
    crfm.net_cash         AS cust_net_cash,
    crfm.recency_ntile,
    crfm.frequency_ntile,
    crfm.monetary_ntile,
    cor.order_seq,
    cor.prev_order_id,
    cor.next_order_id,
    -- Inline scalar subquery: inventory at end of day for top item in order
    (
        SELECT e.eod_qty
        FROM inventory_eod e
        JOIN (
            SELECT oi.product_id
            FROM fact_order_item oi
            WHERE oi.order_id = fo.order_id
            ORDER BY oi.quantity DESC, oi.unit_price DESC
            LIMIT 1
        ) top_item ON top_item.product_id = e.product_id
        WHERE e.d::date = fo.order_created_at::date
        LIMIT 1
    ) AS eod_qty_top_item,
    -- Extra nested subquery: count of distinct tags among customer preferences
    (
        SELECT COUNT(DISTINCT t.tag)
        FROM customer_tags_exploded t
        WHERE t.customer_id = fo.customer_id
    ) AS distinct_tags
FROM final_orders fo
JOIN final_customers fc ON fc.customer_id = fo.customer_id
LEFT JOIN regions r ON r.region_code = fo.region_code
-- Join to category KPIs via derived mapping of the highest revenue product in the order
LEFT JOIN LATERAL (
    SELECT cr.category_group
    FROM (
        SELECT oi.product_id, SUM(oi.net_revenue) AS rev
        FROM fact_order_item oi
        WHERE oi.order_id = fo.order_id
        GROUP BY oi.product_id
        ORDER BY SUM(oi.net_revenue) DESC NULLS LAST
        LIMIT 1
    ) mx
    JOIN products p ON p.product_id = mx.product_id
    JOIN category_rollup cr ON cr.category = p.category
) ck ON true
LEFT JOIN category_kpis ckpi ON ckpi.category_group = ck.category_group
LEFT JOIN customer_rfm crfm ON crfm.customer_id = fo.customer_id
LEFT JOIN customer_order_rank cor ON cor.customer_id = fo.customer_id AND cor.order_id = fo.order_id
WHERE
    fo.order_created_at >= (SELECT lookback_start FROM params)
    AND fo.order_created_at <  (SELECT as_of_date FROM params) + INTERVAL '1 day'
    AND (
        (fo.payment_state = 'PAID' AND fo.paid_amount >= fo.order_net_revenue)
        OR (
            fo.payment_state = 'UNDERPAID' AND fo.paid_amount >= fo.order_net_revenue * 0.8
           )
    )
    AND (
        NOT fo.is_risk OR (
            fo.is_risk AND fo.order_net_revenue <= 10000
        )
    )
    AND fc.customer_id IN (SELECT customer_id FROM final_targets)
ORDER BY fo.order_created_at DESC, fo.order_net_revenue DESC
LIMIT 3000;



