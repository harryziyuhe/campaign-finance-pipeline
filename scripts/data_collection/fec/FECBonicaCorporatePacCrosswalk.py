"""
Build a DIME bonica.rid to FEC corporate PAC committee ID crosswalk.

Reads corporate PAC committee names from data/raw/fec_bulk/cpac and DIME
individual contribution parquet files from data/raw/dime. The corporate PAC
list is retained as the main file, with matching DIME bonica.rid values attached
when exact normalized committee names match. Writes per-cycle and combined
crosswalk CSV files back to data/raw/dime.
"""

"""
Additional Notes:
1. NATIONAL CITY CORPORATION has 2 PACs over the same period (2001-2006). C00365619 is inactive and needs to be removed
2. C00473025 acquired C00316331 in 2016, but name change is not uniform in the two datasets. So needs to update the matching of C00473025 in 2016
3. C00367789 is a company PAC for state activity. It sometimes transfer money to the federal PAC 
4. There is a tricky case where both Baxalta (Baxter C00578336) and Shire Holdings (C00610592) created their respective PACs in 2015, 
    but in 2016 Shire Holdings acquired Baxalta and started using only the aquired PAC. To avoid double matching, I am removing C00610592
    from the crosswalk file, since the disbursement of C00610592 is not considered in the workflow.
5. 
"""

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
DIME_PATH = DATA_ROOT / "data" / "raw" / "dime"
CORPORATE_PACS_PATH = (
    DATA_ROOT / "data" / "raw" / "fec_bulk" / "cpac" / "corporate_pacs_list.csv"
)
PAC_MATCH_FILE = DATA_ROOT / "data" / "processed" / "fec" / "corporate_pac_firm_matches.csv"
OUTPUT_STEM = "bonica_rid_corporate_pac_crosswalk"
AGGREGATE_OUTPUT = DIME_PATH / f"{OUTPUT_STEM}_aggregated.csv"
CYCLE_FILE_PATTERN = re.compile(r"individual_contribution_(\d{4})\.parquet$")


def normalize_name(column: str) -> pl.Expr:
    return (
        pl.col(column)
        .cast(pl.Utf8)
        .str.to_uppercase()
        .str.replace_all(r"[^A-Z0-9]", " ")
        .str.replace_all(r"\s+", " ")
        .str.strip_chars()
    )


def parse_cycle(path: Path) -> int:
    match = CYCLE_FILE_PATTERN.match(path.name)
    if match is None:
        raise ValueError(f"Could not parse DIME cycle from {path.name}")
    return int(match.group(1))


def list_dime_cycle_files(dime_path: Path) -> list[Path]:
    return sorted(
        path
        for path in dime_path.glob("individual_contribution_*.parquet")
        if CYCLE_FILE_PATTERN.match(path.name)
    )


def load_corporate_pacs(path: Path) -> pl.DataFrame:
    return (
        pl.read_csv(
            path,
            schema_overrides={
                "CMTE_ID": pl.Utf8,
                "YEAR": pl.Int64,
                "CMTE_NM": pl.Utf8,
                "CONNECTED_ORG_NM": pl.Utf8,
            },
        )
        .rename({"YEAR": "cycle"})
        .with_columns(normalize_name("CMTE_NM").alias("cmte_name_key"))
        .unique()
    )


def collect_dime_committee_pairs(path: Path, cycle: int) -> pl.DataFrame:
    return (
        pl.scan_parquet(path)
        .filter(
            pl.col("bonica.rid")
            .cast(pl.Utf8)
            .str.to_lowercase()
            .str.contains("comm")
        )
        .select(
            [
                pl.lit(cycle).alias("cycle"),
                pl.col("recipient.name").cast(pl.Utf8),
                pl.col("bonica.rid").cast(pl.Utf8),
                pl.lit(path.name).alias("source_file"),
            ]
        )
        .unique()
        .with_columns(normalize_name("recipient.name").alias("recipient_name_key"))
        .collect()
    )


def match_cycle(
    dime_file: Path,
    corporate_pacs: pl.DataFrame,
) -> pl.DataFrame:
    cycle = parse_cycle(dime_file)
    dime_pairs = collect_dime_committee_pairs(dime_file, cycle)
    corporate_cycle = corporate_pacs.filter(pl.col("cycle") == cycle)

    return (
        corporate_cycle.join(
            dime_pairs,
            left_on=["cycle", "cmte_name_key"],
            right_on=["cycle", "recipient_name_key"],
            how="left",
        )
        .with_columns(pl.col("bonica.rid").is_not_null().alias("matched"))
        .select(
            [
                "cycle",
                "CMTE_ID",
                "CMTE_NM",
                "cmte_name_key",
                "CONNECTED_ORG_NM",
                "bonica.rid",
                "recipient.name",
                "matched",
                "source_file",
            ]
        )
    )


