import pandas as pd
import numpy as np
import ast
import math
from utils import *

def process_contribution(contribution, candidates):
    """
    Process committee contribution data and match with candidates data.
    """
    # Merge contribution and candidates data
    contribution = pd.merge(contribution, candidates,
                            how = "left", on = "CAND_ID")
    
    
    # Group by committee-candidate pairs
    aggregate_dict = {col: 'sum' if col == "TRANSACTION_AMT" else "first"
                      for col in contribution.columns if col not in ["CMTE_ID", "CAND_ID"]}
    
    contribution = contribution.groupby(["CMTE_ID", "CAND_ID"], as_index=False).agg(aggregate_dict)

    # Filter out refunds and recode Minnesota Democratic–Farmer–Labor Party (DFL) to Democrats
    contribution = contribution.loc[contribution["TRANSACTION_AMT"] > 0,]

    contribution["CAND_PTY_AFFILIATION"] = contribution["CAND_PTY_AFFILIATION"].replace("DFL", "DEM")

    # Get partisan scores
    partisan = contribution.groupby(["CMTE_ID", "CAND_PTY_AFFILIATION", "CAND_OFFICE"],
                                    as_index=False)["TRANSACTION_AMT"].agg(count="count", total="sum")
    partisan = partisan[partisan["CAND_PTY_AFFILIATION"].isin(["DEM", "REP"])]

    hedge_party = partisan.groupby(["CMTE_ID", "CAND_PTY_AFFILIATION"])[["count", "total"]].sum().unstack(fill_value=0)
    hedge_chamber = partisan.groupby(["CMTE_ID", "CAND_OFFICE", "CAND_PTY_AFFILIATION"])[["count", "total"]].sum().unstack(["CAND_OFFICE", "CAND_PTY_AFFILIATION"], fill_value=0)
    hedge_party.columns = [f'{val}_{col}' for col, val in hedge_party.columns]
    hedge_party = hedge_party.reset_index()
    hedge_chamber.columns = [f'{val1}_{val2}_{col}' for col, val1, val2 in hedge_chamber.columns]
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

    hedge = pd.merge(hedge_party, hedge_chamber,
                     how = "left", on = "CMTE_ID")
    
    hedge = hedge[["CMTE_ID", "hedge_count", "hedge_amount",
                   "house_hedge_count", "house_hedge_amount",
                   "senate_hedge_count", "senate_hedge_amount",
                   "balance_count", "balance_amount",
                   "house_balance_count", "house_balance_amount",
                   "senate_balance_count", "senate_balance_amount"]]
    
    contribution_sum = contribution.groupby("CMTE_ID", as_index=False)["TRANSACTION_AMT"].agg("sum")
    contribution_sum.columns = ["CMTE_ID", "contribute_sum"]
    diverse = contribution.dropna(subset="CAND_OFFICE_ST").groupby("CMTE_ID", as_index=False)[["CAND_OFFICE_ST", "CAND_NAME"]].agg(count_unique)
    diverse.columns = ["CMTE_ID", "n_states", "n_cands"]

    hedge = pd.merge(hedge, contribution_sum, how = "left", on = "CMTE_ID")
    hedge = pd.merge(hedge, diverse, how = "left", on = "CMTE_ID")

    return hedge

def get_hedge(year,
              cutoff = 1):
    candidates = pd.read_parquet(f"../data/candidates/candidate_master_{year}.parquet")
    contribution = pd.read_csv(f"../data/contributions/committees/corp_candidate_{year}.csv", low_memory=False)

    candidates = exclude_territory(candidates, "CAND_OFFICE_ST")
    contribution = exclude_territory(contribution, "STATE")

    # Keep only direct contributions
    contribution = contribution.loc[(contribution["TRANSACTION_TP"] == "24K"), ["CMTE_ID", "TRANSACTION_AMT", "CAND_ID", "YEAR", "MONTH", "DAY"]].reset_index(drop=True)

    candidates = candidates[["CAND_ID", "CAND_NAME", "CAND_PTY_AFFILIATION", "CAND_OFFICE_ST", "CAND_OFFICE", "CAND_OFFICE_DISTRICT", "CAND_ICI"]]

    # Election period and non-election period
    election_contribution = contribution.loc[
        (contribution["YEAR"] == year) & (contribution["MONTH"].between(cutoff, 10)),
    ].reset_index(drop=True)

    nonelection_contribution = contribution.loc[
        (contribution["YEAR"] == year - 1) | (contribution["MONTH"] < cutoff),
    ].reset_index(drop=True)

    hedge = process_contribution(contribution, candidates)
    election_hedge = process_contribution(election_contribution, candidates)
    nonelection_hedge = process_contribution(nonelection_contribution, candidates)

    hedge["YEAR"] = year
    election_hedge["YEAR"] = year
    nonelection_hedge["YEAR"] = year

    return hedge, election_hedge, nonelection_hedge




