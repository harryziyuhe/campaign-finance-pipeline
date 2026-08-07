from __future__ import annotations

"""Match FEC super-PAC organization contributors to firms in the firm universe.

This is a conservative first pass. It reads organization contributor totals from
the FEC API output and firm aliases from the processed firm universe, then adds
high-confidence firm matches where available. The matching strategy is
intentionally precise:

1. Exact match on normalized names, with common legal suffix variants canonicalized.
2. Exact match on core names after removing legal suffixes such as Corp, Inc, LLC,
   Co, Ltd, Corporation, Incorporated, Group, and Holdings.
3. Limited fuzzy match only when normalized core names are very similar, share
   most tokens, and the best candidate is clearly separated from the runner-up.
4. Optional staged LSEG second pass. One stage searches unmatched de-businessed
   contributor names in LSEG organisations. Private-company organisation hits
   keep their PI. Public-company organisation hits trigger an equity quote search
   so the crosswalk can store equity RIC and PermID for later firm metadata.

False positives are more harmful than false negatives for this file, so all
ambiguous or weak matches are retained as unmatched contributor rows.
"""

import argparse
import os
import re
import unicodedata
from dataclasses import dataclass
from difflib import SequenceMatcher
from pathlib import Path

import pandas as pd
from tqdm import tqdm


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


DATA_ROOT = _require_data_root()
FIRM_UNIVERSE_FILE = DATA_ROOT / "data" / "processed" / "fec" / "fec_firm_universe.csv"
ORGANIZATION_CONTRIBUTORS_FILE = (
    DATA_ROOT / "data" / "raw" / "fec_api" / "contributions" / "super_organization_contributors.csv"
)
OUTPUT_FILE = DATA_ROOT / "data" / "processed" / "fec" / "super_organization_contributor_firm_matches.csv"
CROSSWALK_FILE = DATA_ROOT / "data" / "processed" / "fec" / "super_organization_lseg_pi_crosswalk.csv"
LSEG_FIRM_INFO_FILE = DATA_ROOT / "data" / "processed" / "fec" / "super_organization_lseg_firm_info.csv"
LSEG_CONFIG_PATH = SCRIPT_ROOT / "config"

ALIAS_COLUMNS = ["common_name", "business_name", "former_name"]
FIRM_OUTPUT_COLUMNS = [
    "instrument",
    "cusip",
    "isin",
    "common_name",
    "business_name",
    "former_name",
    "ric",
    "permid",
    "hq",
    "hq_state",
    "hq_city",
    "parent_permid",
    "TRBC_ID",
    "TRBC_Econ_Sector",
    "TRBC_Business_Sector",
    "TRBC_Industry_Group",
    "TRBC_Industry",
    "TRBC_Activity",
]
LEGAL_CANONICAL = {
    "CORPORATION": "CORP",
    "CORP": "CORP",
    "INCORPORATED": "INC",
    "INC": "INC",
    "COMPANY": "CO",
    "COMPANIES": "CO",
    "CO": "CO",
    "LIMITED": "LTD",
    "LTD": "LTD",
}
LEGAL_TOKENS = {
    "AG",
    "BV",
    "CO",
    "CORP",
    "GROUP",
    "HOLDING",
    "HOLDINGS",
    "INC",
    "LLC",
    "LLP",
    "LP",
    "LTD",
    "NV",
    "PLC",
    "SA",
    "SE",
    "THE",
}
POLITICAL_TOKENS = {"PAC", "FEDERAL", "POLITICAL", "ACTION", "COMMITTEE"}
GENERIC_CORE_KEYS = {
    "AMERICA",
    "AMERICAN",
    "ASSOCIATION",
    "COMMITTEE",
    "FOUNDATION",
    "FUND",
    "NATIONAL",
    "PARTNERS",
    "UNITED",
}


@dataclass(frozen=True)
class FirmAlias:
    row_index: int
    alias_type: str
    alias_value: str
    full_key: str
    core_key: str


@dataclass(frozen=True)
class MatchResult:
    row_index: int
    alias_type: str
    alias_value: str
    method: str
    score: float
    runner_up_score: float
    contributor_key: str
    firm_key: str
    lseg_search_query: str = ""
    lseg_search_title: str = ""
    lseg_search_pi: str = ""


