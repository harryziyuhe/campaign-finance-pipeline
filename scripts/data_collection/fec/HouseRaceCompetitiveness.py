"""House race-level competitiveness panel (HII concentration, PAC x party/candidate
dummy matrices, seat-status/retired-incumbent detection).

Extracted from the legacy scripts/FEC/race.py (driven by analysis.ipynb /
candidates.ipynb / network.ipynb). This is a richer race-level competitiveness
construction than HouseData.py's get_race_data() (whose call is currently
commented out in that script's main()) -- it adds Herfindahl concentration on
amount/count/unique-donor shares, PAC x party and PAC x candidate dummy
matrices, and seat-status (open/incumbent-retained/challenger) classification.

Two adaptations from the original notebook-era version:
  - The contribution source (firm_pac_to_candidate_contributions.parquet) is
    already filtered to corporate PACs, so the original's separate
    corporate_pacs_2004_2024.csv membership filter is no longer needed.
  - The original counted transactions via a raw FEC "SUB_ID" column that
    doesn't exist in the current processed schema; a synthetic
    "n_transactions" = 1 column is summed per group instead, which is
    equivalent -- both just count contribution rows.
"""

import argparse
import os
from pathlib import Path

import numpy as np
import pandas as pd

from utils import count_unique, exclude_territory
from PartisanHedgingIndex import get_hedge, CANDIDATE_MASTER_DIR, FIRM_PAC_CONTRIBUTIONS_FILE

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
OUTPUT_DIR = DATA_ROOT / "data" / "processed" / "fec" / "house_race_competitiveness"

CONTRIBUTION_RENAME = {
    "cmte_id": "CMTE_ID",
    "amount": "TRANSACTION_AMT",
    "cand_id": "CAND_ID",
    "year": "YEAR",
    "month": "MONTH",
    "day": "DAY",
    "transaction_type": "TRANSACTION_TP",
}


def get_district(cand_id: str) -> str:
    return cand_id.strip()[4:6]


def get_office(cand_id: str) -> str:
    return cand_id.strip()[0]


def hii(x) -> float | None:
    x = np.asarray(x)
    if x.sum() == 0:
        return None
    p = x / x.sum()
    return np.sum(p ** 2)


def seat_status(x) -> str:
    if "I" not in x.values:
        return "O"
    if ("O" in x.values) & ("C" in x.values):
        return "UK"
    elif "O" in x.values:
        return "O"
    else:
        return "R"


def get_retired_incumbents(group: pd.DataFrame) -> pd.Index:
    if {"O", "I"}.issubset(set(group["CAND_ICI"])):
        return group[group["CAND_ICI"] == "I"].index
    return pd.Index([])


def get_dummy_matrix(df: pd.DataFrame, column1: str, column2: str) -> pd.DataFrame:
    return pd.crosstab(df[column1], df[column2]).gt(0).astype(int)


def get_candidates(cycle: int) -> pd.DataFrame:
    candidates = pd.read_parquet(CANDIDATE_MASTER_DIR / f"candidate_master_{cycle}.parquet")
    return exclude_territory(candidates, "CAND_OFFICE_ST")


def race_contributions(cycle: int, cutoff: int = 1) -> pd.DataFrame:
    contribution = pd.read_parquet(FIRM_PAC_CONTRIBUTIONS_FILE)
    contribution = contribution[contribution["cycle"] == cycle].rename(columns=CONTRIBUTION_RENAME)
    contribution = exclude_territory(contribution, "state")
    contribution = contribution[contribution["TRANSACTION_AMT"] > 0]
    contribution = contribution[
        (contribution["YEAR"] == cycle) & (contribution["MONTH"].between(cutoff, 10))
    ]
    contribution = contribution[~contribution["CAND_ID"].isna()]
    contribution["CAND_OFFICE"] = contribution["CAND_ID"].apply(get_office)
    # Synthetic per-transaction counter: the original notebook-era pipeline
    # counted transactions via a raw FEC "SUB_ID" column that doesn't exist in
    # the current processed schema; this is equivalent (both just count rows).
    contribution["n_transactions"] = 1
    return contribution


