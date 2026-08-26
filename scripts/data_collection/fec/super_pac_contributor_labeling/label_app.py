import sys
from pathlib import Path

import pandas as pd
import streamlit as st

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient

OUTPUT_SUBDIR = "super_org_labeling"

# Seeds the dropdown with the taxonomy already established via the migrated xlsx hand labels;
# any genuinely new value a user types stays available for the rest of the session via
# type_options() picking up whatever's already in the data.
DEFAULT_TYPE_OPTIONS = [
    "Company", "Non-Profit", "Union", "Government", "Committee", "Trade Association", "Other",
]

# Read-only reference columns shown to help decide `matched` -- not editable.
SUGGESTION_COLS = ["lseg_search_title", "lseg_search_pi", "lseg_top_title", "lseg_top_pi"]

DISPLAY_COLS = [
    "contributor_name", "contributor_city", "contributor_state", "contribution_receipt_amount",
]

# `matched` is a hand-verified/corrected PI value (reviewed against lseg_search_pi/lseg_top_pi
# above), not the matcher's own auto-match boolean -- a free-text field, same as Type/connected.
HAND_COLS = ["matched", "Type", "connected"]


def load_review(path: Path) -> pd.DataFrame:
    df = FECClient.read_csv_safe(path, dtype=str).fillna("")
    df["contribution_receipt_amount"] = pd.to_numeric(df["contribution_receipt_amount"], errors="coerce")
    return df


def type_options(df: pd.DataFrame) -> list:
    existing = sorted(v for v in df.get("Type", pd.Series(dtype=str)).unique() if v)
    return [""] + list(dict.fromkeys(DEFAULT_TYPE_OPTIONS + existing))


def main() -> None:
    st.set_page_config(page_title="Super PAC Organization Contributor Labeling", layout="wide")
    st.title("Super PAC Organization Contributor Labeling")

    client = FECClient()
    review_path = Path(client.processed_fec_path) / OUTPUT_SUBDIR / "organization_label_review.csv"
    if not review_path.exists():
        st.error(f"Review file not found: {review_path}. Run build_label_review.py first.")
        return

    if "review_df" not in st.session_state or st.session_state.get("review_path") != str(review_path):
        st.session_state.review_df = load_review(review_path)
        st.session_state.review_path = str(review_path)

    df = st.session_state.review_df

    col1, col2 = st.columns([1, 2])
    show_unlabeled_only = col1.checkbox("Show unlabeled only", value=True)
    search = col2.text_input("Search contributor name")

    view = df.copy()
    if show_unlabeled_only:
        view = view[view["Type"].str.strip() == ""]
    if search:
        view = view[view["contributor_name"].str.contains(search, case=False, na=False)]
    view = view.sort_values("contribution_receipt_amount", ascending=False)

    st.caption(f"{len(view):,} of {len(df):,} contributors shown (${40000:,}+ floor already applied).")

    editor_cols = DISPLAY_COLS + [c for c in SUGGESTION_COLS if c in view.columns] + HAND_COLS
    editor_view = view[editor_cols].copy()

    # Without a form, st.data_editor reruns the whole script every time a cell edit is
    # committed (e.g. tabbing to the next row) -- with ~600 unlabeled rows to filter/sort/
    # rebuild each time, that rerun is what looks like "the page refreshes" after every entry.
    # A form defers all of that until the submit button is clicked, so you can fill in several
    # rows in one pass with no interruption.
    with st.form("label_form"):
        edited = st.data_editor(
            editor_view,
            column_config={
                "Type": st.column_config.SelectboxColumn("Type", options=type_options(df)),
                "connected": st.column_config.TextColumn("connected"),
                "matched": st.column_config.TextColumn(
                    "matched", help="Hand-verified PI -- review lseg_search_pi/lseg_top_pi above and confirm or correct."
                ),
                "contribution_receipt_amount": st.column_config.NumberColumn(
                    "contribution_receipt_amount", format="$%.0f", disabled=True
                ),
            },
            disabled=[c for c in editor_cols if c not in HAND_COLS],
            hide_index=True,
            use_container_width=True,
            key="editor",
        )
        submitted = st.form_submit_button("Save labels", type="primary")

    if submitted:
        for col in HAND_COLS:
            df.loc[edited.index, col] = edited[col]
        FECClient.atomic_write(str(review_path), lambda p: df.to_csv(p, index=False))
        st.session_state.review_df = df
        st.success(f"Saved {len(edited):,} rows to {review_path.name}.")


if __name__ == "__main__":
    main()
