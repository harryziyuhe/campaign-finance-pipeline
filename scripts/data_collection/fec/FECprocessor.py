from re import M
from typing import Literal
import os
from pathlib import Path
import pandas as pd
import polars as pl
from tqdm import tqdm
from utils import add_cycle, senate_cycle_join, parse_last_name

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
FEC_BULK_PATH = str(DATA_ROOT / "data" / "raw" / "fec_bulk") + "/"
FEC_API_PATH = str(DATA_ROOT / "data" / "raw" / "fec_api") + "/"
FEC_PROCESSED_PATH = str(DATA_ROOT / "data" / "processed" / "fec") + "/"
LSEG_RAW_PATH = str(DATA_ROOT / "data" / "raw" / "lseg") + "/"
cand_contribution_vars = {
    "CMTE_ID": "cmte_id",
    "TRANSACTION_TP": "transaction_type",
    "TRANSACTION_PGI": "election_indicator",
    "AMNDT_IND": "amendment",
    "NAME": "name",
    "CITY": "city",
    "STATE": "state",
    "ZIP_CODE": "zip",
    "TRANSACTION_AMT": "amount",
    "OTHER_ID": "rcpt_cmte",
    "CAND_ID": "cand_id",
    "MEMO_TEXT": "memo",
    "YEAR": "year",
    "MONTH": "month",
    "DAY": "day"
}
cmte_contribution_vars = {
    "CMTE_ID": "cmte_id",
    "TRANSACTION_TP": "transaction_type",
    "TRANSACTION_PGI": "election_indicator",
    "AMNDT_IND": "amendment",
    "NAME": "name",
    "CITY": "city",
    "STATE": "state",
    "ZIP_CODE": "zip",
    "TRANSACTION_AMT": "amount",
    "OTHER_ID": "rcpt_cmte",
    "MEMO_TEXT": "memo",
    "YEAR": "year",
    "MONTH": "month",
    "DAY": "day"
}
keep_types = ["24K", "24Z", "24N", "24U", "24P", "24R"]

def process_candidates(candidates: pl.DataFrame) -> pl.DataFrame:
    candidates = (
    candidates
    .drop_nulls(subset = ["candidate_election_year", "district"])
    .with_columns([
        pl.col("candidate_election_year").cast(pl.Int64).alias("year"),
        pl.col("district").cast(pl.Int64),
        pl.col("name").map_elements(parse_last_name, return_dtype=pl.Utf8).alias("last_name")
    ])
    .select([
        "candidate_id",
        "state", 
        "district",
        "year",
        "incumbent_challenge",
        "party",
        "last_name"
    ])
    .rename({"year":"cycle"})
)
    return candidates

# Take bulk downloaded candidate contribution files and aggregate them into a single parquet
def aggregate_candidate_contribution(start_year = 2004, end_year = 2024):
    end_year = end_year + 2
    all_contributions = []
    for year in tqdm(range(start_year, end_year, 2)):
        contributions = pd.read_parquet(f"{FEC_BULK_PATH}contributions/committees/candidates_{year}.parquet")
        contributions["MONTH"] = pd.to_numeric(contributions["TRANSACTION_DT"].str[:2])
        contributions["DAY"] = pd.to_numeric(contributions["TRANSACTION_DT"].str[2:4])
        contributions["YEAR"] = pd.to_numeric(contributions["TRANSACTION_DT"].str[4:])
        contributions = contributions[list(cand_contribution_vars.keys())]
        contributions = contributions.rename(columns = cand_contribution_vars)
        contributions["zip"] = contributions["zip"].astype(str).str[:5]
        all_contributions.append(contributions)
    all_contributions = pd.concat(all_contributions, ignore_index=True)
    all_contributions.to_parquet(f"{FEC_PROCESSED_PATH}committee_to_candidate_contributions.parquet")
    return all_contributions

