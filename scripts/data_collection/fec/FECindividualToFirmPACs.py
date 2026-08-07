from __future__ import annotations

"""Filter FEC individual contribution files to contributions received by firm PACs.

The script reads raw individual-contribution parquet files, keeps rows whose
committee ID matches the corporate PAC-firm match table, writes cycle-level
outputs, and builds employer-occupation summary files for later review.
"""

import argparse
import json
import os
import shutil
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
INPUT_DIR = DATA_ROOT / "data" / "raw" / "fec_bulk" / "contributions" / "individual"
PAC_FILE = DATA_ROOT / "data" / "processed" / "fec" / "corporate_pac_firm_matches.csv"
OUTPUT_DIR = DATA_ROOT / "data" / "processed" / "fec" / "individual_to_firm_pac_contributions"
SCHEMA_FILE = INPUT_DIR / "individual.json"


# CLI configuration for selecting the filtering and aggregation stages.
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Filter FEC individual contributions to contributions received by corporate PACs."
    )
    parser.add_argument(
        "--stage",
        choices=["filter", "aggregate", "all"],
        default="all",
        help="Run filtering, aggregation, or both.",
    )
    parser.add_argument("--start-year", type=int, default=2004)
    parser.add_argument("--end-year", type=int, default=2024)
    parser.add_argument("--batch-size", type=int, default=3_000_000)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


# Source discovery and schema loading for raw FEC individual contribution files.
def source_files(start_year: int, end_year: int) -> list[tuple[int, Path]]:
    files: list[tuple[int, Path]] = []
    for year in range(start_year, end_year + 2, 2):
        parquet_file = INPUT_DIR / f"individual_{year}.parquet"
        if parquet_file.exists():
            files.append((year, parquet_file))
            continue

        split_dir = INPUT_DIR / f"individual_{year}"
        if split_dir.exists():
            parquet_files = sorted(split_dir.glob("*.parquet"))
            files.extend((year, path) for path in parquet_files)
            continue

    return files


def load_schema() -> dict[str, pl.DataType]:
    with SCHEMA_FILE.open("r", encoding="utf-8") as f:
        raw_schema = json.load(f)
    return {
        column: pl.Float64 if dtype == "float64" else pl.String
        for column, dtype in raw_schema.items()
    }


def load_corporate_pac_ids() -> pl.Series:
    return (
        pl.read_csv(PAC_FILE, columns=["cmte_id"], schema_overrides={"cmte_id": pl.String})
        .select(pl.col("cmte_id").str.strip_chars().drop_nulls().unique())
        .to_series()
    )


# Output directory management for reproducible pipeline runs.
def reset_output_dir(overwrite: bool) -> None:
    if OUTPUT_DIR.exists():
        if not overwrite:
            raise FileExistsError(f"{OUTPUT_DIR} exists. Use --overwrite to replace it.")
        if DATA_ROOT.resolve() not in OUTPUT_DIR.resolve().parents:
            raise ValueError(f"Refusing to remove output outside data root: {OUTPUT_DIR}")
        shutil.rmtree(OUTPUT_DIR)
    OUTPUT_DIR.mkdir(parents=True)


def output_path(year: int, source: Path) -> Path:
    year_dir = OUTPUT_DIR / f"cycle_{year}"
    year_dir.mkdir(parents=True, exist_ok=True)
    return year_dir / f"{source.stem}.parquet"


# Row-level filtering against the firm-PAC committee universe.
def filter_frame(frame: pl.DataFrame, year: int, pac_ids: pl.Series) -> pl.DataFrame:
    return (
        frame.with_columns(
            pl.col("CMTE_ID").cast(pl.String).str.strip_chars(),
            pl.lit(year).alias("SOURCE_CYCLE"),
        )
        .filter(pl.col("CMTE_ID").is_in(pac_ids))
    )


def filter_parquet(year: int, path: Path, pac_ids: pl.Series) -> dict:
    input_rows = pl.scan_parquet(path).select(pl.len()).collect().item()
    filtered = (
        pl.scan_parquet(path)
        .with_columns(
            pl.col("CMTE_ID").cast(pl.String).str.strip_chars(),
            pl.lit(year).alias("SOURCE_CYCLE"),
        )
        .filter(pl.col("CMTE_ID").is_in(pac_ids))
        .collect()
    )

    out_file = ""
    if filtered.height > 0:
        out = output_path(year, path)
        filtered.write_parquet(out)
        out_file = str(out.relative_to(DATA_ROOT))

    return manifest_row(year, path, input_rows, filtered.height, out_file)


