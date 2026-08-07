"""
Builds contribution-date-matched Inside Elections rating measures, replacing
the cycle-mean construction currently in HouseData.py's process_elections().
See docs/redistricting-timing-fix-log.md for the full design rationale.

Note: these are RAW ratings (positive = Democrat-favored, negative =
Republican-favored), matching the scale of house_ratings.csv's own "rating"
column -- NOT yet the candidate-specific "favorability" used downstream
(HouseCandData.R computes favorability = rating * democrat, where democrat
is +1/-1 for the candidate's own party). That multiplication happens later
in the merge step, same as the existing pipeline; these outputs are named
rating_* rather than favorability_* to keep that distinction visible.

For every corporate PAC contribution to a House candidate, matches the
Inside Elections rating as of the date the money actually moved (nearest
snapshot at or before that date -- never later). Contributions made before
a race's redistricting floor date (data/processed/electionratings/
redistricting_floor_dates.csv) are matched against the OLD district's rating
history instead of the new one, using the race-level old/new district
crosswalk (race_old_district_crosswalk.csv) -- this applies uniformly to
every floor-date case (both the 2012/2022 decennial transitions and the
FL/NC/PA/VA mid-decade revisions), not just the two redistricting-year
cycles. Contributions with no valid old-district match (open seats from
retirement, brand-new seats from apportionment) are flagged rather than
guessed at.

Produces three constructions:
  - rating_entry: rating at a dyad's first contribution in the cycle
    (extensive margin / entry-decision framing).
  - rating_election_day: rating nearest (at or before) that cycle's
    Election Day, computed once per candidate-cycle regardless of
    contribution activity -- feeds the election-day logit variant for
    everyone, and is the non-contributor fallback for the entry variant.
  - rating_weighted: contribution-amount-weighted average of the
    date-matched rating across all of a dyad's events in the cycle
    (intensive margin / Tobit).

Inputs:
  data/processed/fec/firm_pac_to_principal_committee_contributions.parquet
  data/raw/fec_api/candidates/candidate_history_H.csv
  data/raw/electionratings/IE/house_ratings.csv
  data/processed/electionratings/redistricting_floor_dates.csv
  data/processed/electionratings/race_old_district_crosswalk.csv

Outputs:
  data/processed/house/contribution_rating_dyad.parquet
    (cmte_id, candidate_id, cycle, rating_entry, rating_weighted,
     n_contribs, total_amount) -- main (full-cycle) sample
  data/processed/house/contribution_rating_dyad_election_year.parquet
    same columns, but only from contributions made in the election year
    itself before Election Day (year % 2 == 0 & month < 11), matching
    HouseData.py's aggregate_candidate_contribution(election_year=True)
    filter -- feeds the "_election_year" pre-election robustness sample.
  data/processed/house/race_rating_election_day.parquet
    (candidate_id, cycle, rating_election_day) -- shared by both samples,
    since Election Day and the race's district don't depend on which
    contributions happened to be made.
"""
import os
import re
from pathlib import Path

import numpy as np
import pandas as pd

SCRIPT_ROOT = Path(__file__).resolve().parents[2]


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
FEC_PROCESSED_PATH = DATA_ROOT / "data" / "processed" / "fec"
FEC_API_PATH = DATA_ROOT / "data" / "raw" / "fec_api"
IE_RATINGS_PATH = DATA_ROOT / "data" / "raw" / "electionratings" / "IE" / "house_ratings.csv"
ELECTIONRATINGS_PROCESSED = DATA_ROOT / "data" / "processed" / "electionratings"
HOUSE_PROCESSED_PATH = DATA_ROOT / "data" / "processed" / "house"

STUDY_CYCLES = range(2010, 2023, 2)  # 2010..2022 inclusive, matches the paper's stated window


def election_day(cycle):
    nov1 = pd.Timestamp(year=cycle, month=11, day=1)
    days_to_monday = (0 - nov1.weekday()) % 7
    return nov1 + pd.Timedelta(days=days_to_monday) + pd.Timedelta(days=1)


