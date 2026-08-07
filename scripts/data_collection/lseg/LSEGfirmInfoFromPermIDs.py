from __future__ import annotations

"""Fetch LSEG firm metadata for resolved identifiers found by FEC LSEG search.

This script is the second half of the staged LSEG workflow. The FEC matcher writes
an organisation-name crosswalk. Private-company hits use the organisation PI,
while public-company hits use an equity-search PermID. This script reads the
resolved identifiers, pulls firm-level metadata from LSEG, and writes a CSV with
the same field structure as `data/processed/fec/fec_firm_universe.csv`.
"""

import argparse
import json
import os
from pathlib import Path

import pandas as pd


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
CONFIG_PATH = SCRIPT_ROOT / "config"
LSEG_SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_CROSSWALK_FILE = DATA_ROOT / "data" / "processed" / "fec" / "super_organization_lseg_pi_crosswalk.csv"
DEFAULT_OUTPUT_FILE = DATA_ROOT / "data" / "processed" / "fec" / "super_organization_lseg_firm_info.csv"
COLLAPSE_COLS = {
    "TRBC_ID",
    "TRBC_Econ_Sector",
    "TRBC_Business_Sector",
    "TRBC_Industry_Group",
    "TRBC_Industry",
    "TRBC_Activity",
    "NAICS_ID",
    "NAICS_Sector",
    "NAICS_Subsector",
    "NAICS_Industry_Group",
    "NAICS_International_Industry",
    "NAICS_National_Industry",
}


# CLI configuration keeps LSEG metadata retrieval separate from FEC name matching.
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fetch LSEG firm metadata for crosswalk PermIDs.")
    parser.add_argument("--crosswalk", type=Path, default=DEFAULT_CROSSWALK_FILE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_FILE)
    parser.add_argument("--batch-size", type=int, default=100)
    return parser.parse_args()


def collapse_values(values: pd.Series) -> object:
    clean = [value for value in values if pd.notna(value) and str(value) != ""]
    return clean if clean else ""


# LSEG field mapping mirrors the existing firm-universe collection script.
class LsegFirmInfoFetcher:
    def __init__(self, batch_size: int) -> None:
        os.environ.setdefault("LD_LIB_CONFIG_PATH", str(CONFIG_PATH))
        import lseg.data as ld

        self.ld = ld
        self.batch_size = batch_size
        with (LSEG_SCRIPT_DIR / "data_fields.json").open("r", encoding="utf-8") as file:
            field_map = json.load(file)
        self.fields = list(field_map.keys())
        self.col_names = list(field_map.values())
        self.agg_dict = {
            column: collapse_values if column in COLLAPSE_COLS else "first"
            for column in self.col_names
        }
        self.ld.open_session()

    def fetch(self, permids: list[str]) -> pd.DataFrame:
        frames = []
        for start in range(0, len(permids), self.batch_size):
            batch = permids[start : start + self.batch_size]
            if not batch:
                continue
            frame = self.ld.get_data(universe=batch, fields=self.fields)
            if frame is None or frame.empty:
                continue
            frame.columns = ["instrument"] + self.col_names
            frames.append(frame)

        if not frames:
            return pd.DataFrame(columns=["instrument"] + self.col_names)

        firms = pd.concat(frames, ignore_index=True)
        firms = firms.groupby("instrument", as_index=False).agg(self.agg_dict)
        return firms


def load_permids(crosswalk_file: Path) -> list[str]:
    crosswalk = pd.read_csv(crosswalk_file, dtype=str).fillna("")
    matched = crosswalk.loc[crosswalk["lseg_matched"].astype(str).str.lower().isin(["true", "1"])]
    if "resolved_lseg_id" in matched:
        ids = matched["resolved_lseg_id"]
    elif "lseg_equity_permid" in matched:
        ids = matched["lseg_equity_permid"].where(
            matched["lseg_equity_permid"].astype(str).str.strip() != "",
            matched.get("lseg_org_pi", matched.get("lseg_search_pi", "")),
        )
    else:
        ids = matched["lseg_search_pi"]
    return sorted(set(identifier for identifier in ids.tolist() if str(identifier).strip()))


def main() -> None:
    args = parse_args()
    permids = load_permids(args.crosswalk)
    fetcher = LsegFirmInfoFetcher(args.batch_size)
    firms = fetcher.fetch(permids)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    firms.to_csv(args.output, index=False)
    print(f"Read {len(permids):,} unique PermIDs from {args.crosswalk}.")
    print(f"Saved {len(firms):,} firm metadata rows to {args.output}.")


if __name__ == "__main__":
    main()