# Take bulk downloaded committee to committee contribution files and aggregate them into a single parquet
def aggregate_committee_contribution(start_year = 2004, end_year = 2024):
    end_year = end_year + 2
    all_contributions = []
    for year in tqdm(range(start_year, end_year, 2)):
        contributions = pd.read_parquet(f"{FEC_BULK_PATH}contributions/committees/committees_{year}.parquet")
        contributions["MONTH"] = pd.to_numeric(contributions["TRANSACTION_DT"].str[:2])
        contributions["DAY"] = pd.to_numeric(contributions["TRANSACTION_DT"].str[2:4])
        contributions["YEAR"] = pd.to_numeric(contributions["TRANSACTION_DT"].str[4:])
        contributions = contributions[list(cmte_contribution_vars.keys())]
        contributions = contributions.rename(columns = cmte_contribution_vars)
        contributions["zip"] = contributions["zip"].astype(str).str[:5]
        all_contributions.append(contributions)
    all_contributions = pd.concat(all_contributions, ignore_index = True)
    all_contributions.to_parquet(f"{FEC_PROCESSED_PATH}committee_to_committee_contributions.parquet")
    return all_contributions

# Read in the processed committee->candidate and committee->committee parquet and keep only corporate contributors
def filter_corporate_contribution():
    firms = pd.read_csv(f"{LSEG_RAW_PATH}LSEG_firms.csv")
    cpacs = pd.read_csv(f"{FEC_PROCESSED_PATH}corporate_pac_firm_matches.csv")
    contributions = pd.read_parquet(f"{FEC_PROCESSED_PATH}committee_to_candidate_contributions.parquet")
    contributions = add_cycle(contributions)
    cpacs.rename(columns = {"year": "cycle"}, inplace = True)
    
    all_contrib = pd.merge(contributions, cpacs, how = "inner",
                         on = ["cmte_id", "cycle"])
    ric_str = all_contrib["ric"].astype("string")
    permid_num = pd.to_numeric(all_contrib["permid"], errors="coerce")
    permid_str = permid_num.astype("Int64").astype("string")
    all_contrib["instrument"] = ric_str.fillna(permid_str)
    all_contrib = all_contrib.drop(columns = ["ric", "permid"])
    all_contrib = pd.merge(all_contrib, firms, how = "left",
                         on = "instrument")
    all_contrib["instrument"] = all_contrib["instrument"].astype("string")
    all_contrib.to_parquet(f"{FEC_PROCESSED_PATH}firm_pac_to_candidate_contributions.parquet")

    contributions = pd.read_parquet(f"{FEC_PROCESSED_PATH}committee_to_committee_contributions.parquet")
    contributions = add_cycle(contributions)

    all_contrib = pd.merge(contributions, cpacs, how = "inner",
                         on = ["cmte_id", "cycle"])
    ric_str = all_contrib["ric"].astype("string")
    permid_num = pd.to_numeric(all_contrib["permid"], errors="coerce")
    permid_str = permid_num.astype("Int64").astype("string")
    all_contrib["instrument"] = ric_str.fillna(permid_str)
    all_contrib = all_contrib.drop(columns = ["ric", "permid"])
    all_contrib = pd.merge(all_contrib, firms, how = "left",
                         on = "instrument")
    all_contrib["instrument"] = all_contrib["instrument"].astype("string")
    all_contrib.to_parquet(f"{FEC_PROCESSED_PATH}firm_pac_to_committee_contributions.parquet")

# Take scraped candidate associated committees by chamber and parse out only principal committees
def get_principal_committees(office = "H"):
    """
    Separate candidate-committee matches into different groups
    P (principal committee), A (authorized by candidates), and U+H (Unauthorized House committees) are categorized as candidate-specific committees
    J (joint fundraising committee) is its own category
    """
    candidate_committees = pd.read_csv(f"{FEC_API_PATH}candidates/candidate_committees_{office}.csv")
    principal_committees = candidate_committees[candidate_committees["designation"] == "P"]
    authorized_committees = candidate_committees[candidate_committees["designation"] == "A"]
    unauthorized_committees = candidate_committees[(candidate_committees["designation"] == "U") & (candidate_committees["committee_type"] == office)]

    candidate_committees = pd.concat([principal_committees, authorized_committees, unauthorized_committees]).drop_duplicates().reset_index(drop = True)
    output_name = {
        "H": "house_candidate_principal_committees.csv",
        "S": "senate_candidate_principal_committees.csv",
    }.get(office, f"candidate_principal_committees_{office}.csv")
    candidate_committees.to_csv(f"{FEC_PROCESSED_PATH}{output_name}", index = False)

