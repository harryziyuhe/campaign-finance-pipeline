from __future__ import annotations

"""Filter congressional scandal and committee assignment source CSVs.

This script keeps scandal events from 2005 onward and House committee
assignment rows from the 109th Congress onward. It writes filtered source-level
CSV files under data/processed/congress for later normalization and panel
construction.
"""

"""
A few manual edits on the final crosswalk
1. DesJarlais is named "DES JARLAIS, SCOTT HON." in API (H0TN04195)
2. Hochul is named "HOCHUL, KATHLEEN COURTNEY" in API and first elected in special election for NY-26 in 2011 (H2NY00036)
3. Barber is named "BARBER, RONALD" in API and first elected in special election for AZ-8 in 2012 (H2AZ08094)
4. Wasserman Schultz name in API is not consistent (H4FL20023), should be "WASSERMAN SCHULTZ, DEBBIE"
5. La Malfa is named "LAMALFA, DOUG" in API (H2CA02142)
6. Billy Long is missing in API (H0MO07113, C00460063)
7. Kennedy, Joseph is missing in API (H2MA04073, C00512970)
8. Marshall, Roger is missing in API (H6KS01179, C00576173)
"""

import argparse
import re
import os
from pathlib import Path

import polars as pl


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
SCANDAL_SOURCE = (
    DATA_ROOT
    / "data"
    / "external"
    / "congress"
    / "scandals"
    / "congressional_scandals_1979_2018.csv"
)
COMMITTEE_ASSIGNMENT_SOURCE = (
    DATA_ROOT
    / "data"
    / "external"
    / "congress"
    / "committee_assignments"
    / "house_committee_assignments_103_115.csv"
)
FEC_HOUSE_CANDIDATES_SOURCE = (
    DATA_ROOT / "data" / "raw" / "fec_api" / "candidates" / "candidate_history_H.csv"
)
FEC_HOUSE_CANDIDATE_COMMITTEES_SOURCE = (
    DATA_ROOT / "data" / "raw" / "fec_api" / "candidates" / "candidates_H.csv"
)
OUTPUT_DIR = DATA_ROOT / "data" / "processed" / "congress"
VALIDATED_COMMITTEE_FEC_CROSSWALK = (
    OUTPUT_DIR / "house_committee_assignments_fec_crosswalk.csv"
)
ASSIGNMENT_MATCH_KEYS = ["congress", "committee_code", "id", "date_of_assignment"]
SCANDAL_FEC_MATCH_KEYS = ["congress", "last_name", "state_name", "district"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Filter congressional scandal and House committee assignment sources."
    )
    parser.add_argument("--min-scandal-year", type=int, default=2004)
    parser.add_argument("--min-congress", type=int, default=109)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    parser.add_argument(
        "--validated-crosswalk",
        type=Path,
        default=VALIDATED_COMMITTEE_FEC_CROSSWALK,
    )
    return parser.parse_args()


def extract_year_expr(column: str) -> pl.Expr:
    return (
        pl.col(column)
        .cast(pl.String)
        .str.extract(r"(\d{4})", 1)
        .cast(pl.Int64, strict=False)
    )


def normalize_name_piece(column: str | pl.Expr) -> pl.Expr:
    expr = pl.col(column) if isinstance(column, str) else column
    return (
        expr.cast(pl.String)
        .str.to_lowercase()
        .str.replace_all(r"\([^)]*\)", " ")
        .str.replace_all(r"[^a-z\s]", " ")
        .str.replace_all(r"\b(jr|sr|ii|iii|iv|v)\b", " ")
        .str.replace_all(r"\s+", " ")
        .str.strip_chars()
    )


def last_word_expr(column: str | pl.Expr) -> pl.Expr:
    expr = pl.col(column) if isinstance(column, str) else column
    last_word = (
        expr.cast(pl.String)
        .str.strip_chars()
        .str.split(" ")
        .list.get(-1, null_on_oob=True)
    )
    return normalize_name_piece(last_word)


