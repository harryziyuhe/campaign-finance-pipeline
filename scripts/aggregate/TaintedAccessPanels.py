"""Build event-time DiD panels for the corporate PAC scandal project.

Reads firm PAC contributions to candidate principal committees and a curated
scandal event file. Writes a broad firm-candidate-period panel and a
firm-period panel for relationship-level and firm-level DiD designs.
"""

from __future__ import annotations

import argparse
import math
import shutil
from datetime import date, timedelta
import os
from pathlib import Path
from typing import Iterable

import polars as pl


SCRIPT_ROOT = Path(__file__).resolve().parents[2]


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
DEFAULT_CONTRIBUTIONS_PATH = (
    DATA_ROOT
    / "data"
    / "processed"
    / "fec"
    / "firm_pac_to_principal_committee_contributions.parquet"
)
DEFAULT_EVENTS_PATH = (
    DATA_ROOT
    / "data"
    / "external"
    / "congress"
    / "scandals"
    / "tainted_access_events.csv"
)
DEFAULT_OUTPUT_DIR = DATA_ROOT / "data" / "processed" / "tainted_access"

RELATIONSHIP_OUTPUT = "firm_candidate_period_panel.parquet"
FIRM_OUTPUT = "firm_period_panel.parquet"
STAGING_DIR = "_staging"

REQUIRED_CONTRIBUTION_COLUMNS = {
    "cmte_id",
    "cand_id",
    "amount",
    "year",
    "month",
    "day",
    "cycle",
}
REQUIRED_EVENT_COLUMNS = {"scandal_id", "cand_id", "event_date", "event_label"}

FIRM_METADATA_COLUMNS = [
    "cmte_nm",
    "connected_org_nm",
    "corporation",
    "parent",
    "website",
    "ttl_receipts",
    "instrument",
    "cusip",
    "isin",
    "common_name",
    "business_description",
    "ric",
    "former_name",
    "business_name",
    "hq",
    "hq_state",
    "hq_city",
    "permid",
    "parent_hq",
    "parent_permid",
    "GICS_ID",
    "GICS_Sector",
    "GICS_Industry_Group",
    "GICS_Industry",
    "GIS_Subindustry",
    "ICB_ID",
    "ICB_Industry",
    "ICB_Super_Sector",
    "ICB_Sector",
    "ICB_Sub_Sector",
    "TRBC_ID",
    "TRBC_Econ_Sector",
    "TRBC_Business_Sector",
    "TRBC_Industry_Group",
    "TRBC_Industry",
    "TRBC_Activity",
    "NAICS_ID",
    "NAICS_Sector",
    "NAICS_Subsector",
    "NAICS_Industry_Group",
    "NAICS_International_Industry",
    "NAICS_National_Industry",
]

PERIOD_KEY_COLUMNS = [
    "scandal_id",
    "period_unit",
    "period_length",
    "relative_period",
    "period_start",
    "period_end",
]

RELATIONSHIP_OUTCOME_COLUMNS = [
    "total_amount",
    "positive_amount",
    "refund_amount",
    "contribution_count",
    "positive_contribution_count",
]

