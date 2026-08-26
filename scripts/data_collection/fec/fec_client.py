import json
import os
import tempfile
import time
from datetime import date, datetime
from pathlib import Path

import numpy as np
import pandas as pd
import requests

BASE_URL = "https://api.open.fec.gov/v1/"
SCRIPT_ROOT = Path(__file__).resolve().parents[3]  # repo root -- used only for log/
LOG_DIR = SCRIPT_ROOT / "log"


def current_cycle_threshold(today: date = None) -> int:
    """
    Lowest cycle/election year that still counts as "current" (mutable) as of `today`
    (defaults to the real today). A cycle freezes once its general election has passed:
    before November, `cycle >= current_year` is current; from November on, the just-
    elapsed `current_year` cycle freezes too, so only `cycle >= current_year + 1` is current.
    """
    today = today or date.today()
    return today.year + 1 if today.month >= 11 else today.year


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
        self.data_root = data_root
        fec_api_path = data_root / "data" / "raw" / "fec_api"
        self.candidates_path = str(fec_api_path / "candidates") + "/"
        self.committees_path = str(fec_api_path / "committees") + "/"
        self.expenditures_path = str(fec_api_path / "expenditures") + "/"
        self.contributions_path = str(fec_api_path / "contributions") + "/"
        self.processed_fec_path = str(data_root / "data" / "processed" / "fec") + "/"

    @staticmethod
    def atomic_write(path: str, write_fn) -> None:
        """
        Call write_fn(tmp_path) to write to a temp file in the same directory as `path`, then
        atomically replace `path` with it via os.replace(). Every write in this pipeline writes
        directly onto a file that IS the accumulated history, with no separate backup -- os.replace
        is atomic at the OS level, so a crash or power loss mid-write leaves the old file fully
        intact instead of truncated/corrupted. This matters especially for parquet, which stores
        its schema footer at the *end* of the file: an interrupted write there makes the entire
        file unreadable, not just the newest rows.
        """
        directory = os.path.dirname(str(path)) or "."
        fd, tmp_path = tempfile.mkstemp(dir=directory, prefix=".tmp_", suffix=os.path.splitext(str(path))[1])
        os.close(fd)
        try:
            write_fn(tmp_path)
            # A cloud-synced data folder (Dropbox, OneDrive, ...) can transiently hold the
            # destination open on Windows while it reads the file to sync it -- retry a few
            # times with backoff before giving up, rather than failing the whole run over what
            # is usually a one-off race, not a real conflict.
            for attempt in range(5):
                try:
                    os.replace(tmp_path, path)
                    break
                except PermissionError:
                    if attempt == 4:
                        raise
                    time.sleep(0.5 * (2 ** attempt))
        except BaseException:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
            raise

    @staticmethod
    def read_csv_safe(path: str, **kwargs) -> pd.DataFrame:
        """
        pd.read_csv with pandas' default NA-value sniffing turned off, keeping only a truly
        empty field as missing. pandas' default na_values list includes common real-world
        placeholder strings -- "N/A", "NA", "null", "None", "NaN", etc. -- so a genuine raw data
        value like a contributor_city of "N/A" silently becomes an actual NaN every time the
        file round-trips, changing that row's identity for key-matching purposes on each re-read
        even though nothing about the underlying data changed. Any of this module's merge
        helpers that key on columns which might legitimately contain such text must read through
        this instead of a bare pd.read_csv.
        """
        return pd.read_csv(path, keep_default_na=False, na_values=[""], **kwargs)

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

    def scrape_committee_active_periods(self, params: dict) -> pd.DataFrame:
        """
        Fetch committees matching `params` from the committees/ list endpoint and derive each
        committee's active_start/active_end from its `cycles` field (min/max cycle year) --
        the bulk committee search response already includes `cycles`, so this needs no extra
        per-committee API calls. Committees with no cycle data are dropped (nothing to record).
        """
        committee_url = f"{self.base_url}committees/"
        rows = self.paginate_by_page(committee_url, {"per_page": 100, **params})
        if not rows:
            return pd.DataFrame(columns=["committee_id", "active_start", "active_end"])
        df = pd.json_normalize(rows)[["committee_id", "cycles"]]
        df = df[df["cycles"].apply(lambda c: isinstance(c, list) and len(c) > 0)]
        return pd.DataFrame({
            "committee_id": df["committee_id"],
            "active_start": df["cycles"].apply(min),
            "active_end": df["cycles"].apply(max),
        })

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
            existing_df = FECClient.read_csv_safe(path)
            combined = pd.concat([existing_df, fresh_df], ignore_index=True)
        else:
            combined = fresh_df
        combined = (
            combined
            .drop_duplicates(subset=key_cols, keep="last")
            .sort_values(by=key_cols)
            .reset_index(drop=True)
        )
        FECClient.atomic_write(path, lambda p: combined.to_csv(p, index=False))
        return combined

    @staticmethod
    def insert_only_csv(fresh_df: pd.DataFrame, path: str, key_cols: list) -> pd.DataFrame:
        """
        Merge fresh_df into the CSV at `path` by key_cols, but only ever insert brand-new
        keys -- an existing row is never overwritten, even if the fresh value for that key
        differs. Use this instead of merge_cyclical/upsert_csv when the source snapshot only
        reflects each record's *current* value for every field (e.g. the FEC candidate-search
        endpoint returns a candidate's present name/party for every election_year it lists,
        not what was true as of that year), so a "fresh" value is never more trustworthy than
        what's already stored, even for the current cycle. Writes and returns the merged frame.
        """
        if not os.path.exists(path):
            merged = (
                fresh_df.drop_duplicates(subset=key_cols, keep="last")
                .sort_values(by=key_cols)
                .reset_index(drop=True)
            )
            FECClient.atomic_write(path, lambda p: merged.to_csv(p, index=False))
            return merged

        existing_df = FECClient.read_csv_safe(path)
        fresh_df = fresh_df.drop_duplicates(subset=key_cols, keep="last")
        FECClient._harmonize_key_dtypes(fresh_df, existing_df, key_cols, cycle_col=None)

        is_known = np.asarray(
            fresh_df.merge(existing_df[key_cols], on=key_cols, how="left", indicator=True)["_merge"]
            == "both"
        )
        new_rows = fresh_df[np.logical_not(is_known)]

        merged = (
            pd.concat([existing_df, new_rows], ignore_index=True)
            .drop_duplicates(subset=key_cols, keep="last")
            .sort_values(by=key_cols)
            .reset_index(drop=True)
        )
        FECClient.atomic_write(path, lambda p: merged.to_csv(p, index=False))
        return merged

    @staticmethod
    def _composite_key(df: pd.DataFrame, cols: list) -> pd.Series:
        """
        Build a single unambiguous string key from `cols`, with true-null values mapped to a
        sentinel that can't collide with any real value (including an empty string, which stays
        distinguishable from null). Used instead of a raw pandas multi-column Index/MultiIndex
        for matching: MultiIndex set/intersection operations built from separately-constructed
        DataFrames don't reliably treat null-vs-null (or null-vs-empty-string) the same way
        across calls, which made an all-null-ish key row's identity ambiguous and non-
        deterministic between runs.
        """
        null_sentinel = "\x00__NULL__\x00"
        key = None
        for col in cols:
            values = df[col]
            as_str = values.astype(str).where(values.notna(), null_sentinel)
            key = as_str if key is None else key + "\x01" + as_str
        return key

    @staticmethod
    def append_only_csv(fresh_df: pd.DataFrame, path: str, key_cols: list) -> pd.DataFrame:
        """
        Merge fresh_df into the CSV at `path` by key_cols, preserving row POSITION: an existing
        key's row is refreshed in place (values updated from fresh_df, but the row never moves)
        and a brand-new key is appended at the end. Never re-sorts and never reorders existing
        rows. Use this instead of insert_only_csv whenever something downstream depends on a
        row's *position* in the file (e.g. a positional row index used as a join key elsewhere,
        as FECsuperOrganizationFirmMatcher.py's contributor_row_index is) -- unlike
        insert_only_csv, values (e.g. a running total) DO get refreshed here, just never at the
        cost of moving a row, since resorting or reordering would silently misalign that
        external reference even when no data was lost.
        """
        fresh_df = fresh_df.copy()
        fresh_df["_dedup_key"] = FECClient._composite_key(fresh_df, key_cols)
        fresh_df = fresh_df.drop_duplicates(subset="_dedup_key", keep="last")

        if not os.path.exists(path):
            merged = fresh_df.drop(columns="_dedup_key").reset_index(drop=True)
            FECClient.atomic_write(path, lambda p: merged.to_csv(p, index=False))
            return merged

        existing_df = FECClient.read_csv_safe(path)
        existing_df["_dedup_key"] = FECClient._composite_key(existing_df, key_cols)

        fresh_indexed = fresh_df.set_index("_dedup_key")
        existing_indexed = existing_df.set_index("_dedup_key")

        common_keys = existing_indexed.index.intersection(fresh_indexed.index)
        update_cols = [c for c in fresh_indexed.columns if c in existing_indexed.columns]
        existing_indexed.loc[common_keys, update_cols] = fresh_indexed.loc[common_keys, update_cols]

        new_keys = fresh_indexed.index.difference(existing_indexed.index)
        new_rows = fresh_indexed.loc[new_keys]

        merged = pd.concat([existing_indexed, new_rows]).reset_index(drop=True)
        FECClient.atomic_write(path, lambda p: merged.to_csv(p, index=False))
        return merged

    @staticmethod
    def merge_active_period(fresh_df: pd.DataFrame, path: str, id_col: str = "committee_id") -> pd.DataFrame:
        """
        Merge fresh_df (columns: id_col, active_start, active_end) into the CSV at `path`:
        an id_col never seen before is inserted as-is (gap-fill); for an id_col already on
        file, active_start is left untouched and active_end is only raised to the fresh value
        if it's larger (a PAC still filing in later cycles) -- it's never lowered, and nothing
        else about an already-known row is ever overwritten. Writes and returns the merged frame.
        """
        fresh_df = fresh_df.drop_duplicates(subset=[id_col], keep="last")

        if not os.path.exists(path):
            merged = (
                fresh_df.astype({"active_start": "Int64", "active_end": "Int64"})
                .sort_values(by=id_col)
                .reset_index(drop=True)
            )
            FECClient.atomic_write(path, lambda p: merged.to_csv(p, index=False))
            return merged

        existing_df = FECClient.read_csv_safe(path)
        # A file written before this schema existed (e.g. still has name/committee_type/...
        # columns from the old full-list-refresh scripts) won't have active_start/active_end
        # yet -- add them as missing so the merge below naturally backfills from fresh_df
        # instead of erroring on a suffix that never gets applied (no name collision to suffix).
        for col in ("active_start", "active_end"):
            if col not in existing_df.columns:
                existing_df[col] = np.nan
        existing_df = existing_df[[id_col, "active_start", "active_end"]]

        merged = existing_df.merge(fresh_df, on=id_col, how="outer", suffixes=("", "_fresh"))
        merged["active_start"] = merged["active_start"].combine_first(merged["active_start_fresh"])
        merged["active_end"] = merged[["active_end", "active_end_fresh"]].max(axis=1, skipna=True)
        merged = (
            merged.drop(columns=["active_start_fresh", "active_end_fresh"])
            .astype({"active_start": "Int64", "active_end": "Int64"})
            .sort_values(by=id_col)
            .reset_index(drop=True)
        )
        FECClient.atomic_write(path, lambda p: merged.to_csv(p, index=False))
        return merged

    @staticmethod
    def refresh_unlabeled(
        fresh_df: pd.DataFrame, path: str, key_cols: list, protect_if_set_cols: list
    ) -> pd.DataFrame:
        """
        Merge fresh_df into the CSV at `path` by key_cols, protecting hand-entered labels:
          - a key not yet in the existing file is inserted as-is (gap-fill);
          - a key that exists where every one of `protect_if_set_cols` is still blank/null has
            its ENTIRE row replaced by the fresh version (nothing hand-entered to lose, so it's
            safe to refresh e.g. auto-match suggestions with the latest re-run);
          - a key that exists where any of `protect_if_set_cols` is already set is left
            completely untouched, no matter what the fresh row now says.
        Use this for review files where some columns are machine-suggested (safe to refresh)
        and others are hand-entered (must never be silently overwritten once set). Writes and
        returns the merged frame.
        """
        fresh_df = fresh_df.drop_duplicates(subset=key_cols, keep="last")

        if not os.path.exists(path):
            merged = fresh_df.reset_index(drop=True)
            FECClient.atomic_write(path, lambda p: merged.to_csv(p, index=False))
            return merged

        # dtype=str: a review file's columns (e.g. a PI value like "21730173349") are opaque
        # hand-entered/suggested text, not numeric data -- without this, a numeric-looking
        # column gets inferred as float64 and every value picks up a spurious ".0" suffix on
        # each write-read round-trip.
        existing_df = FECClient.read_csv_safe(path, dtype=str)
        FECClient._harmonize_key_dtypes(fresh_df, existing_df, key_cols, cycle_col=None)

        def _is_blank(df: pd.DataFrame) -> np.ndarray:
            blank = np.ones(len(df), dtype=bool)
            for col in protect_if_set_cols:
                if col not in df.columns:
                    continue
                values = df[col]
                col_blank = values.isna() | (values.astype(str).str.strip() == "")
                blank &= np.asarray(col_blank)
            return blank

        existing_labeled = existing_df[np.logical_not(_is_blank(existing_df))]

        merged_keys = fresh_df.merge(existing_df[key_cols], on=key_cols, how="left", indicator=True)
        is_known = np.asarray(merged_keys["_merge"] == "both")
        new_rows = fresh_df[np.logical_not(is_known)]

        # Fresh rows for already-labeled keys are dropped entirely -- existing_labeled (below)
        # supplies the untouched version of those rows instead.
        labeled_keys = existing_labeled[key_cols]
        fresh_is_labeled = np.asarray(
            fresh_df.merge(labeled_keys, on=key_cols, how="left", indicator=True)["_merge"] == "both"
        )
        refreshed_rows = fresh_df[is_known & np.logical_not(fresh_is_labeled)]

        merged = pd.concat([existing_labeled, refreshed_rows, new_rows], ignore_index=True)
        FECClient.atomic_write(path, lambda p: merged.to_csv(p, index=False))
        return merged

    @staticmethod
    def log_run(script_name: str, **fields) -> None:
        """
        Append a JSON record (finish timestamp + arbitrary run fields, e.g. office/start_year)
        to log/{script_name}.json, to be called once a script's work has completed without
        raising. Each file holds a growing JSON array, one entry per successful run.
        """
        LOG_DIR.mkdir(exist_ok=True)
        log_path = LOG_DIR / f"{script_name}.json"
        record = {"timestamp": datetime.now().isoformat(timespec="seconds"), **fields}

        if log_path.exists():
            with open(log_path, "r") as f:
                records = json.load(f)
        else:
            records = []
        records.append(record)

        def _write(tmp_path):
            with open(tmp_path, "w") as f:
                json.dump(records, f, indent=2)

        FECClient.atomic_write(str(log_path), _write)

    @staticmethod
    def merge_cyclical(
        fresh_df: pd.DataFrame,
        path: str,
        key_cols: list,
        cycle_col: str,
        review_path: str,
        mutable_min_cycle: int = None,
    ) -> pd.DataFrame:
        """
        Merge fresh_df into the CSV at `path` by key_cols, treating rows whose `cycle_col`
        value is below `mutable_min_cycle` (defaults to current_cycle_threshold()) as frozen
        history rather than always-overwritable:
          - a key not yet in the existing file is inserted regardless of cycle (gap-fill);
          - a key that exists and is current (cycle_col >= mutable_min_cycle) is overwritten
            by the fresh row (trusted/live data);
          - a key that exists and is frozen is left untouched -- if the fresh row actually
            differs from the stored row, the conflict is appended to `review_path` for manual
            triage instead of silently overwriting settled history.
        Writes and returns the merged main-output frame; never shrinks it.
        """
        mutable_min_cycle = (
            mutable_min_cycle if mutable_min_cycle is not None else current_cycle_threshold()
        )

        if not os.path.exists(path):
            merged = (
                fresh_df.drop_duplicates(subset=key_cols, keep="last")
                .sort_values(by=key_cols)
                .reset_index(drop=True)
            )
            FECClient.atomic_write(path, lambda p: merged.to_csv(p, index=False))
            return merged

        existing_df = FECClient.read_csv_safe(path)
        fresh_df = fresh_df.drop_duplicates(subset=key_cols, keep="last")
        FECClient._harmonize_key_dtypes(fresh_df, existing_df, key_cols, cycle_col)

        merged_keys = fresh_df.merge(
            existing_df[key_cols], on=key_cols, how="left", indicator=True
        )
        is_known = np.asarray(merged_keys["_merge"] == "both")
        is_current = np.asarray(fresh_df[cycle_col] >= mutable_min_cycle)
        not_known = np.logical_not(is_known)
        not_current = np.logical_not(is_current)

        new_rows = fresh_df[not_known]
        current_rows = fresh_df[is_known & is_current]
        frozen_rows = fresh_df[is_known & not_current]

        conflicts = pd.DataFrame(columns=fresh_df.columns)
        if len(frozen_rows) > 0:
            compare_cols = [c for c in fresh_df.columns if c not in key_cols]
            joined = frozen_rows.merge(
                existing_df, on=key_cols, how="left", suffixes=("__fresh", "__existing")
            )
            differs = pd.Series(False, index=joined.index)
            for col in compare_cols:
                fresh_col, existing_col = f"{col}__fresh", f"{col}__existing"
                if fresh_col not in joined.columns or existing_col not in joined.columns:
                    continue
                a, b = joined[fresh_col], joined[existing_col]
                differs |= (a != b) & ~(a.isna() & b.isna())
            conflicts = frozen_rows[differs.values]

        if len(conflicts) > 0:
            FECClient._log_discrepancies(conflicts, existing_df, key_cols, review_path)

        # Existing rows superseded by a fresh "current" row are dropped from existing_df
        # before concatenation; everything else in existing_df (frozen rows, matched or
        # conflicting) is kept as-is.
        superseded = np.asarray(
            existing_df.merge(
                current_rows[key_cols], on=key_cols, how="left", indicator=True
            )["_merge"]
            == "both"
        )
        kept_existing = existing_df[np.logical_not(superseded)]

        merged = (
            pd.concat([kept_existing, new_rows, current_rows], ignore_index=True)
            .drop_duplicates(subset=key_cols, keep="last")
            .sort_values(by=key_cols)
            .reset_index(drop=True)
        )
        FECClient.atomic_write(path, lambda p: merged.to_csv(p, index=False))
        return merged

    @staticmethod
    def _harmonize_key_dtypes(
        fresh_df: pd.DataFrame, existing_df: pd.DataFrame, key_cols: list, cycle_col: str
    ) -> None:
        """
        Mutate fresh_df/existing_df in place so every key_col has matching dtypes across both
        frames before they're joined. Sparsely-populated ID-like key columns (e.g. an exploded
        joint_committee_id that's all-NaN in one batch) round-trip through CSV as float64, while
        the in-memory version stays object/string -- pandas' merge refuses to join an object
        column against a float64 one. cycle_col is skipped since it must stay numeric for the
        current-cycle threshold comparison, and real cycle values are never sparse/ambiguous.
        """
        for col in key_cols:
            if col == cycle_col:
                continue
            if fresh_df[col].dtype != existing_df[col].dtype:
                fresh_df[col] = fresh_df[col].astype("string")
                existing_df[col] = existing_df[col].astype("string")

    @staticmethod
    def _log_discrepancies(
        conflicts: pd.DataFrame, existing_df: pd.DataFrame, key_cols: list, review_path: str
    ) -> None:
        """Append full-row fresh-vs-existing conflicts to `review_path` for manual triage."""
        existing_matches = conflicts[key_cols].merge(existing_df, on=key_cols, how="left")
        review_rows = conflicts.add_suffix("__fresh").rename(
            columns={f"{c}__fresh": c for c in key_cols}
        )
        existing_renamed = existing_matches.drop(columns=key_cols).add_suffix("__existing")
        new_review = pd.concat(
            [review_rows.reset_index(drop=True), existing_renamed.reset_index(drop=True)], axis=1
        )
        new_review["manual_status"] = ""

        if os.path.exists(review_path):
            prior_review = FECClient.read_csv_safe(review_path)
            combined = pd.concat([prior_review, new_review], ignore_index=True)
            combined["_has_status"] = combined["manual_status"].fillna("").astype(str).str.len() > 0
            combined = combined.sort_values(by=["_has_status"], ascending=True)
            combined = combined.drop_duplicates(subset=key_cols, keep="last").drop(columns="_has_status")
        else:
            combined = new_review

        combined = combined.sort_values(by=key_cols).reset_index(drop=True)
        FECClient.atomic_write(review_path, lambda p: combined.to_csv(p, index=False))
