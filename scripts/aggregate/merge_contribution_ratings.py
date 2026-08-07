"""
Merges the contribution-date-matched ratings (scripts/aggregate/
contribution_favorability.py) into house_firm_cand(_election_year).parquet,
producing the input HouseCandData.R uses instead of the original cycle-mean
construction. Handles both the main (full-cycle) and "_election_year"
(pre-election robustness) samples.

Keeps the original "rating" column (renamed rating_cyclemean) alongside the
new date-matched ones for comparison. Does NOT apply the rating*democrat
transformation here -- that stays in HouseCandData.R, right after "democrat"
is constructed, same as the original pipeline's favorability = rating *
democrat, so the party filter already applied there covers these too.

For dyads with no contribution (contribute == 0), rating_entry and
rating_weighted are null (no contribution to anchor to); HouseCandData.R
falls back to rating_election_day for those, per the design decision that
non-contributors use the same universal Election-Day anchor across every
favorability variant.

Input (main sample):           house_firm_cand.parquet,
                                contribution_rating_dyad.parquet,
                                race_rating_election_day.parquet
Output (main sample):           house_firm_cand_datematch.parquet

Input (election-year sample):  house_firm_cand_election_year.parquet,
                                contribution_rating_dyad_election_year.parquet,
                                race_rating_election_day.parquet (shared)
Output (election-year sample): house_firm_cand_election_year_datematch.parquet
"""
import os
from pathlib import Path

import polars as pl

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
HOUSE_PROCESSED_PATH = DATA_ROOT / "data" / "processed" / "house"


def merge_one(cand_file, dyad_file, out_file):
    cand = pl.read_parquet(HOUSE_PROCESSED_PATH / cand_file)
    cand = cand.rename({"rating": "rating_cyclemean"})

    dyad = pl.read_parquet(HOUSE_PROCESSED_PATH / dyad_file)
    # "total_amount" collides with the existing column of the same name in
    # house_firm_cand.parquet (sum of ALL contributions vs. sum of only the
    # matched ones here) -- rename to keep both distinguishable.
    dyad = dyad.rename({"total_amount": "matched_contrib_dollars"})
    race = pl.read_parquet(HOUSE_PROCESSED_PATH / "race_rating_election_day.parquet")

    merged = (
        cand
        .join(dyad, on=["cmte_id", "candidate_id", "cycle"], how="left")
        .join(race, on=["candidate_id", "cycle"], how="left")
    )

    merged.write_parquet(HOUSE_PROCESSED_PATH / out_file)

    n = merged.shape[0]
    n_contribute = merged.filter(pl.col("contribute") == 1).shape[0]
    n_entry_present = merged.filter(pl.col("rating_entry").is_not_null()).shape[0]
    n_election_day_present = merged.filter(pl.col("rating_election_day").is_not_null()).shape[0]
    print(f"  total rows: {n}")
    print(f"  contribute==1 rows: {n_contribute}")
    print(f"  rows with rating_entry populated: {n_entry_present} (should be <= contribute==1 rows)")
    print(f"  rows with rating_election_day populated: {n_election_day_present} (should cover nearly all rows)")


def main():
    print("=== main (full-cycle) sample ===")
    merge_one("house_firm_cand.parquet", "contribution_rating_dyad.parquet", "house_firm_cand_datematch.parquet")

    print("\n=== pre-election-year sample ===")
    merge_one(
        "house_firm_cand_election_year.parquet",
        "contribution_rating_dyad_election_year.parquet",
        "house_firm_cand_election_year_datematch.parquet",
    )


if __name__ == "__main__":
    main()