FIRM_OUTCOME_COLUMNS = [
    "total_amount_all_candidates",
    "positive_amount_all_candidates",
    "contribution_count_all_candidates",
    "unique_candidates_all",
    "total_amount_excluding_scandal_cand",
    "positive_amount_excluding_scandal_cand",
    "contribution_count_excluding_scandal_cand",
    "unique_candidates_excluding_scandal_cand",
    "total_amount_to_scandal_cand",
    "positive_amount_to_scandal_cand",
    "contribution_count_to_scandal_cand",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build tainted-access firm-candidate and firm-period DiD panels."
    )
    parser.add_argument(
        "--contributions",
        type=Path,
        default=DEFAULT_CONTRIBUTIONS_PATH,
        help="Firm PAC to principal committee contribution parquet.",
    )
    parser.add_argument(
        "--events",
        type=Path,
        default=DEFAULT_EVENTS_PATH,
        help="Curated event CSV with scandal_id, cand_id, event_date, event_label.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Directory for generated panel parquet files.",
    )
    parser.add_argument(
        "--period-unit",
        choices=["quarter", "month"],
        default="quarter",
        help="Base event-time unit.",
    )
    parser.add_argument(
        "--window-pre",
        type=int,
        default=8,
        help="Number of base periods before the event period.",
    )
    parser.add_argument(
        "--window-post",
        type=int,
        default=8,
        help="Number of base periods after and including the event period.",
    )
    parser.add_argument(
        "--period-lengths",
        type=int,
        nargs="+",
        default=[1, 2, 4],
        help="Aggregation lengths in base period units.",
    )
    parser.add_argument(
        "--max-events",
        type=int,
        default=None,
        help="Optional development limit on number of events processed.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing panel outputs.",
    )
    return parser.parse_args()


def validate_columns(columns: Iterable[str], required: set[str], source: Path) -> None:
    missing = sorted(required - set(columns))
    if missing:
        raise ValueError(f"{source} is missing required columns: {missing}")


def add_months(value: date, months: int) -> date:
    month_index = value.month - 1 + months
    year = value.year + month_index // 12
    month = month_index % 12 + 1
    return date(year, month, 1)


