import argparse
import sys
from pathlib import Path

import pandas as pd
from tqdm import tqdm

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient

HISTORY_FIELDS = [
    "candidate_id", "candidate_last_name", "candidate_first_name", "candidate_middle_name",
    "address_city", "address_state", "address_zip", "candidate_election_year",
    "district", "district_number", "incumbent_challenge", "incumbent_challenge_full",
    "name", "office", "party", "party_full", "state",
]
KEY_COLS = ["candidate_id", "candidate_election_year"]


def scrape_candidate_history(client: FECClient, candidate_id: str) -> pd.DataFrame:
    """
    Scrape one candidate's characteristics over time (one row per cycle).
    Use candidate/{candidate_id}/history/ endpoint.
    """
    history_url = f"{client.base_url}candidate/{candidate_id}/history/"
    rows = client.paginate_by_page(history_url, {"per_page": 100})
    if not rows:
        return pd.DataFrame(columns=HISTORY_FIELDS)
    df = pd.json_normalize(rows)
    return df[HISTORY_FIELDS]


def fetch_candidate_history(client: FECClient, office: str = "H", start_year=None, refresh: str = "new") -> None:
    """
    refresh="new": only fetch history for candidate_ids never seen in the output file
    (cheap, catches newly-appeared candidates).
    refresh="all": re-fetch history for every known candidate_id and upsert by
    (candidate_id, candidate_election_year) -- catches new cycles appended to an
    already-known candidate, and rare retroactive corrections. Use this for the
    one-time catch-up from wherever the existing data currently ends.
    """
    candidate_file = f"{client.candidates_path}candidates_{office}.csv"
    output_path = f"{client.candidates_path}candidate_history_{office}.csv"

    candidates_df = pd.read_csv(candidate_file)
    if start_year:
        candidates_df = candidates_df[candidates_df["election_year"] >= start_year]
    candidate_ids = candidates_df["candidate_id"].unique()

    if refresh == "new":
        try:
            existing = pd.read_csv(output_path)
            known_ids = set(existing["candidate_id"].unique())
        except FileNotFoundError:
            known_ids = set()
        candidate_ids = [c for c in candidate_ids if c not in known_ids]

    fresh_rows = []
    for i, candidate_id in enumerate(tqdm(candidate_ids)):
        history = scrape_candidate_history(client, candidate_id)
        if len(history) > 0:
            fresh_rows.append(history)
        else:
            print(f"No history returned for {candidate_id}")

        if fresh_rows and (i + 1) % 50 == 0:
            client.upsert_csv(pd.concat(fresh_rows, ignore_index=True), output_path, KEY_COLS)
            fresh_rows = []

    if fresh_rows:
        client.upsert_csv(pd.concat(fresh_rows, ignore_index=True), output_path, KEY_COLS)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Fetch per-cycle candidate history, upserting by (candidate_id, candidate_election_year)."
    )
    parser.add_argument("--office", default="H", choices=["H", "S", "P"])
    parser.add_argument("--start-year", type=int, default=None)
    parser.add_argument("--refresh", default="new", choices=["new", "all"],
                         help="'new' = only never-seen candidates. 'all' = re-check every known "
                              "candidate too (catch-up runs, or to catch rare retroactive changes).")
    args = parser.parse_args()

    client = FECClient()
    fetch_candidate_history(client, office=args.office, start_year=args.start_year, refresh=args.refresh)