def house_races(contribution: pd.DataFrame, candidates: pd.DataFrame, hedge: pd.DataFrame):
    contribution = contribution[contribution["CAND_OFFICE"] == "H"].reset_index(drop=True)
    funded = contribution.copy()
    funded = funded.groupby("CAND_ID", as_index=False).agg({
        "TRANSACTION_AMT": "sum",
        "n_transactions": "sum",
        "CMTE_ID": count_unique,
    })
    candidates = candidates[(candidates["CAND_OFFICE"] == "H")].copy()
    candidates["CAND_OFFICE_DISTRICT"] = candidates["CAND_OFFICE_DISTRICT"].fillna(
        candidates["CAND_ID"].apply(get_district)
    ).astype(int)
    candidates = candidates.sort_values(by=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"]).dropna(subset="CAND_PCC").reset_index(drop=True)

    funded = pd.merge(
        candidates.drop(columns=["CAND_PCC", "CAND_ST1", "CAND_ST2", "CAND_CITY", "CAND_ST", "CAND_ZIP"]),
        funded,
        how="right", on="CAND_ID",
    )
    seats = (
        funded
        .groupby(["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"], as_index=False)["CAND_ICI"]
        .agg(seat_status)
        .rename(columns={"CAND_ICI": "SEAT_TYPE"})
    )

    retired_incumbents_idx = (
        funded
        .groupby(["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
        .apply(get_retired_incumbents)
        .explode()
        .dropna()
    )
    retired_incumbents = funded.loc[retired_incumbents_idx, ["CAND_ID", "CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"]]
    candidate_contribution = contribution[~contribution["CAND_ID"].isin(retired_incumbents["CAND_ID"])]

    contribution_unique = (
        pd.merge(
            candidates[["CAND_ID", "CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"]],
            contribution,
            how="outer", on="CAND_ID",
        )
        .dropna(subset="CMTE_ID")
        .groupby(["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"], as_index=False)[["CMTE_ID"]]
        .agg(count_unique)
    )
    contribution_unique = contribution_unique.rename(columns={"CMTE_ID": "unique_total"})
    candidate_contribution = (
        candidate_contribution
        .groupby("CAND_ID", as_index=False)
        .agg({"TRANSACTION_AMT": "sum", "n_transactions": "sum", "CMTE_ID": count_unique})
    )
    candidate_contribution = pd.merge(
        candidates.drop(columns=["CAND_PCC", "CAND_ST1", "CAND_ST2", "CAND_CITY", "CAND_ST", "CAND_ZIP"]),
        candidate_contribution,
        how="outer", on="CAND_ID",
    )
    candidate_contribution[["TRANSACTION_AMT", "n_transactions", "CMTE_ID"]] = candidate_contribution[
        ["TRANSACTION_AMT", "n_transactions", "CMTE_ID"]
    ].fillna(0)
    candidate_contribution = candidate_contribution.rename(columns={
        "TRANSACTION_AMT": "amount", "n_transactions": "count", "CMTE_ID": "unique",
    })
    candidate_contribution = candidate_contribution.sort_values(
        by=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"]
    ).reset_index(drop=True)

    df_hii = (
        candidate_contribution
        .groupby(["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"], as_index=False)[["amount", "count", "unique"]]
        .agg(hii)
    )
    df_sum = (
        candidate_contribution
        .groupby(["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"], as_index=False)[["amount", "count", "unique"]]
        .agg("sum")
    )
    contribution_stats = pd.merge(
        df_hii, df_sum, how="left", on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"], suffixes=("_hii", "_sum")
    ).merge(contribution_unique, how="left", on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])

    contribution_seats = pd.merge(candidate_contribution, seats, how="left", on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
    contribution_seats["CAND_TYPE"] = contribution_seats["SEAT_TYPE"].apply(lambda x: x if pd.notna(x) and x == "O" else None)
    contribution_seats["CAND_TYPE"] = contribution_seats["CAND_TYPE"].fillna(contribution_seats["CAND_ICI"])

    top_receipt = (
        contribution_seats
        .sort_values("amount", ascending=False)
        .groupby(["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"], as_index=False)
        .agg({"CAND_TYPE": "first"})
        .rename(columns={"CAND_TYPE": "TOP_CAND"})
    )

    contribution_stats = (
        contribution_stats
        .merge(seats, on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
        .merge(top_receipt, on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
    )

    contribution_party = (
        candidate_contribution
        .groupby(["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT", "CAND_PTY_AFFILIATION"], as_index=False)[["amount", "count"]]
        .agg("sum")
    )
    df_party_hii = (
        contribution_party
        .groupby(["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"], as_index=False)[["amount", "count"]]
        .agg(hii)
    )
    df_party_sum = (
        contribution_party
        .groupby(["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"], as_index=False)[["amount", "count"]]
        .agg("sum")
    )
    contribution_party_stats = (
        pd.merge(
            df_party_hii, df_party_sum, how="left", on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"], suffixes=("_hii", "_sum")
        )
        .merge(seats, on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
        .merge(top_receipt, on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
    )

    party_compete = contribution_party_stats[contribution_party_stats["amount_hii"] < 1]
    party_compete = pd.merge(
        party_compete[["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT", "SEAT_TYPE", "TOP_CAND"]],
        contribution_party,
        how="left", on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"],
    )
    party_compete = party_compete[party_compete["amount"] > 0]
    party_compete = (
        candidate_contribution
        .merge(party_compete[["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"]])
        .merge(contribution, on="CAND_ID")
    )

    pac_party_matrix = {
        f"{st}-{district}": get_dummy_matrix(group, "CMTE_ID", "CAND_PTY_AFFILIATION")
        for (st, district), group in party_compete.groupby(["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
    }
    pac_cand_matrix = {
        f"{st}-{district}": get_dummy_matrix(group, "CMTE_ID", "CAND_ID")
        for (st, district), group in party_compete.groupby(["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
    }

    pac_race = pd.DataFrame()
    for race in pac_party_matrix.keys():
        pac_party = pac_party_matrix[race].reset_index()
        pac_cand = pac_cand_matrix[race]
        cand_ids = pac_cand.columns
        pac_cand["C"] = 0
        pac_cand["I"] = 0
        for col in cand_ids:
            cand_ici = candidate_contribution.loc[candidate_contribution["CAND_ID"] == col, "CAND_ICI"].values
            if "I" in cand_ici:
                pac_cand["I"] = pac_cand["I"] + pac_cand[col]
            elif "C" in cand_ici:
                pac_cand["C"] = pac_cand["C"] + pac_cand[col]
        pac_cand = pac_cand.reset_index()
        pac_race_stats = pac_party.merge(pac_cand[["CMTE_ID", "C", "I"]], how="left", on=["CMTE_ID"])
        pac_race_stats["STATE"] = race.split("-")[0]
        pac_race_stats["DISTRICT"] = race.split("-")[1]
        pac_race = pac_race_stats if len(pac_race) == 0 else pd.concat([pac_race, pac_race_stats])
    pac_race = pac_race.fillna(0).reset_index(drop=True)

    pac_race[["DEM", "REP", "C", "I"]] = pac_race[["DEM", "REP", "C", "I"]].map(
        lambda x: 1 if pd.notna(x) and float(x) > 0 else 0
    )
    pac_race["DISTRICT"] = pac_race["DISTRICT"].astype(float).astype(int)
    pac_race["MULTI_PARTY"] = (pac_race["DEM"] + pac_race["REP"] > 1).astype(int)
    pac_race["IC"] = (pac_race["C"] + pac_race["I"] > 1).astype(int)

    pac_race = pac_race.merge(
        contribution_party_stats, how="left",
        left_on=["STATE", "DISTRICT"], right_on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"],
    )
    pac_race.drop(columns=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"], inplace=True)

    pac_race_firm = pac_race.merge(hedge, how="left", on="CMTE_ID")
    pac_race_firm["race_id"] = pac_race_firm["STATE"].astype(str) + "-" + pac_race_firm["DISTRICT"].astype(str)

    return contribution_stats, contribution_party_stats, pac_race_firm


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build House race-level competitiveness panels.")
    parser.add_argument("--cycles", type=int, nargs="+", required=True, help="Even election-year cycles to process.")
    parser.add_argument("--cutoff", type=int, default=1, help="Month cutoff separating election vs. non-election period.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for cycle in args.cycles:
        candidates = get_candidates(cycle)
        contribution = race_contributions(cycle, cutoff=args.cutoff)
        hedge, _, _ = get_hedge(cycle, cutoff=args.cutoff)
        contribution_stats, contribution_party_stats, pac_race_firm = house_races(contribution, candidates, hedge)

        contribution_stats.to_csv(OUTPUT_DIR / f"house_race_stats_{cycle}.csv", index=False)
        contribution_party_stats.to_csv(OUTPUT_DIR / f"house_race_party_stats_{cycle}.csv", index=False)
        pac_race_firm.to_csv(OUTPUT_DIR / f"house_pac_race_{cycle}.csv", index=False)
        print(f"cycle {cycle}: {len(contribution_stats)} races, {len(pac_race_firm)} pac-race rows")


if __name__ == "__main__":
    main()