def normalize_district(x):
    """candidate_history_H.csv districts arrive as messy strings (' 3', '0.0',
    '01', '10.0', ...). Normalize to a plain int matching house_ratings.csv's
    (already-normalized) district format. District 0 means at-large -> 1."""
    if pd.isna(x):
        return None
    s = str(x).strip()
    if s == "":
        return None
    try:
        n = int(float(s))
    except ValueError:
        return None
    return 1 if n == 0 else n


def load_ratings():
    r = pd.read_csv(IE_RATINGS_PATH, index_col=0, low_memory=False)
    r["date"] = pd.to_datetime(r["date"])
    r["district"] = r["district"].astype(int)
    return r[["date", "state", "district", "rating"]].dropna(subset=["rating"]).sort_values(
        ["state", "district", "date"]
    )


def load_candidate_districts():
    c = pd.read_csv(FEC_API_PATH / "candidates" / "candidate_history_H.csv", dtype={"address_zip": str})
    c["cycle"] = pd.to_numeric(c["candidate_election_year"], errors="coerce")
    c["district"] = c["district"].apply(normalize_district)
    c = c.dropna(subset=["cycle", "district", "state"])
    c["cycle"] = c["cycle"].astype(int)
    c = c[c["cycle"].isin(STUDY_CYCLES)]
    return c[["candidate_id", "cycle", "state", "district"]].drop_duplicates(["candidate_id", "cycle"])


def load_floor_dates():
    f = pd.read_csv(ELECTIONRATINGS_PROCESSED / "redistricting_floor_dates.csv", parse_dates=["floor_date"])
    return f[["state", "cycle", "floor_date"]]


def load_old_district_crosswalk():
    return pd.read_csv(ELECTIONRATINGS_PROCESSED / "race_old_district_crosswalk.csv")


def resolve_effective_district(cand_districts, floor_dates, old_xwalk):
    """For each (candidate_id, cycle): state, new district, floor date (if any),
    and old district (if a valid crosswalk match exists). Contributions before
    the floor date use old_district; contributions on/after it use district."""
    m = cand_districts.merge(floor_dates, on=["state", "cycle"], how="left")
    m = m.merge(
        old_xwalk.rename(columns={"new_district": "district"}),
        on=["state", "district", "cycle"],
        how="left",
    )
    return m[["candidate_id", "cycle", "state", "district", "floor_date", "old_district"]]


def load_contributions(election_year_only=False):
    c = pd.read_parquet(
        FEC_PROCESSED_PATH / "firm_pac_to_principal_committee_contributions.parquet",
        columns=["cmte_id", "cand_id", "amount", "year", "month", "day", "cycle"],
    )
    c = c[(c["cand_id"].str.startswith("H", na=False)) & (c["amount"] > 0) & (c["cycle"].isin(STUDY_CYCLES))]
    if election_year_only:
        # matches HouseData.py's aggregate_candidate_contribution(election_year=True):
        # only contributions made in the election year itself, before November.
        c = c[(c["year"] % 2 == 0) & (c["month"] < 11)]
    c["contrib_date"] = pd.to_datetime(dict(year=c["year"], month=c["month"], day=c["day"]), errors="coerce")
    return c.dropna(subset=["contrib_date"]).rename(columns={"cand_id": "candidate_id"})


def match_ratings_asof(targets, ratings, target_date_col, state_col, district_col):
    """Nearest rating at or before target_date_col, grouped by (state, district).
    Both frames must be sorted by their date column for merge_asof."""
    targets = targets.sort_values(target_date_col).reset_index(drop=True)
    targets[district_col] = targets[district_col].astype(int)
    ratings_sorted = ratings.sort_values("date").reset_index(drop=True)
    ratings_sorted["district"] = ratings_sorted["district"].astype(int)
    matched = pd.merge_asof(
        targets,
        ratings_sorted.rename(columns={"date": target_date_col, "rating": "matched_rating"}),
        on=target_date_col,
        left_by=[state_col, district_col],
        right_by=["state", "district"],
        direction="backward",
    )
    return matched


