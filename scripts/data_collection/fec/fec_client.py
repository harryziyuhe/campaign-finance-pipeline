import os
import time
from pathlib import Path

import pandas as pd
import requests

BASE_URL = "https://api.open.fec.gov/v1/"


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


class FECClient:
    """
    Shared HTTP/pagination/upsert primitives for the fec/candidates, fec/committees,
    and fec/contributions scripts. Each script instantiates one FECClient and passes
    it into its own module-level functions -- keeps every script standalone/runnable
    on its own while avoiding a copy of the same retry/pagination/upsert logic in each.
    """

    def __init__(self):
        self.base_url = BASE_URL
        self.api_key = _require_api_key()
        data_root = _require_data_root()
        fec_api_path = data_root / "data" / "raw" / "fec_api"
        self.candidates_path = str(fec_api_path / "candidates") + "/"
        self.committees_path = str(fec_api_path / "committees") + "/"
        self.expenditures_path = str(fec_api_path / "expenditures") + "/"
        self.contributions_path = str(fec_api_path / "contributions") + "/"

    def get_json(self, url: str, params: dict, retry_sleep: float = 5.0) -> dict:
        """GET with indefinite retry on non-200 (matches prior FECscraper.py behavior)."""
        while True:
            response = requests.get(url, params={**params, "api_key": self.api_key})
            if response.status_code != 200:
                time.sleep(retry_sleep)
                continue
            return response.json()

    def paginate_by_page(self, url: str, params: dict, page_sleep: float = 0.5) -> list:
        """
        Walk a simple page-numbered endpoint (candidate/committee list & history
        endpoints -- these use plain `page` increments, not the cursor-based
        `last_index` pagination that schedule_a/schedule_e need) to exhaustion.
        Returns the concatenated raw `results` rows.
        """
        params = {**params, "page": 1}
        rows = []
        while True:
            data = self.get_json(url, params)
            results = data.get("results", [])
            if not results:
                break
            rows.extend(results)
            total_pages = data.get("pagination", {}).get("pages", 1)
            if params["page"] >= total_pages:
                break
            params["page"] += 1
            time.sleep(page_sleep)
        return rows

    def scrape_committees(self, params: dict, fields: list) -> pd.DataFrame:
        """
        Paginate the committees/ list endpoint with arbitrary filter params
        (e.g. {"designation": "D"}, {"committee_type": "O"}, {"organization_type": "C"}),
        returning `fields` columns. Shared by every fec/committees/*_pacs.py /
        *_committees.py script so each one only has to state its own filter+fields.
        """
        committee_url = f"{self.base_url}committees/"
        rows = self.paginate_by_page(committee_url, {"per_page": 100, **params})
        if not rows:
            return pd.DataFrame(columns=fields)
        df = pd.json_normalize(rows)
        return df[fields]

    @staticmethod
    def upsert_csv(fresh_df: pd.DataFrame, path: str, key_cols: list) -> pd.DataFrame:
        """
        Merge fresh_df into the CSV at `path` by key_cols: a fresh row replaces any
        existing row sharing the same key (catches rare retroactive corrections to
        already-known history), and a fresh row with a never-seen key is appended
        (catches new history). Does not delete a stored row just because the fresh
        pull no longer returns it. Writes the merged result back and returns it.
        """
        if os.path.exists(path):
            existing_df = pd.read_csv(path)
            combined = pd.concat([existing_df, fresh_df], ignore_index=True)
        else:
            combined = fresh_df
        combined = (
            combined
            .drop_duplicates(subset=key_cols, keep="last")
            .sort_values(by=key_cols)
            .reset_index(drop=True)
        )
        combined.to_csv(path, index=False)
        return combined
