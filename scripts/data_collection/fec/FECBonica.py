# filter_contrib_to_parquet.py
import argparse
import os
import polars as pl
from pathlib import Path


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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Filter Bonica contribution files"
    )
    parser.add_argument("--cycle", type=int, required = True)
    return parser.parse_args()


KEEP_COLUMNS = [
    "cycle",
    "transaction.type",
    "amount",
    "date",
    "bonica.cid",
    "contributor.name",
    "contributor.lname",
    "contributor.fname",
    "contributor.mname",
    "contributor.type",
    "contributor.gender",
    "contributor.address",
    "contributor.city",
    "contributor.state",
    "contributor.zipcode",
    "contributor.occupation",
    "occ.standardized",
    "contributor.employer",
    "recipient.name",
    "bonica.rid",
    "recipient.party",
    "recipient.type",
    "recipient.state",
    "seat",
    "election.type",
    "latitude",
    "longitude",
    "gis.confidence",
    "contributor.district",
    "censustract",
    "efec.org.orig",
    "efec.comid.orig",
]


def main() -> None:
    args = parse_args()
    dime_dir = DATA_ROOT / "data" / "raw" / "dime"
    INPUT_PATH = dime_dir / f"contribDB_{args.cycle}.csv"
    OUTPUT_PATH = dime_dir / f"individual_contribution_{args.cycle}.parquet"

    lf = pl.scan_csv(
        INPUT_PATH,
        schema_overrides={
            "bonica.cid": pl.String,
        },
        encoding="utf8-lossy",
        ignore_errors=True,
        low_memory=True,
    )

    query = (
        lf
        .filter(pl.col("seat").str.contains("federal"))
        .select(KEEP_COLUMNS)
    )

    query.sink_parquet(
        OUTPUT_PATH,
        compression="zstd",
    )


if __name__ == "__main__":
    main()