# Take scraped leadership pac data and 1) process them automatically 2) take automatically processed and hand-coded data and recombine them
def process_leadership_pac(step):
    """
    Leadership PAC is only recognized as leadership PACs with D designation post 2010. This function can take two step values
    1. step = "backfill"
        1. Remove all observations for 2026
        2. For all House candidates, back fill their candidate ID before 2010
        The edited file will be split into two separate files, a completed part and a part that needs hand-coding
    2. step = "merge"
        Merge the completed part with the completed hand-coding part
    """
    if step == "backfill":
        leadership_pacs = pd.read_csv(f"{FEC_API_PATH}committees/leadership_history.csv")
        leadership_pacs = leadership_pacs[leadership_pacs["cycle"] != 2026].copy()

        map_2010 = (
            leadership_pacs.loc[leadership_pacs["cycle"] == 2010, ["committee_id", "sponsor_candidate_ids"]]
                           .dropna(subset = ["committee_id"])
                           .assign(sponsor_candidate_ids = lambda x: x["sponsor_candidate_ids"].fillna(""))
                           .loc[lambda x: x["sponsor_candidate_ids"].str.startswith("H", na = False)]
                           .dropna(subset = ["sponsor_candidate_ids"])
                           .groupby("committee_id")["sponsor_candidate_ids"]
                           .first()
        )
        
        mask_old = leadership_pacs["cycle"] <= 2008
        leadership_pacs.loc[mask_old, "sponsor_candidate_ids"] = (
            leadership_pacs.loc[mask_old, "committee_id"].map(map_2010).fillna("")
        )

        has_value = leadership_pacs["sponsor_candidate_ids"].fillna("").astype(str).str.strip().ne("")
        committee_complete_mask = has_value.groupby(leadership_pacs["committee_id"]).transform("all")
        
        df_complete = leadership_pacs[committee_complete_mask].copy()
        df_missing  = leadership_pacs[~committee_complete_mask].copy()

        df_complete.to_csv(f"{FEC_API_PATH}committees/leadership_history_complete.csv", index = False)
        df_missing.to_csv(f"{FEC_API_PATH}committees/leadership_history_hc.csv", index = False)

    if step == "merge":
        df_complete = pd.read_csv(f"{FEC_API_PATH}committees/leadership_history_complete.csv")
        df_hc = pd.read_csv(f"{FEC_API_PATH}committees/leadership_history_hc.csv")
        leadership_history = pd.concat([df_complete, df_hc])
        leadership_history = leadership_history.dropna(subset = ["sponsor_candidate_ids"]).rename({"sponsor_candidate_ids":"sponsor_id"})
        leadership_history.to_csv(f"{FEC_PROCESSED_PATH}leadership_pac_committees.csv", index = False)

