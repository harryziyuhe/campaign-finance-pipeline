import argparse
import json
import os
import sys
import time
from pathlib import Path

import pandas as pd

# fec_client.py lives one level up, in fec/ -- not a package, so direct-script
# execution (`python candidates_list.py`, per this repo's convention) needs an
# explicit sys.path entry rather than a relative import.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient

CAND_FIELDS = ["candidate_id", "name", "party", "party_full"]
KEY_COLS = ["candidate_id", "election_year"]


def expand_candidate(candidate: dict) -> list:
    """
    Expand one candidate dictionary into rows, one row per matching election year
    and principal committee cycle.
    """
    base_fields = {k: v for k, v in candidate.items() if k in CAND_FIELDS}

    rows = []
    election_years = candidate.get("election_years", [])
    committees = candidate.get("principal_committees", [])

    for year in election_years:
        matching_committees = [c for c in committees if year in c.get("cycles", [])]

        if matching_committees:
            for c in matching_committees:
                row = {
                    **base_fields,
                    "election_year": year,
                    "committee_id": c.get("committee_id"),
                    "committee_name": c.get("name"),
                    "committee_state": c.get("state"),
                    "committee_party": c.get("party"),
                    "committee_designation": c.get("designation"),
                    "committee_designation_full": c.get("designation_full"),
                    "committee_treasurer": c.get("treasurer_name"),
                }
            rows.append(row)
        else:
            rows.append({
                **base_fields,
                "election_year": year,
                "committee_id": None,
                "committee_name": None,
                "committee_state": None,
                "committee_party": None,
                "committee_designation": None,
                "committee_designation_full": None,
                "committee_treasurer": None,
            })
    return rows


def scrape_candidates(client: FECClient, office: str = "H") -> None:
    """
    Scrape basic information and principal committees for all candidates by office.
    Saves one raw JSON page per page under candidates_path/{office}/page_{n}.json.
    """
    os.makedirs(f"{client.candidates_path}{office}", exist_ok=True)
    cand_url = f"{client.base_url}candidates/search/"
    page = 1
    while True:
        params = {"page": page, "per_page": 100, "office": office}
        data = client.get_json(cand_url, params)

        with open(f"{client.candidates_path}{office}/page_{page}.json", "w") as f:
            json.dump(data, f)

        total_pages = data.get("pagination", {}).get("pages", 99999)
        print(f"Scraped {page} pages out of {total_pages} pages")
        if page >= total_pages:
            break
        page += 1
        time.sleep(0.5)


def parse_candidates(client: FECClient, office: str = "H") -> pd.DataFrame:
    """
    Parse all scraped JSON pages for `office` into a candidate-committee pair CSV, merging
    into the existing file by (candidate_id, election_year): only new pairs are inserted.
    An existing row is never overwritten -- the candidate-search endpoint reports each
    candidate's *current* name/party/committee for every election_year it lists, not what was
    true as of that year, so a fresh value is never more trustworthy than what's on file, even
    for a pair we've already seen.
    """
    data_dir = f"{client.candidates_path}{office}"

    all_cands = []
    for filename in sorted(os.listdir(data_dir)):
        if filename.endswith(".json"):
            with open(os.path.join(data_dir, filename), "r") as f:
                data = json.load(f)
                for candidate in data.get("results", []):
                    all_cands.extend(expand_candidate(candidate))

    df_cands = pd.DataFrame(all_cands)
    return client.insert_only_csv(
        df_cands,
        f"{client.candidates_path}candidates_{office}.csv",
        KEY_COLS,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Scrape and parse the FEC candidate list (no per-cycle history) for one office."
    )
    parser.add_argument("--office", default="H", choices=["H", "S", "P"])
    args = parser.parse_args()

    client = FECClient()
    scrape_candidates(client, office=args.office)
    parse_candidates(client, office=args.office)
    client.log_run("candidates_list", office=args.office)