# CLI arguments keep this script reusable for alternate inputs and review runs.
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Conservatively match super-PAC organization contributors to firm-universe records."
    )
    parser.add_argument("--firm-universe", type=Path, default=FIRM_UNIVERSE_FILE)
    parser.add_argument("--contributors", type=Path, default=ORGANIZATION_CONTRIBUTORS_FILE)
    parser.add_argument("--output", type=Path, default=OUTPUT_FILE)
    parser.add_argument("--stage", choices=["match", "lseg-search"], default="match")
    parser.add_argument("--first-pass-output", type=Path, default=OUTPUT_FILE)
    parser.add_argument(
        "--use-existing-first-pass",
        action="store_true",
        help="For --stage lseg-search, read a previously saved first-pass output instead of rebuilding it.",
    )
    parser.add_argument("--lseg-crosswalk", type=Path, default=CROSSWALK_FILE)
    parser.add_argument("--lseg-firm-info", type=Path, default=LSEG_FIRM_INFO_FILE)
    parser.add_argument(
        "--use-lseg-files",
        action="store_true",
        help="Merge prebuilt LSEG PI crosswalk and firm-info files into unmatched rows.",
    )
    parser.add_argument("--min-fuzzy-score", type=float, default=0.94)
    parser.add_argument("--min-score-gap", type=float, default=0.03)
    parser.add_argument("--min-lseg-score", type=float, default=1)
    parser.add_argument("--min-lseg-token-overlap", type=float, default=1)
    parser.add_argument("--lseg-max-candidates", type=int, default=5)
    parser.add_argument(
        "--lseg-max-rows",
        type=int,
        default=None,
        help="Optional cap on unmatched rows sent to LSEG during review runs.",
    )
    parser.add_argument(
        "--checkpoint-every",
        type=int,
        default=25,
        help="Save LSEG search crosswalk progress after this many new searches.",
    )
    parser.add_argument(
        "--matched-only",
        action="store_true",
        help="Write only matched contributor rows for review. Defaults to all rows.",
    )
    return parser.parse_args()


# Name normalization harmonizes punctuation and legal suffix variants without broad semantic rewriting.
def normalize_name(value: object, drop_legal: bool = False, drop_political: bool = False) -> str:
    if pd.isna(value):
        return ""

    text = unicodedata.normalize("NFKD", str(value)).encode("ascii", "ignore").decode("ascii")
    text = text.upper()
    text = re.sub(r"\([^)]*\)", " ", text)
    text = re.sub(r"\bAND\s+OTHER\s+FIRMS\b", " ", text)
    text = text.replace("&", " AND ")
    text = re.sub(r"[^A-Z0-9]+", " ", text)

    tokens = []
    for token in text.split():
        token = LEGAL_CANONICAL.get(token, token)
        if drop_legal and token in LEGAL_TOKENS:
            continue
        if drop_political and token in POLITICAL_TOKENS:
            continue
        tokens.append(token)
    return " ".join(tokens)


def is_safe_core_key(key: str) -> bool:
    tokens = key.split()
    if not tokens or key in GENERIC_CORE_KEYS:
        return False
    if len(tokens) == 1:
        return len(tokens[0]) >= 4 and tokens[0] not in GENERIC_CORE_KEYS
    return len(key) >= 6


