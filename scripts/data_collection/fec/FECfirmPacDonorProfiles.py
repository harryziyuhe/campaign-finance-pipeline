from __future__ import annotations

"""Staged corporate-PAC donor profile pipeline.

The pipeline deliberately separates employer-alias review from raw-file person
matching. First, observed employer-PAC pairs are extracted from known corporate
PAC donor records. After manual review, approved aliases are used to search the
large raw FEC individual files one source file at a time.
"""

import argparse
import gc
import os
from pathlib import Path

import polars as pl
from tqdm import tqdm


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
PAC_DONOR_DIR = DATA_ROOT / "data" / "processed" / "fec" / "individual_to_firm_pac_contributions"
RAW_INDIVIDUAL_DIR = DATA_ROOT / "data" / "raw" / "fec_bulk" / "contributions" / "individual"
PAC_MATCH_FILE = DATA_ROOT / "data" / "processed" / "fec" / "corporate_pac_firm_matches.csv"
OUTPUT_DIR = DATA_ROOT / "data" / "processed" / "fec" / "firm_pac_donor_profiles"

ACCEPTED_MANUAL_STATUSES = ["own_firm", "subsidiary_or_affiliate"]
INVALID_COMPANY_ALIASES = [
    "",
    "n a",
    "na",
    "none",
    "not applicable",
    "not employed",
    "null",
    "retired",
    "retiree",
    "self",
    "self employed",
    "unemployed",
    "unknown",
]

LEGAL_SUFFIX_PATTERN = (
    r"\b(the|and|inc|incorporated|corp|corporation|co|company|cos|companies|"
    r"llc|ltd|limited|plc|lp|llp|group|holdings|holding|international|"
    r"industries|services|systems|technologies|technology|usa|us|na)\b"
)
PAC_WORD_PATTERN = r"\b(federal|political|committee|action|election|pac|better|government)\b"
RETIREE_PATTERN = (
    r"\b(retired|retiree|retirement|none|not employed|unemployed|self|self-employed|"
    r"self employed|n/a|na|not applicable)\b"
)
STANDALONE_CHAIR_PATTERN = r"^\s*(chair|chairman|chairwoman|chairperson|board chair)\s*$"
FAMILY_PATTERN = r"\b(spouse|wife|husband|homemaker|home maker|family|housewife|house husband)\b"

NICKNAME_CANONICAL = {
    "alex": "alexander",
    "andy": "andrew",
    "ben": "benjamin",
    "bill": "william",
    "bob": "robert",
    "bobby": "robert",
    "chris": "christopher",
    "dan": "daniel",
    "dave": "david",
    "ed": "edward",
    "jim": "james",
    "jimmy": "james",
    "joe": "joseph",
    "jon": "john",
    "kate": "katherine",
    "kathy": "katherine",
    "liz": "elizabeth",
    "matt": "matthew",
    "mike": "michael",
    "pat": "patrick",
    "rick": "richard",
    "rob": "robert",
    "ron": "ronald",
    "sam": "samuel",
    "steve": "steven",
    "sue": "susan",
    "ted": "edward",
    "tim": "timothy",
    "tom": "thomas",
    "tony": "anthony",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run staged firm-PAC donor profile processing."
    )
    parser.add_argument(
        "--stage",
        required=True,
        choices=[
            "extract-employer-pac-review",
            "build-approved-aliases",
            "search-raw-employees",
            "resolve-identities",
            "link-outside-giving",
        ],
    )
    parser.add_argument("--start-year", type=int, default=2004)
    parser.add_argument("--end-year", type=int, default=2024)
    parser.add_argument("--cycles", nargs="*", type=int)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    parser.add_argument("--review-file", type=Path)
    parser.add_argument("--sample-size", type=int, default=5)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def selected_cycles(args: argparse.Namespace) -> list[int]:
    if args.cycles:
        return sorted(set(args.cycles))
    return list(range(args.start_year, args.end_year + 2, 2))


