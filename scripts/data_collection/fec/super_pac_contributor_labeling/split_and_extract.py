import argparse
import sys
from pathlib import Path

import pandas as pd
import polars as pl

# fec_client.py and FECsuperOrganizationFirmMatcher.py live one level up, in fec/ -- not a
# package, so direct-script execution needs an explicit sys.path entry rather than a relative
# import.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient
from FECsuperOrganizationFirmMatcher import normalize_name

# Citizens United v. FEC (decided 2010-01-21) is what made super PACs possible. Contributions
# scraped under a super PAC committee ID from before this are predecessor-committee/data
# artifacts, not meaningfully part of the study population, so they're excluded entirely
# rather than bucketed as "undefined".
CUTOFF_DATE = "2010-01-01"

OUTPUT_SUBDIR = "super_org_labeling"
CONTRIBUTOR_GROUP_COLS = ["contributor_name", "contributor_city", "contributor_state",
                          "entity_type", "contributor_id"]
# NOT contributor_match_key: that's a normalized key that deliberately collapses distinct raw
# name variants (e.g. "Foo Media" and "Foo Media, LLC" both drop to the same key, by design, for
# firm matching). Using it as the merge identity here would non-deterministically collide rows
# that are still distinct at this table's actual grain (one row per raw name/city/state/
# entity_type/contributor_id combination) -- contributor_match_key is kept as a descriptive
# column only, never as the append_only_csv key.
CONTRIBUTOR_KEY_COLS = CONTRIBUTOR_GROUP_COLS


def split_contributions(contributions: pl.DataFrame) -> dict:
    """
    Classify contributions into individual/organization, excluding anything before CUTOFF_DATE
    entirely and bucketing null-dated rows as undefined regardless of entity_type. Automatic
    first-pass rule only: entity_type == "IND" -> individual; everything else (including a null
    entity_type) -> organization. There is no automatic "committee" bucket -- committee-ness and
    any other FEC-mislabeling correction is assigned by hand during organization labeling.
    """
    total = contributions.height
    undated = contributions.filter(pl.col("contribution_receipt_date").is_null())
    dated = contributions.filter(pl.col("contribution_receipt_date").is_not_null())

    pre_cutoff = dated.filter(pl.col("contribution_receipt_date") < CUTOFF_DATE)
    in_scope = dated.filter(pl.col("contribution_receipt_date") >= CUTOFF_DATE)

    individual = in_scope.filter(pl.col("entity_type") == "IND")
    organization = in_scope.filter((pl.col("entity_type") != "IND") | pl.col("entity_type").is_null())

    print(
        f"{total:,} total rows -- {pre_cutoff.height:,} excluded (before {CUTOFF_DATE}, "
        f"Citizens United), {undated.height:,} undefined (no date), "
        f"{individual.height:,} individual, {organization.height:,} organization."
    )
    assert individual.height + organization.height + undated.height + pre_cutoff.height == total

    return {"individual": individual, "organization": organization, "undefined": undated}


def extract_organization_contributors(organization: pl.DataFrame) -> pd.DataFrame:
    """
    Unique organization-level contributors (name/city/state/entity_type/contributor_id), with
    summed contribution_receipt_amount, plus contributor_match_key -- the same normalized-name
    key FECsuperOrganizationFirmMatcher.py already computes for matching, so the two pipelines
    agree on contributor identity. Rows with no contributor_name at all are dropped: there's
    nothing to label or match without a name, and a handful of distinct "blank-like" identities
    (true null vs. an empty string vs. a literal placeholder) are otherwise indistinguishable
    once round-tripped through CSV, which made append_only_csv's key matching non-deterministic
    for exactly these rows across runs.
    """
    organization = organization.filter(
        pl.col("contributor_name").is_not_null() & (pl.col("contributor_name").str.strip_chars() != "")
    )
    grouped = (
        organization.group_by(CONTRIBUTOR_GROUP_COLS)
        .agg(pl.col("contribution_receipt_amount").sum().alias("contribution_receipt_amount"))
        .to_pandas()
    )
    grouped["contributor_match_key"] = grouped["contributor_name"].apply(
        lambda name: normalize_name(name, drop_legal=True, drop_political=True)
    )
    return grouped


def run(client: FECClient) -> None:
    output_dir = Path(client.processed_fec_path) / OUTPUT_SUBDIR
    output_dir.mkdir(parents=True, exist_ok=True)

    contributions = pl.read_parquet(f"{client.contributions_path}super_contributions.parquet")
    subsets = split_contributions(contributions)

    for name, subset in subsets.items():
        path = output_dir / f"{name}_contributions.parquet"
        client.atomic_write(str(path), lambda p, df=subset: df.write_parquet(p))

    contributors = extract_organization_contributors(subsets["organization"])
    client.append_only_csv(
        contributors, str(output_dir / "organization_contributors.csv"), CONTRIBUTOR_KEY_COLS
    )


if __name__ == "__main__":
    argparse.ArgumentParser(
        description=(
            "Split super_contributions.parquet into individual/organization/undefined subsets "
            "(2010+ only, excluding pre-Citizens-United rows entirely) and extract/refresh the "
            "unique organization-contributor table used by the labeling pipeline."
        )
    ).parse_args()
    run(FECClient())