# Firm alias preparation indexes current, business, and former names for matching.
class FirmAliasIndex:
    def __init__(self, firms: pd.DataFrame) -> None:
        self.firms = firms.reset_index(drop=True)
        self.full_index: dict[str, list[FirmAlias]] = {}
        self.core_index: dict[str, list[FirmAlias]] = {}
        self.block_index: dict[str, list[FirmAlias]] = {}
        self._build_indexes()

    def _build_indexes(self) -> None:
        seen_aliases: set[tuple[int, str, str]] = set()
        for row_index, row in self.firms.iterrows():
            for alias_type in ALIAS_COLUMNS:
                alias_value = row.get(alias_type)
                full_key = normalize_name(alias_value)
                core_key = normalize_name(alias_value, drop_legal=True)
                if not full_key:
                    continue

                dedupe_key = (row_index, alias_type, full_key)
                if dedupe_key in seen_aliases:
                    continue
                seen_aliases.add(dedupe_key)

                alias = FirmAlias(row_index, alias_type, str(alias_value), full_key, core_key)
                self.full_index.setdefault(full_key, []).append(alias)

                if is_safe_core_key(core_key):
                    self.core_index.setdefault(core_key, []).append(alias)
                    self.block_index.setdefault(core_key.split()[0], []).append(alias)

    def exact_full_match(self, key: str) -> MatchResult | None:
        return self._resolve_exact(key, self.full_index, "exact_normalized_name")

    def exact_core_match(self, key: str) -> MatchResult | None:
        if not is_safe_core_key(key):
            return None
        return self._resolve_exact(key, self.core_index, "exact_core_name")

    def fuzzy_core_match(
        self,
        key: str,
        min_score: float,
        min_score_gap: float,
    ) -> MatchResult | None:
        if not is_safe_core_key(key):
            return None

        scored = []
        for alias in self.block_index.get(key.split()[0], []):
            score = similarity_score(key, alias.core_key)
            if score >= min_score and token_overlap(key, alias.core_key) >= 0.80:
                scored.append((score, alias))

        if not scored:
            return None

        best_by_firm: dict[str, tuple[float, FirmAlias]] = {}
        for score, alias in scored:
            identity = self._firm_identity(alias)
            if identity not in best_by_firm or score > best_by_firm[identity][0]:
                best_by_firm[identity] = (score, alias)

        ranked = sorted(best_by_firm.values(), key=lambda item: item[0], reverse=True)
        best_score, best_alias = ranked[0]
        runner_up = ranked[1][0] if len(ranked) > 1 else 0.0
        if runner_up and best_score - runner_up < min_score_gap:
            return None

        return MatchResult(
            best_alias.row_index,
            best_alias.alias_type,
            best_alias.alias_value,
            "high_similarity_core_name",
            best_score,
            runner_up,
            key,
            best_alias.core_key,
        )

    def _resolve_exact(
        self,
        key: str,
        index: dict[str, list[FirmAlias]],
        method: str,
    ) -> MatchResult | None:
        aliases = index.get(key, [])
        if not aliases:
            return None

        grouped = self._group_by_firm_identity(aliases)
        if len(grouped) != 1:
            return None

        alias = grouped[0][0]
        firm_key = alias.full_key if method == "exact_normalized_name" else alias.core_key
        return MatchResult(alias.row_index, alias.alias_type, alias.alias_value, method, 1.0, 0.0, key, firm_key)

    def _group_by_firm_identity(self, aliases: list[FirmAlias]) -> list[list[FirmAlias]]:
        groups: dict[str, list[FirmAlias]] = {}
        for alias in aliases:
            identity = self._firm_identity(alias)
            groups.setdefault(identity, []).append(alias)
        return list(groups.values())

    def _firm_identity(self, alias: FirmAlias) -> str:
        row = self.firms.iloc[alias.row_index]
        return str(row.get("permid") or row.get("instrument") or alias.row_index)


def similarity_score(left: str, right: str) -> float:
    return SequenceMatcher(None, left, right).ratio()


def token_overlap(left: str, right: str) -> float:
    left_tokens = set(left.split())
    right_tokens = set(right.split())
    if not left_tokens or not right_tokens:
        return 0.0
    return len(left_tokens & right_tokens) / len(left_tokens | right_tokens)


def true_values(series: pd.Series) -> pd.Series:
    return series.astype(str).str.strip().str.lower().isin(["true", "1", "yes"])


# Contributor matching tries exact methods first and only then a strict fuzzy fallback.
class SuperOrganizationMatcher:
    def __init__(self, firms: pd.DataFrame, min_fuzzy_score: float, min_score_gap: float) -> None:
        self.alias_index = FirmAliasIndex(firms)
        self.min_fuzzy_score = min_fuzzy_score
        self.min_score_gap = min_score_gap

    def match_name(self, contributor_name: object) -> MatchResult | None:
        full_key = normalize_name(contributor_name, drop_political=True)
        core_key = normalize_name(contributor_name, drop_legal=True, drop_political=True)

        return (
            self.alias_index.exact_full_match(full_key)
            or self.alias_index.exact_core_match(core_key)
            or self.alias_index.fuzzy_core_match(core_key, self.min_fuzzy_score, self.min_score_gap)
        )


