# Databricks notebook source
#
# FlatFair — 6-month rolling backtest
#
# Compares a naive "prices stay flat" baseline against five damped-trend
# settings and a fully-fitted trend, forecasting 4-room median price per
# sqm six months ahead from every point since Jan 2023 (the resale
# dataset has no 2022 records, so the series starts there). Each run's
# parameters and error are logged to MLflow. Run this in a Databricks
# notebook after sql/01_build_tables.sql has created hdb_resale_clean.

import mlflow
import numpy as np
import pandas as pd

df = spark.sql("""
SELECT DATE_TRUNC('month', month) AS month,
       PERCENTILE_APPROX(resale_price / floor_area_sqm, 0.5) AS psm
FROM workspace.default.hdb_resale_clean
WHERE flat_type = '4 ROOM' AND month >= '2023-01-01'
GROUP BY 1 ORDER BY 1
""").toPandas()

s = df["psm"].astype(float).values[:-1]  # drop the latest month, it is incomplete
H, W, start = 6, 12, 18  # 6-month horizon, 12-month trend window, 18 months minimum history


def backtest(predict):
    errs = []
    for t in range(start, len(s) - H + 1):
        hist = s[:t]
        actual = s[t + H - 1]
        errs.append(abs(predict(hist) - actual) / actual * 100)
    return len(errs), float(np.mean(errs))


def damped(phi):
    def f(h):
        slope, _ = np.polyfit(np.arange(W), h[-W:], 1)
        return h[-1] + phi * slope * H
    return f


def fitted_trend(h):
    slope, intercept = np.polyfit(np.arange(W), h[-W:], 1)
    return intercept + slope * (W - 1 + H)


models = {f"damped_{p}": damped(p) for p in [0, 0.25, 0.5, 0.75, 1.0]}  # damped_0 is the naive baseline
models["fitted_trend"] = fitted_trend

for name, fn in models.items():
    n, mape = backtest(fn)
    with mlflow.start_run(run_name=name):
        mlflow.log_params({
            "model": name,
            "horizon_months": H,
            "trend_window": W,
            "n_forecasts": n,
            "data": "4-room median psm, 2023-01 onward",
        })
        mlflow.log_metric("mape_pct", mape)
    print(name, round(mape, 2))

# Expected output (this run):
#   damped_0     1.72   <- naive baseline
#   damped_0.25  1.38   <- best performer
#   damped_0.5   1.51
#   damped_0.75  1.83
#   damped_1.0   2.24
#   fitted_trend 2.71   <- worst, overshoots once the market flattens

# COMMAND ----------
#
# Per-town robustness check
#
# Repeats the same backtest per town, to see whether the national result
# (damped_0.25 beating the naive baseline) holds up at finer granularity.
# Answer: only partially — a 25%-damped trend wins in some towns and
# loses in others, and error rates are much higher, so FlatFair reports
# a national outlook rather than a town-level price prediction.

towns = spark.sql("""
SELECT town, DATE_TRUNC('month', month) AS month,
       COUNT(*) AS deals,
       PERCENTILE_APPROX(resale_price / floor_area_sqm, 0.5) AS psm
FROM workspace.default.hdb_resale_clean
WHERE flat_type = '4 ROOM' AND month >= '2023-01-01'
GROUP BY 1, 2 ORDER BY 1, 2
""").toPandas()

PHI = 0.25
out = []
for town, g in towns.groupby("town"):
    g = g.sort_values("month").iloc[:-1]  # drop the incomplete latest month
    if len(g) < 40 or g["deals"].mean() < 15:  # skip thin markets
        continue
    x = g["psm"].astype(float).values
    e_naive, e_damp = [], []
    for t in range(start, len(x) - H + 1):
        h = x[:t]
        slope, _ = np.polyfit(np.arange(W), h[-W:], 1)
        a = x[t + H - 1]
        e_naive.append(abs(h[-1] - a) / a * 100)
        e_damp.append(abs(h[-1] + PHI * slope * H - a) / a * 100)
    slope, _ = np.polyfit(np.arange(W), x[-W:], 1)
    out.append((
        town,
        round(np.mean(e_naive), 2),
        round(np.mean(e_damp), 2),
        round(x[-1]),
        round((PHI * slope * H) / x[-1] * 100, 2),
    ))

res = pd.DataFrame(out, columns=["town", "naive_err", "damped_err", "latest_psm", "outlook_6m_pct"])
print(res.sort_values("outlook_6m_pct").to_string(index=False))
print("towns tested:", len(res), "| damped beats naive in", (res.damped_err < res.naive_err).sum())
print("avg error - naive:", round(res.naive_err.mean(), 2), "| damped:", round(res.damped_err.mean(), 2))
