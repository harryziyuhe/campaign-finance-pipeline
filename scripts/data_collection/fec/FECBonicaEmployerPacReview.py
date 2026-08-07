from __future__ import annotations

"""Build and stage-review DIME employer-to-corporate-PAC rows.

Reads the aggregated Bonica/FEC corporate PAC crosswalk, DIME individual
contribution parquet files, and FEC corporate PAC metadata. The first stage
writes employer review rows; the second stage auto-matches obvious
organization/employer names; the third stage prepares unmatched rows for LLM
review after any manual edits to the unmatched CSV.
"""

"""
Manual work done to dime_employer_bonica_pac_unmatched.csv
1. Delete "C00003194", which is a non-profit
2. Delete "C00079681", which is a trade association
3. Delete "C00039941", which is a trade association
4. Delete "C00048579", which is a non-profit
5. Delete "C00109819", which is a trade association
6. Delete "C00280743", which is a trade group
7. Delete "C00298190", which is a trade association
8. Delete "C00304634", which is a trade association
9. Delete "C00323659", which is a trade association
10. Delete "C00357160", which is a homeowners association
11. Delete "C00408344", which is a government entity
12. Delete "C00410084", which is a trade association
13. Delete "C00202184", which is a trade association
14. Delete "C00016444", which is a trade association
15. Delete "C00214148", which is a trade association
16. Delete "C00343137", which is a trade association
17. Delete "C00507699", which is a trade association
18. Delete "C00401695", which is a trade association
19. Delete "C00547919", which is a trade association
20. Delete "C00587923", which is a trade association
21. Delete "C00161570", which is a trade association
22. Delete "C00397083", which is an unknown entity
23. Delete "C00237065", which is a trade association
24. Delete "C00683235", which is a trade association
25. Delete "C00375048", which is a trade association
26. Delete "C00379180", which is a trade association
27. Delete "C00139279", which is a trade association
28. Delete "C00143818", which is a cooperative
29. Delete "C00161604", which is a cooperative
30. Delete "C00220269", which is a cooperative
31. Delete "C00004952", which is a cooperative
"""

import argparse
import re
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
DIME_DIR = DATA_ROOT / "data" / "raw" / "dime"
CROSSWALK_FILE = DIME_DIR / "bonica_rid_corporate_pac_crosswalk_aggregated.csv"
PAC_FILE = DATA_ROOT / "data" / "raw" / "fec_bulk" / "cpac" / "corporate_pacs_list.csv"
OUTPUT_FILE = (
    DATA_ROOT
    / "data"
    / "raw"
    / "dime"
    / "dime_employer_bonica_pac_review.csv"
)
AUTO_MATCHED_FILE = DIME_DIR / "dime_employer_bonica_pac_auto_matched.csv"
UNMATCHED_FILE = DIME_DIR / "dime_employer_bonica_pac_unmatched.csv"
PROMPT_DIR = DIME_DIR / "dime_employer_bonica_pac_prompts"
CYCLE_FILE_PATTERN = re.compile(r"individual_contribution_(\d{4})\.parquet$")
BUSINESS_STOPWORDS = {
    "and",
    "co",
    "companies",
    "company",
    "corp",
    "corporate",
    "corporation",
    "group",
    "holding",
    "holdings",
    "inc",
    "incorporated",
    "industries",
    "international",
    "limited",
    "llc",
    "llp",
    "lp",
    "ltd",
    "na",
    "plc",
    "services",
    "systems",
    "technologies",
    "technology",
    "the",
    "us",
    "usa",
}
REVIEW_COLUMNS = [
    "cycle",
    "cmte_id",
    "cmte_nm",
    "connected_org_nm",
    "bonica.rid",
    "contributor_employer",
    "first_recipient_name",
    "row_count",
    "total_amount",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Aggregate DIME contributor employers linked to corporate PAC bonica.rid values."
    )
    parser.add_argument(
        "--stage",
        choices=["build-review", "auto-match", "generate-prompts"],
        default="build-review",
        help="Build the review CSV, run deterministic auto-matching, or prepare prompts.",
    )
    parser.add_argument("--start-year", type=int, default=2004)
    parser.add_argument("--end-year", type=int, default=2024)
    parser.add_argument("--output-file", type=Path, default=OUTPUT_FILE)
    parser.add_argument("--review-file", type=Path, default=OUTPUT_FILE)
    parser.add_argument("--matched-file", type=Path, default=AUTO_MATCHED_FILE)
    parser.add_argument("--unmatched-file", type=Path, default=UNMATCHED_FILE)
    parser.add_argument("--prompt-dir", type=Path, default=PROMPT_DIR)
    parser.add_argument("--prompt-chunk-size", type=int, default=500)
    return parser.parse_args()