# Cycle-level aggregation turns filtered source parts into one parquet per cycle.
def cycle_dirs(start_year: int, end_year: int) -> list[tuple[int, Path]]:
    return [
        (year, OUTPUT_DIR / f"cycle_{year}")
        for year in range(start_year, end_year + 2, 2)
        if (OUTPUT_DIR / f"cycle_{year}").exists()
    ]


def aggregate_cycle(year: int, folder: Path) -> Path | None:
    output = folder / f"individual_{year}.parquet"
    inputs = sorted(path for path in folder.glob("*.parquet") if path.name != output.name)
    if not inputs:
        return output if output.exists() else None

    if len(inputs) == 1 and not output.exists():
        inputs[0].rename(output)
    else:
        pl.scan_parquet(inputs).sink_parquet(output)
    return output


# Summary extraction for employer-occupation pairs in matched contributions.
def collect_employer_occupation_pairs(cycle_files: list[Path]) -> None:
    pair_frames = []
    for path in cycle_files:
        columns = pl.scan_parquet(path).collect_schema().names()
        if {"EMPLOYER", "OCCUPATION", "TRANSACTION_AMT"}.issubset(columns):
            pair_frames.append(
                pl.scan_parquet(path).select(
                    pl.col("EMPLOYER").cast(pl.String).str.strip_chars().alias("employer"),
                    pl.col("OCCUPATION").cast(pl.String).str.strip_chars().alias("occupation"),
                    pl.col("TRANSACTION_AMT").cast(pl.Float64).alias("transaction_amount"),
                )
            )

    if pair_frames:
        pairs = (
            pl.concat(pair_frames)
            .filter(
                pl.col("employer").is_not_null()
                & pl.col("occupation").is_not_null()
                & (pl.col("employer") != "")
                & (pl.col("occupation") != "")
            )
            .group_by(["employer", "occupation"])
            .agg(pl.col("transaction_amount").sum().alias("total_transaction_amount"))
            .sort("total_transaction_amount", descending=True)
            .collect()
        )
    else:
        pairs = pl.DataFrame(
            {"employer": [], "occupation": [], "total_transaction_amount": []},
            schema={
                "employer": pl.String,
                "occupation": pl.String,
                "total_transaction_amount": pl.Float64,
            },
        )

    pairs.write_csv(OUTPUT_DIR / "employer_occupation_pairs.csv")


def aggregate_outputs(start_year: int, end_year: int) -> None:
    cycle_files = []
    for year, folder in tqdm(cycle_dirs(start_year, end_year), desc="Aggregating cycle outputs"):
        output = aggregate_cycle(year, folder)
        if output is not None and output.exists():
            cycle_files.append(output)

    collect_employer_occupation_pairs(cycle_files)
    print(f"Aggregated {len(cycle_files):,} cycle files.")


# Manifest rows capture source coverage and matched row counts for auditability.
def manifest_row(year: int, path: Path, input_rows: int, matched_rows: int, output_file: str) -> dict:
    return {
        "source_file": str(path.relative_to(DATA_ROOT)),
        "cycle": year,
        "input_rows": input_rows,
        "matched_rows": matched_rows,
        "output_file": output_file,
    }


# Pipeline entrypoint coordinating optional filter and aggregation stages.
def main() -> None:
    args = parse_args()

    if args.stage in {"filter", "all"}:
        files = source_files(args.start_year, args.end_year)
        if not files:
            raise FileNotFoundError("No individual contribution files found.")

        reset_output_dir(args.overwrite)
        schema = load_schema()
        pac_ids = load_corporate_pac_ids()
        print(f"Loaded {len(pac_ids):,} corporate PAC committee IDs.")

        records = []
        for year, path in tqdm(files, desc="Filtering individual contributions"):
            record = filter_parquet(year, path, pac_ids)
            records.append(record)

        pl.DataFrame(records).write_csv(OUTPUT_DIR / "_manifest.csv")
        matched_rows = sum(row["matched_rows"] for row in records)
        print(f"Saved {matched_rows:,} rows to {OUTPUT_DIR}.")

    if args.stage in {"aggregate", "all"}:
        aggregate_outputs(args.start_year, args.end_year)


if __name__ == "__main__":
    main()
