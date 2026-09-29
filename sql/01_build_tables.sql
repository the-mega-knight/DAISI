-- FlatFair: build the cleaned base table and the derived tables the
-- dashboard and backtest run on. Run against `workspace.default`, with
-- hdb_resale_prices and hdb_income_by_dwelling already loaded.

-- 0) Data quality check on the raw table (all counts should be 0 except total_rows)
SELECT COUNT(*) AS total_rows,
       SUM(CASE WHEN resale_price IS NULL OR resale_price <= 0 THEN 1 ELSE 0 END) AS bad_price,
       SUM(CASE WHEN floor_area_sqm IS NULL OR floor_area_sqm <= 0 THEN 1 ELSE 0 END) AS bad_area,
       SUM(CASE WHEN lease_commence_date IS NULL THEN 1 ELSE 0 END) AS null_lease,
       SUM(CASE WHEN town IS NULL OR flat_type IS NULL THEN 1 ELSE 0 END) AS null_town_or_type,
       COUNT(*) - COUNT(DISTINCT month, town, flat_type, block, street_name, storey_range,
                        floor_area_sqm, flat_model, lease_commence_date, resale_price) AS possible_duplicates,
       MIN(99 - (YEAR(month) - lease_commence_date)) AS min_lease_left,
       MAX(99 - (YEAR(month) - lease_commence_date)) AS max_lease_left
FROM workspace.default.hdb_resale_prices;

-- 1) Cleaned base table, with remaining lease and price per sqm added
CREATE OR REPLACE TABLE workspace.default.hdb_resale_clean
COMMENT 'HDB resale transactions Jan 2017 onwards (data.gov.sg) with remaining lease and price per sqm. Source has no 2022 records.'
AS
SELECT month, town, flat_type, storey_range, floor_area_sqm, flat_model, lease_commence_date,
       99 - (YEAR(month) - lease_commence_date) AS remaining_lease_yrs,
       resale_price,
       ROUND(resale_price / floor_area_sqm, 1) AS psm
FROM workspace.default.hdb_resale_prices
WHERE resale_price > 0 AND floor_area_sqm > 0 AND lease_commence_date IS NOT NULL;

-- 2) Affordability trend, 4-room (2022 absent in source; income after 2023 held at 2023)
CREATE OR REPLACE TABLE workspace.default.affordability_trend_4room
COMMENT 'Years of household income to buy an average 4-room flat. Household income = per-member income x 3.'
AS
WITH p AS (
  SELECT YEAR(month) AS yr, ROUND(AVG(resale_price)) AS avg_price
  FROM workspace.default.hdb_resale_clean
  WHERE flat_type = '4 ROOM'
  GROUP BY 1
)
SELECT p.yr, p.avg_price, i.HDB4_RoomFlats AS income_per_member,
       ROUND(p.avg_price / (i.HDB4_RoomFlats * 3 * 12), 1) AS years_of_income
FROM p
JOIN workspace.default.hdb_income_by_dwelling i ON i.Dollar = LEAST(p.yr, 2023);

-- 3) Town affordability and lease-adjusted value, 4-room, 2026 (towns with 30+ sales)
CREATE OR REPLACE TABLE workspace.default.affordability_by_town_2026
COMMENT 'Per-town 4-room affordability and cost per remaining lease year, 2026 sales, towns with 30+ deals.'
AS
SELECT town,
       COUNT(*) AS deals,
       ROUND(AVG(resale_price)) AS avg_price,
       ROUND(AVG(remaining_lease_yrs), 1) AS avg_lease_left,
       ROUND(AVG(resale_price) / (3431 * 3 * 12), 1) AS years_of_income,
       ROUND(AVG(resale_price / remaining_lease_yrs)) AS cost_per_lease_year
FROM workspace.default.hdb_resale_clean
WHERE flat_type = '4 ROOM' AND YEAR(month) = 2026
GROUP BY town
HAVING COUNT(*) >= 30;

-- 4) Monthly 4-room price per sqm, full calendar so 2022 shows as a gap
CREATE OR REPLACE TABLE workspace.default.monthly_psm_4room
COMMENT 'Median 4-room price per sqm by month. 2022 rows are empty because the source has no 2022 data.'
AS
WITH months AS (
  SELECT EXPLODE(SEQUENCE(DATE'2017-01-01', DATE'2026-09-01', INTERVAL 1 MONTH)) AS month
),
p AS (
  SELECT CAST(DATE_TRUNC('month', month) AS DATE) AS month, COUNT(*) AS deals,
         ROUND(PERCENTILE_APPROX(psm, 0.5)) AS median_psm
  FROM workspace.default.hdb_resale_clean
  WHERE flat_type = '4 ROOM'
  GROUP BY 1
)
SELECT m.month, p.deals, p.median_psm
FROM months m LEFT JOIN p ON m.month = p.month;

-- 5) Confirm the row counts
SELECT 'hdb_resale_clean' AS tbl, COUNT(*) AS n FROM workspace.default.hdb_resale_clean
UNION ALL SELECT 'affordability_trend_4room', COUNT(*) FROM workspace.default.affordability_trend_4room
UNION ALL SELECT 'affordability_by_town_2026', COUNT(*) FROM workspace.default.affordability_by_town_2026
UNION ALL SELECT 'monthly_psm_4room', COUNT(*) FROM workspace.default.monthly_psm_4room;