# LSEG search stage writes a contributor-name to PI crosswalk for later metadata retrieval.
class LsegOrganisationSearcher:
    def __init__(
        self,
        min_score: float,
        min_token_overlap: float,
        max_candidates: int,
    ) -> None:
        os.environ.setdefault("LD_LIB_CONFIG_PATH", str(LSEG_CONFIG_PATH))
        import lseg.data as ld
        from lseg.data.content import search

        self.ld = ld
        self.search = search
        self.min_score = min_score
        self.min_token_overlap = min_token_overlap
        self.max_candidates = max_candidates
        self.ld.open_session()

    def search_name(self, contributor_name: object) -> dict[str, object] | None:
        search_key = normalize_name(contributor_name, drop_legal=True, drop_political=True)
        if not is_safe_core_key(search_key):
            return None

        first_rejected_candidate = None
        for query in [f'"{search_key}"', search_key]:
            response = self._search_organisations(query)
            candidate = self._best_candidate(search_key, query, response)
            if candidate is None:
                continue
            if candidate.get("lseg_accepted"):
                return candidate
            if first_rejected_candidate is None:
                first_rejected_candidate = candidate
        return first_rejected_candidate

    def _search_organisations(self, query: str) -> pd.DataFrame:
        response = self.search.Definition(
            query,
            view=self.search.Views.ORGANISATIONS,
        ).get_data()
        return response.data.df

    def _search_equity_quotes(self, query: str) -> pd.DataFrame:
        response = self.search.Definition(
            query,
            view=self.search.Views.EQUITY_QUOTES,
            filter="SearchAllCategory eq 'Equities'",
        ).get_data()
        return response.data.df

    def _best_candidate(self, search_key: str, query: str, response: pd.DataFrame) -> dict[str, object] | None:
        if response is None or response.empty:
            return None

        candidates = []
        for rank, (_, row) in enumerate(response.head(self.max_candidates).iterrows(), start=1):
            title = str(row.get("DocumentTitle", "")).strip()
            pi = str(row.get("PI", "")).strip()
            if not title or not pi or pi == "nan":
                continue

            title_key = normalize_name(self._organisation_match_name(title), drop_legal=True, drop_political=True)
            score = similarity_score(search_key, title_key)
            overlap = token_overlap(search_key, title_key)
            candidates.append(
                {
                    "rank": rank,
                    "query": query,
                    "title": title,
                    "pi": pi,
                    "title_key": title_key,
                    "score": score,
                    "token_overlap": overlap,
                    "accepted": self._passes_title_check(search_key, title_key),
                    "org_type": self._organisation_type(title),
                }
            )

        if not candidates:
            return None

        top_candidate = max(
            candidates,
            key=lambda item: (
                float(item["score"]),
                float(item["token_overlap"]),
                -int(item["rank"]),
            ),
        )
        accepted_candidates = [candidate for candidate in candidates if candidate["accepted"]]
        if not accepted_candidates:
            return self._rejected_top_candidate(search_key, top_candidate)

        accepted_candidates.sort(key=lambda item: item["score"], reverse=True)
        best = accepted_candidates[0]
        runner_up = accepted_candidates[1]["score"] if len(accepted_candidates) > 1 else 0.0
        title = str(best["title"])
        pi = str(best["pi"])
        title_key = str(best["title_key"])
        org_type = str(best["org_type"])
        resolved_id = pi if org_type == "Private Company" else ""
        resolved_id_type = "PI" if org_type == "Private Company" else ""
        equity = self._equity_match_for_public_organisation(title) if org_type == "Public Company" else {}
        if equity:
            resolved_id = equity["lseg_equity_permid"]
            resolved_id_type = "PermID"

        result = {
            "lseg_accepted": True,
            "lseg_top_query": top_candidate["query"],
            "lseg_top_title": top_candidate["title"],
            "lseg_top_pi": top_candidate["pi"],
            "lseg_top_type": top_candidate["org_type"],
            "lseg_top_rank": top_candidate["rank"],
            "lseg_top_similarity_score": round(float(top_candidate["score"]), 4),
            "lseg_top_token_overlap": round(float(top_candidate["token_overlap"]), 4),
            "lseg_top_title_key": top_candidate["title_key"],
            "lseg_reject_reason": "",
            "lseg_search_query": best["query"],
            "lseg_search_title": title,
            "lseg_search_pi": pi,
            "lseg_org_query": best["query"],
            "lseg_org_title": title,
            "lseg_org_pi": pi,
            "lseg_org_type": org_type,
            "lseg_org_match_score": round(float(best["score"]), 4),
            "lseg_org_runner_up_score": round(runner_up, 4),
            "lseg_equity_query": "",
            "lseg_equity_title": "",
            "lseg_equity_ric": "",
            "lseg_equity_permid": "",
            "lseg_equity_match_score": "",
            "resolved_lseg_id": resolved_id,
            "resolved_lseg_id_type": resolved_id_type,
            "lseg_match_score": round(float(best["score"]), 4),
            "lseg_runner_up_score": round(runner_up, 4),
            "contributor_match_key": search_key,
            "lseg_title_key": title_key,
        }
        result.update(equity)
        return result

    def _rejected_top_candidate(self, search_key: str, candidate: dict[str, object]) -> dict[str, object]:
        return {
            "lseg_accepted": False,
            "lseg_top_query": candidate["query"],
            "lseg_top_title": candidate["title"],
            "lseg_top_pi": candidate["pi"],
            "lseg_top_type": candidate["org_type"],
            "lseg_top_rank": candidate["rank"],
            "lseg_top_similarity_score": round(float(candidate["score"]), 4),
            "lseg_top_token_overlap": round(float(candidate["token_overlap"]), 4),
            "lseg_top_title_key": candidate["title_key"],
            "lseg_reject_reason": self._reject_reason(search_key, str(candidate["title_key"])),
            "contributor_match_key": search_key,
        }

    def _passes_title_check(self, search_key: str, title_key: str) -> bool:
        search_tokens = search_key.split()
        title_tokens = title_key.split()
        if not search_tokens or not title_tokens:
            return False
        if search_tokens[0] != title_tokens[0]:
            return False
        if len(search_tokens) == 1:
            return search_tokens[0] in title_tokens[:2]
        return (
            similarity_score(search_key, title_key) >= self.min_score
            and token_overlap(search_key, title_key) >= self.min_token_overlap
        )

    def _reject_reason(self, search_key: str, title_key: str) -> str:
        search_tokens = search_key.split()
        title_tokens = title_key.split()
        if not search_tokens or not title_tokens:
            return "missing_comparable_tokens"
        if search_tokens[0] != title_tokens[0]:
            return "first_token_mismatch"
        if len(search_tokens) == 1:
            return "single_token_not_near_title_start"
        return "below_similarity_or_token_overlap_threshold"

    def _organisation_type(self, title: str) -> str:
        for org_type in ["Private Company", "Public Company", "Holding Company", "Fund Entity"]:
            if org_type.lower() in title.lower():
                return org_type
        return ""

    def _organisation_match_name(self, title: str) -> str:
        if "," not in title:
            return title.strip()
        return title.rsplit(",", 1)[0].strip()

    def _equity_search_name(self, organisation_title: str) -> str:
        return self._organisation_match_name(organisation_title)

    def _equity_match_for_public_organisation(self, organisation_title: str) -> dict[str, object]:
        equity_name = self._equity_search_name(organisation_title)
        if not equity_name:
            return {}

        for query in [f'"{equity_name}"', equity_name]:
            response = self._search_equity_quotes(query)
            candidate = self._best_equity_candidate(equity_name, query, response)
            if candidate:
                return candidate
        return {}

    def _best_equity_candidate(self, equity_name: str, query: str, response: pd.DataFrame) -> dict[str, object]:
        if response is None or response.empty:
            return {}

        search_key = normalize_name(equity_name, drop_legal=True, drop_political=True)
        candidates = []
        for _, row in response.head(self.max_candidates).iterrows():
            title = str(row.get("DocumentTitle", ""))
            ric = str(row.get("RIC", ""))
            permid = str(row.get("PermID", ""))
            if not title or not ric or not permid or permid == "nan":
                continue

            title_key = normalize_name(title, drop_legal=True, drop_political=True)
            score = self._equity_title_score(search_key, title_key)
            if score >= self.min_lseg_equity_score():
                candidates.append((score, title, ric, permid))

        if not candidates:
            return {}

        candidates.sort(key=lambda item: item[0], reverse=True)
        score, title, ric, permid = candidates[0]
        return {
            "lseg_equity_query": query,
            "lseg_equity_title": title,
            "lseg_equity_ric": ric,
            "lseg_equity_permid": permid,
            "lseg_equity_match_score": round(score, 4),
            "resolved_lseg_id": permid,
            "resolved_lseg_id_type": "PermID",
        }

    def _equity_title_score(self, search_key: str, title_key: str) -> float:
        search_tokens = search_key.split()
        title_tokens = title_key.split()
        if not search_tokens or not title_tokens or search_tokens[0] != title_tokens[0]:
            return 0.0
        return len(set(search_tokens) & set(title_tokens)) / len(set(search_tokens))

    def min_lseg_equity_score(self) -> float:
        return 0.80