def last_word_without_suffix_expr(column: str | pl.Expr) -> pl.Expr:
    expr = pl.col(column) if isinstance(column, str) else column
    name_without_suffix = (
        expr.cast(pl.String)
        .str.strip_chars()
        .str.replace_all(r"(?i)[,\.\s]+(jr|sr|ii|iii|iv|v)\.?\s*$", "")
    )
    last_word = (
        name_without_suffix.str.strip_chars()
        .str.split(" ")
        .list.get(-1, null_on_oob=True)
    )
    return normalize_name_piece(last_word)


def clean_column_names(frame: pl.DataFrame) -> pl.DataFrame:
    rename_map = {
        column: re.sub(r"_+", "_", re.sub(r"[^a-z0-9]+", "_", column.lower())).strip("_")
        for column in frame.columns
    }
    return frame.rename(rename_map)


def filter_scandals(min_year: int) -> pl.DataFrame:
    return (
        pl.read_csv(SCANDAL_SOURCE, infer_schema_length=10000)
        .with_columns(extract_year_expr("breakdate").alias("break_year"))
        .filter(pl.col("break_year") >= min_year)
        .filter(pl.col("house") == 1)
        .drop("house")
        .sort(["break_year", "bioguide", "breakdate"])
    )


def filter_committee_assignments(min_congress: int) -> pl.DataFrame:
    assignments = clean_column_names(
        pl.read_csv(COMMITTEE_ASSIGNMENT_SOURCE, infer_schema_length=10000)
    )
    return (
        assignments.with_columns(
            pl.col("congress").cast(pl.Int64, strict=False),
            pl.col("state_name").cast(pl.String).str.to_uppercase().str.strip_chars(),
        )
        .filter(pl.col("congress") >= min_congress)
        .filter(~pl.col("state_name").is_in(["AS", "VI", "GU", "PR", "DC"]).fill_null(False))
        .sort(["congress", "committee_code", "id"])
    )


def add_committee_assignment_match_fields(assignments: pl.DataFrame) -> pl.DataFrame:
    split_name = pl.col("name").cast(pl.String).str.split_exact(",", 1)
    return (
        assignments.with_columns(
            split_name.struct.field("field_0").alias("_assignment_last_name_raw"),
            pl.col("date_of_assignment")
            .cast(pl.String)
            .str.strptime(pl.Date, "%m/%d/%Y", strict=False)
            .alias("assignment_date"),
        )
        .with_columns(
            last_word_expr("_assignment_last_name_raw").alias("last_name"),
            pl.col("assignment_date").dt.year().alias("assignment_year"),
        )
        .with_columns(
            (pl.col("assignment_year") + (pl.col("assignment_year") % 2) - 2).alias("election_year"),
            pl.col("cd").cast(pl.Int64, strict=False).alias("district"),
        )
        .drop(
            ["_assignment_last_name_raw", "assignment_year"]
        )
    )


def load_fec_house_candidates_for_matching() -> pl.DataFrame:
    candidates = pl.read_csv(
        FEC_HOUSE_CANDIDATES_SOURCE,
        infer_schema_length=10000,
        schema_overrides={"candidate_id": pl.String, "candidate_election_year": pl.Float64, "address_zip": pl.String},
    )
    split_name = pl.col("name").cast(pl.String).str.split_exact(",", 1)
    return (
        candidates.with_columns(
            split_name.struct.field("field_0").alias("_fec_last_name_raw"),
        )
        .with_columns(
            last_word_expr("_fec_last_name_raw").alias("last_name"),
            pl.col("state").alias("state_name"),
            pl.col("candidate_election_year").cast(pl.Int64, strict=False).alias("election_year"),
            pl.col("district").cast(pl.Int64, strict=False).alias("district")
        )
        .with_columns(
            pl.when(pl.col("district") == 0).then(1).otherwise(pl.col("district")).alias("district")
        )
        .select(
            [
                "candidate_id",
                pl.col("name").alias("fec_candidate_name"),
                "election_year",
                "last_name",
                "state_name",
                "district"
            ]
        )
        .unique()
    )