# Take all firm contribution records and match to candidates
def match_cands():
    # load data
    cand_contrib = pl.read_parquet(f"{FEC_PROCESSED_PATH}firm_pac_to_candidate_contributions.parquet")
    cmte_contrib = pl.read_parquet(f"{FEC_PROCESSED_PATH}firm_pac_to_committee_contributions.parquet")
    principal_cmtes_H = pl.read_csv(f"{FEC_PROCESSED_PATH}house_candidate_principal_committees.csv")
    principal_cmtes_S = pl.read_csv(f"{FEC_PROCESSED_PATH}senate_candidate_principal_committees.csv")
    leadership_cmtes = pl.read_csv(f"{FEC_PROCESSED_PATH}leadership_pac_committees.csv")

    # prepare candidate-committees mapping dataframes
    principal_cmtes_H = (
        principal_cmtes_H
        .filter(pl.col("candidate_ids").str.starts_with("H"))
        .select(["committee_id", "cycle", "candidate_id"])
        .rename({"committee_id":"rcpt_cmte", "candidate_id":"matched_cand"})
        .unique()
    )

    principal_cmtes_S = (
        principal_cmtes_S
        .filter(pl.col("candidate_ids").str.starts_with("S"))
        .select(["committee_id", "cycle", "candidate_id"])
        .rename({"committee_id":"rcpt_cmte", "candidate_id":"matched_cand"})
        .unique()
    )

    leadership_cmtes = (
        leadership_cmtes
        .filter(pl.col("sponsor_candidate_ids").str.starts_with("H"))
        .select(["committee_id", "cycle", "sponsor_candidate_ids"])
        .rename({"committee_id":"rcpt_cmte", "sponsor_candidate_ids":"matched_cand"})
        .unique()
    )

    cand_cmtes = pl.concat([principal_cmtes_H, principal_cmtes_S])
    cand_cmtes = cand_cmtes.with_columns(
        pl.lit("P").alias("cmte_type")
    )
    leadership_cmtes = leadership_cmtes.with_columns(
        pl.lit("D").alias("cmte_type")
    )

    # Prepare contribution records for merging
    # Records from the committee -> candidate raw data parquet
    cand_contrib = cand_contrib.filter(pl.col("transaction_type").is_in(keep_types))
    cand_contrib = cand_contrib.with_columns(([
        pl.col("rcpt_cmte").fill_null(pl.col("cand_id")).alias("rcpt_cmte"),
        pl.col("cand_id").fill_null(pl.col("rcpt_cmte")).alias("cand_id")
    ]))
    cand_contrib = cand_contrib.with_columns([
        pl.when(pl.col("rcpt_cmte").str.contains(r"^C"))
        .then(pl.col("rcpt_cmte"))
        .otherwise(None)
        .alias("rcpt_cmte"),
        pl.when(pl.col("cand_id").str.contains(r"^[PHS]"))
        .then(pl.col("cand_id"))
        .otherwise(None)
        .alias("cand_id")
    ])

    # Records from the committee -> committee raw data parquet
    cmte_contrib = cmte_contrib.filter(pl.col("transaction_type").is_in(keep_types))
    cmte_contrib = cmte_contrib.with_columns(
        pl.col("rcpt_cmte").alias("cand_id")
    )
    cmte_contrib = cmte_contrib.with_columns([
        pl.when(pl.col("rcpt_cmte").str.contains(r"^C"))
        .then(pl.col("rcpt_cmte"))
        .otherwise(None)
        .alias("rcpt_cmte"),
        pl.when(pl.col("cand_id").str.contains(r"^[PHS]"))
        .then(pl.col("cand_id"))
        .otherwise(None)
        .alias("cand_id")
    ])

    # Create new dataframe for committee contribution to candidate principal committees
    # Contribution to candidates from the contribution to candidates raw data parquet
    cand_cand_contrib = cand_contrib.join(cand_cmtes, on = ["rcpt_cmte", "cycle"], how = "left")
    cand_cand_contrib = (
        cand_cand_contrib
        .with_columns([
            pl.col("matched_cand").fill_null(pl.col("cand_id")).alias("matched_cand")
            ])
        .drop_nulls(subset = ["matched_cand", "cmte_type"])
        .drop("cand_id")
        .rename({"matched_cand": "cand_id"})
    )

    # Contribution to candidates from the the contribution to committees raw data parquet (theoretically contribution to candidates is a subset of this larger dataframe)
    cand_cmte_contrib = cmte_contrib.join(cand_cmtes, on = ["rcpt_cmte", "cycle"], how = "left")
    cand_cmte_contrib = (
        cand_cmte_contrib
        .with_columns([
            pl.col("matched_cand").fill_null(pl.col("cand_id")).alias("matched_cand")
            ])
        .drop_nulls(subset = ["matched_cand", "cmte_type"])
        .drop("cand_id")
        .rename({"matched_cand": "cand_id"})
    )

    # Merging and dropping duplicates to create the final dataframe
    # By dropping duplicates I may ignore real "duplicated" contributions (same committee giving same amount to same committee on the same day)
    full_cand_contrib = pl.concat([cand_cand_contrib, cand_cmte_contrib]).unique(maintain_order=True)
    #full_cand_contrib = full_cand_contrib.filter(pl.col("amount") > 0)
    full_cand_contrib.write_parquet(f"{FEC_PROCESSED_PATH}firm_pac_to_principal_committee_contributions.parquet")

    # Create new dataframe for committee contribution to candidate leadership PACs committees
    # Contribution to leadership PACs from the contribution to candidates raw data parquet
    lead_cand_contrib = cand_contrib.join(leadership_cmtes, on = ["rcpt_cmte", "cycle"], how = "left")
    lead_cand_contrib = (
        lead_cand_contrib
        .with_columns([
            pl.col("matched_cand").fill_null(pl.col("cand_id")).alias("matched_cand")
        ])
        .drop_nulls(subset = ["matched_cand", "cmte_type"])
        .drop("cand_id")
        .rename({"matched_cand": "cand_id"})
    )

    # Contribution to leadership PACs  from the the contribution to committees raw data parquet (theoretically contribution to candidates is a subset of this larger dataframe)
    lead_cmte_contrib = cmte_contrib.join(leadership_cmtes, on = ["rcpt_cmte", "cycle"], how = "left")
    lead_cmte_contrib = (
        lead_cmte_contrib
        .with_columns([
            pl.col("matched_cand").fill_null(pl.col("cand_id")).alias("matched_cand")
        ])
        .drop_nulls(subset = ["matched_cand", "cmte_type"])
        .drop("cand_id")
        .rename({"matched_cand": "cand_id"})
    )

    # Merging and dropping duplicates to create the final dataframe
    # By dropping duplicates I may ignore real "duplicated" contributions (same committee giving same amount to same committee on the same day)
    full_leadership_contrib = pl.concat([lead_cand_contrib, lead_cmte_contrib]).unique(maintain_order=True)
    #full_leadership_contrib = full_leadership_contrib.filter(pl.col("amount") > 0)
    full_leadership_contrib.write_parquet(f"{FEC_PROCESSED_PATH}firm_pac_to_leadership_pac_contributions.parquet")