def base_period_start(value: date, period_unit: str) -> date:
    if period_unit == "month":
        return date(value.year, value.month, 1)
    quarter_start_month = ((value.month - 1) // 3) * 3 + 1
    return date(value.year, quarter_start_month, 1)


def base_months(period_unit: str) -> int:
    return 1 if period_unit == "month" else 3


def existing_output_paths(output_dir: Path) -> list[Path]:
    return [
        output_dir / RELATIONSHIP_OUTPUT,
        output_dir / FIRM_OUTPUT,
    ]


def check_outputs(output_dir: Path, overwrite: bool) -> None:
    existing = [path for path in existing_output_paths(output_dir) if path.exists()]
    if existing and not overwrite:
        paths = ", ".join(str(path) for path in existing)
        raise FileExistsError(f"Output already exists. Use --overwrite: {paths}")


def reset_staging_dir(output_dir: Path) -> Path:
    staging_dir = output_dir / STAGING_DIR
    resolved_output = output_dir.resolve()
    resolved_staging = staging_dir.resolve()
    if resolved_output not in resolved_staging.parents:
        raise ValueError(f"Refusing to clear staging path outside output dir: {staging_dir}")
    if staging_dir.exists():
        shutil.rmtree(staging_dir)
    staging_dir.mkdir(parents=True, exist_ok=True)
    return staging_dir


def clean_staging_dir(staging_dir: Path) -> None:
    resolved_staging = staging_dir.resolve()
    if staging_dir.exists() and staging_dir.name == STAGING_DIR:
        shutil.rmtree(resolved_staging)


def load_events(path: Path, max_events: int | None) -> pl.DataFrame:
    events = pl.read_csv(path, infer_schema_length=10000)
    validate_columns(events.columns, REQUIRED_EVENT_COLUMNS, path)

    events = (
        events.rename({"cand_id": "scandal_cand_id"})
        .with_columns(
            pl.col("scandal_id").cast(pl.Utf8),
            pl.col("scandal_cand_id").cast(pl.Utf8),
            pl.col("event_label").cast(pl.Utf8),
            pl.col("event_date").str.strptime(pl.Date, strict=False),
        )
        .drop_nulls(subset=["scandal_id", "scandal_cand_id", "event_date"])
    )

    for column in ["retirement_date", "resignation_date"]:
        if column in events.columns and events.schema[column] == pl.Utf8:
            events = events.with_columns(
                pl.col(column).str.strptime(pl.Date, strict=False)
            )

    if max_events is not None:
        events = events.head(max_events)
    if events.is_empty():
        raise ValueError(f"No valid events found in {path}")
    return events


def load_contributions(path: Path) -> pl.DataFrame:
    contributions = pl.read_parquet(path)
    validate_columns(contributions.columns, REQUIRED_CONTRIBUTION_COLUMNS, path)

    return contributions.with_columns(
        pl.date(
            pl.col("year").cast(pl.Int32),
            pl.col("month").cast(pl.Int8),
            pl.col("day").cast(pl.Int8),
        ).alias("transaction_date"),
        pl.col("cmte_id").cast(pl.Utf8),
        pl.col("cand_id").cast(pl.Utf8),
    )


def first_non_null(column: str) -> pl.Expr:
    return pl.col(column).drop_nulls().first().alias(column)


def firm_metadata(contributions: pl.DataFrame) -> pl.DataFrame:
    metadata_columns = [
        column for column in FIRM_METADATA_COLUMNS if column in contributions.columns
    ]
    if not metadata_columns:
        return contributions.select("cmte_id").unique()

    return (
        contributions.group_by("cmte_id")
        .agg([first_non_null(column) for column in metadata_columns])
        .sort("cmte_id")
    )


def event_periods(
    event: dict[str, object],
    period_unit: str,
    window_pre: int,
    window_post: int,
    period_lengths: list[int],
) -> pl.DataFrame:
    event_date = event["event_date"]
    if not isinstance(event_date, date):
        raise TypeError("event_date must be parsed as a date")

    anchor = base_period_start(event_date, period_unit)
    base_period_months = base_months(period_unit)
    rows: list[dict[str, object]] = []

    for period_length in period_lengths:
        if period_length <= 0:
            raise ValueError("All --period-lengths values must be positive integers")

        step_months = base_period_months * period_length
        pre_bins = math.ceil(window_pre / period_length)
        post_bins = math.ceil(window_post / period_length)

        for relative_period in range(-pre_bins, post_bins):
            period_start = add_months(anchor, relative_period * step_months)
            period_end = add_months(period_start, step_months) - timedelta(days=1)
            row = dict(event)
            row.update(
                {
                    "period_unit": period_unit,
                    "period_length": period_length,
                    "relative_period": relative_period,
                    "period_start": period_start,
                    "period_end": period_end,
                    "post": int(relative_period >= 0),
                }
            )
            rows.append(row)

    return pl.DataFrame(rows)


def periodized_contributions(
    contributions: pl.DataFrame,
    periods: pl.DataFrame,
) -> pl.DataFrame:
    period_lookup = periods.select(PERIOD_KEY_COLUMNS).unique()
    return (
        contributions.join(period_lookup, how="cross")
        .filter(
            (pl.col("transaction_date") >= pl.col("period_start"))
            & (pl.col("transaction_date") <= pl.col("period_end"))
        )
    )


def relationship_outcomes(periodized: pl.DataFrame) -> pl.DataFrame:
    return periodized.group_by(["cmte_id", "cand_id", *PERIOD_KEY_COLUMNS]).agg(
        pl.col("amount").sum().alias("total_amount"),
        pl.when(pl.col("amount") > 0)
        .then(pl.col("amount"))
        .otherwise(0)
        .sum()
        .alias("positive_amount"),
        pl.when(pl.col("amount") < 0)
        .then(-pl.col("amount"))
        .otherwise(0)
        .sum()
        .alias("refund_amount"),
        pl.len().alias("contribution_count"),
        (pl.col("amount") > 0).sum().alias("positive_contribution_count"),
    )


def firm_outcomes(
    periodized: pl.DataFrame,
    scandal_cand_id: str,
) -> tuple[pl.DataFrame, pl.DataFrame, pl.DataFrame]:
    all_candidates = periodized.group_by(["cmte_id", *PERIOD_KEY_COLUMNS]).agg(
        pl.col("amount").sum().alias("total_amount_all_candidates"),
        pl.when(pl.col("amount") > 0)
        .then(pl.col("amount"))
        .otherwise(0)
        .sum()
        .alias("positive_amount_all_candidates"),
        pl.len().alias("contribution_count_all_candidates"),
        pl.col("cand_id").n_unique().alias("unique_candidates_all"),
    )

    excluding_scandal = (
        periodized.filter(pl.col("cand_id") != scandal_cand_id)
        .group_by(["cmte_id", *PERIOD_KEY_COLUMNS])
        .agg(
            pl.col("amount").sum().alias("total_amount_excluding_scandal_cand"),
            pl.when(pl.col("amount") > 0)
            .then(pl.col("amount"))
            .otherwise(0)
            .sum()
            .alias("positive_amount_excluding_scandal_cand"),
            pl.len().alias("contribution_count_excluding_scandal_cand"),
            pl.col("cand_id").n_unique().alias("unique_candidates_excluding_scandal_cand"),
        )
    )

    scandal_candidate = (
        periodized.filter(pl.col("cand_id") == scandal_cand_id)
        .group_by(["cmte_id", *PERIOD_KEY_COLUMNS])
        .agg(
            pl.col("amount").sum().alias("total_amount_to_scandal_cand"),
            pl.when(pl.col("amount") > 0)
            .then(pl.col("amount"))
            .otherwise(0)
            .sum()
            .alias("positive_amount_to_scandal_cand"),
            pl.len().alias("contribution_count_to_scandal_cand"),
        )
    )

    return all_candidates, excluding_scandal, scandal_candidate


def pre_scandal_relationships(
    contributions: pl.DataFrame,
    scandal_cand_id: str,
    event_date: date,
) -> tuple[pl.DataFrame, pl.DataFrame, pl.DataFrame]:
    positive_pre = contributions.filter(
        (pl.col("transaction_date") < event_date) & (pl.col("amount") > 0)
    )

    candidate_pre = positive_pre.group_by(["cmte_id", "cand_id"]).agg(
        pl.col("amount").sum().alias("pre_amount_to_candidate"),
        pl.len().alias("pre_count_to_candidate"),
    )

    scandal_pre = (
        positive_pre.filter(pl.col("cand_id") == scandal_cand_id)
        .group_by("cmte_id")
        .agg(
            pl.col("amount").sum().alias("pre_amount_to_scandal_cand"),
            pl.len().alias("pre_count_to_scandal_cand"),
        )
    )

    firm_pre = positive_pre.group_by("cmte_id").agg(
        pl.col("amount").sum().alias("pre_total_amount_all_candidates"),
        pl.col("cand_id").n_unique().alias("pre_unique_candidates_all"),
    )

    return candidate_pre, scandal_pre, firm_pre


def zero_fill(frame: pl.DataFrame, columns: list[str]) -> pl.DataFrame:
    present_columns = [column for column in columns if column in frame.columns]
    if not present_columns:
        return frame
    return frame.with_columns([pl.col(column).fill_null(0) for column in present_columns])


def build_relationship_panel(
    event_contributions: pl.DataFrame,
    periods: pl.DataFrame,
    firm_info: pl.DataFrame,
    scandal_cand_id: str,
    event_date: date,
) -> pl.DataFrame:
    risk_pairs = event_contributions.select(["cmte_id", "cand_id"]).unique()
    full_panel = risk_pairs.join(periods, how="cross")
    periodized = periodized_contributions(event_contributions, periods)

    candidate_pre, scandal_pre, _ = pre_scandal_relationships(
        event_contributions, scandal_cand_id, event_date
    )
    outcomes = relationship_outcomes(periodized)

    panel = (
        full_panel.join(outcomes, on=["cmte_id", "cand_id", *PERIOD_KEY_COLUMNS], how="left")
        .join(candidate_pre, on=["cmte_id", "cand_id"], how="left")
        .join(scandal_pre, on="cmte_id", how="left")
        .join(firm_info, on="cmte_id", how="left")
    )

    panel = zero_fill(
        panel,
        [
            *RELATIONSHIP_OUTCOME_COLUMNS,
            "pre_amount_to_candidate",
            "pre_count_to_candidate",
            "pre_amount_to_scandal_cand",
            "pre_count_to_scandal_cand",
        ],
    )

    panel = panel.with_columns(
        (pl.col("positive_contribution_count") > 0)
        .cast(pl.Int8)
        .alias("any_contribution"),
        (pl.col("pre_count_to_candidate") > 0)
        .cast(pl.Int8)
        .alias("ever_pre_contributed_to_candidate"),
        (pl.col("pre_count_to_scandal_cand") > 0)
        .cast(pl.Int8)
        .alias("ever_pre_contributed_to_scandal_cand"),
        (pl.col("cand_id") == pl.col("scandal_cand_id"))
        .cast(pl.Int8)
        .alias("scandal_cand"),
    )

    panel = panel.with_columns(
        (
            (pl.col("scandal_cand") == 1)
            & (pl.col("ever_pre_contributed_to_scandal_cand") == 1)
        )
        .cast(pl.Int8)
        .alias("pre_treated_pair")
    )

    return panel.with_columns(
        pl.col("pre_treated_pair").alias("treated_pair"),
        (pl.col("pre_treated_pair") * pl.col("post")).alias("did_treated_post"),
    )


def build_firm_panel(
    event_contributions: pl.DataFrame,
    periods: pl.DataFrame,
    firm_info: pl.DataFrame,
    scandal_cand_id: str,
    event_date: date,
) -> pl.DataFrame:
    risk_firms = event_contributions.select("cmte_id").unique()
    full_panel = risk_firms.join(periods, how="cross")
    periodized = periodized_contributions(event_contributions, periods)

    _, scandal_pre, firm_pre = pre_scandal_relationships(
        event_contributions, scandal_cand_id, event_date
    )
    all_candidates, excluding_scandal, scandal_candidate = firm_outcomes(
        periodized, scandal_cand_id
    )

    panel = (
        full_panel.join(all_candidates, on=["cmte_id", *PERIOD_KEY_COLUMNS], how="left")
        .join(excluding_scandal, on=["cmte_id", *PERIOD_KEY_COLUMNS], how="left")
        .join(scandal_candidate, on=["cmte_id", *PERIOD_KEY_COLUMNS], how="left")
        .join(firm_pre, on="cmte_id", how="left")
        .join(scandal_pre, on="cmte_id", how="left")
        .join(firm_info, on="cmte_id", how="left")
    )

    panel = zero_fill(
        panel,
        [
            *FIRM_OUTCOME_COLUMNS,
            "pre_total_amount_all_candidates",
            "pre_unique_candidates_all",
            "pre_amount_to_scandal_cand",
            "pre_count_to_scandal_cand",
        ],
    )

    panel = panel.rename(
        {"pre_amount_to_scandal_cand": "pre_total_amount_to_scandal_cand"}
    )

    panel = panel.with_columns(
        (pl.col("contribution_count_all_candidates") > 0)
        .cast(pl.Int8)
        .alias("any_contribution_all"),
        (pl.col("contribution_count_excluding_scandal_cand") > 0)
        .cast(pl.Int8)
        .alias("any_contribution_excluding_scandal_cand"),
        (pl.col("contribution_count_to_scandal_cand") > 0)
        .cast(pl.Int8)
        .alias("any_contribution_to_scandal_cand"),
        (pl.col("pre_count_to_scandal_cand") > 0)
        .cast(pl.Int8)
        .alias("exposed_firm"),
    )

    return panel.with_columns(
        pl.col("exposed_firm").alias("pre_exposed_firm"),
        (pl.col("exposed_firm") * pl.col("post")).alias("did_exposed_post"),
    )


def build_panels(
    contributions: pl.DataFrame,
    events: pl.DataFrame,
    period_unit: str,
    window_pre: int,
    window_post: int,
    period_lengths: list[int],
) -> tuple[pl.DataFrame, pl.DataFrame]:
    firm_info = firm_metadata(contributions)
    relationship_panels: list[pl.DataFrame] = []
    firm_panels: list[pl.DataFrame] = []

    for event in events.iter_rows(named=True):
        periods = event_periods(
            event,
            period_unit=period_unit,
            window_pre=window_pre,
            window_post=window_post,
            period_lengths=period_lengths,
        )
        window_start = periods["period_start"].min()
        window_end = periods["period_end"].max()
        scandal_cand_id = str(event["scandal_cand_id"])
        event_date = event["event_date"]

        event_contributions = contributions.filter(
            (pl.col("transaction_date") >= window_start)
            & (pl.col("transaction_date") <= window_end)
        )
        if event_contributions.is_empty():
            continue

        relationship_panels.append(
            build_relationship_panel(
                event_contributions,
                periods,
                firm_info,
                scandal_cand_id,
                event_date,
            )
        )
        firm_panels.append(
            build_firm_panel(
                event_contributions,
                periods,
                firm_info,
                scandal_cand_id,
                event_date,
            )
        )

    if not relationship_panels or not firm_panels:
        raise ValueError("No panel rows were created for the supplied event windows")

    relationship_panel = pl.concat(relationship_panels, how="diagonal_relaxed")
    firm_panel = pl.concat(firm_panels, how="diagonal_relaxed")
    return relationship_panel, firm_panel


def combine_partitions(part_paths: list[Path], output_path: Path) -> None:
    if not part_paths:
        raise ValueError(f"No partitions available for {output_path}")
    scans = [pl.scan_parquet(part_path) for part_path in part_paths]
    pl.concat(scans, how="diagonal_relaxed").sink_parquet(output_path)


def build_panel_files(
    contributions: pl.DataFrame,
    events: pl.DataFrame,
    period_unit: str,
    window_pre: int,
    window_post: int,
    period_lengths: list[int],
    output_dir: Path,
) -> None:
    firm_info = firm_metadata(contributions)
    staging_dir = reset_staging_dir(output_dir)
    relationship_parts: list[Path] = []
    firm_parts: list[Path] = []

    try:
        for event_number, event in enumerate(events.iter_rows(named=True), start=1):
            periods = event_periods(
                event,
                period_unit=period_unit,
                window_pre=window_pre,
                window_post=window_post,
                period_lengths=period_lengths,
            )
            window_start = periods["period_start"].min()
            window_end = periods["period_end"].max()
            scandal_cand_id = str(event["scandal_cand_id"])
            event_date = event["event_date"]

            event_contributions = contributions.filter(
                (pl.col("transaction_date") >= window_start)
                & (pl.col("transaction_date") <= window_end)
            )
            if event_contributions.is_empty():
                continue

            relationship_panel = build_relationship_panel(
                event_contributions,
                periods,
                firm_info,
                scandal_cand_id,
                event_date,
            )
            firm_panel = build_firm_panel(
                event_contributions,
                periods,
                firm_info,
                scandal_cand_id,
                event_date,
            )

            relationship_part = staging_dir / f"relationship_{event_number:04d}.parquet"
            firm_part = staging_dir / f"firm_{event_number:04d}.parquet"
            relationship_panel.write_parquet(relationship_part)
            firm_panel.write_parquet(firm_part)
            relationship_parts.append(relationship_part)
            firm_parts.append(firm_part)

            del relationship_panel
            del firm_panel
            del event_contributions

        combine_partitions(relationship_parts, output_dir / RELATIONSHIP_OUTPUT)
        combine_partitions(firm_parts, output_dir / FIRM_OUTPUT)
    finally:
        clean_staging_dir(staging_dir)


def main() -> None:
    args = parse_args()
    check_outputs(args.output_dir, args.overwrite)

    events = load_events(args.events, args.max_events)
    contributions = load_contributions(args.contributions)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    build_panel_files(
        contributions=contributions,
        events=events,
        period_unit=args.period_unit,
        window_pre=args.window_pre,
        window_post=args.window_post,
        period_lengths=args.period_lengths,
        output_dir=args.output_dir,
    )


if __name__ == "__main__":
    main()
