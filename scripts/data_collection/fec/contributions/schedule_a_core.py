import os
import time

import polars as pl
import requests
from tqdm import tqdm

# Shared logic for the per-PAC-type schedule_a scripts in this folder
# (hybrid_pac_contributions.py, super_pac_contributions.py, etc.) -- not a
# standalone script itself, has no CLI/__main__.
#
# Donor-side receipts (Schedule A: money flowing INTO a committee). This is the
# individual/donor-identity track, distinct from a PAC's outbound giving to
# candidates (Schedule B), which has no scraper here yet.
#
# KNOWN GAP (not fixed in this pass): fetch_schedule_a_for_committees skips a
# committee entirely once it has any contributions on file, so a committee's
# contributions received AFTER the first pull are never picked up. A real fix
# needs a stored per-committee "last contribution_receipt_date fetched"
# checkpoint passed back in as min_date on the next run, not a skip-if-seen
# check. Left as-is here -- this was called out as an easier, still-open
# follow-up, not the candidate/committee-history case-1/case-2 work.

VAR_LIST = ["committee_id", "amendment_indicator", "amendment_indicator_desc",
            "contribution_receipt_amount", "contribution_receipt_date", "contributor_id",
            "contributor_aggregate_ytd", "contributor_city", "contributor_employer", "contributor_name",
            "contributor_first_name", "contributor_last_name", "contributor_middle_name",
            "contributor_occupation", "contributor_state", "contributor_zip", "donor_committee_name",
            "election_type", "entity_type", "entity_type_desc", "fec_election_type_desc",
            "is_individual", "line_number", "line_number_label", "receipt_type", "receipt_type_desc",
            "receipt_type_full", "image_number", "pdf_url"]


def scrape_schedule_a(client, committee_id: str, pbar, year=None):
    """
    Scrape individual contributions to a committee. Use schedules/schedule_a/ endpoint.
    Returns (status_code, polars.DataFrame). A 504 on the first attempt for a
    committee signals the caller to retry year-by-year instead (schedule_a can
    time out on committees with a very long contribution history).
    """
    contrib_url = f"{client.base_url}schedules/schedule_a/"
    all_pages = []
    page = 1

    params = {"committee_id": committee_id, "per_page": 100,
              "sort": "-contribution_receipt_date", "api_key": client.api_key}
    if year is not None:
        params["min_date"] = f"{year}-01-01"
        params["max_date"] = f"{year}-12-31"

    status_code = None
    error_page = None

    while True:
        response = requests.get(contrib_url, params=params)
        if response.status_code != 200:
            print(f"Error processing Committee {committee_id} with year {year}: {response.status_code}")
            if response.status_code == 504:
                if status_code == 504:
                    return status_code, None
                error_page = page
                status_code = 504
            time.sleep(5)
            continue
        data = response.json()
        total_pages = data.get("pagination", {}).get("pages", 0)
        if total_pages == 0:
            break
        last_sort_idx = data.get("pagination", {}).get("last_indexes", {}).get("last_index", "")
        last_sort_info = data.get("pagination", {}).get("last_indexes", {}).get("last_contribution_receipt_date", "")
        if last_sort_info == "":
            break

        page_df = pl.from_dicts(data.get("results", []))
        missing_cols = [col for col in VAR_LIST if col not in page_df.columns]
        if missing_cols:
            page_df = page_df.with_columns([pl.lit(None).alias(col) for col in missing_cols])
        if len(page_df) == 0:
            break
        page_df = page_df.select(VAR_LIST)
        all_pages.append(page_df)

        if page >= total_pages:
            break
        pbar.set_postfix_str(f"page {page}/{total_pages}")
        if error_page and page - error_page > 10:
            error_page = None
            status_code = None
        page += 1

        params["last_index"] = last_sort_idx
        params["last_contribution_receipt_date"] = last_sort_info
        time.sleep(0.5)

    if len(all_pages) == 0:
        return 200, pl.DataFrame(schema={col: pl.Null for col in VAR_LIST})
    return 200, pl.concat(all_pages, how="vertical_relaxed")


def fetch_schedule_a_for_committees(client, committee_file: str, output_file: str,
                                     skip: int = 0, save_every: int = 100) -> None:
    """Fetch schedule_a contributions for every committee_id listed in committee_file."""
    if os.path.exists(output_file):
        all_history = pl.read_parquet(output_file)
        existing_committees = set(all_history["committee_id"].drop_nulls().to_list())
        print(f"Existing contribution history found for {len(existing_committees)} committees.")
    else:
        all_history = pl.DataFrame()
        existing_committees = set()

    committees_df = pl.read_csv(committee_file)
    counter = 0

    with tqdm(range(len(committees_df))) as pbar:
        for i in pbar:
            row = committees_df.row(i, named=True)
            committee = row["committee_id"]
            pbar.set_description(f"Committee {committee}")
            pbar.refresh()
            counter += 1

            if counter < skip:
                continue
            if committee in existing_committees:
                continue

            status_code, contributions = scrape_schedule_a(client, committee, pbar)

            if status_code == 504:
                start_year = row["active_start_year"]
                end_year = row["active_end_year"]
                chunk_results = []
                for year in range(start_year, end_year + 1):
                    pbar.set_description(f"Committee {committee} - Year {year}")
                    status_code_chunk, contributions_chunk = scrape_schedule_a(client, committee, pbar, year)
                    if status_code_chunk == 504:
                        print(f"Committee {committee} continues to return 504 error for year {year}")
                    if contributions_chunk is not None and contributions_chunk.height > 0:
                        chunk_results.append(contributions_chunk)
                contributions = pl.concat(chunk_results, how="vertical_relaxed") if chunk_results else pl.DataFrame()

            if contributions is not None and contributions.height > 0:
                all_history = contributions if all_history.height == 0 else pl.concat([all_history, contributions], how="vertical_relaxed")
                existing_committees.add(committee)

            if counter % save_every == 0 and all_history.height > 0:
                print(f"Processed {counter} committees. Saving progress to {output_file}...")
                all_history.write_parquet(output_file)

    if all_history.height > 0:
        all_history.write_parquet(output_file)
