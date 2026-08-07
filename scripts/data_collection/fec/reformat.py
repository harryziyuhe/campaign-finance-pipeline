import argparse
import json
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
FEC_BULK_PATH = DATA_ROOT / "data" / "raw" / "fec_bulk"


def polars_schema(columns: dict[str, str]) -> dict[str, pl.DataType]:
    return {
        name: pl.Float64 if dtype == "float64" else pl.String
        for name, dtype in columns.items()
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert FEC pipe-delimited .txt bulk files to parquet."
    )
    parser.add_argument(
        "subfolders",
        nargs="*",
        help="Optional subfolders under data/raw/fec_bulk to scan, e.g. contributions/individual.",
    )
    return parser.parse_args()


def scan_roots(subfolders: list[str]) -> list[Path]:
    if not subfolders:
        return [FEC_BULK_PATH]
    return [FEC_BULK_PATH / subfolder for subfolder in subfolders]


def schema_name_for(file: str) -> str:
    parts = Path(file).stem.split("_")
    while parts and parts[-1].isdigit():
        parts.pop()
    return "_".join(parts) + ".json"


def reformat_txt(root: Path, file: str, json_file: str) -> None:
    input_path = root / file
    output_path = root / file.replace(".txt", ".parquet")
    if output_path.exists():
        print(f"skipping existing {output_path}")
        return

    with (root / json_file).open("r", encoding="utf-8") as f:
        columns = json.load(f)

    df = pl.read_csv(
        input_path,
        separator="|",
        has_header=False,
        new_columns=list(columns),
        schema_overrides=polars_schema(columns),
        encoding="iso8859-1",
        quote_char=None,
    )
    df.write_parquet(output_path)


if __name__ == "__main__":
    args = parse_args()
    for scan_root in scan_roots(args.subfolders):
        if not scan_root.exists():
            print(f"missing folder: {scan_root}")
            continue

        for root, _, files in os.walk(scan_root):
            root_path = Path(root)
            file_set = set(files)
            for file in files:
                if not file.endswith(".txt"):
                    continue
                json_file = schema_name_for(file)
                if json_file not in file_set:
                    continue
                print(f"processing {root_path / file}")
                try:
                    reformat_txt(root_path, file, json_file)
                except Exception as e:
                    print(e)