def separate_pac_contributors(type):
    # First order of separateion, by line number
    # 11A1/11AI - Contributions from individuals, partnerships and other persons who are not political committees.
    # 11B       - Contributions from political party committees
    # 11C       - Contributions from other political committees
    # 11D       - Contributions from candidate
    # 12        - Transfers from other authorized committees of the same candidate
    # 13        - All loans
    # 13A       - Loans from the candidate
    # 13B       - All other loans
    # 14        - Loan repayments
    # 15        - Offsets to operating expenditures such as: refunds, rebates, and returns of deposits
    # 16        - Refunds of contributions made to federal candidates and other political committees
    # 17        - Other receipts such as dividends and interest
    # 17A       - Contributions from individuals other than political committees
    # 17C       - Contributions from other political committees
    # 17D       - Contributions from the candidate
    # 1A        - Unknown
    # 21        - Other receipts such as dividends and interest
    # SL2       - Unknown
    contributions = pl.read_parquet(f"{FEC_API_PATH}contributions/{type}_contributions.parquet")
    # Replace 11AI with 11A1
    contributions = contributions.with_columns(
        pl.col("line_number").str.replace_all("11AI", "11A1")
    )
    # Filter out committee contributions
    committee_contributions = contributions.filter(pl.col("line_number").is_in(["11C", "17C"]))
    if committee_contributions.shape[0] > 0:
        committee_contributions.write_parquet(f"{FEC_API_PATH}contributions/{type}_committee_contributions.parquet")
        committees = (
            committee_contributions
            .group_by(["contributor_name", "contributor_id", "entity_type"])
            .agg(pl.col("contribution_receipt_amount").sum())
            .sort("contribution_receipt_amount", descending = True)
        )
        committees.write_csv(f"{FEC_API_PATH}contributions/{type}_committee_contributors.csv")

    # Filter out individual and organization contributions
    individual_contributions = contributions.filter((pl.col("entity_type")=="IND") & pl.col("line_number").is_in(["11A1", "13", "13B", "17A"]))
    organization_contributions = contributions.filter((pl.col("entity_type")!="IND") & pl.col("line_number").is_in(["11A1", "13", "13B", "17A"]))
    undefined_contributions = contributions.filter((pl.col("entity_type").is_null()) & pl.col("line_number").is_in(["11A1", "13", "13B", "17A"]))
    if individual_contributions.shape[0] > 0:
        individual_contributions.write_parquet(f"{FEC_API_PATH}contributions/{type}_individual_contributions.parquet")
        employers = individual_contributions[["contributor_employer", "contributor_city", "contributor_state"]].drop_nulls().unique()
        employers.write_csv(f"{FEC_API_PATH}contributions/{type}_individual_contributor_employers.csv")
    if organization_contributions.shape[0] > 0:
        organization_contributions.write_parquet(f"{FEC_API_PATH}contributions/{type}_organization_contributions.parquet")
        organizations = (
            organization_contributions
            .group_by(["contributor_name", "contributor_city", "contributor_state", "entity_type", "contributor_id"])
            .agg(pl.col("contribution_receipt_amount").sum())
            .sort("contribution_receipt_amount", descending = True)
        )
        organizations.write_csv(f"{FEC_API_PATH}contributions/{type}_organization_contributors.csv")
    if undefined_contributions.shape[0] > 0:
        undefined_contributions.write_csv(f"{FEC_API_PATH}contributions/{type}_undefined_contributions.csv")

