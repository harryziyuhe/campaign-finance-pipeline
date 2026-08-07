from typing import Any
from urllib import response

import pandas as pd
import polars as pl
import requests
import time
import json
import os
from tqdm import tqdm
from pathlib import Path

BASE_URL = "https://api.open.fec.gov/v1/"
SCRIPT_ROOT = Path(__file__).resolve().parents[3]


def _require_data_root() -> Path:
    value = os.environ.get("CAMPAIGNFINANCE_DATA_ROOT")
    if not value:
        raise RuntimeError(
            "CAMPAIGNFINANCE_DATA_ROOT is not set. Point it at the campaign-finance-data "
            "folder (contains data/ and outputs/), e.g.:\n"
            '  $env:CAMPAIGNFINANCE_DATA_ROOT = "C:\\Users\\<you>\\Dropbox\\campaign-finance-data"'
        )
    root = Path(value)
    if not root.is_dir():
        raise RuntimeError(f"CAMPAIGNFINANCE_DATA_ROOT does not exist: {root}")
    return root


def _require_api_key() -> str:
    value = os.environ.get("FEC_API_KEY")
    if not value:
        raise RuntimeError(
            "FEC_API_KEY is not set. Get a key at https://api.data.gov/signup/ and set it, e.g.:\n"
            '  $env:FEC_API_KEY = "<your-key>"'
        )
    return value


DATA_ROOT = _require_data_root()
FEC_API_PATH = DATA_ROOT / "data" / "raw" / "fec_api"
CANDIDATES_FILE_PATH = str(FEC_API_PATH / "candidates") + "/"
COMMITTEES_FILE_PATH = str(FEC_API_PATH / "committees") + "/"
EXPENDITURES_FILE_PATH = str(FEC_API_PATH / "expenditures") + "/"
CONTRIBUTIONS_FILE_PATH = str(FEC_API_PATH / "contributions") + "/"
API_KEY = _require_api_key()
IE_PACS = ["hybrid", "independent expenditure"]
large_pacs = ["C00484642"]