def valid_string_expr(column: str) -> pl.Expr:
    cleaned = pl.col(column).cast(pl.String).str.strip_chars()
    return cleaned.is_not_null() & ~cleaned.str.to_lowercase().is_in(["", "none", "null", "nan"])


def clean_key_expr(column: str) -> pl.Expr:
    return pl.col(column).cast(pl.String).str.strip_chars()


def parse_cycle(path: Path) -> int:
    match = CYCLE_FILE_PATTERN.match(path.name)
    if match is None:
        raise ValueError(f"Could not parse DIME cycle from {path.name}")
    return int(match.group(1))


def list_dime_cycle_files(start_year: int, end_year: int) -> list[Path]:
    return sorted(
        path
        for path in DIME_DIR.glob("individual_contribution_*.parquet")
        if CYCLE_FILE_PATTERN.match(path.name)
        and start_year <= parse_cycle(path) <= end_year
    )


def load_crosswalk() -> pl.DataFrame:
    return (
        pl.read_csv(
            CROSSWALK_FILE,
            schema_overrides={
                "cycle": pl.Int64,
                "CMTE_ID": pl.String,
                "bonica.rid": pl.String,
            },
        )
        .rename({"CMTE_ID": "cmte_id"})
        .with_columns(
            clean_key_expr("cmte_id").alias("cmte_id"),
            clean_key_expr("bonica.rid").alias("bonica.rid"),
        )
        .filter(valid_string_expr("cmte_id") & valid_string_expr("bonica.rid"))
        .unique(["cycle", "cmte_id", "bonica.rid"])
    )


def load_pac_metadata() -> pl.DataFrame:
    return (
        pl.read_csv(
            PAC_FILE,
            schema_overrides={
                "YEAR": pl.Int64,
                "CMTE_ID": pl.String,
                "CMTE_NM": pl.String,
                "CONNECTED_ORG_NM": pl.String,
            },
        )
        .rename(
            {
                "YEAR": "cycle",
                "CMTE_ID": "cmte_id",
                "CMTE_NM": "cmte_nm",
                "CONNECTED_ORG_NM": "connected_org_nm",
            }
        )
        .with_columns(clean_key_expr("cmte_id").alias("cmte_id"))
        .unique(["cycle", "cmte_id"])
    )


def aggregate_cycle(path: Path, crosswalk: pl.DataFrame) -> pl.DataFrame:
    cycle = parse_cycle(path)
    cycle_bonica_ids = crosswalk.filter(pl.col("cycle") == cycle).select("bonica.rid").unique()
    return (
        pl.scan_parquet(path)
        .select(
            [
                pl.lit(cycle).alias("cycle"),
                clean_key_expr("contributor.employer").alias("contributor_employer"),
                clean_key_expr("bonica.rid").alias("bonica.rid"),
                pl.col("recipient.name").cast(pl.String).alias("first_recipient_name"),
                pl.col("amount").cast(pl.Float64).alias("amount"),
            ]
        )
        .join(cycle_bonica_ids.lazy(), on="bonica.rid", how="inner")
        .filter(valid_string_expr("contributor_employer"))
        .group_by(["cycle", "bonica.rid", "contributor_employer"])
        .agg(
            pl.col("first_recipient_name").drop_nulls().first(),
            pl.len().alias("row_count"),
            pl.col("amount").sum().alias("total_amount"),
        )
        .collect()
    )


