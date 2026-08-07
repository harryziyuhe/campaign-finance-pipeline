import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import ast
from utils import *

def prefix_priority(val):
    if isinstance(val, str):
        if val.startswith("S"):
            return 0
        elif val.startswith("H"):
            return 1
    return 2

def get_dummy_matrix(df, column1, column2):
    return pd.crosstab(df[column1], df[column2]).gt(0).astype(int)

def count_shared_pacs(matrix):
    return (matrix.sum(axis=1) > 1).sum()

def safe_literal_eval(val):
    if pd.isna(val):
        return None
    try:
        return ast.literal_eval(val)
    except (ValueError, SyntaxError):
        return None
    
def get_district(id):
    return id.strip()[4:6]

def get_office(id):
    return id.strip()[0]

def hii(x):
    x = np.asarray(x)
    if x.sum() == 0:
        return None
    p = x / x.sum()
    return np.sum(p ** 2)

def seat_status(x):
    if ("I" not in x.values):
        return "O"
    if ("O" in x.values) & ("C" in x.values):
        return "UK"
    elif "O" in x.values:
        return "O"
    else:
        return "R"

def get_retired_incumbents(group):
    if {"O", "I"}.issubset(set(group["CAND_ICI"])):
        return group[group["CAND_ICI"] == "I"].index
    return pd.Index([])

def get_cpacs():
    cpac = pd.read_csv("../data/cpac/corporate_pacs_2004_2024.csv")
    cpac_id = cpac["CMTE_ID"].tolist()
    return cpac_id

def get_candidates(year):
    candidates = pd.read_parquet(f"../data/candidates/candidate_master_{year}.parquet")
    candidates = exclude_territory(candidates, "CAND_OFFICE_ST")
    return candidates

def race_contributions(year,
                       cutoff = 1):
    contribution = pd.read_csv(f"../data/contributions/committees/corp_candidate_{year}.csv")
    contribution = exclude_territory(contribution, "STATE")
    corporate_pac = get_cpacs()
    cpac_contribution = contribution[contribution["CMTE_ID"].isin(corporate_pac)].reset_index(drop=True)
    cpac_contribution = cpac_contribution[cpac_contribution["TRANSACTION_AMT"] > 0]
    cpac_contribution = cpac_contribution[(cpac_contribution["YEAR"] == year) & 
                                          (cpac_contribution["MONTH"].between(cutoff, 10))]
    cpac_contribution = cpac_contribution[~cpac_contribution["CAND_ID"].isna()]
    cpac_contribution["CAND_OFFICE"] = cpac_contribution["CAND_ID"].apply(get_office)
    return cpac_contribution

