import argparse
import sys
import time
from pathlib import Path

import pandas as pd
from tqdm import tqdm

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient

PAC_TYPE_FILES = {
    "hybrid": "hybrid_pacs.csv",
    "independent-expenditure": "super_pacs.csv",
    "leadership": "leadership_pacs.csv",
}


def scrape_committee_active_period(client: FECClient, committee_id: str):
    active_url = f"{client.base_url}committee/{committee_id}/history/"
    data = client.get_json(active_url, {"per_page": 20})
    results = data.get("results", [])
    if len(results) == 0:
        return None, None
    cycles = results[0].get("cycles", [])
    if len(cycles) == 0:
        return None, None
    return min(cycles), max(cycles)


def fill_committee_active_period(client: FECClient, category: str) -> None:
    if category not in PAC_TYPE_FILES:
        raise ValueError(f"{category} is not a supported PAC category")
    committee_file = f"{client.committees_path}{PAC_TYPE_FILES[category]}"
    df = pd.read_csv(committee_file)
    df["active_start_year"] = None
    df["active_end_year"] = None

    for idx, row in tqdm(df.iterrows(), total=df.shape[0]):
        start_year, end_year = scrape_committee_active_period(client, row["committee_id"])
        df.at[idx, "active_start_year"] = start_year
        df.at[idx, "active_end_year"] = end_year
        time.sleep(0.5)
        if idx % 100 == 0:
            df.to_csv(committee_file, index=False)

    df.to_csv(committee_file, index=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fill active_start_year/active_end_year on a committee list file.")
    parser.add_argument("--category", required=True, choices=list(PAC_TYPE_FILES.keys()))
    args = parser.parse_args()

    client = FECClient()
    fill_committee_active_period(client, category=args.category)