def add_multiple_match_flags(crosswalk: pl.DataFrame) -> pl.DataFrame:
    match_counts = (
        crosswalk.filter(pl.col("bonica.rid").is_not_null())
        .group_by("bonica.rid")
        .agg(pl.col("CMTE_ID").n_unique().alias("matched_cmte_id_count"))
    )

    return (
        crosswalk.join(match_counts, on="bonica.rid", how="left")
        .with_columns(
            [
                pl.col("matched_cmte_id_count").fill_null(0),
                (pl.col("matched_cmte_id_count") > 1).alias(
                    "multiple_cmte_nm_for_bonica_rid"
                ),
            ]
        )
        .sort(["CMTE_ID", "cycle", "CMTE_NM", "bonica.rid"])
    )


def write_crosswalks(crosswalk: pl.DataFrame, dime_path: Path) -> None:
    combined_path = dime_path / f"{OUTPUT_STEM}.csv"
    crosswalk.write_csv(combined_path)

    for cycle in crosswalk["cycle"].unique().sort():
        cycle_crosswalk = crosswalk.filter(pl.col("cycle") == cycle)
        cycle_path = dime_path / f"{OUTPUT_STEM}_{cycle}.csv"
        cycle_crosswalk.write_csv(cycle_path)


def load_valid_corporate_pac_ids(path: Path = PAC_MATCH_FILE) -> pl.DataFrame:
    return (
        pl.read_csv(path, columns=["cmte_id"], schema_overrides={"cmte_id": pl.Utf8})
        .select(pl.col("cmte_id").str.strip_chars().str.to_uppercase().alias("CMTE_ID"))
        .filter(pl.col("CMTE_ID").is_not_null() & (pl.col("CMTE_ID") != ""))
        .unique()
    )


def aggregate_crosswalk(
    crosswalk_path: Path = DIME_PATH / f"{OUTPUT_STEM}.csv",
    output_path: Path | None = AGGREGATE_OUTPUT,
    pac_match_path: Path = PAC_MATCH_FILE,
) -> pl.DataFrame:
    valid_corporate_pac_ids = load_valid_corporate_pac_ids(pac_match_path)
    crosswalk = (
        pl.read_csv(
            crosswalk_path,
            schema_overrides={
                "cycle": pl.Int64,
                "CMTE_ID": pl.Utf8,
                "bonica.rid": pl.Utf8,
            },
        )
        .select(["cycle", "CMTE_ID", "bonica.rid"])
        .with_columns(
            pl.col("CMTE_ID").str.strip_chars().str.to_uppercase(),
            pl.col("bonica.rid").str.strip_chars(),
        )
        .join(valid_corporate_pac_ids, on="CMTE_ID", how="inner")
    )

    valid_bonica_rid = (
        pl.col("bonica.rid").is_not_null()
        & ~pl.col("bonica.rid").str.to_lowercase().is_in(["", "none", "null", "nan"])
    )

    valid_matches = crosswalk.filter(valid_bonica_rid).unique()
    nonempty_pairs = valid_matches.select(["cycle", "CMTE_ID"]).unique()
    empty_pairs = (
        crosswalk.select(["cycle", "CMTE_ID"])
        .unique()
        .join(nonempty_pairs, on=["cycle", "CMTE_ID"], how="anti")
    )

    fill_candidates = (
        empty_pairs.join(
            valid_matches.rename({"cycle": "source_cycle"}),
            on="CMTE_ID",
            how="left",
        )
        .with_columns(
            (pl.col("cycle") - pl.col("source_cycle"))
            .abs()
            .alias("cycle_distance")
        )
    )
    nearest_distances = fill_candidates.group_by(["cycle", "CMTE_ID"]).agg(
        pl.col("cycle_distance").min().alias("nearest_cycle_distance")
    )

    filled_matches = (
        fill_candidates.join(nearest_distances, on=["cycle", "CMTE_ID"], how="left")
        .filter(
            (pl.col("cycle_distance") == pl.col("nearest_cycle_distance"))
            | pl.col("nearest_cycle_distance").is_null()
        )
        .select(["cycle", "CMTE_ID", "bonica.rid"])
        .unique()
    )

    aggregate = pl.concat([valid_matches, filled_matches]).sort(
        ["CMTE_ID", "cycle", "bonica.rid"]
    )
    if output_path is not None:
        aggregate.write_csv(output_path)
    return aggregate


def build_crosswalk() -> pl.DataFrame:
    corporate_pacs = load_corporate_pacs(CORPORATE_PACS_PATH)
    dime_files = list_dime_cycle_files(DIME_PATH)
    if not dime_files:
        raise FileNotFoundError(f"No DIME parquet files found in {DIME_PATH}")

    cycle_matches = [match_cycle(dime_file, corporate_pacs) for dime_file in dime_files]
    crosswalk = add_multiple_match_flags(pl.concat(cycle_matches, how="vertical"))
    write_crosswalks(crosswalk, DIME_PATH)
    return crosswalk

if __name__ == "__main__":
    # build_crosswalk()
    # After building the crosswalk, I will need to manually review the matches and update the corporate PAC list as needed to improve matching.
    # Then run the aggregate crosswalk function to produce a simpler crosswalk file.
    aggregate_crosswalk()