def house_races(contribution, candidates, hedge):
    contribution = contribution[contribution["CAND_OFFICE"] == "H"].reset_index(drop=True)
    funded = contribution.copy()
    funded = funded.groupby("CAND_ID", as_index=False).agg({"TRANSACTION_AMT": "sum",
                                                                        "SUB_ID": "count",
                                                                        "CMTE_ID": count_unique})
    candidates = candidates[(candidates["CAND_OFFICE"] == "H")].copy()
    candidates["CAND_OFFICE_DISTRICT"] = candidates["CAND_OFFICE_DISTRICT"].fillna(candidates["CAND_ID"].apply(get_district)).astype(int)
    candidates = candidates.sort_values(by=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"]).dropna(subset="CAND_PCC").reset_index(drop=True)

    funded = pd.merge(candidates.drop(columns=["CAND_PCC", "CAND_ST1", "CAND_ST2", "CAND_CITY", "CAND_ST", "CAND_ZIP"],),
                            funded,
                            how = "right", on = "CAND_ID")
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
        pd
        .merge(candidates[["CAND_ID", "CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"]],
               contribution,
               how = "outer", on = "CAND_ID")
        .dropna(subset="CMTE_ID")
        .groupby(["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"], as_index=False)[["CMTE_ID"]]
        .agg(count_unique)
    )
    contribution_unique = contribution_unique.rename(columns={"CMTE_ID": "unique_total"})
    candidate_contribution = (
        candidate_contribution
        .groupby("CAND_ID", as_index=False)
        .agg({"TRANSACTION_AMT": "sum",
              "SUB_ID": "count",
              "CMTE_ID": count_unique})
    )
    candidate_contribution = pd.merge(candidates.drop(columns=["CAND_PCC", "CAND_ST1", "CAND_ST2", "CAND_CITY", "CAND_ST", "CAND_ZIP"],),
                                  candidate_contribution,
                                  how="outer", on="CAND_ID")
    candidate_contribution[["TRANSACTION_AMT", "SUB_ID", "CMTE_ID"]] = candidate_contribution[["TRANSACTION_AMT", "SUB_ID", "CMTE_ID"]].fillna(0)
    candidate_contribution = candidate_contribution.rename(columns = {
        "TRANSACTION_AMT": "amount",
        "SUB_ID": "count",
        "CMTE_ID": "unique"
    })
    candidate_contribution = candidate_contribution.sort_values(by = ["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"]).reset_index(drop=True)

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

    contribution_stats = pd.merge(df_hii, df_sum,
                                        how="left", on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"],
                                        suffixes=("_hii", "_sum")).merge(contribution_unique,
                                                                         how="left", on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])

    contribution_seats = pd.merge(candidate_contribution, seats,
                                        how="left", on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
    contribution_seats["CAND_TYPE"] = contribution_seats["SEAT_TYPE"].apply(lambda x: x if pd.notna(x) and x == "O" else None)
    contribution_seats["CAND_TYPE"] = contribution_seats["CAND_TYPE"].fillna(contribution_seats["CAND_ICI"])

    top_receipt = (
        contribution_seats
        .sort_values("amount", ascending=False)
        .groupby(["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"], as_index=False)
        .agg({"CAND_TYPE": "first"})
        .rename(columns={"CAND_TYPE":"TOP_CAND"})
    )

    contribution_stats = (
        contribution_stats
        .merge(seats, on = ["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
        .merge(top_receipt, on = ["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
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
        pd
        .merge(df_party_hii, df_party_sum,
               how="left", on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"],
               suffixes = ("_hii", "_sum"))
        .merge(seats, on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
        .merge(top_receipt, on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
    )

    party_compete = contribution_party_stats[contribution_party_stats["amount_hii"] < 1]
    party_compete = pd.merge(party_compete[["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT", "SEAT_TYPE", "TOP_CAND"]],
                             contribution_party,
                             how="left", on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
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

    races = pac_party_matrix.keys()
    pac_race = pd.DataFrame()
    for race in races:
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
        if len(pac_race) == 0:
            pac_race = pac_race_stats
        else:
            pac_race = pd.concat([pac_race, pac_race_stats])
    pac_race = pac_race.fillna(0).reset_index(drop=True)

    pac_race[["DEM", "REP", "C", "I"]] = pac_race[["DEM", "REP", "C", "I"]].map(
        lambda x: 1 if pd.notna(x) and float(x) > 0 else 0
    )
    pac_race["DISTRICT"] = pac_race["DISTRICT"].astype(float).astype(int)
    pac_race["MULTI_PARTY"] = (pac_race["DEM"] + pac_race["REP"] > 1).astype(int)
    pac_race["IC"] = (pac_race["C"] + pac_race["I"] > 1).astype(int)

    pac_race = pac_race.merge(contribution_party_stats, how="left",
                              left_on=["STATE", "DISTRICT"], right_on=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"])
    pac_race.drop(columns=["CAND_OFFICE_ST", "CAND_OFFICE_DISTRICT"], inplace=True)

    pac_race_firm = (
        pac_race
        .merge(hedge, how="left", on="CMTE_ID")
    )
    pac_race_firm["race_id"] = pac_race_firm["STATE"].astype(str) + "-" + pac_race_firm["DISTRICT"].astype(str)

    return contribution_stats, contribution_party_stats, pac_race_firm



