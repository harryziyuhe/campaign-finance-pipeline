import pandas as pd
import xml.etree.ElementTree as ET
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
label_map = {
    0: "Toss-up",
    1: "Tilt Democrat",
    2: "Lean Democrat",
    3: "Likely Democrat",
    4: "Solid Democrat",
    -1: "Tilt Republican",
    -2: "Lean Republican",
    -3: "Likely Republican",
    -4: "Solid Republican"
}

def remap_rating(rating):
    rating = int(rating)
    if 1 <= rating <= 5:
        return rating - 1
    elif 6 <= rating <= 9:
        return 5 - rating
    else:
        return None
    
def remap_label(rating):
    return label_map.get(rating, "Unknown")

def normalize_district(district, state):
    # Some snapshots (observed exclusively in odd-year/off-cycle pages) encode
    # district as "{state}-{n}" (e.g. "PA-17") instead of the bare number used
    # everywhere else, and at-large states as "{state}-AL" instead of "1".
    if district is None:
        return district
    prefix = f"{state}-"
    if district.startswith(prefix):
        suffix = district[len(prefix):]
        return "1" if suffix == "AL" else suffix
    return district


def parse_records(id, date):
    path = IEPATH / f"house_{id}.xml"
    if not os.path.exists(path):
        print(f"{path} does not exist")
        return pd.DataFrame()
    tree = ET.parse(path)
    root = tree.getroot()
    records = []
    for race in root.findall("race"):
        rating_elem = race.find("rating/id")
        rating = rating_elem.text if rating_elem is not None else None

        label_elem = race.find("rating/label")
        label = label_elem.text if label_elem is not None else None

        open_elem = race.find("notes/open")
        open = open_elem.text if open_elem is not None else None

        special_elem = race.find("notes/special")
        special = special_elem.text if special_elem is not None else None

        state = race.findtext("state")
        race_info = {
            "date": date,
            "state": state,
            "district": normalize_district(race.findtext("district"), state),
            "incumbent_party": race.findtext("party"),
            "incumbent": race.findtext("incumbent"),
            "open": open,
            "special": special,
            "rating": rating,
            "label": label,
        }
        records.append(race_info)

    records = pd.DataFrame(records)
    records["rating"] = records["rating"].apply(remap_rating)
    records["label"] = records["rating"].apply(remap_label)
    return records


if __name__ == "__main__":
    directory = pd.read_csv(IEPATH / "directory.csv")
    house = directory[directory["office"] == "house"].copy()
    house["date"] = pd.to_datetime(house["date"])
    ratings = []
    for index, row in house.iterrows():
        ratings.append(parse_records(row["id"], row["date"]))
    ratings = pd.concat(ratings, ignore_index=True)
    ratings.to_csv(IEPATH / "house_ratings.csv")
