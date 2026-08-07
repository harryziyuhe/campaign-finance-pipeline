"""
Builds a per-state, per-House-election-cycle "floor date" table: the date the
congressional map actually in effect on that cycle's Election Day became
effective. Any Inside Elections rating snapshot for a race before its state's
floor date for that cycle describes a different map than the one the
eventual candidate ran under, and should not be used for date-matched
contribution-to-competitiveness merges.

Source: All About Redistricting (Loyola Law School)'s "full data about all
cycles" export, which tracks every enacted/court-drawn congressional plan per
state with Start Date / End Date / Plan Status -- including mid-decade
revisions (e.g. PA's Jan 2018 map replacing the 2011 map; NY's 2022 chain of
a legislature map struck down, a court map struck down, then a
special-master/commission map). This single source subsumes what would
otherwise be two separate problems (the ordinary decennial map transition,
and rarer mid-decade court-ordered replacements): for every state and cycle,
find whichever enacted plan's [Start Date, End Date] window contains that
cycle's Election Day, and use its Start Date as the floor.

Download the source CSV before running this (URL changes with each AAR
export refresh):
    https://redistricting.lls.edu/national-overview/
    -> "Maps for Download" / full-cycle CSV export

Input:  data/external/redistricting/aar_states_and_cycles.csv (place the
        downloaded AAR export here)
Output: data/processed/electionratings/redistricting_floor_dates.csv
"""
import os
from pathlib import Path

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
AAR_PATH = DATA_ROOT / "data" / "external" / "redistricting" / "aar_states_and_cycles.csv"
OUT_PATH = DATA_ROOT / "data" / "processed" / "electionratings" / "redistricting_floor_dates.csv"

# House election cycles covered by the current study window, plus 2010 (needs
# the prior, 2000-cycle map) and a couple of years of padding on each end.
CYCLES = [2010, 2012, 2014, 2016, 2018, 2020, 2022, 2024]


def election_day(cycle):
    """US general Election Day: the Tuesday after the first Monday in November."""
    nov1 = pd.Timestamp(year=cycle, month=11, day=1)
    days_to_monday = (0 - nov1.weekday()) % 7
    first_monday = nov1 + pd.Timedelta(days=days_to_monday)
    return first_monday + pd.Timedelta(days=1)


def load_congress_plans():
    df = pd.read_csv(AAR_PATH, parse_dates=["Start Date", "End Date"])
    cong = df[df["Level"] == "Congress"].copy()
    # include the prior (2000-cycle) map too: the 2010 House election ran
    # under it, since 2010-cycle maps mostly weren't enacted until 2011-2012
    cong = cong[cong["Cycle Year"].isin([2000, 2010, 2020])]
    return cong.dropna(subset=["Start Date"])


def build_floor_table(cong):
    rows = []
    for state, g in cong.groupby("State"):
        g = g.sort_values("Start Date")
        for cycle in CYCLES:
            eday = election_day(cycle)
            # the plan whose window covers this cycle's Election Day
            covering = g[(g["Start Date"] <= eday) & ((g["End Date"].isna()) | (g["End Date"] > eday))]
            if covering.empty:
                # fall back to the most recent plan that had already started
                covering = g[g["Start Date"] <= eday].tail(1)
            if covering.empty:
                continue
            plan = covering.iloc[-1]
            rows.append({
                "state": state,
                "cycle": cycle,
                "floor_date": plan["Start Date"].date(),
                "plan_end_date": plan["End Date"].date() if pd.notna(plan["End Date"]) else None,
                "plan_status": plan["Plan Status"],
                "drawn_by": plan["Drawn by"],
                "party_drawing": plan["Party drawing"],
                "court_action": plan["Court Action"],
            })
    return pd.DataFrame(rows)


if __name__ == "__main__":
    cong = load_congress_plans()
    floor_table = build_floor_table(cong)
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    floor_table.to_csv(OUT_PATH, index=False)

    print(f"states covered: {floor_table['state'].nunique()}")
    print(f"state-cycle rows: {len(floor_table)}")
    # within a single decade's cycles (2012-2020, all sharing one initial
    # post-census map), >1 distinct floor date means a real mid-decade
    # revision landed before one of those elections -- NOT just the ordinary
    # decennial transition (which trivially changes the floor at 2022/2024)
    within_2010s = floor_table[floor_table["cycle"].isin([2012, 2014, 2016, 2018, 2020])]
    changed = within_2010s.groupby("state")["floor_date"].nunique()
    print("states with a genuine mid-decade (2012-2020) map revision:")
    print(changed[changed > 1])
