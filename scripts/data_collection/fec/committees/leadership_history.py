import argparse
import os
import sys
import time
from pathlib import Path

import pandas as pd
from tqdm import tqdm

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient
from leadership_pacs import fetch_leadership_pacs  # same folder, direct import

HISTORY_FIELDS = ["committee_id", "committee_type", "committee_type_full",
                   "cycle", "designation", "designation_full", "is_active", "name",
                   "party", "party_full", "state"]
# sponsor_candidate_ids can explode into multiple rows per (committee_id, cycle).
KEY_COLS = ["committee_id", "cycle", "sponsor_candidate_ids"]


def scrape_leadership_history(client: FECClient, committee_id: str) -> pd.DataFrame:
    """Scrape one committee's characteristics over time. Use committee/{id}/history/ endpoint."""
    history_url = f"{client.base_url}committee/{committee_id}/history/"
    all_pages = []
    page = 1

    while True:
        data = client.get_json(history_url, {"page": page, "per_page": 100})
        total_pages = data.get("pagination", {}).get("pages", 99999)
        time.sleep(0.5)

        base = pd.json_normalize(data.get("results", []))
        if len(base) == 0:
            break
        base = base[HISTORY_FIELDS]

        sponsors = (
            pd.json_normalize(data.get("results", []))[["committee_id", "cycle", "sponsor_candidate_ids"]]
            .explode("sponsor_candidate_ids")
            .reset_index(drop=True)
        )
        page_df = pd.merge(base, sponsors, on=["committee_id", "cycle"], how="left")
        all_pages.append(page_df)

        if page >= total_pages:
            break
        page += 1

    if len(all_pages) == 0:
        return pd.DataFrame()
    return pd.concat(all_pages, ignore_index=True)


def fetch_leadership_history(client: FECClient, refresh: str = "new") -> None:
    """
    refresh="new": only fetch history for committee_ids never seen in the output file.
    refresh="all": re-fetch every known committee_id and upsert -- catch-up runs, or to
    catch a leadership PAC gaining a new cycle / rare retroactive correction.
    """
    committee_file = f"{client.committees_path}leadership_pacs.csv"
    output_path = f"{client.committees_path}leadership_history.csv"

    if not os.path.exists(committee_file):
        fetch_leadership_pacs(client)
    committee_ids = pd.read_csv(committee_file)["committee_id"].unique()

    if refresh == "new":
        try:
            existing = pd.read_csv(output_path)
            known_ids = set(existing["committee_id"].unique())
        except FileNotFoundError:
            known_ids = set()
        committee_ids = [c for c in committee_ids if c not in known_ids]

    fresh_rows = []
    for i, committee_id in enumerate(tqdm(committee_ids)):
        history = scrape_leadership_history(client, committee_id)
        if len(history) > 0:
            fresh_rows.append(history)

        if fresh_rows and (i + 1) % 50 == 0:
            client.upsert_csv(pd.concat(fresh_rows, ignore_index=True), output_path, KEY_COLS)
            fresh_rows = []

    if fresh_rows:
        client.upsert_csv(pd.concat(fresh_rows, ignore_index=True), output_path, KEY_COLS)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Fetch leadership PAC committee history, upserting by (committee_id, cycle, sponsor_candidate_ids)."
    )
    parser.add_argument("--refresh", default="new", choices=["new", "all"])
    args = parser.parse_args()

    client = FECClient()
    fetch_leadership_history(client, refresh=args.refresh)
