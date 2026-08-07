"""Corporate PAC partisan-hedging and balance index.

Extracted from the legacy scripts/FEC/get_hedging.py (driven by analysis.ipynb /
summary_stats.ipynb / analysis_2024.ipynb), which computed a DEM/REP hedging and
balance index per corporate PAC per cycle, chamber-split, across three timing
windows (full-cycle, election-period, non-election-period). That logic was
never migrated into the active data_collection/aggregate pipeline; calc_hedge/
calc_balance/count_unique/exclude_territory already exist in this directory's
utils.py, unused, until now.

For each cycle: reads FEC candidate metadata and corporate-PAC-to-candidate
contributions, computes per-committee hedge/balance scores over three windows,
and writes one CSV per cycle.
"""

import argparse
import os
from pathlib import Path

import pandas as pd

from utils import calc_hedge, calc_balance, count_unique, exclude_territory

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
CANDIDATE_MASTER_DIR = DATA_ROOT / "data" / "raw" / "fec_bulk" / "candidates"
FIRM_PAC_CONTRIBUTIONS_FILE = DATA_ROOT / "data" / "processed" / "fec" / "firm_pac_to_candidate_contributions.parquet"
OUTPUT_DIR = DATA_ROOT / "data" / "processed" / "fec" / "partisan_hedging_index"

# Renames the current pipeline's lowercase contribution schema back to the
# uppercase FEC bulk convention the ported process_contribution()/get_hedge()
# logic below was written against, so that logic stays byte-for-byte as it
# was in get_hedging.py.
CONTRIBUTION_RENAME = {
    "cmte_id": "CMTE_ID",
    "amount": "TRANSACTION_AMT",
    "cand_id": "CAND_ID",
    "year": "YEAR",
    "month": "MONTH",
    "day": "DAY",
    "transaction_type": "TRANSACTION_TP",
}


def process_contribution(contribution: pd.DataFrame, candidates: pd.DataFrame) -> pd.DataFrame:
    """Process committee contribution data and match with candidates data."""
    contribution = pd.merge(contribution, candidates, how="left", on="CAND_ID")

    # Group by committee-candidate pairs
    aggregate_dict = {
        col: "sum" if col == "TRANSACTION_AMT" else "first"
        for col in contribution.columns
        if col not in ["CMTE_ID", "CAND_ID"]
    }
    contribution = contribution.groupby(["CMTE_ID", "CAND_ID"], as_index=False).agg(aggregate_dict)

    # Filter out refunds and recode Minnesota Democratic-Farmer-Labor Party (DFL) to Democrats
    contribution = contribution.loc[contribution["TRANSACTION_AMT"] > 0, ]
    contribution["CAND_PTY_AFFILIATION"] = contribution["CAND_PTY_AFFILIATION"].replace("DFL", "DEM")

    # Get partisan scores
    partisan = contribution.groupby(
        ["CMTE_ID", "CAND_PTY_AFFILIATION", "CAND_OFFICE"], as_index=False
    )["TRANSACTION_AMT"].agg(count="count", total="sum")
    partisan = partisan[partisan["CAND_PTY_AFFILIATION"].isin(["DEM", "REP"])]

    hedge_party = partisan.groupby(["CMTE_ID", "CAND_PTY_AFFILIATION"])[["count", "total"]].sum().unstack(fill_value=0)
    hedge_chamber = (
        partisan.groupby(["CMTE_ID", "CAND_OFFICE", "CAND_PTY_AFFILIATION"])[["count", "total"]]
        .sum()
        .unstack(["CAND_OFFICE", "CAND_PTY_AFFILIATION"], fill_value=0)
    )
    hedge_party.columns = [f"{val}_{col}" for col, val in hedge_party.columns]
    hedge_party = hedge_party.reset_index()
    hedge_chamber.columns = [f"{val1}_{val2}_{col}" for col, val1, val2 in hedge_chamber.columns]
    hedge_chamber = hedge_chamber.reset_index()

    hedge_party["hedge_count"] = calc_hedge(hedge_party, "DEM_count", "REP_count")
    hedge_party["hedge_amount"] = calc_hedge(hedge_party, "DEM_total", "REP_total")
    hedge_chamber["house_hedge_count"] = calc_hedge(hedge_chamber, "H_DEM_count", "H_REP_count")
    hedge_chamber["house_hedge_amount"] = calc_hedge(hedge_chamber, "H_DEM_total", "H_REP_total")
    hedge_chamber["senate_hedge_count"] = calc_hedge(hedge_chamber, "S_DEM_count", "S_REP_count")
    hedge_chamber["senate_hedge_amount"] = calc_hedge(hedge_chamber, "S_DEM_total", "S_REP_total")

    hedge_party["balance_count"] = calc_balance(hedge_party, "DEM_count", "REP_count")
    hedge_party["balance_amount"] = calc_balance(hedge_party, "DEM_total", "REP_total")
    hedge_chamber["house_balance_count"] = calc_balance(hedge_chamber, "H_DEM_count", "H_REP_count")
    hedge_chamber["house_balance_amount"] = calc_balance(hedge_chamber, "H_DEM_total", "H_REP_total")
    hedge_chamber["senate_balance_count"] = calc_balance(hedge_chamber, "S_DEM_count", "S_REP_count")
    hedge_chamber["senate_balance_amount"] = calc_balance(hedge_chamber, "S_DEM_total", "S_REP_total")

    hedge = pd.merge(hedge_party, hedge_chamber, how="left", on="CMTE_ID")
    hedge = hedge[[
        "CMTE_ID", "hedge_count", "hedge_amount",
        "house_hedge_count", "house_hedge_amount",
        "senate_hedge_count", "senate_hedge_amount",
        "balance_count", "balance_amount",
        "house_balance_count", "house_balance_amount",
        "senate_balance_count", "senate_balance_amount",
    ]]

    contribution_sum = contribution.groupby("CMTE_ID", as_index=False)["TRANSACTION_AMT"].agg("sum")
    contribution_sum.columns = ["CMTE_ID", "contribute_sum"]
    diverse = (
        contribution.dropna(subset="CAND_OFFICE_ST")
        .groupby("CMTE_ID", as_index=False)[["CAND_OFFICE_ST", "CAND_NAME"]]
        .agg(count_unique)
    )
    diverse.columns = ["CMTE_ID", "n_states", "n_cands"]

    hedge = pd.merge(hedge, contribution_sum, how="left", on="CMTE_ID")
    hedge = pd.merge(hedge, diverse, how="left", on="CMTE_ID")
    return hedge


