-- Standalone monthly median price-per-sqm series, 4-room flats, full
-- calendar range with empty rows for 2022 so a chart shows the gap as a
-- real break instead of joining a straight line across the missing year.

WITH months AS (
  SELECT EXPLODE(SEQUENCE(DATE'2017-01-01', DATE'2026-09-01', INTERVAL 1 MONTH)) AS month
),
p AS (
  SELECT CAST(DATE_TRUNC('month', month) AS DATE) AS month,
         COUNT(*) AS deals,
         ROUND(PERCENTILE_APPROX(resale_price / floor_area_sqm, 0.5)) AS median_psm
  FROM workspace.default.hdb_resale_prices
  WHERE flat_type = '4 ROOM'
  GROUP BY 1
)
SELECT m.month, p.deals, p.median_psm
FROM months m
LEFT JOIN p ON m.month = p.month
ORDER BY m.month;
