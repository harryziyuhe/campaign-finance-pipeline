import argparse
import os
from pathlib import Path
import polars as pl
from utils import remove_punc, parse_last_name, validate_frame

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
ELECTION_RATINGS_PATH = DATA_ROOT / "data" / "raw" / "electionratings"
EXTERNAL_PATH = DATA_ROOT / "data" / "external"
HOUSE_PROCESSED_PATH = DATA_ROOT / "data" / "processed" / "house"

def load_data():
    # Load in FEC processed data for contributions from firms to candidates
    contributions = pl.read_parquet(FEC_PROCESSED_PATH / "firm_pac_to_principal_committee_contributions.parquet")
    validate_frame(
        contributions,
        ["cmte_id", "cand_id", "amount", "cycle", "year", "month"],
        name="firm_pac_to_principal_committee_contributions.parquet",
    )
    leadership_contributions = pl.read_parquet(FEC_PROCESSED_PATH / "firm_pac_to_leadership_pac_contributions.parquet")
    validate_frame(
        leadership_contributions,
        ["cmte_id", "cand_id", "amount", "cycle", "year", "month"],
        name="firm_pac_to_leadership_pac_contributions.parquet",
    )
    candidates = pl.read_csv(FEC_API_PATH / "candidates" / "candidate_history_H.csv",
                         schema_overrides={"address_zip": pl.Utf8})
    validate_frame(
        candidates,
        ["candidate_id", "state", "district", "candidate_election_year", "incumbent_challenge", "party", "name"],
        name="candidate_history_H.csv",
    )
    elections = pl.read_csv(ELECTION_RATINGS_PATH / "IE" / "house_ratings.csv")
    elections = elections[:, 1:]
    validate_frame(
        elections,
        ["date", "state", "district", "incumbent_party", "incumbent", "open", "special", "rating"],
        name="house_ratings.csv",
    )
    general_cands = pl.read_csv(EXTERNAL_PATH / "other" / "house_general_cands.csv")
    general_cands = general_cands.rename({"year":"cycle"})
    validate_frame(
        general_cands,
        ["cycle", "state_po", "district", "candidate", "party", "candidatevotes", "totalvotes", "writein"],
        name="house_general_cands.csv",
    )
    return contributions, leadership_contributions, candidates, elections, general_cands

def process_elections(elections: pl.DataFrame) -> pl.DataFrame:
    # Process elections
    elections = elections.with_columns([
        pl.col("date").str.to_datetime().alias("date"),
        pl.col("date").str.to_datetime().dt.year().alias("year")
    ])

    # Inside Elections snapshots dated in odd years were found corrupted
    # (silently overwritten with a duplicate current-ratings payload during
    # a 2026-07-26 re-scrape -- see docs/redistricting-timing-fix-log.md and
    # the 2026-08 incident notes). Even-year snapshots are unaffected.
    # Restrict to even years until the odd-year archive is restored/re-scraped.
    elections = elections.filter(pl.col("year") % 2 == 0)

    elections = elections.filter(pl.col("date").dt.month() > 5)

    # Aggregate ratings by taking the mean, and interpreting this as continuous values from -4 to 4
    elections = (
        elections
        .group_by(["state", "district", "year"])
        .agg([
            pl.col("incumbent_party").first(),
            pl.col("incumbent").first(),
            pl.col("open").first(),
            pl.col("special").first(),
            pl.col("rating").mean()
        ])
    )

    elections = elections.with_columns([
        ((pl.col("incumbent_party") == "republican") & (pl.col("rating") < 0))
        .cast(pl.Int8)
        .alias("flip"),
        pl.col("rating").abs().alias("uncertainty")
    ]).rename({"year":"cycle"})

    return elections

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

def process_contributions(contributions: pl.DataFrame) -> pl.DataFrame:
    # Process contributions
    firm_size = (
        contributions
        .filter(pl.col("amount") > 0)
        .group_by(["cmte_id", "cycle"])
        .agg([
            pl.col("amount").sum().alias("firm_amount"),
            pl.col("cand_id").n_unique().alias("firm_candidates")
        ])
    )
    contributions= (
        contributions
        .filter(pl.col("cand_id").str.starts_with("H"))
        #.filter(pl.col("amount") > 0)
        .select([
            "cmte_id", "name", "amount", "cand_id", "rcpt_cmte", "year", "month", "day", "cycle",
            "cmte_nm", "connected_org_nm", "corporation", "ttl_receipts", "instrument", "cusip",
            "hq", "hq_state", "hq_city", "ric", "permid", "GICS_Sector", "GICS_Industry_Group",
            "GICS_Industry", "GIS_Subindustry", "TRBC_Econ_Sector", "TRBC_Business_Sector",
            "TRBC_Industry_Group", "TRBC_Industry", "TRBC_ID", "NAICS_Sector", "NAICS_Subsector",
            "NAICS_Industry_Group"
        ])
        .join(firm_size, on = ["cmte_id", "cycle"], how = "left")
    )

    return contributions

