import xml.etree.ElementTree as ET
import pandas as pd
import os
from pathlib import Path

SCRIPT_ROOT = Path(__file__).resolve().parents[4]


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
IEPATH = DATA_ROOT / "data" / "raw" / "electionratings" / "IE"


def parse_rating_ids(path: str) -> pd.DataFrame:
    tree = ET.parse(path)
    root = tree.getroot()

    records = []
    for rating_type in root.findall("ratings_type"):
        office = rating_type.attrib.get("type")
        for rating in rating_type.findall("rating"):
            records.append(
                {
                    "office": office,
                    "id": rating.attrib.get("id"),
                    "date": rating.attrib.get("date"),
                    "timestamp": rating.attrib.get("timestamp"),
                    "url": rating.attrib.get("uri"),
                }
            )

    return pd.DataFrame(records)


if __name__ == "__main__":
    directory = parse_rating_ids(IEPATH / "directory.xml")
    directory.to_csv(IEPATH / "directory.csv", index=False)
