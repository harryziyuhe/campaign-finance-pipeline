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
# fetch_schedule_a_for_committees scrapes incrementally: a committee already on
# file resumes from its own latest known contribution_receipt_date (min_date)
# instead of being skipped or re-pulled from scratch. Re-querying from min_date
# (inclusive) re-returns that boundary day's rows alongside genuinely new ones.
#
# Rows are deduped by NATURAL_KEY_COLS, not FEC's own sub_id: data scraped before
# sub_id was added to VAR_LIST has no sub_id at all, and every existing committee's
# history predates it, so a sub_id-based dedup would either treat every old,
# sub_id-less row as a duplicate of every other (collapsing almost all existing
# history the first time this runs -- both pandas' and polars' duplicate-detection
# treat matching nulls as equal) or fail to recognize an old row and its freshly
# refetched twin as the same transaction at all. NATURAL_KEY_COLS is verified
# (against live schedule_a data) to uniquely identify a row without relying on any
# field introduced after existing data was collected -- image_number/line_number
# alone collide often (one filed image/line can list many itemized contributions),
# but combined with contributor identity/amount/date they don't.
NATURAL_KEY_COLS = ["committee_id", "contributor_id", "contributor_name", "donor_committee_name",
                     "contribution_receipt_amount", "contribution_receipt_date", "image_number",
                     "line_number"]

VAR_LIST = ["committee_id", "amendment_indicator", "amendment_indicator_desc",
            "contribution_receipt_amount", "contribution_receipt_date", "contributor_id",
            "contributor_aggregate_ytd", "contributor_city", "contributor_employer", "contributor_name",
            "contributor_first_name", "contributor_last_name", "contributor_middle_name",
            "contributor_occupation", "contributor_state", "contributor_zip", "donor_committee_name",
            "election_type", "entity_type", "entity_type_desc", "fec_election_type_desc",
            "is_individual", "line_number", "line_number_label", "receipt_type", "receipt_type_desc",
            "receipt_type_full", "image_number", "pdf_url", "sub_id"]


def scrape_schedule_a(client, committee_id: str, pbar, year=None, min_date=None):
    """
    Scrape individual contributions to a committee. Use schedules/schedule_a/ endpoint.
    Returns (status_code, polars.DataFrame). A 504 on the first attempt for a
    committee signals the caller to retry year-by-year instead (schedule_a can
    time out on committees with a very long contribution history).

    `min_date` (a "YYYY-MM-DD" string) restricts to contribution_receipt_date >= min_date,
    for an incremental pull that only fetches what's newer than a committee's last known
    date. Combined with `year` (the post-504 chunked-retry path), the chunk's own min_date
    (`{year}-01-01`) is raised to `min_date` when that's later, so a still-504ing incremental
    pull doesn't re-walk years it already has.
    """
    contrib_url = f"{client.base_url}schedules/schedule_a/"
    all_pages = []
    page = 1

    params = {"committee_id": committee_id, "per_page": 100,
              "sort": "-contribution_receipt_date", "api_key": client.api_key}
    if year is not None:
        chunk_min_date = f"{year}-01-01"
        if min_date is not None and min_date > chunk_min_date:
            chunk_min_date = min_date
        params["min_date"] = chunk_min_date
        params["max_date"] = f"{year}-12-31"
    elif min_date is not None:
        params["min_date"] = min_date

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


def _last_date_by_committee(all_history: pl.DataFrame) -> dict:
    if all_history.height == 0:
        return {}
    return dict(
        all_history.group_by("committee_id")
        .agg(pl.col("contribution_receipt_date").max())
        .iter_rows()
    )


def _merge_dedup(all_history: pl.DataFrame, fresh_batches: list) -> pl.DataFrame:
    fresh = pl.concat(fresh_batches, how="vertical_relaxed")
    # diagonal_relaxed (not vertical_relaxed): all_history may predate a VAR_LIST column
    # (e.g. sub_id) and be missing it entirely -- vertical_relaxed only reconciles dtypes
    # for columns both sides already share, it errors on a differing column set; diagonal
    # fills a genuinely missing column with nulls instead.
    combined = fresh if all_history.height == 0 else pl.concat([all_history, fresh], how="diagonal_relaxed")
    return combined.unique(subset=NATURAL_KEY_COLS, keep="last")


def fetch_schedule_a_for_committees(client, committee_file: str, output_file: str,
                                     skip: int = 0, save_every: int = 100) -> None:
    """
    Fetch schedule_a contributions for every committee_id in committee_file, incrementally: a
    committee already on file resumes from its own latest known contribution_receipt_date
    instead of being skipped or re-pulled from scratch.
    """
    if os.path.exists(output_file):
        all_history = pl.read_parquet(output_file)
        last_date_by_committee = _last_date_by_committee(all_history)
        print(f"Existing contribution history found for {len(last_date_by_committee)} committees.")
    else:
        all_history = pl.DataFrame()
        last_date_by_committee = {}

    committees_df = pl.read_csv(committee_file)
    counter = 0
    fresh_batches = []

    with tqdm(range(len(committees_df))) as pbar:
        for i in pbar:
            row = committees_df.row(i, named=True)
            committee = row["committee_id"]
            pbar.set_description(f"Committee {committee}")
            pbar.refresh()
            counter += 1

            if counter < skip:
                continue

            min_date = last_date_by_committee.get(committee)
            status_code, contributions = scrape_schedule_a(client, committee, pbar, min_date=min_date)

            if status_code == 504:
                start_year = row["active_start"]
                end_year = row["active_end"]
                if start_year is None or end_year is None:
                    print(f"Committee {committee} has no active_start/active_end -- can't chunk by year, skipping 504 fallback.")
                    contributions = pl.DataFrame()
                else:
                    if min_date is not None:
                        start_year = max(start_year, int(min_date[:4]))
                    chunk_results = []
                    for year in range(start_year, end_year + 1):
                        pbar.set_description(f"Committee {committee} - Year {year}")
                        year_min_date = min_date if year == start_year else None
                        status_code_chunk, contributions_chunk = scrape_schedule_a(
                            client, committee, pbar, year=year, min_date=year_min_date
                        )
                        if status_code_chunk == 504:
                            print(f"Committee {committee} continues to return 504 error for year {year}")
                        if contributions_chunk is not None and contributions_chunk.height > 0:
                            chunk_results.append(contributions_chunk)
                    contributions = pl.concat(chunk_results, how="vertical_relaxed") if chunk_results else pl.DataFrame()

            if contributions is not None and contributions.height > 0:
                fresh_batches.append(contributions)

            if counter % save_every == 0 and fresh_batches:
                print(f"Processed {counter} committees. Saving progress to {output_file}...")
                all_history = _merge_dedup(all_history, fresh_batches)
                fresh_batches = []
                client.atomic_write(output_file, lambda p: all_history.write_parquet(p))

    if fresh_batches:
        all_history = _merge_dedup(all_history, fresh_batches)
    if all_history.height > 0:
        client.atomic_write(output_file, lambda p: all_history.write_parquet(p))
