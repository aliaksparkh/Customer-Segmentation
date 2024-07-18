WITH 
-- Compute for F & M
t1 AS (
    SELECT  
        CustomerID,
        Country,
        MAX(DATE(InvoiceDate)) AS last_purchase_date,
        COUNT(DISTINCT InvoiceNo) AS frequency,
        ROUND(SUM(Quantity * UnitPrice), 2) AS monetary 
    FROM `turing_data_analytics.rfm` AS rfm
    WHERE DATE(InvoiceDate) <= '2011-12-01' 
        AND CustomerID IS NOT NULL 
        AND Quantity >= 0 
        AND UnitPrice > 0
    GROUP BY CustomerID, Country
),

-- Select the most recent country for each CustomerID
t2 AS (
    SELECT 
        CustomerID,
        ARRAY_AGG(STRUCT(Country, last_purchase_date) ORDER BY last_purchase_date DESC LIMIT 1)[OFFSET(0)].Country AS Country,
        MAX(last_purchase_date) AS last_purchase_date,
        MAX(frequency) AS frequency,
        MAX(monetary) AS monetary
    FROM t1
    GROUP BY CustomerID
),

-- Compute for R
t3 AS (
    SELECT 
        CustomerID,
        Country,
        frequency,
        monetary,
        DATE_DIFF(reference_date, last_purchase_date, DAY) AS recency
    FROM (
        SELECT  
            t2.*,
            MAX(t2.last_purchase_date) OVER () AS reference_date
        FROM t2
    )  
),

-- Determine quintiles for RFM
t4 AS (
    SELECT 
        a.*,
        -- All percentiles for MONEY_VALUE
        b.percentiles[offset(25)] AS m25, 
        b.percentiles[offset(50)] AS m50,
        b.percentiles[offset(75)] AS m75, 
        b.percentiles[offset(100)] AS m100,    
        -- All percentiles for FREQUENCY
        c.percentiles[offset(25)] AS f25, 
        c.percentiles[offset(50)] AS f50,
        c.percentiles[offset(75)] AS f75, 
        c.percentiles[offset(100)] AS f100,    
        -- All percentiles for RECENCY
        d.percentiles[offset(25)] AS r25, 
        d.percentiles[offset(50)] AS r50,
        d.percentiles[offset(75)] AS r75, 
        d.percentiles[offset(100)] AS r100
    FROM 
        t3 a,
        (SELECT APPROX_QUANTILES(monetary, 100) percentiles FROM t3) b,
        (SELECT APPROX_QUANTILES(frequency, 100) percentiles FROM t3) c,
        (SELECT APPROX_QUANTILES(recency, 100) percentiles FROM t3) d
),

-- Assign scores for R and combined FM
t5 AS (
    SELECT *, 
    CAST(ROUND((f_score + m_score) / 2, 0) AS INT64) AS fm_score
    FROM (
        SELECT *, 
        CASE WHEN monetary <= m25 THEN 1
            WHEN monetary <= m50 AND monetary > m25 THEN 2 
            WHEN monetary <= m75 AND monetary > m50 THEN 3 
            WHEN monetary <= m100 AND monetary > m75 THEN 4 
        END AS m_score,
        CASE WHEN frequency <= f25 THEN 1
            WHEN frequency <= f50 AND frequency > f25 THEN 2 
            WHEN frequency <= f75 AND frequency > f50 THEN 3 
            WHEN frequency <= f100 AND frequency > f75 THEN 4 
        END AS f_score,
        -- Recency scoring is reversed
        CASE WHEN recency <= r25 THEN 4
            WHEN recency <= r50 AND recency > r25 THEN 3 
            WHEN recency <= r75 AND recency > r50 THEN 2 
            WHEN recency <= r100 AND recency > r75 THEN 1 
        END AS r_score
        FROM t4
    )
),

-- Define RFM segments
t6 AS (
    SELECT 
        CustomerID, 
        Country,
        recency,
        frequency, 
        monetary,
        r_score,
        f_score,
        m_score,
        fm_score,
        CASE 
        WHEN (r_score = 4 AND fm_score = 4) THEN 'Best Customers'
        WHEN (r_score = 4 AND fm_score = 3) 
            OR (r_score = 3 AND fm_score = 4)
            OR (r_score = 3 AND fm_score = 3) THEN 'Loyal Customers'
        WHEN (r_score = 2 AND fm_score = 3) 
            OR (r_score = 2 AND fm_score = 4) THEN 'Potential Loyalists'
        WHEN (r_score = 4 AND fm_score = 1) 
            OR (r_score = 4 AND fm_score = 2) THEN 'Recent Customers'
        WHEN (r_score = 3 AND fm_score = 2)
            OR (r_score = 3 AND fm_score = 1) THEN 'Promising Customers'
        WHEN (r_score = 2 AND fm_score = 2)
            OR (r_score = 2 AND fm_score = 1) THEN 'At Risk'
        WHEN (r_score = 1 AND fm_score = 2)
            OR (r_score = 1 AND fm_score = 3)
            OR (r_score = 1 AND fm_score = 4) THEN 'Hibernating Customers'
        WHEN r_score = 1 AND fm_score = 1 THEN 'Lost Customers'
        END AS rfm_segment 
    FROM t5
)

SELECT *
FROM t6;