# Output assembly preserves original contributor fields and appends firm and match metadata.
def build_match_output(
    contributors: pd.DataFrame,
    firms: pd.DataFrame,
    matcher: SuperOrganizationMatcher,
    matched_only: bool,
) -> pd.DataFrame:
    records = []
    firm_columns = FIRM_OUTPUT_COLUMNS

    for contributor_index, contributor in contributors.iterrows():
        match = matcher.match_name(contributor.get("contributor_name"))
        if match is None and matched_only:
            continue

        record = contributor.to_dict()
        record["matched"] = match is not None

        if match is None:
            for column in firm_columns:
                record[f"firm_{column}"] = ""
            record.update(
                {
                    "match_method": "",
                    "match_score": "",
                    "runner_up_score": "",
                    "matched_alias_type": "",
                    "matched_alias_value": "",
                    "contributor_match_key": normalize_name(
                        contributor.get("contributor_name"), drop_legal=True, drop_political=True
                    ),
                    "firm_match_key": "",
                    "lseg_search_query": "",
                    "lseg_search_title": "",
                    "lseg_search_pi": "",
                    "lseg_accepted": "",
                    "lseg_top_query": "",
                    "lseg_top_title": "",
                    "lseg_top_pi": "",
                    "lseg_top_type": "",
                    "lseg_top_rank": "",
                    "lseg_top_similarity_score": "",
                    "lseg_top_token_overlap": "",
                    "lseg_top_title_key": "",
                    "lseg_reject_reason": "",
                    "lseg_org_query": "",
                    "lseg_org_title": "",
                    "lseg_org_pi": "",
                    "lseg_org_type": "",
                    "lseg_org_match_score": "",
                    "lseg_org_runner_up_score": "",
                    "lseg_equity_query": "",
                    "lseg_equity_title": "",
                    "lseg_equity_ric": "",
                    "lseg_equity_permid": "",
                    "lseg_equity_match_score": "",
                    "resolved_lseg_id": "",
                    "resolved_lseg_id_type": "",
                    "contributor_row_index": contributor_index,
                }
            )
            records.append(record)
            continue

        firm = firms.iloc[match.row_index].to_dict()
        for column in firm_columns:
            record[f"firm_{column}"] = firm.get(column, "")
        record.update(
            {
                "match_method": match.method,
                "match_score": round(match.score, 4),
                "runner_up_score": round(match.runner_up_score, 4),
                "matched_alias_type": match.alias_type,
                "matched_alias_value": match.alias_value,
                "contributor_match_key": match.contributor_key,
                "firm_match_key": match.firm_key,
                "lseg_search_query": match.lseg_search_query,
                "lseg_search_title": match.lseg_search_title,
                "lseg_search_pi": match.lseg_search_pi,
                "lseg_accepted": "",
                "lseg_top_query": "",
                "lseg_top_title": "",
                "lseg_top_pi": "",
                "lseg_top_type": "",
                "lseg_top_rank": "",
                "lseg_top_similarity_score": "",
                "lseg_top_token_overlap": "",
                "lseg_top_title_key": "",
                "lseg_reject_reason": "",
                "lseg_org_query": "",
                "lseg_org_title": "",
                "lseg_org_pi": "",
                "lseg_org_type": "",
                "lseg_org_match_score": "",
                "lseg_org_runner_up_score": "",
                "lseg_equity_query": "",
                "lseg_equity_title": "",
                "lseg_equity_ric": "",
                "lseg_equity_permid": "",
                "lseg_equity_match_score": "",
                "resolved_lseg_id": "",
                "resolved_lseg_id_type": "",
                "contributor_row_index": contributor_index,
            }
        )
        records.append(record)

    output = pd.DataFrame(records)
    if "contribution_receipt_amount" not in output:
        return output

    output["_sort_contribution_receipt_amount"] = pd.to_numeric(
        output["contribution_receipt_amount"], errors="coerce"
    ).fillna(0)
    output = output.sort_values("_sort_contribution_receipt_amount", ascending=False)
    return output.drop(columns="_sort_contribution_receipt_amount").reset_index(drop=True)