def build_review_file(start_year: int, end_year: int) -> pl.DataFrame:
    crosswalk = load_crosswalk()
    dime_files = list_dime_cycle_files(start_year, end_year)
    if not dime_files:
        raise FileNotFoundError(f"No DIME contribution parquet files found in {DIME_DIR}")

    crosswalk_for_cycles = crosswalk.filter(
        pl.col("cycle").is_between(start_year, end_year)
    )

    employer_frames = [
        aggregate_cycle(path, crosswalk_for_cycles)
        for path in tqdm(dime_files, desc="Aggregating DIME employer pairs")
    ]
    employer_pairs = pl.concat(employer_frames, how="vertical")

    return (
        employer_pairs.join(crosswalk_for_cycles, on=["cycle", "bonica.rid"], how="left")
        .join(load_pac_metadata(), on=["cycle", "cmte_id"], how="left")
        .select(
            [
                "cycle",
                "cmte_id",
                "cmte_nm",
                "connected_org_nm",
                "bonica.rid",
                "contributor_employer",
                "first_recipient_name",
                "row_count",
                "total_amount",
            ]
        )
        .sort(["cycle", "cmte_id", "bonica.rid", "row_count"], descending=[False, False, False, True])
    )


def normalize_business_name(value: str | None) -> str:
    if value is None:
        return ""
    cleaned = re.sub(r"[^a-z0-9]+", " ", str(value).lower())
    words = [word for word in cleaned.split() if word not in BUSINESS_STOPWORDS]
    return " ".join(words)


def acronym(value: str | None) -> str:
    normalized = normalize_business_name(value)
    return "".join(word[0] for word in normalized.split())


def add_match_fields(review: pl.DataFrame) -> pl.DataFrame:
    return (
        review.with_columns(
            pl.col("connected_org_nm")
            .map_elements(normalize_business_name, return_dtype=pl.String)
            .alias("connected_org_norm"),
            pl.col("contributor_employer")
            .map_elements(normalize_business_name, return_dtype=pl.String)
            .alias("contributor_employer_norm"),
            pl.col("connected_org_nm")
            .map_elements(acronym, return_dtype=pl.String)
            .alias("connected_org_acronym"),
        )
        .with_columns(
            pl.col("contributor_employer_norm")
            .str.replace_all(r"\s+", "")
            .alias("contributor_employer_compact")
        )
        .with_columns(
            (
                (pl.col("connected_org_norm") != "")
                & (pl.col("connected_org_norm") == pl.col("contributor_employer_norm"))
            ).alias("is_exact_normalized_match"),
            (
                (pl.col("connected_org_acronym") != "")
                & (pl.col("connected_org_acronym") == pl.col("contributor_employer_compact"))
            ).alias("is_acronym_match"),
        )
        .with_columns(
            pl.when(pl.col("is_exact_normalized_match"))
            .then(pl.lit("exact_normalized"))
            .when(pl.col("is_acronym_match"))
            .then(pl.lit("connected_org_acronym"))
            .otherwise(None)
            .alias("match_method")
        )
    )


def unique_prompt_pairs(unmatched: pl.DataFrame) -> pl.DataFrame:
    return (
        unmatched.group_by(
            [
                "connected_org_nm",
                "contributor_employer",
                "connected_org_norm",
                "contributor_employer_norm",
            ]
        )
        .agg(
            pl.col("cmte_nm").drop_nulls().first().alias("example_cmte_nm"),
            pl.col("cmte_id").n_unique().alias("committee_count"),
            pl.col("cycle").n_unique().alias("cycle_count"),
            pl.col("row_count").sum().alias("total_rows"),
            pl.col("total_amount").sum().alias("total_amount"),
        )
        .sort(["total_rows", "total_amount"], descending=[True, True])
    )