def manual_candidate_matches() -> pl.DataFrame:
    return pl.DataFrame(
        [
            ("desjarlais", "TN", 4, "H0TN04195", None),
            ("hochul", "NY", 26, "H2NY00036", None),
            ("barber", "AZ", 8, "H2AZ08094", None),
            ("schultz", "FL", 20, "H4FL20023", None),
            ("malfa", "CA", 1, "H2CA02142", None),
            ("hahn", "CA", 36, "H8CA36097", None),
            ("long", "MO", 7, "H0MO07113", "C00460063"),
            ("kennedy", "MA", 4, "H2MA04073", "C00512970"),
            ("marshall", "KS", 1, "H6KS01179", "C00576173"),
        ],
        schema=[
            "last_name",
            "state_name",
            "district",
            "manual_candidate_id",
            "manual_committee_id",
        ],
        orient="row",
    )


def load_fec_candidate_committees() -> pl.DataFrame:
    return (
        pl.read_csv(
            FEC_HOUSE_CANDIDATE_COMMITTEES_SOURCE,
            infer_schema_length=10000,
            schema_overrides={
                "candidate_id": pl.String,
                "election_year": pl.Int64,
                "committee_id": pl.String,
            },
        )
        .select(["candidate_id", "election_year", "committee_id"])
        .filter(pl.col("candidate_id").is_not_null() & pl.col("election_year").is_not_null())
        .unique(["candidate_id", "election_year"], maintain_order=True)
    )


def add_manual_candidates(crosswalk: pl.DataFrame) -> pl.DataFrame:
    return (
        crosswalk.join(
            manual_candidate_matches(),
            on=["last_name", "state_name", "district"],
            how="left",
        )
        .with_columns(
            pl.coalesce(["candidate_id", "manual_candidate_id"]).alias("candidate_id"),
        )
        .drop("manual_candidate_id")
    )


def add_candidate_committees(crosswalk: pl.DataFrame) -> pl.DataFrame:
    return (
        crosswalk.join(
            load_fec_candidate_committees().rename(
                {"election_year": "match_election_year"}
            ),
            on=["candidate_id", "match_election_year"],
            how="left",
        )
        .with_columns(pl.coalesce(["committee_id", "manual_committee_id"]).alias("committee_id"))
        .drop("manual_committee_id")
    )


def add_candidate_match_validation_flag(matches: pl.DataFrame) -> pl.DataFrame:
    match_counts = (
        matches.group_by(ASSIGNMENT_MATCH_KEYS + ["match_election_year"])
        .agg(pl.col("candidate_id").drop_nulls().n_unique().alias("_candidate_match_count"))
    )
    return (
        matches.join(
            match_counts,
            on=ASSIGNMENT_MATCH_KEYS + ["match_election_year"],
            how="left",
        )
        .with_columns(
            pl.when(pl.col("_candidate_match_count") > 1)
            .then(True)
            .otherwise(None)
            .alias("manual_validation_required")
        )
        .drop("_candidate_match_count")
    )


def find_existing_column(frame: pl.DataFrame, options: list[str], label: str) -> str:
    for option in options:
        if option in frame.columns:
            return option
    raise ValueError(f"Could not find a {label} column. Tried: {', '.join(options)}")


def add_scandal_match_fields(scandals: pl.DataFrame) -> pl.DataFrame:
    state_column = find_existing_column(scandals, ["state_name", "state"], "state")
    district_column = find_existing_column(scandals, ["district", "cd"], "district")
    return scandals.with_columns(
        pl.col("congress").cast(pl.Int64, strict=False),
        last_word_without_suffix_expr("name").alias("last_name"),
        pl.col(state_column)
        .cast(pl.String)
        .str.to_uppercase()
        .str.strip_chars()
        .alias("state_name"),
        pl.col(district_column).cast(pl.Int64, strict=False).alias("district"),
    )


