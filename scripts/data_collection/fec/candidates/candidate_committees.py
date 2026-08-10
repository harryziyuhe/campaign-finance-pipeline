import argparse
import sys
import time
from pathlib import Path

import pandas as pd
from tqdm import tqdm

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient, current_cycle_threshold

COMMITTEE_FIELDS = [
    "committee_id", "committee_type", "committee_type_full",
    "cycle", "designation", "designation_full", "is_active",
    "name", "organization_type", "organization_type_full",
    "party", "party_full", "state",
]
# Composite key: a candidate/committee/cycle can fan out into multiple rows via
# the joint-fundraising-committee and related-candidate_ids explodes below, so
# the key has to include those to avoid an upsert collapsing distinct rows.
KEY_COLS = ["candidate_id", "committee_id", "cycle", "joint_committee_id", "candidate_ids"]


def scrape_candidate_committees(client: FECClient, candidate_id: str) -> pd.DataFrame:
    """Scrape one candidate's affiliated committees over time, including joint committees."""
    committee_url = f"{client.base_url}candidate/{candidate_id}/committees/history/"
    all_pages = []
    page = 1

    while True:
        data = client.get_json(committee_url, {"page": page, "per_page": 100})
        total_pages = data.get("pagination", {}).get("pages", 99999)

        base = pd.json_normalize(data.get("results", []))
        if len(base) == 0:
            break
        base = base[COMMITTEE_FIELDS].copy()
        base["candidate_id"] = candidate_id

        related_candidates = (
            pd.json_normalize(data.get("results", []))[["committee_id", "cycle", "candidate_ids"]]
            .explode("candidate_ids")
            .reset_index(drop=True)
        )

        jfc_rows = []
        for row in data.get("results", []):
            for j in row.get("jfc_committee", []) or []:
                jfc_rows.append({
                    "committee_id": row.get("committee_id"),
                    "cycle": row.get("cycle"),
                    "joint_committee_id": j.get("joint_committee_id"),
                    "joint_committee_name": j.get("joint_committee_name"),
                })
        jfc = pd.DataFrame(jfc_rows, columns=["committee_id", "cycle", "joint_committee_id", "joint_committee_name"])

        page_df = base.merge(related_candidates, on=["committee_id", "cycle"], how="left") \
                       .merge(jfc, on=["committee_id", "cycle"], how="left")
        all_pages.append(page_df)

        if page >= total_pages:
            break
        page += 1
        time.sleep(0.5)

    if len(all_pages) == 0:
        return pd.DataFrame()
    return pd.concat(all_pages, ignore_index=True)


def fetch_candidate_committees(client: FECClient, office: str = "H", start_year=None) -> None:
    """
    Fetch per-candidate affiliated-committee history and merge it in by
    (candidate_id, committee_id, cycle, joint_committee_id, candidate_ids), only calling the
    API for candidates that actually need it: a candidate_id is skipped if every
    (candidate_id, election_year) pair it has in the candidate list already appears (as a
    (candidate_id, cycle) pair) in the output file and outside the current (mutable) cycle.
    The committees endpoint returns a candidate's entire history in one call, so once a
    candidate is fetched, merge_cyclical still protects any already-settled past cycles from
    being overwritten.
    """
    candidate_file = f"{client.candidates_path}candidates_{office}.csv"
    output_path = f"{client.candidates_path}candidate_committees_{office}.csv"
    review_path = f"{client.candidates_path}candidate_committees_{office}_discrepancies.csv"

    candidates_df = pd.read_csv(candidate_file)
    if start_year:
        candidates_df = candidates_df[candidates_df["election_year"] >= start_year]

    threshold = current_cycle_threshold()
    try:
        known_keys = pd.read_csv(output_path)[["candidate_id", "cycle"]] \
            .rename(columns={"cycle": "election_year"}).drop_duplicates()
    except FileNotFoundError:
        known_keys = pd.DataFrame(columns=["candidate_id", "election_year"])

    is_known = candidates_df.merge(
        known_keys, on=["candidate_id", "election_year"], how="left", indicator=True
    )["_merge"].to_numpy() == "both"
    needs_fetch = ~is_known | (candidates_df["election_year"].to_numpy() >= threshold)
    candidate_ids = candidates_df[needs_fetch]["candidate_id"].unique()

    fresh_rows = []
    for i, candidate_id in enumerate(tqdm(candidate_ids)):
        committees = scrape_candidate_committees(client, candidate_id)
        if len(committees) > 0:
            fresh_rows.append(committees)

        if fresh_rows and (i + 1) % 50 == 0:
            client.merge_cyclical(
                pd.concat(fresh_rows, ignore_index=True), output_path, KEY_COLS,
                cycle_col="cycle", review_path=review_path, mutable_min_cycle=threshold,
            )
            fresh_rows = []

    if fresh_rows:
        client.merge_cyclical(
            pd.concat(fresh_rows, ignore_index=True), output_path, KEY_COLS,
            cycle_col="cycle", review_path=review_path, mutable_min_cycle=threshold,
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Fetch candidate-affiliated committee history, merging by "
                     "(candidate_id, committee_id, cycle, joint_committee_id, candidate_ids)."
    )
    parser.add_argument("--office", default="H", choices=["H", "S", "P"])
    parser.add_argument("--start-year", type=int, default=None)
    args = parser.parse_args()

    client = FECClient()
    fetch_candidate_committees(client, office=args.office, start_year=args.start_year)
    client.log_run("candidate_committees", office=args.office, start_year=args.start_year)