def build_lseg_pi_crosswalk(
    local_output: pd.DataFrame,
    searcher: LsegOrganisationSearcher,
    crosswalk_file: Path,
    max_rows: int | None,
    checkpoint_every: int,
) -> pd.DataFrame:
    records = load_existing_lseg_crosswalk(crosswalk_file)
    searched_row_ids = {
        str(record.get("contributor_row_index", ""))
        for record in records
        if str(record.get("search_status", "searched")) == "searched"
    }
    unmatched = local_output.loc[~true_values(local_output["matched"])].copy()
    if "contributor_id" in unmatched:
        unmatched = unmatched.loc[unmatched["contributor_id"].astype(str).str.strip() == ""]
    unmatched = unmatched.loc[~unmatched["contributor_row_index"].astype(str).isin(searched_row_ids)]
    if max_rows is not None:
        unmatched = unmatched.head(max_rows)

    new_searches = 0
    new_matches = 0
    new_no_matches = 0
    new_rejections = 0
    checkpoints = 0
    print(
        f"LSEG search resume state: {len(records):,} saved rows, "
        f"{len(searched_row_ids):,} previously searched rows, {len(unmatched):,} rows remaining."
    )

    progress = tqdm(
        unmatched.iterrows(),
        total=len(unmatched),
        desc="Searching LSEG organisations",
        unit="name",
    )
    for _, row in progress:
        search_result = searcher.search_name(row.get("contributor_name"))
        lseg_accepted = bool(search_result and search_result.get("lseg_accepted"))
        record = {
            "contributor_row_index": row.get("contributor_row_index"),
            "contributor_name": row.get("contributor_name"),
            "contributor_city": row.get("contributor_city"),
            "contributor_state": row.get("contributor_state"),
            "contribution_receipt_amount": row.get("contribution_receipt_amount"),
            "contributor_match_key": row.get("contributor_match_key"),
            "lseg_matched": lseg_accepted,
            "lseg_search_query": "",
            "lseg_search_title": "",
            "lseg_search_pi": "",
            "lseg_accepted": "",
            "lseg_top_query": "",
            "lseg_top_title": "",
            "lseg_top_pi": "",
            "lseg_top_type": "",
            "lseg_top_rank": "",
            "lseg_top_similarity_score": "",
            "lseg_top_token_overlap": "",
            "lseg_top_title_key": "",
            "lseg_reject_reason": "",
            "lseg_org_query": "",
            "lseg_org_title": "",
            "lseg_org_pi": "",
            "lseg_org_type": "",
            "lseg_org_match_score": "",
            "lseg_org_runner_up_score": "",
            "lseg_equity_query": "",
            "lseg_equity_title": "",
            "lseg_equity_ric": "",
            "lseg_equity_permid": "",
            "lseg_equity_match_score": "",
            "resolved_lseg_id": "",
            "resolved_lseg_id_type": "",
            "lseg_match_score": "",
            "lseg_runner_up_score": "",
            "lseg_title_key": "",
            "search_status": "searched",
        }
        if search_result is not None:
            record.update(search_result)
            if lseg_accepted:
                new_matches += 1
            else:
                new_rejections += 1
                new_no_matches += 1
        else:
            new_no_matches += 1
        records.append(record)
        new_searches += 1
        progress.set_postfix(
            {
                "matched": new_matches,
                "no_match": new_no_matches,
                "rejected_top": new_rejections,
                "checkpoints": checkpoints,
                "last": str(row.get("contributor_name", ""))[:28],
            }
        )

        if checkpoint_every > 0 and new_searches % checkpoint_every == 0:
            save_lseg_crosswalk(records, crosswalk_file)
            checkpoints += 1
            print(f"Checkpointed {new_searches:,} new LSEG searches to {crosswalk_file}.")

    crosswalk = pd.DataFrame(records)
    if "contribution_receipt_amount" not in crosswalk or crosswalk.empty:
        return crosswalk

    crosswalk["_sort_contribution_receipt_amount"] = pd.to_numeric(
        crosswalk["contribution_receipt_amount"], errors="coerce"
    ).fillna(0)
    crosswalk = crosswalk.sort_values("_sort_contribution_receipt_amount", ascending=False)
    return crosswalk.drop(columns="_sort_contribution_receipt_amount").reset_index(drop=True)


