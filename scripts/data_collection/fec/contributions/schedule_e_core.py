import os
import time

import pandas as pd
import requests
from tqdm import tqdm

# Shared logic for the per-PAC-type schedule_e scripts in this folder
# (hybrid_pac_expenditures.py, super_pac_expenditures.py) -- not a standalone
# script itself, has no CLI/__main__.
#
# KNOWN GAP (not fixed in this pass): fetch_schedule_e_for_committees skips a
# committee entirely once it has any expenditures on file -- same "skip if
# seen" limitation as schedule_a_core.py, not yet converted to a real
# last-timestamp checkpoint.

VAR_LIST = ["committee_id", "candidate_id", "support_oppose_indicator",
            "action_code", "amendment_indicator", "candidate_last_name", "candidate_first_name",
            "candidate_party", "category_code", "category_code_full", "disbursement_dt",
            "election_type", "expenditure_amount", "expenditure_date", "expenditure_description",
            "image_number", "pdf_url"]


def scrape_schedule_e(client, committee_id: str) -> pd.DataFrame:
    """Scrape a committee's independent expenditures. Use schedules/schedule_e/ endpoint."""
    ie_url = f"{client.base_url}schedules/schedule_e/"
    all_pages = []
    page = 1

    params = {"committee_id": committee_id, "per_page": 100,
              "sort": "-expenditure_date", "api_key": client.api_key}

    while True:
        response = requests.get(ie_url, params=params)
        if response.status_code != 200:
            print(response.status_code)
            time.sleep(5)
            continue
        data = response.json()
        total_pages = data.get("pagination", {}).get("pages", 0)
        if total_pages == 0:
            break
        last_sort_idx = data.get("pagination", {}).get("last_indexes", {}).get("last_index", "")
        last_sort_info = data.get("pagination", {}).get("last_indexes", {}).get("last_expenditure_date", "")
        time.sleep(0.5)

        page_df = pd.json_normalize(data.get("results", []))
        if len(page_df) == 0:
            break
        page_df = page_df[VAR_LIST]
        all_pages.append(page_df)

        if page >= total_pages:
            break
        page += 1
        params["last_index"] = last_sort_idx
        params["last_expenditure_date"] = last_sort_info

    if len(all_pages) == 0:
        return pd.DataFrame()
    return pd.concat(all_pages, ignore_index=True)


def fetch_schedule_e_for_committees(client, committee_file: str, output_file: str, skip: int = 0) -> None:
    """Fetch schedule_e independent expenditures for every committee_id listed in committee_file."""
    if os.path.exists(output_file):
        all_history = pd.read_csv(output_file)
        existing_committees = all_history["committee_id"].values
    else:
        all_history = pd.DataFrame()
        existing_committees = []

    committees = pd.read_csv(committee_file)["committee_id"].unique()
    counter = 0

    for committee in tqdm(committees):
        counter += 1
        if counter < skip:
            continue
        if committee in existing_committees:
            continue
        expenditures = scrape_schedule_e(client, committee)
        if len(expenditures) > 0:
            all_history = pd.concat([all_history, expenditures])
            all_history.to_csv(output_file, index=False)