def load_validated_committee_fec_crosswalk(crosswalk_path: Path) -> pl.DataFrame:
    crosswalk = pl.read_csv(
        crosswalk_path,
        infer_schema_length=10000,
        schema_overrides={
            "candidate_id": pl.String,
            "committee_id": pl.String,
            "congress": pl.Int64,
            "district": pl.Int64,
        },
    )
    if "manual_validation_required" not in crosswalk.columns:
        crosswalk = crosswalk.with_columns(
            pl.lit(None, dtype=pl.Boolean).alias("manual_validation_required")
        )
    return (
        crosswalk.with_columns(
            pl.col("congress").cast(pl.Int64, strict=False),
            pl.col("state_name")
            .cast(pl.String)
            .str.to_uppercase()
            .str.strip_chars(),
            pl.col("district").cast(pl.Int64, strict=False),
            normalize_name_piece("last_name").alias("last_name"),
            pl.col("manual_validation_required")
            .cast(pl.String)
            .str.to_lowercase()
            .eq("true")
            .fill_null(False)
            .alias("_crosswalk_manual_validation_required"),
        )
        .group_by(SCANDAL_FEC_MATCH_KEYS)
        .agg(
            pl.col("candidate_id").drop_nulls().unique().sort().alias("_candidate_ids"),
            pl.col("committee_id").drop_nulls().unique().sort().alias("_committee_ids"),
            pl.col("fec_candidate_name")
            .drop_nulls()
            .unique()
            .sort()
            .alias("_fec_candidate_names"),
            pl.col("_crosswalk_manual_validation_required")
            .any()
            .alias("_crosswalk_manual_validation_required"),
        )
        .with_columns(
            pl.col("_candidate_ids").list.join("; ").alias("candidate_id"),
            pl.col("_committee_ids").list.join("; ").alias("committee_id"),
            pl.col("_fec_candidate_names").list.join("; ").alias("fec_candidate_name"),
            pl.when(
                pl.col("_crosswalk_manual_validation_required")
                | (pl.col("_candidate_ids").list.len() > 1)
            )
            .then(True)
            .otherwise(None)
            .alias("scandal_fec_manual_validation_required"),
        )
        .drop(
            [
                "_candidate_ids",
                "_committee_ids",
                "_fec_candidate_names",
                "_crosswalk_manual_validation_required",
            ]
        )
    )


def merge_scandals_with_fec_ids(
    scandals: pl.DataFrame,
    crosswalk_path: Path,
) -> pl.DataFrame:
    scandal_match_frame = add_scandal_match_fields(scandals)
    crosswalk = load_validated_committee_fec_crosswalk(crosswalk_path)
    return scandal_match_frame.join(crosswalk, on=SCANDAL_FEC_MATCH_KEYS, how="left")


def build_committee_assignment_fec_crosswalk(
    assignments: pl.DataFrame,
) -> pl.DataFrame:
    """Match assignments to FEC House candidates by parsed name and election year."""
    assignment = add_committee_assignment_match_fields(assignments)
    fec_candidates = load_fec_house_candidates_for_matching().rename(
        {"election_year": "match_election_year"}
    )
    match_keys = ["last_name", "match_election_year", "state_name", "district"]
    first_match = (
        assignment.with_columns(pl.col("election_year").alias("match_election_year"))
        .join(fec_candidates, on=match_keys, how="left")
    )
    special_match = (
        assignment.join(
            first_match.filter(pl.col("candidate_id").is_null()).select(
                ASSIGNMENT_MATCH_KEYS
            ),
            on=ASSIGNMENT_MATCH_KEYS,
            how="inner",
        )
        .with_columns((pl.col("election_year") + 2).alias("match_election_year"))
        .join(fec_candidates, on=match_keys, how="left")
    )
    crosswalk = (
        pl.concat(
            [
                add_candidate_match_validation_flag(
                    first_match.filter(pl.col("candidate_id").is_not_null())
                ),
                add_candidate_match_validation_flag(special_match),
            ],
            how="diagonal",
        )
        .sort(["congress", "committee_code", "id", "candidate_id"])
    )
    return add_candidate_committees(add_manual_candidates(crosswalk))


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    scandals = filter_scandals(args.min_scandal_year)
    assignments = filter_committee_assignments(args.min_congress)

    scandals.write_csv(
        args.output_dir
        / f"congressional_scandals_post_{args.min_scandal_year}.csv"
    )
    merge_scandals_with_fec_ids(scandals, args.validated_crosswalk).write_csv(
        args.output_dir
        / f"congressional_scandals_post_{args.min_scandal_year}_with_fec_ids.csv"
    )
    assignments.write_csv(
        args.output_dir
        / f"house_committee_assignments_{args.min_congress}_115.csv"
    )
    build_committee_assignment_fec_crosswalk(assignments).write_csv(
        args.output_dir
        / f"house_committee_assignments_fec_crosswalk_raw.csv"
    )


if __name__ == "__main__":
    main()