def load_existing_lseg_crosswalk(crosswalk_file: Path) -> list[dict[str, object]]:
    if not crosswalk_file.exists():
        return []
    existing = pd.read_csv(crosswalk_file, dtype=str).fillna("")
    if "search_status" not in existing.columns:
        existing["search_status"] = "searched"
    return existing.to_dict("records")


def save_lseg_crosswalk(records: list[dict[str, object]], crosswalk_file: Path) -> None:
    crosswalk_file.parent.mkdir(parents=True, exist_ok=True)
    crosswalk = pd.DataFrame(records)
    if not crosswalk.empty and "contributor_row_index" in crosswalk:
        crosswalk = crosswalk.drop_duplicates("contributor_row_index", keep="last")
    if not crosswalk.empty and "contribution_receipt_amount" in crosswalk:
        crosswalk["_sort_contribution_receipt_amount"] = pd.to_numeric(
            crosswalk["contribution_receipt_amount"], errors="coerce"
        ).fillna(0)
        crosswalk = crosswalk.sort_values("_sort_contribution_receipt_amount", ascending=False)
        crosswalk = crosswalk.drop(columns="_sort_contribution_receipt_amount")
    crosswalk.to_csv(crosswalk_file, index=False)


def load_first_pass_output(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f"Missing first-pass output file: {path}")
    output = pd.read_csv(path, dtype=str).fillna("")
    required_columns = {"matched", "contributor_row_index", "contributor_name"}
    missing_columns = required_columns - set(output.columns)
    if missing_columns:
        missing = ", ".join(sorted(missing_columns))
        raise ValueError(f"First-pass output is missing required columns: {missing}")
    return output