def merge_contribution_candidate():
    """
    Merge the firm_pac_to_principal_committee_contributions and candidate information
    """
    principal_contrib = pl.read_parquet(f"{FEC_PROCESSED_PATH}firm_pac_to_principal_committee_contributions.parquet")
    house_cand = pl.read_csv(f"{FEC_API_PATH}candidates/candidate_history_H.csv")
    senate_cand = pl.read_csv(f"{FEC_API_PATH}candidates/candidate_history_S.csv")

    house_cand = process_candidates(house_cand)
    senate_cand = process_candidates(senate_cand)

    principal_contrib = principal_contrib.rename(
        {"name": "rcpt_name",
         "city": "rcpt_city",
         "state": "rcpt_state",
         "zip": "rcpt_zip"})
    
    data_merged = principal_contrib.join(
        house_cand,
        left_on = ["cand_id", "cycle"],
        right_on = ["candidate_id", "cycle"],
        how = "left"
    )

    data_merged = senate_cycle_join(
        A=data_merged,
        B=senate_cand,
        left_match_cols=["cand_id"],
        right_match_cols=["candidate_id"],
        left_cycle_col="cycle",
        right_cycle_col="cycle",
        tolerance=4,
    )

    data_merged = data_merged.with_columns(
        pl.col("last_name").fill_null(pl.col("last_name_B")).alias("last_name"),
        pl.col("state").fill_null(pl.col("state_B")).alias("state"),
        pl.col("district").fill_null(pl.col("district_B")).alias("district"),
        pl.col("incumbent_challenge").fill_null(pl.col("incumbent_challenge_B")).alias("incumbent_challenge"),
        pl.col("party").fill_null(pl.col("party_B")).alias("party"),
        pl.col("matched_cycle_B").fill_null(pl.col("cycle")).alias("matched_cycle")
    ).drop([
        "last_name_B",
        "state_B",
        "district_B",
        "incumbent_challenge_B",
        "party_B",
        "cycle",
        "matched_cycle_B"
    ]).rename({"matched_cycle": "cycle"})

    data_merged.write_parquet(f"{FEC_PROCESSED_PATH}firm_pac_to_principal_committee_contributions_with_candidate_info.parquet")

if __name__ == "__main__":
    # aggregate_candidate_contribution()
    # aggregate_committee_contribution()
    filter_corporate_contribution()
    get_principal_committees("H")
    get_principal_committees("S")
    # process_leadership_pac(step = "merge")
    match_cands()
    # separate_pac_contributors("super")
    
