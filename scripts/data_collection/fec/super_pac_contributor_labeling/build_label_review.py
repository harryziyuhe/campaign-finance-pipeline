import argparse
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient

# Running FECsuperOrganizationFirmMatcher.py against organization_contributors.csv is a
# documented workflow step (see docs), not something this script invokes itself:
#   python FECsuperOrganizationFirmMatcher.py --contributors .../organization_contributors.csv \
#       --output .../organization_firm_matches.csv --stage match
#   (optionally) python FECsuperOrganizationFirmMatcher.py --stage lseg-search
#       --use-existing-first-pass --first-pass-output .../organization_firm_matches.csv \
#       --lseg-crosswalk .../organization_lseg_pi_crosswalk.csv
# This script only reads whatever of those two output files already exist.

OUTPUT_SUBDIR = "super_org_labeling"
LABEL_THRESHOLD = 40000
REVIEW_KEY_COLS = ["contributor_match_key"]
# All three are hand fields (Type/connected are freely hand-labeled; `matched` is a hand-
# verified/corrected LSEG PI value, reviewed against the lseg_search_pi/lseg_top_pi suggestion
# columns -- NOT the matcher's own auto-match boolean). The row freezes once any is set.
PROTECT_COLS = ["Type", "connected", "matched"]

# The review file only surfaces this reduced column set -- everything else from the matcher's
# output (firm_* columns, match_method/score, etc.) is noise for the hand-labeling workflow.
FINAL_COLUMNS = [
    "contributor_name", "contributor_city", "contributor_state", "contribution_receipt_amount",
    "contributor_match_key", "lseg_search_title", "lseg_search_pi", "lseg_top_title", "lseg_top_pi",
    "matched", "Type", "connected",
]

# lseg-search crosswalk columns worth surfacing as suggestions in the review file, when the
# crosswalk file exists (it's an optional, heavier stage that needs a live LSEG session).
SUGGESTION_COLS_FROM_CROSSWALK = [
    "lseg_matched", "lseg_search_query", "lseg_search_title", "lseg_search_pi",
    "lseg_top_query", "lseg_top_title", "lseg_top_pi", "lseg_top_type",
    "lseg_top_rank", "lseg_top_similarity_score", "lseg_top_token_overlap",
    "resolved_lseg_id", "resolved_lseg_id_type",
]


def _clean_numeric_str(value) -> str:
    """PI/PermID-like values read from Excel often come back as float64 (e.g. 5079215000.0) --
    render them as clean integer strings instead of carrying a trailing ".0" into the CSV."""
    if pd.isna(value) or str(value).strip() == "":
        return ""
    try:
        return str(int(float(value)))
    except (ValueError, TypeError):
        return str(value).strip()


def build_review_candidates(matches_path: Path, crosswalk_path: Path) -> pd.DataFrame:
    """
    Build the set of contributor + auto-match-suggestion rows worth promoting into the label
    review file, filtered to contribution_receipt_amount >= LABEL_THRESHOLD. Optionally enriches
    with lseg-search crosswalk suggestions when that (optional) file exists.
    """
    matches = FECClient.read_csv_safe(matches_path, dtype=str)
    matches["contribution_receipt_amount"] = pd.to_numeric(
        matches["contribution_receipt_amount"], errors="coerce"
    )

    # organization_firm_matches.csv has one row per raw contributor_name variant (its source,
    # organization_contributors.csv, is grouped by raw name, not by contributor_match_key), but
    # contributor_match_key deliberately collapses variants of the same entity (e.g. "Foo Media"
    # and "Foo Media, LLC"). Consolidate to one row per match key BEFORE applying the amount
    # floor: summing first means an entity split across variants is judged by its true combined
    # total instead of being under-counted (and possibly missed) per variant, and picking the
    # largest-amount variant as the representative row (rather than an arbitrary/last one) keeps
    # this deterministic across runs.
    matches = matches.sort_values("contribution_receipt_amount", ascending=False)
    matches["contribution_receipt_amount"] = matches.groupby("contributor_match_key")[
        "contribution_receipt_amount"
    ].transform("sum")
    matches = matches.drop_duplicates("contributor_match_key", keep="first")

    candidates = matches[matches["contribution_receipt_amount"] >= LABEL_THRESHOLD].copy()
    # The matcher's own `matched` is an auto-match boolean -- a different concept from this
    # pipeline's `matched` column below, which is a hand-verified/corrected PI value the user
    # fills in by reviewing lseg_search_pi/lseg_top_pi. Never auto-populated from this boolean.
    candidates = candidates.drop(columns=["matched"], errors="ignore")

    if crosswalk_path.exists():
        crosswalk = FECClient.read_csv_safe(crosswalk_path, dtype=str)
        crosswalk_cols = ["contributor_match_key"] + [
            c for c in SUGGESTION_COLS_FROM_CROSSWALK if c in crosswalk.columns
        ]
        crosswalk = crosswalk[crosswalk_cols].drop_duplicates("contributor_match_key", keep="last")
        candidates = candidates.merge(
            crosswalk, on="contributor_match_key", how="left", suffixes=("", "_crosswalk")
        )
        for col in SUGGESTION_COLS_FROM_CROSSWALK:
            crosswalk_col = f"{col}_crosswalk"
            if crosswalk_col not in candidates.columns:
                continue
            blank = candidates[col].isna() | (candidates[col].astype(str).str.strip() == "")
            candidates[col] = candidates[col].where(~blank, candidates[crosswalk_col])
            candidates = candidates.drop(columns=[crosswalk_col])

    for col in FINAL_COLUMNS:
        if col not in candidates.columns:
            candidates[col] = ""
    return candidates[FINAL_COLUMNS]