def prompt_text(rows: list[dict]) -> str:
    lines = [
        "# Employer Match Review",
        "",
        "You are reviewing whether an employer string from individual contribution records refers to the PAC's connected organization.",
        "Each row is a unique connected-organization/employer pair collapsed across election cycles.",
        "Do not infer from year-specific context; decide only from the organization and employer names.",
        "",
        "Decision rules:",
        "- `keep`: true only if the employer is the same organization, a parent, subsidiary, or close affiliate of the connected organization.",
        "- `keep`: false for unrelated companies, generic employers, occupations, retirees, unions, governments, universities, nonprofits, consultants, or ambiguous text.",
        "- `hierarchy`: use `self`, `parent`, `subsidiary`, `affiliate`, `unrelated`, or `uncertain`.",
        "- `confidence`: use a number from 0 to 1. Use lower confidence when the match depends on abbreviation expansion or weak context.",
        "- Prefer `uncertain` with low confidence rather than guessing.",
        "",
        "Return CSV with columns: connected_org_nm,contributor_employer,keep,hierarchy,confidence,notes",
        "Preserve connected_org_nm and contributor_employer exactly as shown.",
        "",
        "Reference columns:",
        "- `connected_org_norm` and `contributor_employer_norm` are stopword-stripped normalized names.",
        "- `committee_count`, `cycle_count`, `total_rows`, and `total_amount` show how often this unique pair appears, but should not override the name-based decision.",
        "",
        "Rows:",
        "",
        "| connected_org_nm | contributor_employer | connected_org_norm | contributor_employer_norm | example_cmte_nm | committee_count | cycle_count | total_rows | total_amount |",
        "| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            "| {connected_org_nm} | {contributor_employer} | {connected_org_norm} | "
            "{contributor_employer_norm} | {example_cmte_nm} | {committee_count} | "
            "{cycle_count} | {total_rows} | {total_amount} |".format(
                connected_org_nm=str(row.get("connected_org_nm", "")).replace("|", " "),
                contributor_employer=str(row.get("contributor_employer", "")).replace("|", " "),
                connected_org_norm=str(row.get("connected_org_norm", "")).replace("|", " "),
                contributor_employer_norm=str(row.get("contributor_employer_norm", "")).replace("|", " "),
                example_cmte_nm=str(row.get("example_cmte_nm", "")).replace("|", " "),
                committee_count=row.get("committee_count", ""),
                cycle_count=row.get("cycle_count", ""),
                total_rows=row.get("total_rows", ""),
                total_amount=row.get("total_amount", ""),
            )
        )
    lines.append("")
    return "\n".join(lines)


def write_prompt_documents(unmatched: pl.DataFrame, prompt_dir: Path, chunk_size: int) -> None:
    if chunk_size < 1:
        raise ValueError("--prompt-chunk-size must be at least 1")

    prompt_dir.mkdir(parents=True, exist_ok=True)
    for path in prompt_dir.glob("unmatched_prompt_*.md"):
        path.unlink()

    prompt_pairs = unique_prompt_pairs(unmatched)
    prompt_columns = [
        "connected_org_nm",
        "contributor_employer",
        "connected_org_norm",
        "contributor_employer_norm",
        "example_cmte_nm",
        "committee_count",
        "cycle_count",
        "total_rows",
        "total_amount",
    ]
    rows = prompt_pairs.select(prompt_columns).to_dicts()
    for chunk_index, start in enumerate(range(0, len(rows), chunk_size), start=1):
        chunk = rows[start : start + chunk_size]
        prompt_path = prompt_dir / f"unmatched_prompt_{chunk_index:04d}.md"
        prompt_path.write_text(prompt_text(chunk), encoding="utf-8")