def apply_lseg_files(output: pd.DataFrame, crosswalk_file: Path, firm_info_file: Path) -> pd.DataFrame:
    if not crosswalk_file.exists():
        raise FileNotFoundError(f"Missing LSEG crosswalk file: {crosswalk_file}")
    if not firm_info_file.exists():
        raise FileNotFoundError(f"Missing LSEG firm-info file: {firm_info_file}")

    crosswalk = pd.read_csv(crosswalk_file, dtype=str).fillna("")
    firm_info = pd.read_csv(firm_info_file, dtype=str).fillna("")
    crosswalk = crosswalk.loc[crosswalk["lseg_matched"].astype(str).str.lower().isin(["true", "1"])]
    firm_by_pi = firm_info.drop_duplicates("permid").set_index("permid").to_dict("index")
    crosswalk_by_row = crosswalk.drop_duplicates("contributor_row_index").set_index("contributor_row_index")

    merged = output.copy()
    for index, row in merged.loc[~true_values(merged["matched"])].iterrows():
        row_key = str(row.get("contributor_row_index", ""))
        if row_key not in crosswalk_by_row.index:
            continue

        match = crosswalk_by_row.loc[row_key]
        resolved_id = str(match.get("resolved_lseg_id", ""))
        if not resolved_id:
            resolved_id = str(match.get("lseg_equity_permid", "")) or str(match.get("lseg_org_pi", ""))
        firm = firm_by_pi.get(resolved_id, {})
        merged.at[index, "matched"] = True
        merged.at[index, "match_method"] = "lseg_organisation_crosswalk"
        merged.at[index, "match_score"] = match.get("lseg_match_score", "")
        merged.at[index, "runner_up_score"] = match.get("lseg_runner_up_score", "")
        merged.at[index, "matched_alias_type"] = "lseg_search_title"
        merged.at[index, "matched_alias_value"] = match.get("lseg_org_title", match.get("lseg_search_title", ""))
        merged.at[index, "firm_match_key"] = match.get("lseg_title_key", "")
        merged.at[index, "lseg_search_query"] = match.get("lseg_search_query", "")
        merged.at[index, "lseg_search_title"] = match.get("lseg_search_title", "")
        merged.at[index, "lseg_search_pi"] = match.get("lseg_search_pi", "")
        for column in [
            "lseg_accepted",
            "lseg_top_query",
            "lseg_top_title",
            "lseg_top_pi",
            "lseg_top_type",
            "lseg_top_rank",
            "lseg_top_similarity_score",
            "lseg_top_token_overlap",
            "lseg_top_title_key",
            "lseg_reject_reason",
            "lseg_org_query",
            "lseg_org_title",
            "lseg_org_pi",
            "lseg_org_type",
            "lseg_org_match_score",
            "lseg_org_runner_up_score",
            "lseg_equity_query",
            "lseg_equity_title",
            "lseg_equity_ric",
            "lseg_equity_permid",
            "lseg_equity_match_score",
            "resolved_lseg_id",
            "resolved_lseg_id_type",
        ]:
            merged.at[index, column] = match.get(column, "")
        for column in FIRM_OUTPUT_COLUMNS:
            merged.at[index, f"firm_{column}"] = firm.get(column, "")

    return merged


def main() -> None:
    args = parse_args()

    if args.stage == "lseg-search" and args.use_existing_first_pass:
        output = load_first_pass_output(args.first_pass_output)
    else:
        firms = pd.read_csv(args.firm_universe, dtype=str).fillna("")
        contributors = pd.read_csv(args.contributors, dtype=str).fillna("")
        matcher = SuperOrganizationMatcher(firms, args.min_fuzzy_score, args.min_score_gap)
        output = build_match_output(
            contributors,
            firms,
            matcher,
            matched_only=args.matched_only and args.stage != "lseg-search",
        )

    if args.stage == "lseg-search":
        searcher = LsegOrganisationSearcher(
            args.min_lseg_score,
            args.min_lseg_token_overlap,
            args.lseg_max_candidates,
        )
        crosswalk = build_lseg_pi_crosswalk(
            output,
            searcher,
            args.lseg_crosswalk,
            args.lseg_max_rows,
            args.checkpoint_every,
        )
        save_lseg_crosswalk(crosswalk.to_dict("records"), args.lseg_crosswalk)
        print(f"Saved {len(crosswalk):,} LSEG organisation search rows to {args.lseg_crosswalk}.")
        if not crosswalk.empty and "lseg_matched" in crosswalk:
            print(crosswalk["lseg_matched"].value_counts(dropna=False).to_string())
        return

    firms = pd.read_csv(args.firm_universe, dtype=str).fillna("")
    contributors = pd.read_csv(args.contributors, dtype=str).fillna("")
    if args.use_lseg_files:
        output = apply_lseg_files(output, args.lseg_crosswalk, args.lseg_firm_info)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.to_csv(args.output, index=False)

    print(f"Read {len(contributors):,} organization contributors and {len(firms):,} firm records.")
    output_label = "matched rows" if args.matched_only else "rows"
    print(f"Saved {len(output):,} {output_label} to {args.output}.")
    if not output.empty and "match_method" in output:
        print(output["match_method"].value_counts(dropna=False).to_string())


if __name__ == "__main__":
    main()