def prepare_output(path: Path, overwrite: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if not overwrite:
            raise FileExistsError(f"{path} exists. Use --overwrite to replace it.")
        path.unlink()


def write_parquet(frame: pl.LazyFrame, path: Path, overwrite: bool) -> None:
    prepare_output(path, overwrite)
    frame.sink_parquet(path)


def write_csv(frame: pl.LazyFrame, path: Path, overwrite: bool) -> None:
    prepare_output(path, overwrite)
    frame.collect().write_csv(path)


def pac_donor_file_for_cycle(cycle: int) -> Path:
    return PAC_DONOR_DIR / f"cycle_{cycle}" / f"individual_{cycle}.parquet"


def raw_files_for_cycle(cycle: int) -> list[Path]:
    split_dir = RAW_INDIVIDUAL_DIR / f"individual_{cycle}"
    if split_dir.exists():
        split_files = sorted(split_dir.glob("*.parquet"))
        if split_files:
            return split_files

    single_file = RAW_INDIVIDUAL_DIR / f"individual_{cycle}.parquet"
    return [single_file] if single_file.exists() else []


def clean_text_expr(column: str | pl.Expr) -> pl.Expr:
    expr = pl.col(column) if isinstance(column, str) else column
    return (
        expr.cast(pl.String)
        .str.to_lowercase()
        .str.replace_all(r"[^a-z0-9\s]", " ")
        .str.replace_all(r"\s+", " ")
        .str.strip_chars()
    )


def clean_company_expr(column: str | pl.Expr) -> pl.Expr:
    return (
        clean_text_expr(column)
        .str.replace_all(LEGAL_SUFFIX_PATTERN, " ")
        .str.replace_all(PAC_WORD_PATTERN, " ")
        .str.replace_all(r"\s+", " ")
        .str.strip_chars()
    )


def cleaned_name_piece(expr: pl.Expr) -> pl.Expr:
    return (
        expr.cast(pl.String)
        .str.to_lowercase()
        .str.replace_all(r"[^a-z\s]", " ")
        .str.replace_all(r"\b(jr|sr|ii|iii|iv|v)\b", " ")
        .str.replace_all(r"\s+", " ")
        .str.strip_chars()
    )


def add_name_fields(frame: pl.LazyFrame) -> pl.LazyFrame:
    split_name = pl.col("NAME").cast(pl.String).str.split_exact(",", 1)
    return (
        frame.with_columns(
            split_name.struct.field("field_0").alias("_raw_last_name"),
            split_name.struct.field("field_1").alias("_raw_given_names"),
        )
        .with_columns(
            cleaned_name_piece(pl.col("_raw_last_name")).alias("last_name"),
            cleaned_name_piece(pl.col("_raw_given_names")).alias("_clean_given_names"),
        )
        .with_columns(
            pl.col("_clean_given_names")
            .str.split(" ")
            .list.get(0, null_on_oob=True)
            .alias("first_name"),
        )
        .with_columns(
            pl.col("first_name").replace(NICKNAME_CANONICAL).alias("canonical_first_name"),
            pl.col("first_name").str.slice(0, 1).alias("first_initial"),
            clean_text_expr("CITY").alias("city_norm"),
            clean_text_expr("STATE").alias("state_norm"),
            pl.col("ZIP_CODE").cast(pl.String).str.extract(r"^(\d{5})", 1).alias("zip5"),
        )
        .drop(["_raw_last_name", "_raw_given_names", "_clean_given_names"])
    )


def add_exclusion_flags(frame: pl.LazyFrame) -> pl.LazyFrame:
    employer = clean_text_expr("EMPLOYER")
    occupation = clean_text_expr("OCCUPATION")
    return frame.with_columns(
        (employer.str.contains(RETIREE_PATTERN) | occupation.str.contains(RETIREE_PATTERN)).alias(
            "is_retiree_like"
        ),
        occupation.str.contains(STANDALONE_CHAIR_PATTERN).alias("is_board_exec_like"),
        (employer.str.contains(FAMILY_PATTERN) | occupation.str.contains(FAMILY_PATTERN)).alias(
            "is_family_like"
        ),
    ).with_columns(
        (
            pl.col("is_retiree_like")
            | pl.col("is_board_exec_like")
            | pl.col("is_family_like")
        ).alias("is_excluded_profile")
    )


def firm_id_expr() -> pl.Expr:
    fallback = clean_company_expr("corporation")
    permid = pl.col("permid").cast(pl.String).str.strip_chars()
    ric = pl.col("ric").cast(pl.String).str.strip_chars()
    return (
        pl.when(permid.is_not_null() & (permid != ""))
        .then(pl.concat_str([pl.lit("permid:"), permid]))
        .when(ric.is_not_null() & (ric != ""))
        .then(pl.concat_str([pl.lit("ric:"), ric]))
        .when(fallback.is_not_null() & (fallback != ""))
        .then(pl.concat_str([pl.lit("corp:"), fallback]))
        .otherwise(pl.concat_str([pl.lit("cmte:"), pl.col("cmte_id").cast(pl.String).str.strip_chars()]))
    )


def load_pac_matches(cycle: int | None = None) -> pl.LazyFrame:
    frame = (
        pl.scan_csv(
            PAC_MATCH_FILE,
            schema_overrides={
                "cmte_id": pl.String,
                "cmte_nm": pl.String,
                "connected_org_nm": pl.String,
                "corporation": pl.String,
                "year": pl.Int64,
                "ric": pl.String,
                "permid": pl.String,
                "parent": pl.String,
                "website": pl.String,
                "ttl_receipts": pl.String,
            },
        )
        .with_columns(
            pl.col("cmte_id").cast(pl.String).str.strip_chars().alias("cmte_id"),
            firm_id_expr().alias("firm_id"),
            clean_company_expr("corporation").alias("corporation_norm"),
            clean_company_expr("connected_org_nm").alias("connected_org_norm"),
            clean_company_expr("parent").alias("parent_norm"),
        )
    )
    return frame.filter(pl.col("year") == cycle) if cycle is not None else frame


def pac_donor_rows(cycle: int) -> pl.LazyFrame:
    path = pac_donor_file_for_cycle(cycle)
    if not path.exists():
        return pl.LazyFrame()

    donors = (
        pl.scan_parquet(path)
        .with_columns(
            pl.lit(cycle, dtype=pl.Int64).alias("cycle"),
            pl.col("CMTE_ID").cast(pl.String).str.strip_chars(),
            clean_company_expr("EMPLOYER").alias("employer_norm"),
        )
        .join(
            load_pac_matches(cycle),
            left_on=["CMTE_ID", "cycle"],
            right_on=["cmte_id", "year"],
            how="inner",
        )
    )
    return add_exclusion_flags(add_name_fields(donors))


def triad_path(output_dir: Path, cycle: int) -> Path:
    return output_dir / "pac_donor_employer_triads" / f"cycle_{cycle}.parquet"


def review_path(output_dir: Path) -> Path:
    return output_dir / "employer_pac_alias_review.csv"


def approved_alias_path(output_dir: Path) -> Path:
    return output_dir / "approved_employer_pac_firm_aliases.parquet"


def approved_alias_csv_path(output_dir: Path) -> Path:
    return output_dir / "approved_employer_pac_firm_aliases.csv"


def raw_employee_part_path(output_dir: Path, cycle: int, raw_file: Path) -> Path:
    return output_dir / "raw_firm_employee_contributions" / f"cycle_{cycle}" / f"{raw_file.stem}.parquet"


def identity_link_part_path(output_dir: Path, cycle: int, part_file: Path) -> Path:
    return output_dir / "identity_links" / f"cycle_{cycle}" / part_file.name


def person_index_path(output_dir: Path, cycle: int) -> Path:
    return output_dir / "person_firm_cycle_index" / f"cycle_{cycle}.parquet"


def outside_part_path(output_dir: Path, cycle: int, part_file: Path) -> Path:
    return output_dir / "linked_outside_giving" / f"cycle_{cycle}" / part_file.name


def employer_review_rows(cycles: list[int], sample_size: int) -> pl.LazyFrame:
    frames = []
    for cycle in cycles:
        donors = pac_donor_rows(cycle)
        if len(donors.collect_schema()) == 0:
            continue

        triads = donor_triads(donors)
        frames.append(employer_review_for_triads(triads, sample_size))

    if not frames:
        return pl.LazyFrame()
    return pl.concat(frames, how="diagonal_relaxed").sort(["cycle", "CMTE_ID", "employer_norm"])


def donor_triads(donors: pl.LazyFrame) -> pl.LazyFrame:
    return (
        donors.filter(
            pl.col("employer_norm").is_not_null()
            & (~pl.col("employer_norm").is_in(INVALID_COMPANY_ALIASES))
            & pl.col("last_name").is_not_null()
            & (pl.col("last_name") != "")
            & pl.col("first_name").is_not_null()
            & (pl.col("first_name") != "")
        )
        .group_by(
            [
                "cycle",
                "firm_id",
                "CMTE_ID",
                "cmte_nm",
                "corporation",
                "connected_org_nm",
                "ric",
                "permid",
                "parent",
                "corporation_norm",
                "connected_org_norm",
                "parent_norm",
                "NAME",
                "last_name",
                "first_name",
                "canonical_first_name",
                "EMPLOYER",
                "employer_norm",
                "OCCUPATION",
            ]
        )
        .agg(
            pl.len().alias("pac_contribution_rows"),
            pl.col("TRANSACTION_AMT").cast(pl.Float64).sum().alias("pac_contribution_amount"),
            pl.col("is_retiree_like").max().alias("is_retiree_like"),
            pl.col("is_board_exec_like").max().alias("is_board_exec_like"),
            pl.col("is_family_like").max().alias("is_family_like"),
        )
    )


def employer_review_for_triads(triads: pl.LazyFrame, sample_size: int) -> pl.LazyFrame:
    return (
        triads.with_columns(
            (pl.col("employer_norm") == pl.col("corporation_norm")).alias("matches_corporation"),
            (pl.col("employer_norm") == pl.col("connected_org_norm")).alias("matches_connected_org"),
            (pl.col("employer_norm") == pl.col("parent_norm")).alias("matches_parent"),
        )
        .group_by(
            [
                "cycle",
                "firm_id",
                "CMTE_ID",
                "cmte_nm",
                "corporation",
                "connected_org_nm",
                "ric",
                "permid",
                "parent",
                "corporation_norm",
                "connected_org_norm",
                "parent_norm",
                "EMPLOYER",
                "employer_norm",
            ]
        )
        .agg(
            pl.col("NAME").n_unique().alias("unique_pac_contributors"),
            pl.col("pac_contribution_rows").sum().alias("pac_contribution_rows"),
            pl.col("pac_contribution_amount").sum().alias("pac_contribution_amount"),
            pl.col("OCCUPATION").drop_nulls().unique().sort().head(sample_size).alias("sample_occupations"),
            pl.col("NAME").drop_nulls().unique().sort().head(sample_size).alias("sample_names"),
            pl.col("matches_corporation").max().alias("matches_corporation"),
            pl.col("matches_connected_org").max().alias("matches_connected_org"),
            pl.col("matches_parent").max().alias("matches_parent"),
            pl.col("is_retiree_like").max().alias("any_retiree_like"),
            pl.col("is_board_exec_like").max().alias("any_board_exec_like"),
            pl.col("is_family_like").max().alias("any_family_like"),
        )
        .with_columns(
            pl.when(pl.col("employer_norm").is_in(INVALID_COMPANY_ALIASES))
            .then(pl.lit("invalid_placeholder"))
            .when(
                pl.col("matches_corporation")
                | pl.col("matches_connected_org")
                | pl.col("matches_parent")
            )
            .then(pl.lit("own_firm"))
            .otherwise(pl.lit("unclear"))
            .alias("suggested_status"),
            pl.lit("").alias("manual_status"),
            pl.lit("").alias("manual_firm_alias"),
            pl.lit("").alias("manual_notes"),
        )
        .with_columns(
            pl.col("sample_occupations").list.join("; ").alias("sample_occupations"),
            pl.col("sample_names").list.join("; ").alias("sample_names"),
        )
    )


def stage_extract_employer_pac_review(args: argparse.Namespace) -> None:
    review_frames = []
    for cycle in tqdm(selected_cycles(args), desc="Extracting PAC donor employer triads"):
        donors = pac_donor_rows(cycle)
        if len(donors.collect_schema()) == 0:
            continue

        triads = donor_triads(donors)
        write_parquet(triads, triad_path(args.output_dir, cycle), args.overwrite)
        review_frames.append(employer_review_for_triads(triads, args.sample_size))

    if review_frames:
        review = pl.concat(review_frames, how="diagonal_relaxed").sort(
            ["cycle", "CMTE_ID", "employer_norm"]
        )
    else:
        review = pl.LazyFrame()
    write_csv(review, review_path(args.output_dir), args.overwrite)


def stage_build_approved_aliases(args: argparse.Namespace) -> None:
    input_file = args.review_file or review_path(args.output_dir)
    review = pl.read_csv(input_file, infer_schema_length=10000)
    if "manual_status" not in review.columns:
        raise ValueError("Review file must contain a manual_status column.")

    approved = (
        review.lazy()
        .with_columns(
            clean_text_expr("manual_status").str.replace_all(" ", "_").alias("manual_status_norm"),
            pl.when(clean_text_expr("manual_firm_alias").is_not_null() & (clean_text_expr("manual_firm_alias") != ""))
            .then(pl.col("manual_firm_alias").cast(pl.String))
            .otherwise(pl.col("EMPLOYER").cast(pl.String))
            .alias("approved_employer_alias"),
        )
        .with_columns(clean_company_expr("approved_employer_alias").alias("approved_employer_norm"))
        .filter(
            pl.col("manual_status_norm").is_in(ACCEPTED_MANUAL_STATUSES)
            & pl.col("approved_employer_norm").is_not_null()
            & (~pl.col("approved_employer_norm").is_in(INVALID_COMPANY_ALIASES))
        )
        .select(
            "cycle",
            "firm_id",
            "CMTE_ID",
            "cmte_nm",
            "corporation",
            "connected_org_nm",
            "ric",
            "permid",
            "parent",
            "approved_employer_alias",
            "approved_employer_norm",
            "manual_status_norm",
            "manual_notes",
            "unique_pac_contributors",
            "pac_contribution_rows",
            "pac_contribution_amount",
        )
        .unique(["cycle", "firm_id", "CMTE_ID", "approved_employer_norm"])
        .sort(["cycle", "CMTE_ID", "approved_employer_norm"])
    )
    write_parquet(approved, approved_alias_path(args.output_dir), args.overwrite)
    write_csv(approved, approved_alias_csv_path(args.output_dir), args.overwrite)


def approved_aliases_for_cycle(output_dir: Path, cycle: int) -> pl.LazyFrame:
    path = approved_alias_path(output_dir)
    if not path.exists():
        raise FileNotFoundError(f"Missing approved aliases: {path}")
    return pl.scan_parquet(path).filter(pl.col("cycle") == cycle)


def raw_employee_matches(cycle: int, raw_file: Path, aliases: pl.LazyFrame) -> pl.LazyFrame:
    raw = (
        pl.scan_parquet(raw_file)
        .with_row_index("raw_row_id")
        .with_columns(
            pl.lit(cycle, dtype=pl.Int64).alias("cycle"),
            pl.lit(str(raw_file.relative_to(DATA_ROOT))).alias("source_file"),
            pl.col("CMTE_ID").cast(pl.String).str.strip_chars(),
            clean_company_expr("EMPLOYER").alias("employer_norm"),
        )
    )
    raw = add_exclusion_flags(add_name_fields(raw))

    return (
        raw.filter(
            pl.col("employer_norm").is_not_null()
            & (~pl.col("employer_norm").is_in(INVALID_COMPANY_ALIASES))
            & pl.col("last_name").is_not_null()
            & (pl.col("last_name") != "")
            & pl.col("first_name").is_not_null()
            & (pl.col("first_name") != "")
        )
        .join(
            aliases,
            left_on=["cycle", "employer_norm"],
            right_on=["cycle", "approved_employer_norm"],
            how="inner",
        )
        .with_columns(pl.col("employer_norm").alias("approved_employer_norm"))
        .with_columns(
            pl.len().over(["source_file", "raw_row_id"]).alias("alias_match_count"),
        )
        .with_columns((pl.col("alias_match_count") > 1).alias("is_ambiguous_employer_alias"))
    )


def stage_search_raw_employees(args: argparse.Namespace) -> None:
    records = []
    for cycle in tqdm(selected_cycles(args), desc="Searching raw FEC employee rows"):
        aliases = approved_aliases_for_cycle(args.output_dir, cycle)
        for raw_file in tqdm(raw_files_for_cycle(cycle), desc=f"Cycle {cycle}", leave=False):
            output = raw_employee_part_path(args.output_dir, cycle, raw_file)
            matches = raw_employee_matches(cycle, raw_file, aliases)
            write_parquet(matches, output, args.overwrite)
            records.append(
                {
                    "cycle": cycle,
                    "source_file": str(raw_file.relative_to(DATA_ROOT)),
                    "output_file": str(output.relative_to(DATA_ROOT)),
                }
            )
            del matches
            gc.collect()

    if records:
        manifest = pl.DataFrame(records).lazy()
        write_csv(manifest, args.output_dir / "raw_employee_search_manifest.csv", args.overwrite)


def person_id_expr() -> pl.Expr:
    return pl.concat_str(
        [
            pl.col("cycle").cast(pl.String),
            pl.lit("|"),
            pl.col("firm_id"),
            pl.lit("|"),
            pl.col("last_name"),
            pl.lit("|"),
            pl.col("canonical_first_name"),
        ]
    )


def employee_parts_for_cycle(output_dir: Path, cycle: int) -> list[Path]:
    folder = output_dir / "raw_firm_employee_contributions" / f"cycle_{cycle}"
    return sorted(folder.glob("*.parquet")) if folder.exists() else []


def stage_resolve_identities(args: argparse.Namespace) -> None:
    for cycle in tqdm(selected_cycles(args), desc="Resolving person-firm-cycle identities"):
        parts = employee_parts_for_cycle(args.output_dir, cycle)
        if not parts:
            continue

        all_links = (
            pl.scan_parquet(parts)
            .with_columns(person_id_expr().alias("person_firm_cycle_id"))
        )
        person_index = (
            all_links.group_by(["cycle", "firm_id", "person_firm_cycle_id"])
            .agg(
                pl.col("NAME").drop_nulls().unique().sort().alias("observed_names"),
                pl.col("EMPLOYER").drop_nulls().unique().sort().alias("observed_employers"),
                pl.col("approved_employer_alias").drop_nulls().unique().sort().alias("approved_aliases"),
                pl.col("approved_employer_norm").drop_nulls().unique().sort().alias("approved_alias_norms"),
                pl.col("CITY").drop_nulls().unique().sort().head(args.sample_size).alias("sample_cities"),
                pl.col("STATE").drop_nulls().unique().sort().alias("states"),
                pl.col("zip5").drop_nulls().unique().sort().head(args.sample_size).alias("sample_zip5s"),
                pl.col("is_ambiguous_employer_alias").max().alias("has_ambiguous_employer_alias"),
                pl.col("is_excluded_profile").max().alias("has_excluded_profile"),
                pl.len().alias("raw_contribution_rows"),
                pl.col("TRANSACTION_AMT").cast(pl.Float64).sum().alias("raw_contribution_amount"),
            )
            .sort(["cycle", "firm_id", "person_firm_cycle_id"])
        )
        write_parquet(person_index, person_index_path(args.output_dir, cycle), args.overwrite)

        for part in tqdm(parts, desc=f"Cycle {cycle} identity parts", leave=False):
            links = pl.scan_parquet(part).with_columns(person_id_expr().alias("person_firm_cycle_id"))
            write_parquet(links, identity_link_part_path(args.output_dir, cycle, part), args.overwrite)
            del links
            gc.collect()


def pac_donor_people(output_dir: Path, cycle: int) -> pl.LazyFrame:
    triads = pl.scan_parquet(triad_path(output_dir, cycle))
    aliases = approved_aliases_for_cycle(output_dir, cycle).select(
        "cycle",
        "firm_id",
        "CMTE_ID",
        "approved_employer_norm",
    )
    return (
        triads.join(
            aliases,
            left_on=["cycle", "firm_id", "CMTE_ID", "employer_norm"],
            right_on=["cycle", "firm_id", "CMTE_ID", "approved_employer_norm"],
            how="inner",
        )
        .with_columns(person_id_expr().alias("person_firm_cycle_id"))
        .select("cycle", "firm_id", "person_firm_cycle_id", "CMTE_ID")
        .unique()
        .with_columns(pl.lit(True).alias("is_firm_pac_donor"))
    )


def firm_pac_committees(output_dir: Path, cycle: int) -> pl.LazyFrame:
    return (
        approved_aliases_for_cycle(output_dir, cycle)
        .select("cycle", "firm_id", "CMTE_ID")
        .unique()
        .with_columns(pl.lit(True).alias("is_own_firm_pac_committee"))
    )


def identity_link_parts_for_cycle(output_dir: Path, cycle: int) -> list[Path]:
    folder = output_dir / "identity_links" / f"cycle_{cycle}"
    return sorted(folder.glob("*.parquet")) if folder.exists() else []


def stage_link_outside_giving(args: argparse.Namespace) -> None:
    for cycle in tqdm(selected_cycles(args), desc="Linking outside giving"):
        donor_people = pac_donor_people(args.output_dir, cycle).select(
            "cycle",
            "firm_id",
            "person_firm_cycle_id",
            "is_firm_pac_donor",
        ).unique()
        own_pacs = firm_pac_committees(args.output_dir, cycle)

        for part in tqdm(identity_link_parts_for_cycle(args.output_dir, cycle), desc=f"Cycle {cycle}", leave=False):
            linked = (
                pl.scan_parquet(part)
                .join(
                    donor_people,
                    on=["cycle", "firm_id", "person_firm_cycle_id"],
                    how="left",
                )
                .join(own_pacs, on=["cycle", "firm_id", "CMTE_ID"], how="left")
                .with_columns(
                    pl.col("is_firm_pac_donor").fill_null(False),
                    pl.col("is_own_firm_pac_committee").fill_null(False),
                )
                .with_columns(
                    pl.when(pl.col("is_firm_pac_donor"))
                    .then(pl.lit("firm_pac_donor"))
                    .otherwise(pl.lit("same_firm_non_pac_donor"))
                    .alias("cohort"),
                    (~pl.col("is_own_firm_pac_committee")).alias("is_outside_contribution"),
                )
            )
            write_parquet(linked, outside_part_path(args.output_dir, cycle, part), args.overwrite)
            del linked
            gc.collect()


def main() -> None:
    args = parse_args()
    args.output_dir = args.output_dir.resolve()

    if args.stage == "extract-employer-pac-review":
        stage_extract_employer_pac_review(args)
    elif args.stage == "build-approved-aliases":
        stage_build_approved_aliases(args)
    elif args.stage == "search-raw-employees":
        stage_search_raw_employees(args)
    elif args.stage == "resolve-identities":
        stage_resolve_identities(args)
    elif args.stage == "link-outside-giving":
        stage_link_outside_giving(args)


if __name__ == "__main__":
    main()
