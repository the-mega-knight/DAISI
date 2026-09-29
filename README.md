# FlatFair

DAISI Challenge Singapore 2026 · Round 1 · Track C1 (HDB resale market intelligence and affordability forecasting)

FlatFair shows first-time HDB buyers, town by town, how many years of income a flat costs, what they pay per year of remaining lease, and a backtested 6-month price outlook.

Everything here runs on Databricks Free Edition. This repo holds the SQL and the notebook code as plain files so the analysis can be read and reviewed outside the workspace; it isn't a runnable app on its own, since it depends on the two source tables already being loaded into a Databricks workspace (see below).

## Data

- `hdb_resale_prices` — HDB Resale Flat Prices, Jan 2017 onwards. [data.gov.sg](https://data.gov.sg/datasets/d_8b84c4ee58e3cfc0ece0d773c8ca6abc/view), 214,087 rows. The source has no 2022 records.
- `hdb_income_by_dwelling` — Average Monthly Household Employment Income per Household Member by Type of Dwelling, 2000–2023 (SingStat, via [data.gov.sg](https://data.gov.sg/datasets/d_c49b6cc84ccab3a0523ad15a907e57be/view)).

Both were uploaded manually into Unity Catalog (`workspace.default`) through the Catalog UI, since Free Edition serverless compute can't reach data.gov.sg without identity verification.

## Contents

| File | What it does |
|---|---|
| `sql/01_build_tables.sql` | Data quality check on the raw resale table, then builds `hdb_resale_clean` and three derived tables: `affordability_trend_4room`, `affordability_by_town_2026`, `monthly_psm_4room`. |
| `sql/02_monthly_price_series.sql` | Standalone monthly median price-per-sqm series for 4-room flats, with every 2022 month present but empty so the gap in the source data shows as a real break in any chart, not a smoothed line. |
| `notebooks/backtest.py` | Rolling 6-month backtest of a naive baseline against five damped-trend settings and a full trend model, over 4-room median price per sqm since Jan 2023. Logs every run's parameters and error to MLflow. Also includes the per-town robustness check. |

## Key result

Nationally, a 25%-damped trend beat a "prices stay flat" baseline (1.38% vs. 1.72% average error over a rolling 6-month horizon). A full trend-following model did worst of all (2.71%), because it kept extending a rise that had already flattened out. At the town level the same damped model had no reliable edge over the baseline, so FlatFair currently reports a national range rather than a town-by-town price prediction.

## Status

Built: Unity Catalog, Delta tables, Databricks SQL, serverless notebooks, MLflow experiment tracking, an AI/BI dashboard.
Planned: automated ingestion (Lakeflow), a buyer-facing budget tool (Databricks Apps), a mix-adjusted price index, and MLflow model registration.

Full write-up: see the Round 1 slide deck and the [Devpost project page](https://devpost.com/software/flatfair).