def generate_prompt_documents(
    unmatched_file: Path = UNMATCHED_FILE,
    prompt_dir: Path = PROMPT_DIR,
    prompt_chunk_size: int = 500,
) -> pl.DataFrame:
    unmatched = pl.read_csv(
        unmatched_file,
        schema_overrides={
            "cycle": pl.Int64,
            "cmte_id": pl.String,
            "cmte_nm": pl.String,
            "connected_org_nm": pl.String,
            "bonica.rid": pl.String,
            "contributor_employer": pl.String,
            "first_recipient_name": pl.String,
            "row_count": pl.Int64,
            "total_amount": pl.Float64,
            "connected_org_norm": pl.String,
            "contributor_employer_norm": pl.String,
        },
    )
    prompt_pairs = unique_prompt_pairs(unmatched)
    write_prompt_documents(unmatched, prompt_dir, prompt_chunk_size)
    return prompt_pairs


def auto_match_review_file(
    review_file: Path = OUTPUT_FILE,
    matched_file: Path = AUTO_MATCHED_FILE,
    unmatched_file: Path = UNMATCHED_FILE,
) -> tuple[pl.DataFrame, pl.DataFrame]:
    review = pl.read_csv(
        review_file,
        schema_overrides={
            "cycle": pl.Int64,
            "cmte_id": pl.String,
            "cmte_nm": pl.String,
            "connected_org_nm": pl.String,
            "bonica.rid": pl.String,
            "contributor_employer": pl.String,
            "first_recipient_name": pl.String,
            "row_count": pl.Int64,
            "total_amount": pl.Float64,
        },
    ).select(REVIEW_COLUMNS)
    matched_fields = add_match_fields(review)
    matched = (
        matched_fields.filter(pl.col("match_method").is_not_null())
        .with_columns(
            pl.lit(True).alias("keep"),
            pl.lit("self").alias("hierarchy"),
            pl.lit(1.0).alias("confidence"),
        )
        .sort(["cycle", "cmte_id", "bonica.rid", "row_count"], descending=[False, False, False, True])
    )
    unmatched = (
        matched_fields.filter(pl.col("match_method").is_null())
        .with_columns(
            pl.lit(None, dtype=pl.Boolean).alias("keep"),
            pl.lit(None, dtype=pl.String).alias("hierarchy"),
            pl.lit(None, dtype=pl.Float64).alias("confidence"),
        )
        .sort(["cycle", "cmte_id", "bonica.rid", "row_count"], descending=[False, False, False, True])
    )

    matched_file.parent.mkdir(parents=True, exist_ok=True)
    unmatched_file.parent.mkdir(parents=True, exist_ok=True)
    matched.write_csv(matched_file)
    unmatched.write_csv(unmatched_file)
    return matched, unmatched


def main() -> None:
    args = parse_args()

    if args.stage == "build-review":
        review_file = args.output_file
        review_file.parent.mkdir(parents=True, exist_ok=True)
        review = build_review_file(args.start_year, args.end_year)
        review.write_csv(review_file)
        print(f"Wrote {review.height:,} employer review rows to {review_file}")

    if args.stage == "auto-match":
        matched, unmatched = auto_match_review_file(
            review_file=args.review_file,
            matched_file=args.matched_file,
            unmatched_file=args.unmatched_file,
        )
        print(f"Wrote {matched.height:,} auto-matched rows to {args.matched_file}")
        print(f"Wrote {unmatched.height:,} unmatched rows to {args.unmatched_file}")

    if args.stage == "generate-prompts":
        prompt_pairs = generate_prompt_documents(
            unmatched_file=args.unmatched_file,
            prompt_dir=args.prompt_dir,
            prompt_chunk_size=args.prompt_chunk_size,
        )
        print(f"Wrote prompt documents for {prompt_pairs.height:,} unique pairs to {args.prompt_dir}")


if __name__ == "__main__":
    main()
