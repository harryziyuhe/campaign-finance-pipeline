"""Per-committee monthly contribution-spike detector.

Extracted from the legacy scripts/FEC/pre_election.ipynb (zscore_rolling_spike
and its clean_contrib panel-construction cells). Builds a complete
committee x month panel of contribution amount/count/unique-candidate-count
for a cycle, then flags months where a committee's giving is an outlier
relative to its own trailing EMA-smoothed baseline (an anomalous late-cycle
giving spike). No equivalent exists anywhere in the active pipeline.

Adaptation from the original notebook-era version: the original was hardcoded
to the 2024 cycle and counted transactions via a raw FEC "SUB_ID" column that
doesn't exist in the current processed schema; both are generalized here (any
--cycle, and a synthetic per-transaction counter in place of SUB_ID).
"""

import argparse
import os
from pathlib import Path

import numpy as np
import pandas as pd
from tqdm import tqdm

from utils import count_unique
from PartisanHedgingIndex import FIRM_PAC_CONTRIBUTIONS_FILE

SCRIPT_ROOT = Path(__file__).resolve().parents[3]


def _require_data_root() -> Path:
    value = os.environ.get("CAMPAIGNFINANCE_DATA_ROOT")
    if not value:
        raise RuntimeError(
            "CAMPAIGNFINANCE_DATA_ROOT is not set. Point it at the campaign-finance-data "
            "folder (contains data/ and outputs/), e.g.:\n"
            '  $env:CAMPAIGNFINANCE_DATA_ROOT = "C:\\Users\\<you>\\Dropbox\\campaign-finance-data"'
        )
    root = Path(value)
    if not root.is_dir():
        raise RuntimeError(f"CAMPAIGNFINANCE_DATA_ROOT does not exist: {root}")
    return root


DATA_ROOT = _require_data_root()
OUTPUT_DIR = DATA_ROOT / "data" / "processed" / "fec" / "contribution_spike_detection"

VALUE_COLS = ["amount", "count", "unique"]


def build_monthly_panel(cycle: int) -> pd.DataFrame:
    """Committee x month panel, MONTH normalized 1..24 across the two-year cycle
    (year cycle-1 -> months 1-12, year cycle -> months 13-24), reindexed to a
    complete grid per committee so gaps become explicit zero-giving months."""
    base_year = cycle - 1
    contrib = pd.read_parquet(FIRM_PAC_CONTRIBUTIONS_FILE)
    contrib = contrib[contrib["cycle"] == cycle].copy()
    contrib = contrib[contrib["amount"] > 0]
    contrib["MONTH"] = (contrib["year"] - base_year) * 12 + contrib["month"]
    contrib["n_transactions"] = 1

    panel = (
        contrib[["cmte_id", "MONTH", "amount", "n_transactions", "cand_id"]]
        .groupby(["cmte_id", "MONTH"], as_index=False)
        .agg({"amount": "sum", "n_transactions": "sum", "cand_id": count_unique})
    )
    panel.columns = ["CMTE_ID", "MONTH", "amount", "count", "unique"]

    df_index = pd.MultiIndex.from_product(
        [panel["CMTE_ID"].unique(), range(1, 25)], names=["CMTE_ID", "MONTH"]
    )
    panel = panel.set_index(["CMTE_ID", "MONTH"]).reindex(df_index).fillna(0).reset_index()
    return panel


def zscore_rolling_spike(
    df: pd.DataFrame,
    value_cols: list[str],
    window: int = 6,
    alpha: float = 0.5,
    scale_method: str = "ema_absdev",
    scale_eps: float = 1e-4,
) -> pd.DataFrame:
    df = df.sort_values(["CMTE_ID", "MONTH"])
    result = []
    for id_val, group in tqdm(df.groupby("CMTE_ID")):
        group = group.sort_values("MONTH").reset_index(drop=True)
        n = len(group)
        if n < window:
            continue

        for i in range(window, n):
            row = {"CMTE_ID": id_val, "MONTH": group.loc[i, "MONTH"]}
            for col in value_cols:
                series = group[col].iloc[i - window:i + 1]  # include current
                current = series.iloc[-1]
                past = series.iloc[:-1]

                # 1. Smoothed average (EMA)
                ema = past.ewm(alpha=alpha).mean().iloc[-1]

                # 2. Scale estimator
                if scale_method == "ema_absdev":
                    abs_dev = (past - ema).abs()
                    scale = abs_dev.ewm(alpha=alpha).mean().iloc[-1]
                elif scale_method == "std":
                    scale = past.std()
                elif scale_method == "iqr":
                    scale = np.percentile(past, 75) - np.percentile(past, 25)
                else:
                    raise ValueError(f"Unknown scale_method: {scale_method}")

                scale = max(scale, scale_eps)  # avoid divide-by-zero
                score = (current - ema) / scale

                row[f"{col}_spike_score"] = score
                row[f"{col}_is_spike"] = score > 2.5

            result.append(row)

    return pd.DataFrame(result)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Detect anomalous per-committee monthly giving spikes.")
    parser.add_argument("--cycles", type=int, nargs="+", required=True, help="Even election-year cycles to process.")
    parser.add_argument("--window", type=int, default=6, help="Trailing window (months) for the EMA baseline.")
    parser.add_argument("--alpha", type=float, default=0.5, help="EMA smoothing factor.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for cycle in args.cycles:
        panel = build_monthly_panel(cycle)
        spikes = zscore_rolling_spike(panel, VALUE_COLS, window=args.window, alpha=args.alpha)
        spikes.to_csv(OUTPUT_DIR / f"contribution_spikes_{cycle}.csv", index=False)
        n_spikes = int(spikes["amount_is_spike"].sum()) if len(spikes) else 0
        print(f"cycle {cycle}: {len(spikes)} committee-months scored, {n_spikes} amount spikes flagged")


if __name__ == "__main__":
    main()
