import argparse
import sys
from pathlib import Path

import polars as pl

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient
from FECsuperOrganizationFirmMatcher import normalize_name

OUTPUT_SUBDIR = "super_org_labeling"


def run(client: FECClient) -> None:
    """
    Join organization_label_review.csv's hand labels (Type/connected/matched) onto every
    contribution row in organization_contributions.parquet, by contributor_match_key. Pure
    re-derivation -- safe to re-run any time the review file changes, which is the "reflect the
    update in the subset data" step.
    """
    output_dir = Path(client.processed_fec_path) / OUTPUT_SUBDIR
    contributions = pl.read_parquet(str(output_dir / "organization_contributions.parquet"))
    review = pl.read_csv(
        str(output_dir / "organization_label_review.csv"), infer_schema_length=10000
    ).select(["contributor_match_key", "Type", "connected", "matched"])

    # normalize_name is computed once per distinct contributor_name (not once per row) --
    # contribution-level files can have far more rows than distinct contributors.
    unique_names = contributions.select("contributor_name").unique()
    unique_names = unique_names.with_columns(
        pl.col("contributor_name")
        .map_elements(
            lambda name: normalize_name(name, drop_legal=True, drop_political=True),
            return_dtype=pl.Utf8,
        )
        .alias("contributor_match_key")
    )

    labeled = (
        contributions.join(unique_names, on="contributor_name", how="left")
        .join(review, on="contributor_match_key", how="left")
    )

    n_labeled = labeled.filter(pl.col("Type").is_not_null() & (pl.col("Type") != "")).height
    print(f"{n_labeled:,} of {labeled.height:,} contribution rows matched a labeled contributor.")

    out_path = output_dir / "organization_contributions_labeled.parquet"
    client.atomic_write(str(out_path), lambda p: labeled.write_parquet(p))


if __name__ == "__main__":
    argparse.ArgumentParser(
        description="Join organization_label_review.csv's Type/connected onto "
                    "organization_contributions.parquet by contributor_match_key."
    ).parse_args()
    run(FECClient())
