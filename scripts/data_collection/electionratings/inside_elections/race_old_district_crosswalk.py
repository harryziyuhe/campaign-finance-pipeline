"""
Builds a race-level (not candidate-level) crosswalk from each new congressional
district to whichever old district it corresponds to, for every state-cycle
where the map changed (per redistricting_floor_dates.csv).

Rationale: money follows the race, not an individual candidate's biography.
A challenger contesting a newly-drawn district doesn't need their own
independent old-district identity -- whatever old district the race itself
corresponds to (via incumbent continuity) applies to every candidate in that
race, since firms deciding whether to back the incumbent or the challenger
are reacting to the same underlying electoral contest.

Method: purely empirical, no new external data. For a new district's
earliest post-floor-date snapshot, take the rated incumbent's surname, then
search the same state's districts *before* the floor date for whichever one
was represented by that same surname. If found, every candidate in the new
district's race for that cycle can be safely matched to Inside Elections
ratings for the corresponding old district prior to the floor date.

This only covers seats with a continuing incumbent across the map change.
Open seats (retirement) and brand-new seats (apportionment gains) have no
name to chain on and are left unmatched -- those pre-floor contributions
have no valid old-map proxy and should be excluded/flagged downstream rather
than guessed at.

Inputs:  data/raw/electionratings/IE/house_ratings.csv
         data/processed/electionratings/redistricting_floor_dates.csv
Output:  data/processed/electionratings/race_old_district_crosswalk.csv
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
FLOOR_DATES_PATH = DATA_ROOT / "data" / "processed" / "electionratings" / "redistricting_floor_dates.csv"
OUT_PATH = DATA_ROOT / "data" / "processed" / "electionratings" / "race_old_district_crosswalk.csv"


def norm_name(x):
    if pd.isna(x):
        return None
    return re.sub(r"[^A-Za-z]", "", str(x)).lower()


def load_ratings():
    r = pd.read_csv(IE_RATINGS_PATH, index_col=0, low_memory=False)
    r["date"] = pd.to_datetime(r["date"])
    cal_year = r["date"].dt.year
    r["cycle"] = np.where(cal_year % 2 == 0, cal_year, cal_year + 1)
    r["incumbent_norm"] = r["incumbent"].apply(norm_name)
    return r


def load_floor_dates():
    f = pd.read_csv(FLOOR_DATES_PATH, parse_dates=["floor_date"])
    return f[["state", "cycle", "floor_date"]]


def build_crosswalk(ratings, floor_dates):
    rows = []
    for _, fd in floor_dates.iterrows():
        state, cycle, floor_date = fd["state"], fd["cycle"], fd["floor_date"]

        # earliest snapshot on/after the floor date, per new district, in this state+cycle
        post = ratings[(ratings["state"] == state) & (ratings["cycle"] == cycle)
                       & (ratings["date"] >= floor_date)]
        if post.empty:
            continue
        post_first = post.sort_values("date").groupby("district").first().reset_index()

        # all snapshots before the floor date, in this state (any district, any cycle
        # up to the one immediately preceding this floor date) -- the "old map" pool
        pre = ratings[(ratings["state"] == state) & (ratings["date"] < floor_date)]
        if pre.empty:
            for _, new_row in post_first.iterrows():
                rows.append({
                    "state": state, "new_district": new_row["district"], "cycle": cycle,
                    "old_district": None, "match_incumbent": new_row["incumbent"],
                    "reason": "no prior ratings available for this state",
                })
            continue
        # most recent old-map rating per old district, keyed by normalized incumbent name
        pre_last = pre.sort_values("date").groupby("district").last().reset_index()
        name_to_old_district = dict(zip(pre_last["incumbent_norm"], pre_last["district"]))

        for _, new_row in post_first.iterrows():
            name = new_row["incumbent_norm"]
            old_district = name_to_old_district.get(name) if name is not None else None
            rows.append({
                "state": state, "new_district": new_row["district"], "cycle": cycle,
                "old_district": old_district, "match_incumbent": new_row["incumbent"],
                "reason": "matched" if old_district is not None else "no continuing incumbent (open seat / new seat)",
            })
    return pd.DataFrame(rows)


if __name__ == "__main__":
    ratings = load_ratings()
    floor_dates = load_floor_dates()
    crosswalk = build_crosswalk(ratings, floor_dates)
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    crosswalk.to_csv(OUT_PATH, index=False)

    matched = crosswalk["old_district"].notna().sum()
    print(f"total new-district-cycle races considered: {len(crosswalk)}")
    print(f"matched to an old district via incumbent continuity: {matched} ({100*matched/len(crosswalk):.1f}%)")
    print(f"unmatched (open seat / new seat / no prior data): {len(crosswalk) - matched}")
