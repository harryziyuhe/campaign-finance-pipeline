"""
Flags (state, district, cycle) races where the Inside Elections rating series
is likely describing two different underlying districts rather than one
race whose competitiveness genuinely moved over time.

Two independent signals, combined rather than substituted for each other:

  Signal A (incumbent-identity discontinuity): the rated incumbent's surname
  changes within a single cycle with no special election in between. A named
  officeholder cannot change through the ordinary electoral process before
  the next election, so this is near-certain evidence that the district label
  now refers to a different seat (redistricting), or a rare non-boundary event
  (disqualification, resignation without the special flag set). Either way,
  ratings before the break describe a race that predates whatever produced
  the discontinuity.

  Signal B (structural break in rating level): finds the single split point
  in a race's rating series that best separates it into two stable segments
  (low within-segment variance, large between-segment gap). Catches cases
  where the map changed enough to alter competitiveness even though the same
  incumbent was carried into the new district.

Neither signal alone determines whether a flagged race needs a floor date:
    - Coordinated, statewide breaks clustered on the same date are strong
      evidence of an actual map replacement.
    - Isolated single-district breaks are more likely real politics
      (retirement, scandal, disqualification) -- exactly the kind of
      legitimate temporal variation the date-matched design is supposed to
      capture, not an artifact to remove.
This script only flags candidates for review; classification against
external redistricting-litigation sources happens downstream.

Inputs:  data/raw/electionratings/IE/house_ratings.csv
Outputs: data/processed/electionratings/race_stability_signal_a.csv
         data/processed/electionratings/race_stability_signal_b.csv
         data/processed/electionratings/race_stability_state_cycle_summary.csv
"""
import re
import os
from pathlib import Path

import numpy as np
import pandas as pd

SCRIPT_ROOT = Path(__file__).resolve().parents[4]


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
IE_RATINGS_PATH = DATA_ROOT / "data" / "raw" / "electionratings" / "IE" / "house_ratings.csv"
OUT_PATH = DATA_ROOT / "data" / "processed" / "electionratings"

# Signal B thresholds: a split must explain most of the series' variance and
# have a real gap between segment means to count as a structural break.
MIN_EXPLAINED_VAR = 0.6
MIN_GAP = 2.0


def norm_name(x):
    if pd.isna(x):
        return None
    return re.sub(r"[^A-Za-z]", "", str(x)).lower()


def names_match(a, b):
    # "Rogers" vs "M. Rogers" style formatting variants count as the same person
    if a is None or b is None:
        return a == b
    return a == b or a in b or b in a


def load_ratings():
    r = pd.read_csv(IE_RATINGS_PATH, index_col=0, low_memory=False)
    r["date"] = pd.to_datetime(r["date"])
    # off-year (odd) snapshots describe the upcoming even-year election;
    # map them onto that cycle rather than their own calendar year
    cal_year = r["date"].dt.year
    r["cycle"] = np.where(cal_year % 2 == 0, cal_year, cal_year + 1)
    return r.drop_duplicates(["state", "district", "date"]).sort_values(["state", "district", "date"])


def find_signal_a(r):
    rows = []
    for (state, district, cycle), g in r.groupby(["state", "district", "cycle"]):
        g = g.sort_values("date").reset_index(drop=True)
        names = g["incumbent"].apply(norm_name).tolist()
        specials = g["special"].tolist()
        dates = g["date"].tolist()
        for i in range(1, len(names)):
            if not names_match(names[i - 1], names[i]) and specials[i - 1] == 0 and specials[i] == 0:
                rows.append({
                    "state": state, "district": district, "cycle": cycle,
                    "date_before": dates[i - 1], "incumbent_before": g["incumbent"].iloc[i - 1],
                    "date_after": dates[i], "incumbent_after": g["incumbent"].iloc[i],
                    "rating_before": g["rating"].iloc[i - 1], "rating_after": g["rating"].iloc[i],
                })
    return pd.DataFrame(rows)


def find_signal_b(r):
    rows = []
    for (state, district, cycle), g in r.groupby(["state", "district", "cycle"]):
        g = g.sort_values("date").reset_index(drop=True)
        ratings = g["rating"].to_numpy(dtype=float)
        n = len(ratings)
        if n < 4:
            continue  # need >= 2 points on each side to call a segment "stable"

        sse_flat = np.sum((ratings - ratings.mean()) ** 2)
        if sse_flat == 0:
            continue

        best = None
        for k in range(2, n - 1):
            left, right = ratings[:k], ratings[k:]
            sse_split = np.sum((left - left.mean()) ** 2) + np.sum((right - right.mean()) ** 2)
            gap = abs(left.mean() - right.mean())
            if best is None or sse_split < best[0]:
                best = (sse_split, k, gap)

        sse_split, k, gap = best
        explained = 1 - (sse_split / sse_flat)
        if explained >= MIN_EXPLAINED_VAR and gap >= MIN_GAP:
            rows.append({
                "state": state, "district": district, "cycle": cycle,
                "split_date": g["date"].iloc[k], "gap": gap, "explained_var": explained,
                "mean_before": ratings[:k].mean(), "mean_after": ratings[k:].mean(),
                "n_before": k, "n_after": n - k,
            })
    return pd.DataFrame(rows)


def build_state_cycle_summary(a_df, b_df):
    a_counts = (a_df.drop_duplicates(["state", "district", "cycle"])
                .groupby(["state", "cycle"]).size().rename("n_districts_signal_a"))
    b_counts = (b_df.groupby(["state", "cycle"]).size().rename("n_districts_signal_b"))
    summary = pd.concat([a_counts, b_counts], axis=1).fillna(0).astype(int).reset_index()
    summary["total"] = summary["n_districts_signal_a"] + summary["n_districts_signal_b"]
    return summary.sort_values(["cycle", "total"], ascending=[True, False])


if __name__ == "__main__":
    OUT_PATH.mkdir(parents=True, exist_ok=True)

    ratings = load_ratings()
    signal_a = find_signal_a(ratings)
    signal_b = find_signal_b(ratings)
    summary = build_state_cycle_summary(signal_a, signal_b)

    signal_a.to_csv(OUT_PATH / "race_stability_signal_a.csv", index=False)
    signal_b.to_csv(OUT_PATH / "race_stability_signal_b.csv", index=False)
    summary.to_csv(OUT_PATH / "race_stability_state_cycle_summary.csv", index=False)

    print(f"Signal A (incumbent-identity discontinuity): {len(signal_a)} transitions flagged")
    print(f"Signal B (structural break in rating level): {len(signal_b)} races flagged")
    print(f"Distinct (state, cycle) events implicated: {len(summary)}")
