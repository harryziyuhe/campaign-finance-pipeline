import os
import time

import pandas as pd
import requests
from tqdm import tqdm

# Shared logic for the per-PAC-type schedule_e scripts in this folder
# (hybrid_pac_expenditures.py, super_pac_expenditures.py) -- not a standalone
# script itself, has no CLI/__main__.
#
# fetch_schedule_e_for_committees scrapes incrementally: a committee already on
# file resumes from its own latest known expenditure_date (min_date) instead of
# being skipped or re-pulled from scratch. Re-querying from min_date (inclusive)
# re-returns that boundary day's rows alongside genuinely new ones.
#
# Rows are deduped by NATURAL_KEY_COLS, not FEC's own sub_id: data scraped before
# sub_id was added to VAR_LIST has no sub_id at all, and every existing committee's
# history predates it, so a sub_id-based dedup would treat every old, sub_id-less
# row as a duplicate of every other (pandas' duplicate-detection treats matching
# nulls as equal), collapsing almost all existing history the first time this
# runs. NATURAL_KEY_COLS is verified (against live schedule_e data) to uniquely
# identify a row without relying on any field introduced after existing data was
# collected -- image_number/category_code alone collide often (one filed image can
# list several expenditures), but combined with candidate/amount/date/description
# they don't.
NATURAL_KEY_COLS = ["committee_id", "candidate_id", "expenditure_amount", "expenditure_date",
                     "expenditure_description", "image_number"]

VAR_LIST = ["committee_id", "candidate_id", "support_oppose_indicator",
            "action_code", "amendment_indicator", "candidate_last_name", "candidate_first_name",
            "candidate_party", "category_code", "category_code_full", "disbursement_dt",
            "election_type", "expenditure_amount", "expenditure_date", "expenditure_description",
            "image_number", "pdf_url", "sub_id"]


def scrape_schedule_e(client, committee_id: str, min_date=None) -> pd.DataFrame:
    """
    Scrape a committee's independent expenditures. Use schedules/schedule_e/ endpoint.
    `min_date` (a "YYYY-MM-DD" string) restricts to expenditure_date >= min_date, for an
    incremental pull that only fetches what's newer than a committee's last known date.
    """
    ie_url = f"{client.base_url}schedules/schedule_e/"
    all_pages = []
    page = 1

    params = {"committee_id": committee_id, "per_page": 100,
              "sort": "-expenditure_date", "api_key": client.api_key}
    if min_date is not None:
        params["min_date"] = min_date

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
    """
    Fetch schedule_e independent expenditures for every committee_id in committee_file,
    incrementally: a committee already on file resumes from its own latest known
    expenditure_date instead of being skipped or re-pulled from scratch.
    """
    if os.path.exists(output_file):
        all_history = pd.read_csv(output_file)
        last_date_by_committee = all_history.groupby("committee_id")["expenditure_date"].max().to_dict()
    else:
        all_history = pd.DataFrame()
        last_date_by_committee = {}

    committees = pd.read_csv(committee_file)["committee_id"].unique()
    counter = 0

    for committee in tqdm(committees):
        counter += 1
        if counter < skip:
            continue
        min_date = last_date_by_committee.get(committee)
        expenditures = scrape_schedule_e(client, committee, min_date=min_date)
        if len(expenditures) > 0:
            all_history = pd.concat([all_history, expenditures], ignore_index=True)
            all_history = all_history.drop_duplicates(subset=NATURAL_KEY_COLS, keep="last")
            client.atomic_write(output_file, lambda p: all_history.to_csv(p, index=False))
