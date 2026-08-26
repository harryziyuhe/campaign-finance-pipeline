import base64
import json
import os
import time
from datetime import date
from pathlib import Path

import pandas as pd
import requests

# Cook Political Report API (docs: https://www.cookpolitical.com/api/documentation).
# Shared HTTP/auth/pagination/rate-limit primitives for the per-datapoint scripts in this
# folder (house_ratings.py, senate_ratings.py, governor_ratings.py, presidential_ratings.py),
# matching the fec/fec_client.py convention used elsewhere in this repo. Not runnable on its own.
#
# ASSUMPTIONS -- verify against a real response before relying on this in production, since
# these scripts have deliberately not been run yet (per instruction) and the public docs page
# doesn't fully spell out the response envelope:
#   - fetch_all_pages() handles either a bare JSON list or a dict wrapping rows under a common
#     key ("data"/"results"/"races"/"rows"); update _extract_rows() if the real shape differs.
#   - Pagination is assumed to terminate when a page returns zero rows (the docs don't describe
#     a total-page/total-count field to check instead).
#   - Each per-datapoint script overwrites its output file with the latest snapshot rather than
#     accumulating history -- Cook Political ratings are a current-state view (data isn't
#     updated more than once a day per their own docs), not a per-cycle ledger. If you want to
#     track how a rating changes over time, that needs a separate append-with-date step on top
#     of this.

BASE_URL = "https://www.cookpolitical.com/api/"


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


def _require_credentials() -> tuple:
    email = os.environ.get("COOK_POLITICAL_EMAIL")
    password = os.environ.get("COOK_POLITICAL_PASSWORD")
    if not email or not password:
        raise RuntimeError(
            "COOK_POLITICAL_EMAIL and COOK_POLITICAL_PASSWORD must both be set -- the API uses "
            "HTTP Basic Auth with your Cook Political Report account email/password, e.g.:\n"
            '  $env:COOK_POLITICAL_EMAIL = "you@example.com"\n'
            '  $env:COOK_POLITICAL_PASSWORD = "..."'
        )
    return email, password


class CookPoliticalClient:
    """
    Shared client for the Cook Political Report race-ratings API: HTTP Basic Auth, `page`-based
    pagination, and a per-endpoint once-a-day rate-limit guard (Cook Political's own docs say
    ratings are never updated more than once a day and ask API consumers to call at most once a
    day -- see check_rate_limit()).
    """

    def __init__(self):
        email, password = _require_credentials()
        token = base64.b64encode(f"{email}:{password}".encode()).decode()
        self.base_url = BASE_URL
        self.headers = {"Authorization": f"Basic {token}", "Accept": "application/json"}

        data_root = _require_data_root()
        self.output_path = str(data_root / "data" / "raw" / "electionratings" / "cook_political") + "/"
        os.makedirs(self.output_path, exist_ok=True)
        self._rate_limit_file = Path(self.output_path) / "_last_fetch.json"

    def check_rate_limit(self, endpoint: str, force: bool = False) -> None:
        """
        Refuse to fetch `endpoint` again today if it was already fetched today (persisted in
        _last_fetch.json). Re-fetching more often than daily wastes calls against a quota
        without ever seeing new data, since Cook Political's own docs say ratings aren't
        updated more than once a day. Pass force=True to override (e.g. a genuine retry after
        an earlier failed run today).
        """
        today = date.today().isoformat()
        record = {}
        if self._rate_limit_file.exists():
            with open(self._rate_limit_file, "r") as f:
                record = json.load(f)

        last = record.get(endpoint)
        if last == today and not force:
            raise RuntimeError(
                f"'{endpoint}' was already fetched today ({today}). Cook Political's API asks "
                f"consumers to call at most once a day (and data isn't updated more often than "
                f"that anyway) -- pass force=True if you genuinely need to re-fetch."
            )

        record[endpoint] = today
        with open(self._rate_limit_file, "w") as f:
            json.dump(record, f, indent=2)

    def get_json(self, endpoint: str, params: dict = None, retry_sleep: float = 5.0, max_retries: int = 5) -> dict:
        """
        GET with a LIMITED retry on non-200 -- unlike fec_client.FECClient.get_json's indefinite
        retry, this API is explicitly rate-limited, so hammering it on failure risks making
        things worse rather than just being slow.
        """
        url = f"{self.base_url}race/{endpoint}"
        attempt = 0
        while True:
            response = requests.get(url, headers=self.headers, params=params or {})
            if response.status_code == 200:
                return response.json()
            attempt += 1
            if attempt >= max_retries:
                response.raise_for_status()
            time.sleep(retry_sleep)

    def fetch_all_pages(self, endpoint: str) -> list:
        """
        Walk the `page` parameter (starting at 0, per the docs) until a page returns no rows.
        """
        page = 0
        rows = []
        while True:
            data = self.get_json(endpoint, {"page": page})
            page_rows = self._extract_rows(data)
            if not page_rows:
                break
            rows.extend(page_rows)
            page += 1
            time.sleep(1.0)
        return rows

    @staticmethod
    def _extract_rows(data) -> list:
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            for key in ("data", "results", "races", "rows"):
                if key in data and isinstance(data[key], list):
                    return data[key]
        return []

    @staticmethod
    def to_csv(rows: list, fields: list, path: str) -> pd.DataFrame:
        df = pd.DataFrame(rows)
        if not df.empty:
            df = df[[c for c in fields if c in df.columns]]
        df.to_csv(path, index=False)
        return df