def build_contribution_lookup_keys(contribs, resolved):
    m = contribs.merge(resolved, on=["candidate_id", "cycle"], how="inner")
    is_pre_floor = m["floor_date"].notna() & (m["contrib_date"] < m["floor_date"])
    m["lookup_district"] = np.where(is_pre_floor, m["old_district"], m["district"])
    m["unmatched"] = is_pre_floor & m["old_district"].isna()
    return m


def build_dyad_ratings(ratings, resolved, election_year_only=False):
    """Entry + amount-weighted dyad-level ratings. Set election_year_only=True
    to restrict to the pre-election-year sample's contribution window."""
    contribs = load_contributions(election_year_only=election_year_only)
    keyed = build_contribution_lookup_keys(contribs, resolved)
    n_unmatched = keyed["unmatched"].sum()
    print(f"contributions with no valid old-district match (excluded): {n_unmatched} of {len(keyed)}")
    keyed = keyed[~keyed["unmatched"]].copy()
    keyed["lookup_district"] = keyed["lookup_district"].astype(int)

    matched = match_ratings_asof(
        keyed.rename(columns={"lookup_district": "district_key"}),
        ratings,
        target_date_col="contrib_date",
        state_col="state",
        district_col="district_key",
    )
    n_no_snapshot = matched["matched_rating"].isna().sum()
    print(f"contributions with no snapshot at/before their own date: {n_no_snapshot} of {len(matched)}")
    matched = matched.dropna(subset=["matched_rating"])

    matched = matched.sort_values("contrib_date")
    dyad = matched.groupby(["cmte_id", "candidate_id", "cycle"])
    entry = dyad["matched_rating"].first().rename("rating_entry")
    weighted = dyad.apply(
        lambda g: np.average(g["matched_rating"], weights=g["amount"]), include_groups=False
    ).rename("rating_weighted")
    counts = dyad.agg(n_contribs=("amount", "count"), total_amount=("amount", "sum"))
    return pd.concat([entry, weighted, counts], axis=1).reset_index()


def build_race_election_day_ratings(ratings, resolved):
    """Rating nearest (at/before) Election Day, every candidate-cycle --
    shared by both the main and election-year samples (doesn't depend on
    which contributions happened to be made)."""
    race_targets = resolved.copy()
    race_targets["election_day"] = race_targets["cycle"].apply(election_day)
    race_matched = match_ratings_asof(
        race_targets.rename(columns={"district": "district_key"}),
        ratings,
        target_date_col="election_day",
        state_col="state",
        district_col="district_key",
    )
    return race_matched[["candidate_id", "cycle", "matched_rating"]].rename(
        columns={"matched_rating": "rating_election_day"}
    )


def main():
    ratings = load_ratings()
    cand_districts = load_candidate_districts()
    floor_dates = load_floor_dates()
    old_xwalk = load_old_district_crosswalk()
    resolved = resolve_effective_district(cand_districts, floor_dates, old_xwalk)

    print("=== main (full-cycle) sample ===")
    dyad_out = build_dyad_ratings(ratings, resolved, election_year_only=False)
    dyad_out.to_parquet(HOUSE_PROCESSED_PATH / "contribution_rating_dyad.parquet", index=False)
    print(f"dyad-level rows written: {len(dyad_out)}")

    print("\n=== pre-election-year sample ===")
    dyad_out_ey = build_dyad_ratings(ratings, resolved, election_year_only=True)
    dyad_out_ey.to_parquet(HOUSE_PROCESSED_PATH / "contribution_rating_dyad_election_year.parquet", index=False)
    print(f"dyad-level rows written: {len(dyad_out_ey)}")

    print("\n=== race-level Election-Day ratings (shared by both samples) ===")
    race_out = build_race_election_day_ratings(ratings, resolved)
    race_out.to_parquet(HOUSE_PROCESSED_PATH / "race_rating_election_day.parquet", index=False)
    print(f"race-level rows written: {len(race_out)}")
    print(f"race-level rows with no Election-Day-eligible snapshot: {race_out['rating_election_day'].isna().sum()}")


if __name__ == "__main__":
    main()