class FECScraper:
    def __init__(self):
        self.base_url = BASE_URL
        self.apikey = API_KEY
        self.candidates_path = CANDIDATES_FILE_PATH
        self.committees_path = COMMITTEES_FILE_PATH
        self.expenditures_path = EXPENDITURES_FILE_PATH
        self.contributions_path = CONTRIBUTIONS_FILE_PATH
    
    def expand_candidate(self, candidate: dict) -> list:
        """
        Parse basic information of candidates' records.
        Expand one candidate dictionary into rows, one row per matching election year and principal committee cycle
        """
        vars_list = ["candidate_id", "name", "party", "party_full"]
        base_fields = {
            k: v for k, v in candidate.items()
            if k in vars_list
        }
        
        rows = []
        election_years = candidate.get("election_years", [])
        committees = candidate.get("principal_committees", []) 

        for year in election_years:
            matching_committees = [
                c for c in committees if year in c.get("cycles", [])
            ]

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
                        "committee_affiliate": c.get("affiliated_committee_name")
                    }
                rows.append(row)
            else:
                row = {
                    **base_fields,
                    "election_year": year,
                    "committee_id": None,
                    "committee_name": None,
                    "committee_state": None,
                    "committee_party": None,
                    "committee_designation": None,
                    "committee_designation_full": None,
                    "committee_treasurer": None,
                    "committee_affiliate": None,
                }
                rows.append(row)
        return rows

    def parse_candidates(self, office = "H") -> None:
        """
        Parse all json files from the API scrape. Generate a comprehensive candidate-committee pair dataframe
        """
        data_dir = f"{self.candidates_path}{office}"
        
        all_cands = []
        
        for filename in sorted(os.listdir(data_dir)):
            if filename.endswith(".json"):
                filepath = os.path.join(data_dir, filename)
                with open(filepath, "r") as f:
                    data = json.load(f)

                    for candidate in data.get("results", []):
                        all_cands.extend(self.expand_candidate(candidate))

        df_cands = pd.DataFrame(all_cands)
        df_cands.to_csv(f"{self.candidates_path}candidates_{office}.csv")

    def scrape_candidates(self, office:str = "H") -> None:
        """
        Scrape basic information and principal committees for all candidates by office.
        Save scraped records in json files by page in candidates file path.
        Use candidates/search/ endpoint
        Each candidate is paired with identified principal committee
        """
        page = 1
        cand_url = f"{self.base_url}candidates/search/"
        while True:
            params = {
                "page": page,
                "per_page": 100,
                "office": office,
                "api_key": self.apikey
            }
            response = requests.get(cand_url, params = params)
            if response.status_code != 200:
                time.sleep(5)
                continue
            data = response.json()

            with open(f"{self.candidates_path}{office}/page_{page}.json", "w") as f:
                json.dump(data, f)
            
            total_pages = data.get("pagination", {}).get("pages", 99999)
            print(f"Scraped {page} pages out of {total_pages} pages")
            if page == total_pages:
                break
            page = page + 1
            time.sleep(0.5)

    def scrape_candidate_history(self, candidate_id: str) -> pd.DataFrame:
        """
        Scrape candidate's characteristics over time. Information aggregated by candidate_id,
        a unique identifier per candidate per office.
        Use candidate/{candidate_id}/history/ endpoint 
        """
        history_url = f"{self.base_url}candidate/{candidate_id}/history/"

        vars_list = ["candidate_id", "candidate_last_name", "candidate_first_name", "candidate_middle_name",
                         "address_city", "address_state", "address_zip", "candidate_election_year",
                         "district", "district_number", "incumbent_challenge", "incumbent_challenge_full",
                         "name", "office", "party", "party_full", "state"]
        
        all_pages = []
        page = 1

        while True:
            params = {
                "page": page,
                "per_page": 100,
                "api_key": self.apikey
            }
            response = requests.get(history_url, params = params)
            if response.status_code != 200:
                time.sleep(5)
                continue
            data = response.json()
            total_pages = data.get("pagination", {}).get("pages", 99999)
            time.sleep(0.5)
            
            page_df = pd.json_normalize(data.get("results", []))
            if len(page_df) == 0:
                break
            page_df = page_df[vars_list]

            all_pages.append(page_df)

            if page >= total_pages:
                break

            page = page + 1

        if len(all_pages) == 0:
            return pd.DataFrame()
        return pd.concat(all_pages, ignore_index = True)

    def fetch_candidate_history(self, office: str = "H", start_year = None):
        candidate_file = f"{self.candidates_path}candidates_{office}.csv"
        if not os.path.exists(candidate_file):
            self.parse_candidates()
        candidates_df = pd.read_csv(candidate_file)
        if start_year:
            candidates_df = candidates_df[candidates_df["election_year"] >= start_year]
        candidates = candidates_df["candidate_id"].unique()
        if os.path.exists(f"{self.candidates_path}candidate_history_{office}.csv"):
            all_hist = pd.read_csv(f"{self.candidates_path}candidate_history_{office}.csv")
            existing_cands = all_hist["candidate_id"].values
        else:
            all_hist = pd.DataFrame()
            existing_cands = []
        for candidate in tqdm(candidates):
            if candidate in existing_cands:
                continue
            history = self.scrape_candidate_history(candidate)
            if len(history) > 0:
                all_hist = pd.concat([all_hist, pd.DataFrame(history)])
            else:
                print(candidate)
            all_hist.to_csv(f"{self.candidates_path}candidate_history_{office}.csv", index = False)

    def scrape_candidate_committees(self, candidate_id: str) -> pd.DataFrame:
        """
        Scrape candidate's affiliated committees over time
        Use candidate/{candidate_id}/committees/history/ endpoint
        """
        committee_url = f"{self.base_url}candidate/{candidate_id}/committees/history/"

        var_list = ["committee_id", "committee_type", "committee_type_full",
                    "cycle", "designation", "designation_full", "is_active", 
                    "name", "organization_type", "organization_type_full",
                    "party", "party_full", "state"]

        all_pages = []
        page = 1

        while True:
            params = {"page": page,
                      "per_page": 100,
                      "api_key": self.apikey}
            response = requests.get(committee_url, params = params)
            if response.status_code != 200:
                print(f"Scraping {candidate_id} Failed. Network Error.")
                time.sleep(5)
                continue
            data = response.json()
            total_pages = data.get("pagination", {}).get("pages", 99999)

            # Get base columns
            base = pd.json_normalize((data.get("results", [])))
            if len(base) == 0:
                break
            base = base[var_list].copy()
            base["candidate_id"] = candidate_id

            # Process multiple candidate_id values
            candidates = (
                pd.json_normalize(data.get("results", []))[["committee_id", "cycle", "candidate_ids"]]
                .explode("candidate_ids")
                .reset_index(drop = True)
            )

            # Process joint committee data
            jfc_rows = []
            for row in data.get("results", []):
                cid = row.get("committee_id")
                cycle = row.get("cycle")
                for j in row.get("jfc_committee", []) or []:
                    jfc_rows.append({
                        "committee_id": cid,
                        "cycle": cycle,
                        "joint_committee_id": j.get("joint_committee_id"),
                        "joint_committee_name": j.get("joint_committee_name"),
                    })

            jfc = pd.DataFrame(
                jfc_rows,
                columns=["committee_id", "cycle", "joint_committee_id", "joint_committee_name"]
            )

            page_df = (
                base
                .merge(candidates, on = ["committee_id", "cycle"], how = "left")
                .merge(jfc, on = ["committee_id", "cycle"], how = "left")
            )

            all_pages.append(page_df)

            if page >= total_pages:
                break

            page = page + 1
        
        if len(all_pages) == 0:
            return pd.DataFrame()
        return pd.concat(all_pages, ignore_index = True)

    def fetch_candidate_committees(self, office: str = "H", start_year = None):
        counter = 0

        candidate_file = f"{self.candidates_path}candidates_{office}.csv"
        if not os.path.exists(candidate_file):
            self.parse_candidates()
        candidates_df = pd.read_csv(candidate_file)
        if start_year:
            candidates_df = candidates_df[candidates_df["election_year"] >= start_year]
        candidates = candidates_df["candidate_id"].unique()
        if os.path.exists(f"{self.candidates_path}candidate_committees_{office}.csv"):
            all_committees = pd.read_csv(f"{self.candidates_path}candidate_committees_{office}.csv")
            existing_cands = all_committees["candidate_id"].values
        else:
            all_committees = pd.DataFrame()
            existing_cands = []
        for candidate in tqdm(candidates):
            if candidate in existing_cands:
                continue
            committees = self.scrape_candidate_committees(candidate)
            if len(committees) > 0:
                all_committees = pd.concat([all_committees, pd.DataFrame(committees)])
                counter += 1
            else:
                continue
            if counter % 50 == 0:
                all_committees.to_csv(f"{self.candidates_path}candidate_committees_{office}.csv", index = False)
                counter = 0
        all_committees.to_csv(f"{self.candidates_path}candidate_committees_{office}.csv", index = False)

    def scrape_committee_designation(self, designation):
        """
        Scrape all leadership pacs
        Use committees/ endpoint
        """
        page = 1
        committee_url = f"{self.base_url}committees/"
        vars_list = ["committee_id", "committee_type", "committee_type_full",
                     "designation", "designation_full", "name", "state"]

        all_pages = []

        # request first page to get total_pages
        params = {
            "page": page,
            "per_page": 100,
            "designation": designation,
            "api_key": self.apikey
        }
        response = requests.get(committee_url, params=params)
        response.raise_for_status()
        data = response.json()
        total_pages = data.get("pagination", {}).get("pages", 1)

        with tqdm(total=total_pages, desc=f"Scraping {designation} PACs") as pbar:
            while True:
                params["page"] = page
                response = requests.get(committee_url, params=params)
                if response.status_code != 200:
                    time.sleep(5)
                    continue
                data = response.json()
                time.sleep(0.5)

                page_df = pd.json_normalize(data.get("results", []))
                if len(page_df) == 0:
                    break
                page_df = page_df[vars_list]
                all_pages.append(page_df)

                pbar.update(1)  # update progress

                if page >= total_pages:
                    break
                page += 1

        if len(all_pages) == 0:
            return
        if designation == "D":
            pd.concat(all_pages).to_csv(f"{self.committees_path}leadership_pacs.csv", index=False)
        elif designation == "J":
            pd.concat(all_pages).to_csv(f"{self.committees_path}joint_committees.csv", index=False)

    def scrape_committee_type(self, type):
        """
        Scrape all leadership pacs
        Use committees/ endpoint
        """
        page = 1
        committee_url = f"{self.base_url}committees/"
        vars_list = ["committee_id", "committee_type", "committee_type_full",
                     "designation", "designation_full", "name", "state"]

        all_pages = []

        # request first page to get total_pages
        params = {
            "page": page,
            "per_page": 100,
            "committee_type": type,
            "api_key": self.apikey
        }
        response = requests.get(committee_url, params=params)
        response.raise_for_status()
        data = response.json()
        total_pages = data.get("pagination", {}).get("pages", 1)

        with tqdm(total=total_pages, desc=f"Scraping {type} PACs") as pbar:
            while True:
                params["page"] = page
                response = requests.get(committee_url, params=params)
                if response.status_code != 200:
                    time.sleep(5)
                    continue
                data = response.json()
                time.sleep(0.5)

                page_df = pd.json_normalize(data.get("results", []))
                if len(page_df) == 0:
                    break
                page_df = page_df[vars_list]
                all_pages.append(page_df)

                pbar.update(1)  # update progress

                if page >= total_pages:
                    break
                page += 1

        if len(all_pages) == 0:
            return
        return pd.concat(all_pages)

    def fetch_expenditure_pacs(self, type = None):

        if type not in IE_PACS:
            raise ValueError(f"{type} is not a valid expenditure PAC type")
        
        if type is None:
            type = IE_PACS[0]
        
        if type == "hybrid":
            nonqualified = self.scrape_committee_type(type = "V")
            qualified = self.scrape_committee_type(type = "W")
            pd.concat([nonqualified, qualified]).to_csv(f"{self.committees_path}hybrid_pacs.csv", index=False) 

        if type == "independent expenditure":
            superpacs = self.scrape_committee_type(type = "O")
            singlecand = self.scrape_committee_type(type = "U")
            pd.concat([superpacs, singlecand]).to_csv(f"{self.committees_path}super_pacs.csv", index=False)
        
    def scrape_leadership_history(self, committee_id: str) -> pd.DataFrame:
        """
        Scrape committee's characteristics over time. Information aggregated by committee_id
        Use committee/{committee_id}/history/ endpoint
        """
        history_url = f"{self.base_url}committee/{committee_id}/history/"

        var_list = ["committee_id", "committee_type", "committee_type_full",
                    "cycle", "designation", "designation_full", "is_active", "name", 
                    "party", "party_full", "state"]
        
        all_pages = []
        page = 1

        while True:
            params = {
                "page": page,
                "per_page": 100,
                "api_key": self.apikey
            }
            response = requests.get(history_url, params = params)
            if response.status_code != 200:
                time.sleep(5)
                continue
            data = response.json()
            total_pages = data.get("pagination", {}).get("pages", 99999)
            time.sleep(0.5)

            base = pd.json_normalize(data.get("results", []))
            if len(base) == 0:
                break
            base = base[var_list]

            sponsors = (
                pd.json_normalize(data.get("results", []))[["committee_id", "cycle", "sponsor_candidate_ids"]]
                .explode("sponsor_candidate_ids")
                .reset_index(drop = True)
            )

            page_df = pd.merge(base, sponsors,
                               on = ["committee_id", "cycle"],
                               how = "left")
            
            all_pages.append(page_df)

            if page >= total_pages:
                break
            page = page + 1
        
        if len(all_pages) == 0:
            return pd.DataFrame()
        return pd.concat(all_pages, ignore_index = True)
    
    def fetch_leadership_history(self):
        committee_file = f"{self.committees_path}leadership_pacs.csv"
        if not os.path.exists(committee_file):
            self.scrape_leadership_pacs()
        committees_df = pd.read_csv(committee_file)
        committees = committees_df["committee_id"].unique()
        if os.path.exists(f"{self.committees_path}leadership_history.csv"):
            all_history = pd.read_csv(f"{self.committees_path}leadership_history.csv")
            existing_committees = all_history["committee_id"].values
        else:
            all_history = pd.DataFrame()
            existing_committees = []
        for committee in tqdm(committees):
            if committee in existing_committees:
                continue
            history = self.scrape_leadership_history(committee)
            if len(history) > 0:
                all_history = pd.concat([all_history, pd.DataFrame(history)])
                all_history.to_csv(f"{self.committees_path}leadership_history.csv", index = False)

    def scrape_independent_expenditure(self, committee_id: str) -> pd.DataFrame:
        """
        Scrape committee's characteristics over time. Information aggregated by committee_id
        Use schedules/schedule_e/ endpoint
        """
        ie_url = f"{self.base_url}schedules/schedule_e/"

        var_list = ["committee_id", "candidate_id", "support_oppose_indicator",
                    "action_code", "amendment_indicator", "candidate_last_name", "candidate_first_name", 
                    "candidate_party", "category_code", 
                    "category_code_full", "disbursement_dt", "election_type", 
                    "expenditure_amount", "expenditure_date", "expenditure_description", 
                    "image_number", "pdf_url"]

        all_pages = []
        page = 1

        params = {
            "committee_id": committee_id,
            "per_page": 100,
            "sort": "-expenditure_date",
            "api_key": self.apikey
        }

        while True:
            response = requests.get(ie_url, params = params)
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
            page_df = page_df[var_list]
            all_pages.append(page_df)
            if page >= total_pages:
                break
            page = page + 1

            params["last_index"] = last_sort_idx
            params["last_expenditure_date"] = last_sort_info
        
        if len(all_pages) == 0:
            return pd.DataFrame()
        return pd.concat(all_pages, ignore_index = True)

    def fetch_independent_expenditure(self, type = None, skip = 0):
        if type not in IE_PACS:
            raise ValueError(f"{type} is not a valid expenditure PAC type")
        
        if type is None:
            type = IE_PACS[0]

        if type == "hybrid":
            pac_type = "hybrid"
        if type == "independent expenditure":
            pac_type = "super"

        committee_file = f"{self.committees_path}{pac_type}_pacs.csv"
        if os.path.exists(f"{self.expenditures_path}{pac_type}_expenditures.csv"):
            all_history = pd.read_csv(f"{self.expenditures_path}{pac_type}_expenditures.csv")
            existing_committees = all_history["committee_id"].values
        else:
            all_history = pd.DataFrame()
            existing_committees = []

        committees_df = pd.read_csv(committee_file)
        committees = committees_df["committee_id"].unique()

        counter = 0
        
        for committee in tqdm(committees):
            counter = counter + 1
            if counter < skip:
                continue
            if committee in existing_committees:
                continue
            expenditures = self.scrape_independent_expenditure(committee)
            if len(expenditures) > 0:
                all_history = pd.concat([all_history, pd.DataFrame(expenditures)])
                all_history.to_csv(f"{self.expenditures_path}{pac_type}_expenditures.csv", index=False)

    def scrape_contributions(self, committee_id: str, pbar, year = None):
        """
        Scrape individual contributions to a committee. Use schedules/schedule_a/ endpoint
        """
        contrib_url = f"{self.base_url}schedules/schedule_a/"

        var_list = ["committee_id", "amendment_indicator", "amendment_indicator_desc", 
                    "contribution_receipt_amount", "contribution_receipt_date", "contributor_id", 
                    "contributor_aggregate_ytd", "contributor_city", "contributor_employer", "contributor_name",
                    "contributor_first_name", "contributor_last_name", "contributor_middle_name",
                    "contributor_occupation", "contributor_state", "contributor_zip", "donor_committee_name",
                    "election_type", "entity_type", "entity_type_desc", "fec_election_type_desc",
                    "is_individual",  "line_number", "line_number_label", "receipt_type", "receipt_type_desc",
                    "receipt_type_full", "image_number", "pdf_url"]

        all_pages = []
        page = 1

        params = {
            "committee_id": committee_id,
            "per_page": 100,
            "sort": "-contribution_receipt_date",
            "api_key": self.apikey
        }

        if year is not None:
            params["min_date"] = f"{year}-01-01"
            params["max_date"] = f"{year}-12-31"

        status_code = None
        error_page = None

        while True:
            response = requests.get(contrib_url, params = params)
            if response.status_code != 200:
                print(f"Error processing Committee {committee_id} with year {year}: {response.status_code}")
                if response.status_code == 504:
                    if status_code == 504:
                        return status_code, None
                    else:
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
            missing_cols = [col for col in var_list if col not in page_df.columns]
            if missing_cols:
                page_df = page_df.with_columns(
                    [pl.lit(None).alias(col) for col in missing_cols]
                )
            if len(page_df) == 0:
                break
            page_df = page_df.select(var_list)
            all_pages.append(page_df)
            if page >= total_pages:
                break
            pbar.set_postfix_str(f"page {page}/{total_pages}")
            if error_page and page - error_page > 10:
                error_page = None
                status_code = None
            page = page + 1

            params["last_index"] = last_sort_idx
            params["last_contribution_receipt_date"] = last_sort_info

            time.sleep(0.5)
        
        if len(all_pages) == 0:
            return 200, pl.DataFrame(schema={col: pl.Null for col in var_list})
        return 200, pl.concat(all_pages, how="vertical_relaxed")

    def fetch_contributions(self, type = None, skip = 0, save_every = 100):
        if type == "hybrid":
            pac_type = "hybrid"
        elif type == "independent expenditure":
            pac_type = "super"
        elif type == "leadership":
            pac_type = "leadership"
        elif type == "corporate":
            pac_type = "corporate"
        else:
            raise ValueError(f"{type} is not a supported PAC type")

        committee_file = f"{self.committees_path}{pac_type}_pacs.csv"
        output_file = f"{self.contributions_path}{pac_type}_contributions.parquet"

        if os.path.exists(f"{self.contributions_path}{pac_type}_contributions.parquet"):
            all_history = pl.read_parquet(output_file)
            existing_committees = set(all_history["committee_id"].drop_nulls().to_list())
            print(f"Existing contribution history found for {len(existing_committees)} committees.")
        else:
            all_history = pl.DataFrame()
            existing_committees = set()

        committees_df = pl.read_csv(committee_file)

        counter = 0
        pbar = tqdm(
            range(len(committees_df))
        )
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

                status_code, contributions = self.scrape_contributions(committee, pbar)
            
                #  Handle case where API returns 504 error for certain committees. Scrape contributions by year for those committees to bypass timeout issue
                if status_code == 504:
                    start_year = row["active_start_year"]
                    end_year = row["active_end_year"]

                    chunk_results = []
                    for year in range(start_year, end_year + 1):
                        pbar.set_description(f"Committee {committee} - Year {year}")
                        status_code_chunk, contributions_chunk = self.scrape_contributions(committee, pbar, year)
                        if status_code_chunk == 504:
                            print(f"Committee {committee} continues to return 504 error for year {year}")
                        if contributions_chunk.height > 0:
                            chunk_results.append(contributions_chunk)

                    if chunk_results:
                        contributions = pl.concat(chunk_results, how="vertical_relaxed")
                    else:                    
                        contributions = pl.DataFrame()

                if contributions.height > 0:
                    if all_history.height == 0:
                        all_history = contributions
                    else:
                        all_history = pl.concat([all_history, contributions], how="vertical_relaxed")

                    existing_committees.add(committee)
            
                if counter % save_every == 0 and all_history.height > 0:
                    print(f"Processed {counter} committees. Saving progress to {output_file}...")
                    all_history.write_parquet(output_file)

    def scrape_committee_active_period(self, committee_id: str):
        active_url = f"{self.base_url}committee/{committee_id}/history/"

        params = {
            "per_page": 20,
            "api_key": self.apikey
        }

        while True:
            response = requests.get(active_url, params = params)
            if response.status_code != 200:
                print(f"Error processing Committee {committee_id} with url {active_url}: {response.status_code}")
                time.sleep(5)
                continue
            data = response.json()
            results = data.get("results", [])
            if len(results) == 0:
                return None, None
            cycles = results[0].get("cycles", [])
            if len(cycles) == 0:
                return None, None
            return min(cycles), max(cycles)
        
    def fill_committee_active_period(self, type: str):
        if type == "hybrid":
            pac_type = "hybrid"
        elif type == "independent expenditure":
            pac_type = "super"
        elif type == "leadership":
            pac_type = "leadership"
        else:
            raise ValueError(f"{type} is not a supported PAC type")
        committee_file = f"{self.committees_path}{pac_type}_pacs.csv"
        df = pd.read_csv(committee_file)
        df["active_start_year"] = None
        df["active_end_year"] = None

        for idx, row in tqdm(df.iterrows(), total=df.shape[0]):
            committee_id = row["committee_id"]
            start_year, end_year = self.scrape_committee_active_period(committee_id)
            df.at[idx, "active_start_year"] = start_year
            df.at[idx, "active_end_year"] = end_year

            if idx % 100 == 0:
                df.to_csv(committee_file, index=False)

if __name__ == "__main__":
    scraper = FECScraper()
    """
    Order of scraping process
    1. Scrape information of all candidates by chamber (H/S/P) and their principal committee using 
        scrape_candidates(). Save records to candidates_{chamber}.csv
    2. Scrape all history of candidates running using fetch_candidate_history(). Save records to 
        candidate_history_{chamber}.csv
    """
    # scraper.scrape_candidates("S")
    # scraper.parse_candidates("S")
    # scraper.fetch_candidate_history(office = "S", start_year = 2004)
    # scraper.fetch_candidate_committees(office = "S", start_year = 2004)
    # scraper.scrape_committee_designation(designation = "D")
    # scraper.fetch_leadership_history()
    # scraper.scrape_committee_designation(designation = "J")
    # scraper.fetch_expenditure_pacs(type = "hybrid")
    # scraper.fetch_expenditure_pacs(type = "independent expenditure")
    # scraper.fill_committee_active_period(type = "independent expenditure")
    # print(scraper.scrape_independent_expenditure("C00877886"))
    # scraper.fetch_independent_expenditure(type = "independent expenditure", skip = 3653)
    # scraper.fetch_contributions(type = "independent expenditure", skip = 6180)
    # print(scraper.scrape_contributions("C00554410"))