def get_corporate_pacs(contributions: pl.DataFrame) -> None:
    vars = ["cmte_id", "cycle", "corporation", "ttl_receipts", "instrument", "cusip",
        "hq", "hq_state", "hq_city", "ric", "permid", "GICS_Sector", "GICS_Industry_Group",
        "GICS_Industry", "GIS_Subindustry", "TRBC_Econ_Sector", "TRBC_Business_Sector",
        "TRBC_Industry_Group", "TRBC_Industry", "TRBC_ID", "NAICS_Sector", "NAICS_Subsector",
        "NAICS_Industry_Group", "firm_amount", "firm_candidates"]

    corporate_pacs = (
        contributions
        .select(vars)
        .unique()
    )
    
    corporate_pacs.write_parquet(FEC_PROCESSED_PATH / "firm_pac_cycle_panel.parquet")
    return corporate_pacs

def aggregate_candidate_contribution(contributions: pl.DataFrame, candidates: pl.DataFrame, elections: pl.DataFrame, election_year = True) -> tuple[pl.DataFrame, pl.DataFrame | None]:
    if election_year:
        previous_contributions = contributions.filter(
            pl.col("year") % 2 == 1
        )
        previous_contributions = (
            previous_contributions
            .group_by(["cmte_id", "year", "cand_id"])
            .agg([
                pl.col("amount").sum().alias("prior_amount")
            ])
            .rename({"cand_id": "candidate_id"})
        )
        contributions = contributions.filter(
            (pl.col("year") % 2 == 0) & (pl.col("month") < 11)
        )
    else:
        previous_contributions = contributions.filter(
            pl.col("year") % 2 == 1
        )
        previous_contributions = (
            contributions
            .select(["cmte_id", "year", "cand_id"])
            .unique()
            .with_columns(pl.lit(0).alias("prior_amount"))
            .rename({"cand_id": "candidate_id"})
        )
        contributions = contributions.filter(
            (pl.col("year") % 2 == 1) | (pl.col("month") < 11)
        )
    merged_data = (
        contributions
        .join(
            candidates,
            left_on = ["cand_id", "cycle"],
            right_on = ["candidate_id", "cycle"],
            how = "inner"
        )
        .with_columns(
            pl.when(pl.col("district") == 0)
            .then(1)
            .otherwise(pl.col("district"))
            .alias("district")
        )
        .join(
            elections,
            on = ["state", "district", "cycle"],
            how = "inner"
        )
        .filter(pl.col("amount") > 0)
    )

    return merged_data, previous_contributions

def get_race_data(merged_data: pl.DataFrame,
                  corporate_pacs: pl.DataFrame,
                  elections: pl.DataFrame):
    products = (
        merged_data
        .group_by(["cmte_id", "year", "state", "district"])
        .agg([
            pl.col("amount").sum().alias("total_amount"),
            pl.col("amount").count().alias("total_count"),
            pl.col("party").n_unique().alias("nparty")
        ])
        .with_columns(pl.lit(1).alias("contribute"))
    )

    race_data = (
        corporate_pacs
        .join(elections, on = "year", how = "inner")
        .join(
            products,
            on = ["cmte_id", "year", "state", "district"],
            how = "left"
        )
        .with_columns([
            pl.col("total_amount").fill_null(0),
            pl.col("total_count").fill_null(0),
            pl.col("nparty").fill_null(0),
            pl.col("contribute").fill_null(0)
        ])
    )

    return race_data
    

def get_leadership_outcome(merged_data: pl.DataFrame) -> pl.DataFrame:
    # Mirrors the "products" aggregation in get_cand_data, but for contributions
    # to a candidate's leadership PAC (FEC designation "D") rather than their
    # principal campaign committee.
    return (
        merged_data
        .group_by(["cmte_id", "cycle", "cand_id"])
        .agg([
            pl.col("amount").sum().alias("total_amount_leadership"),
            pl.col("amount").count().alias("total_count_leadership"),
        ])
        .rename({"cand_id": "candidate_id"})
        .with_columns(pl.lit(1).alias("contribute_leadership"))
    )

