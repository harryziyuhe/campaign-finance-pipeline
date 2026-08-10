import argparse
import sys
from pathlib import Path

import pandas as pd
from tqdm import tqdm

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient, current_cycle_threshold

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


def fetch_candidate_history(client: FECClient, office: str = "H", start_year=None) -> None:
    """
    Fetch per-candidate history and merge it in by (candidate_id, candidate_election_year),
    only calling the API for candidates that actually need it: a candidate_id is skipped if
    every (candidate_id, election_year) pair it has in the candidate list is already present
    in the output file and outside the current (mutable) cycle. The history endpoint returns
    a candidate's entire history in one call, so once a candidate is fetched, merge_cyclical
    still protects any of its already-settled past cycles from being overwritten.
    """
    candidate_file = f"{client.candidates_path}candidates_{office}.csv"
    output_path = f"{client.candidates_path}candidate_history_{office}.csv"
    review_path = f"{client.candidates_path}candidate_history_{office}_discrepancies.csv"

    candidates_df = pd.read_csv(candidate_file)
    if start_year:
        candidates_df = candidates_df[candidates_df["election_year"] >= start_year]

    threshold = current_cycle_threshold()
    try:
        known_keys = pd.read_csv(output_path)[["candidate_id", "candidate_election_year"]] \
            .rename(columns={"candidate_election_year": "election_year"}).drop_duplicates()
    except FileNotFoundError:
        known_keys = pd.DataFrame(columns=["candidate_id", "election_year"])

    is_known = candidates_df.merge(
        known_keys, on=["candidate_id", "election_year"], how="left", indicator=True
    )["_merge"].to_numpy() == "both"
    needs_fetch = ~is_known | (candidates_df["election_year"].to_numpy() >= threshold)
    candidate_ids = candidates_df[needs_fetch]["candidate_id"].unique()

    fresh_rows = []
    for i, candidate_id in enumerate(tqdm(candidate_ids)):
        history = scrape_candidate_history(client, candidate_id)
        if len(history) > 0:
            fresh_rows.append(history)
        else:
            print(f"No history returned for {candidate_id}")

        if fresh_rows and (i + 1) % 50 == 0:
            client.merge_cyclical(
                pd.concat(fresh_rows, ignore_index=True), output_path, KEY_COLS,
                cycle_col="candidate_election_year", review_path=review_path,
                mutable_min_cycle=threshold,
            )
            fresh_rows = []

    if fresh_rows:
        client.merge_cyclical(
            pd.concat(fresh_rows, ignore_index=True), output_path, KEY_COLS,
            cycle_col="candidate_election_year", review_path=review_path,
            mutable_min_cycle=threshold,
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Fetch per-cycle candidate history, merging by (candidate_id, candidate_election_year)."
    )
    parser.add_argument("--office", default="H", choices=["H", "S", "P"])
    parser.add_argument("--start-year", type=int, default=None)
    args = parser.parse_args()

    client = FECClient()
    fetch_candidate_history(client, office=args.office, start_year=args.start_year)
    client.log_run("candidate_history", office=args.office, start_year=args.start_year)