def load_candidates(cycle: int) -> pd.DataFrame:
    candidates = pd.read_parquet(CANDIDATE_MASTER_DIR / f"candidate_master_{cycle}.parquet")
    candidates = exclude_territory(candidates, "CAND_OFFICE_ST")
    return candidates[[
        "CAND_ID", "CAND_NAME", "CAND_PTY_AFFILIATION",
        "CAND_OFFICE_ST", "CAND_OFFICE", "CAND_OFFICE_DISTRICT", "CAND_ICI",
    ]]


def load_contributions(cycle: int) -> pd.DataFrame:
    contribution = pd.read_parquet(FIRM_PAC_CONTRIBUTIONS_FILE)
    contribution = contribution[contribution["cycle"] == cycle].rename(columns=CONTRIBUTION_RENAME)
    contribution = exclude_territory(contribution, "state")
    # Keep only direct contributions (FEC transaction type 24K)
    contribution = contribution.loc[
        contribution["TRANSACTION_TP"] == "24K",
        ["CMTE_ID", "TRANSACTION_AMT", "CAND_ID", "YEAR", "MONTH", "DAY"],
    ].reset_index(drop=True)
    return contribution


def get_hedge(cycle: int, cutoff: int = 1) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    candidates = load_candidates(cycle)
    contribution = load_contributions(cycle)

    # Election period and non-election period
    election_contribution = contribution.loc[
        (contribution["YEAR"] == cycle) & (contribution["MONTH"].between(cutoff, 10)),
    ].reset_index(drop=True)
    nonelection_contribution = contribution.loc[
        (contribution["YEAR"] == cycle - 1) | (contribution["MONTH"] < cutoff),
    ].reset_index(drop=True)

    hedge = process_contribution(contribution, candidates)
    election_hedge = process_contribution(election_contribution, candidates)
    nonelection_hedge = process_contribution(nonelection_contribution, candidates)

    hedge["YEAR"] = cycle
    election_hedge["YEAR"] = cycle
    nonelection_hedge["YEAR"] = cycle
    return hedge, election_hedge, nonelection_hedge


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compute the partisan hedging/balance index per corporate PAC.")
    parser.add_argument("--cycles", type=int, nargs="+", required=True, help="Even election-year cycles to process.")
    parser.add_argument("--cutoff", type=int, default=1, help="Month cutoff separating election vs. non-election period.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for cycle in args.cycles:
        hedge, election_hedge, nonelection_hedge = get_hedge(cycle, cutoff=args.cutoff)
        hedge.to_csv(OUTPUT_DIR / f"cpac_hedging_{cycle}.csv", index=False)
        election_hedge.to_csv(OUTPUT_DIR / f"cpac_hedging_{cycle}_election.csv", index=False)
        nonelection_hedge.to_csv(OUTPUT_DIR / f"cpac_hedging_{cycle}_nonelection.csv", index=False)
        print(f"cycle {cycle}: {len(hedge)} committees")


if __name__ == "__main__":
    main()