def get_cand_data(merged_data: pl.DataFrame,
                  corporate_pacs: pl.DataFrame,
                  general_cands: pl.DataFrame,
                  elections: pl.DataFrame,
                  candidates: pl.DataFrame,
                  previous_contributions: pl.DataFrame,
                  leadership_products: pl.DataFrame):
    general_cands = (
        general_cands
        .filter(pl.col("cycle") >= 2010)
        .filter(~pl.col("writein"))
        .filter(~pl.col("party").is_null())
        .with_columns(
            pl.col("candidate").map_elements(parse_last_name, return_dtype=pl.Utf8).alias("last_name")
        )
    )

    vars = ["cycle", "state_po", "district", "candidate", "party", "candidatevotes", "totalvotes", "last_name"]
    general_cands = (
        general_cands
        .select(vars)
        .rename({"state_po": "state"})
    )

    filter_cands = (
        general_cands.join(
            candidates,
            on = ["cycle", "state", "district", "last_name"],
            how = "left",
            suffix = "_y"
        )
        .drop_nulls(subset = ["candidate_id"])
        .rename({"party_y": "party_abb"})
        .select([
            "cycle", "state", "district", "candidate", "party",
            "candidatevotes", "totalvotes", "candidate_id", "incumbent_challenge"
        ])
        .with_columns(
            pl.when(pl.col("district") == 0)
            .then(1)
            .otherwise(pl.col("district"))
            .alias("district")
        )
        .join(elections, on = ["state", "district", "cycle"], how = "inner")
    )

    products = (
        merged_data
        .group_by(["cmte_id", "cycle", "cand_id"])
        .agg([
            pl.col("amount").sum().alias("total_amount"),
            pl.col("amount").count().alias("total_count"),
            pl.col("party").n_unique().alias("nparty")
        ])
        .rename({"cand_id": "candidate_id"})
        .with_columns(pl.lit(1).alias("contribute"))
    )

    if previous_contributions.shape[0] > 0:
        previous_contributions = previous_contributions.with_columns(
            (pl.col("year") + 1).alias("cycle")
        )

    cand_data = (
        corporate_pacs
        .join(filter_cands, on = "cycle", how = "inner")
        .join(products, on = ["cmte_id", "cycle", "candidate_id"], how = "left")
        .join(previous_contributions, on = ["cmte_id", "cycle", "candidate_id"], how = "left")
        .join(leadership_products, on = ["cmte_id", "cycle", "candidate_id"], how = "left")
        .with_columns([
            pl.col("total_amount").fill_null(0),
            pl.col("total_count").fill_null(0),
            pl.col("nparty").fill_null(0),
            pl.col("contribute").fill_null(0),
            pl.col("prior_amount").fill_null(0),
            pl.col("total_amount_leadership").fill_null(0),
            pl.col("total_count_leadership").fill_null(0),
            pl.col("contribute_leadership").fill_null(0)
        ])
        .with_columns([
            (pl.col("total_amount") + pl.col("total_amount_leadership")).alias("total_amount_combined"),
            (pl.col("total_count") + pl.col("total_count_leadership")).alias("total_count_combined"),
            pl.max_horizontal(["contribute", "contribute_leadership"]).alias("contribute_combined")
        ])
    )

    return cand_data

def parse_args():
    parser = argparse.ArgumentParser(
        description="Build House candidate-level contribution panels."
    )
    parser.add_argument(
        "--scope",
        choices=["election-year", "all"],
        default=None,
        help=(
            "Aggregate election-year contributions only, or all cycles. "
            "If omitted, prompts interactively (previous default behavior)."
        ),
    )
    return parser.parse_args()


def main():
    args = parse_args()

    contributions, leadership_contributions, candidates, elections, general_cands = load_data()
    elections = process_elections(elections)
    candidates = process_candidates(candidates)
    contributions = process_contributions(contributions)
    leadership_contributions = process_contributions(leadership_contributions)
    contributions.write_parquet(HOUSE_PROCESSED_PATH / "house_firm_contributions.parquet")
    firm_pacs_path = FEC_PROCESSED_PATH / "firm_pac_cycle_panel.parquet"
    if os.path.exists(firm_pacs_path):
        corporate_pacs = pl.read_parquet(firm_pacs_path)
        corporate_pacs = corporate_pacs.rename({"year":"cycle"})
    else:
        corporate_pacs = get_corporate_pacs(contributions)

    if args.scope is not None:
        election_year = args.scope == "election-year"
    else:
        election_year = input("Aggregate for election year only? (y/n): ") == "y"

    merged_data, previous_contributions = aggregate_candidate_contribution(contributions, candidates, elections, election_year=election_year)
    previous_contributions.write_csv(HOUSE_PROCESSED_PATH / "house_previous_contributions.csv")

    merged_data_leadership, _ = aggregate_candidate_contribution(leadership_contributions, candidates, elections, election_year=election_year)
    leadership_products = get_leadership_outcome(merged_data_leadership)

    #race_data = get_race_data(merged_data, corporate_pacs, elections)
    cand_data = get_cand_data(merged_data, corporate_pacs, general_cands, elections, candidates, previous_contributions, leadership_products)

    output_name = "house_firm_cand_election_year.parquet" if election_year else "house_firm_cand.parquet"
    # HouseCandData.R reads this file next and joins on cmte_id/candidate_id/party;
    # catch an empty or malformed result here rather than as a downstream R join failure.
    validate_frame(
        cand_data,
        ["cmte_id", "cycle", "candidate_id", "party", "total_amount", "contribute",
         "total_amount_leadership", "contribute_leadership",
         "total_amount_combined", "contribute_combined"],
        name=output_name,
    )

    if election_year:
        #race_data.write_parquet(HOUSE_PROCESSED_PATH / "house_firm_race_election_year.parquet")
        cand_data.write_parquet(HOUSE_PROCESSED_PATH / output_name)
    else:
        #race_data.write_parquet(HOUSE_PROCESSED_PATH / "house_firm_race.parquet")
        cand_data.write_parquet(HOUSE_PROCESSED_PATH / output_name)

if __name__ == "__main__":
    main()