def migrate_xlsx_labels(review_path: Path, xlsx_path: Path) -> None:
    """
    One-time seed: read the existing hand-labeled xlsx (read-only, never modified) and apply
    its Type/connected/matched values onto the new review file by contributor_match_key, so
    switching from xlsx to CSV doesn't lose already-completed hand labels.
    """
    if not xlsx_path.exists():
        raise FileNotFoundError(f"Migration source not found: {xlsx_path}")
    if not review_path.exists():
        raise FileNotFoundError(f"Review file not found -- run build_label_review.py first: {review_path}")

    def _first_non_blank(values: pd.Series) -> str:
        for value in values:
            if pd.notna(value) and str(value).strip() != "":
                return value
        return ""

    xlsx = pd.read_excel(xlsx_path, keep_default_na=False, na_values=[""])
    # xlsx's `matched` is a hand-verified PI, stored by Excel as float64 (e.g. 5079215000.0) --
    # clean it to a plain integer string before it's carried anywhere else.
    xlsx["matched"] = xlsx["matched"].apply(_clean_numeric_str)
    xlsx = xlsx[["contributor_match_key", "Type", "connected", "matched"]].dropna(subset=["contributor_match_key"])
    # contributor_match_key is NOT unique in the xlsx -- normalize_name collapses distinct
    # original names (e.g. many committees all routing through "ACTBLUE") onto the same key, so
    # a naive drop_duplicates can throw away a row that actually has a hand-applied label in
    # favor of a blank duplicate of the same key. Coalesce each hand column independently across
    # every duplicate sharing a key instead, so a label set on ANY of them survives.
    xlsx = xlsx.groupby("contributor_match_key", as_index=False).agg(
        Type=("Type", _first_non_blank),
        connected=("connected", _first_non_blank),
        matched=("matched", _first_non_blank),
    )

    review = FECClient.read_csv_safe(review_path, dtype=str)
    review = review.merge(xlsx, on="contributor_match_key", how="left", suffixes=("", "_xlsx"))

    seeded_mask = pd.Series(False, index=review.index)
    for col in ("Type", "connected", "matched"):
        xlsx_col = f"{col}_xlsx"
        has_value = review[xlsx_col].notna() & (review[xlsx_col].astype(str).str.strip() != "")
        seeded_mask |= has_value
        review.loc[has_value, col] = review.loc[has_value, xlsx_col]
        review = review.drop(columns=[xlsx_col])

    FECClient.atomic_write(str(review_path), lambda p: review.to_csv(p, index=False))
    print(f"Seeded {int(seeded_mask.sum()):,} rows from {xlsx_path.name} into {review_path.name}.")


def run(client: FECClient, migrate_xlsx: bool) -> None:
    output_dir = Path(client.processed_fec_path) / OUTPUT_SUBDIR
    matches_path = output_dir / "organization_firm_matches.csv"
    crosswalk_path = output_dir / "organization_lseg_pi_crosswalk.csv"
    review_path = output_dir / "organization_label_review.csv"

    if not matches_path.exists():
        raise FileNotFoundError(
            f"{matches_path} not found -- run FECsuperOrganizationFirmMatcher.py --stage match "
            f"against {output_dir / 'organization_contributors.csv'} first."
        )

    candidates = build_review_candidates(matches_path, crosswalk_path)
    print(f"{len(candidates):,} contributors at or above ${LABEL_THRESHOLD:,} eligible for review.")
    FECClient.refresh_unlabeled(candidates, str(review_path), REVIEW_KEY_COLS, PROTECT_COLS)

    if migrate_xlsx:
        xlsx_path = Path(client.contributions_path) / "super_contributor_org_label.xlsx"
        migrate_xlsx_labels(review_path, xlsx_path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Build/refresh the organization contributor label review file from "
                    "FECsuperOrganizationFirmMatcher.py's match output."
    )
    parser.add_argument(
        "--migrate-xlsx", action="store_true",
        help="One-time: seed Type/connected from the existing super_contributor_org_label.xlsx.",
    )
    args = parser.parse_args()
    run(FECClient(), migrate_xlsx=args.migrate_xlsx)
