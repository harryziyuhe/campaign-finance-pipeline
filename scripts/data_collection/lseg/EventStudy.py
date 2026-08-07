from __future__ import annotations

import glob
from dataclasses import dataclass
from math import isfinite
import os
from pathlib import Path
from typing import Optional, Sequence, Dict, Any, List

import numpy as np
import pandas as pd
from tqdm import tqdm


# ==============================
# Dataclasses: ReturnLeg & EventSpec
# ==============================

@dataclass(frozen=True)
class ReturnLeg:
    """
    Defines how to compute a single-period return around an event.

    Example:
      - Overnight:  start_lag=-1, start_price_col="close_price",
                    end_lag=0,   end_price_col="open_price"
      - Intraday:   start_lag=0, start_price_col="open_price",
                    end_lag=0,   end_price_col="close_price"
    """
    label: str
    start_lag: int
    start_price_col: str
    end_lag: int
    end_price_col: str


@dataclass(frozen=True)
class EventSpec:
    """
    A single event (e.g., a presidential election) with its own date and leg.

    - date: the info-arrival calendar date
    - name: a short label used in column names
    - leg: if None, fall back to cfg.default_leg
    """
    date: str
    name: str
    leg: Optional[ReturnLeg] = None


# ==============================
# Global config
# ==============================

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
RAW_LSEG_DIR = DATA_ROOT / "data" / "raw" / "lseg"
PROCESSED_MARKET_DIR = DATA_ROOT / "data" / "processed" / "market"

@dataclass(frozen=True)
class EventStudyConfig:
    data_dir: Path = PROCESSED_MARKET_DIR
    returns_dir: Path = RAW_LSEG_DIR / "returns"
    firm_sector_file: str = "firm_sector.csv"
    spy_file: str = "ASPY_returns.csv"
    firm_glob: str = "*_returns.csv"

    # market model settings
    estimation_days: int = 120
    estimation_buffer: int = 5
    min_estimation_obs: int = 30  # minimum obs after cleaning

    # if this column exists in firm/market CSV, we use it.
    # if None or missing, we derive returns from 'close_price'.
    estimation_return_col: Optional[str] = "intra_day_return"

    # default leg (used if an EventSpec doesn't specify one)
    default_leg: ReturnLeg = ReturnLeg(
        label="overnight",
        start_lag=-1,            # previous trading day
        start_price_col="close_price",
        end_lag=0,               # event trading day
        end_price_col="open_price",
    )

    oneday_leg: ReturnLeg = ReturnLeg(
        label="OTO",
        start_lag=0,
        start_price_col="open_price",
        end_lag=1,
        end_price_col="open_price",
    )

    # elections: for now, all use the *same overnight leg*
    elections: Sequence[EventSpec] = (
        EventSpec(date="2000-12-12", name="2000_BushGore", leg = oneday_leg),
        EventSpec(date="2001-05-24", name="2001_Jeffords", leg = oneday_leg),  # Sen Jeffords switches VT Dem
        EventSpec(date="2002-11-06", name="2002_midterm"),
        EventSpec(date="2004-11-03", name="2004_BushKerry"),
        EventSpec(date="2006-11-08", name="2006_midterm"),
        EventSpec(date="2008-11-05", name="2008_Obama"),
        EventSpec(date="2010-11-03", name="2010_midterm"),
        EventSpec(date="2012-11-07", name="2012_Obama2"),
        EventSpec(date="2014-11-05", name="2014_midterm"),
        EventSpec(date="2016-11-09", name="2016_Trump"),
        EventSpec(date="2018-11-07", name="2018_midterm"),
        EventSpec(date="2020-11-04", name="2020_gridlock"),
        EventSpec(date="2022-11-09", name="2022_midterm"),
        EventSpec(date="2024-11-06", name="2024_Trump2"),
    )


CFG = EventStudyConfig()


# ==============================
# I/O helpers
# ==============================

def read_spy(cfg: EventStudyConfig) -> pd.DataFrame:
    spy = pd.read_csv(cfg.returns_dir / cfg.spy_file)
    if "Date" not in spy.columns:
        raise ValueError(f"{cfg.spy_file} must contain a 'Date' column")
    spy["Date"] = pd.to_datetime(spy["Date"])
    spy = spy.sort_values("Date").set_index("Date")
    return spy


def read_firm_sector(cfg: EventStudyConfig) -> pd.DataFrame:
    df = pd.read_csv(cfg.data_dir / cfg.firm_sector_file)
    df = df[
        [
            "symbol",
            "TRBC Business Sector All",
            "TRBC Industry Group All",
            "TRBC Industry All",
        ]
    ].drop_duplicates()
    df = df.rename(
        columns={
            "TRBC Business Sector All": "sector",
            "TRBC Industry Group All": "industry_group",
            "TRBC Industry All": "industry",
        }
    )
    df["ticker"] = (
        df["symbol"]
        .astype(str)
        .str.upper()
        .str.split(".", n=1)
        .str[0]
    )
    return df


def load_firm_returns(file_path: Path) -> pd.DataFrame:
    name = file_path.name
    df = pd.read_csv(file_path)
    if "Date" not in df.columns:
        raise ValueError(f"{name} must contain a 'Date' column")
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values("Date").set_index("Date")
    return df


# ==============================
# Core math utilities
# ==============================

def _align_to_trading_day(index: pd.DatetimeIndex, target_day: pd.Timestamp) -> Optional[pd.Timestamp]:
    """
    Align a calendar date to the nearest trading day ON OR AFTER target_day.

    If target_day > last index date → return None.
    """
    if target_day in index:
        return target_day
    pos = index.searchsorted(target_day)
    if pos >= len(index):
        return None
    return index[pos]


def _get_position(index: pd.DatetimeIndex, day: pd.Timestamp) -> Optional[int]:
    """
    Get integer position of a day in index; handle slices.
    """
    try:
        loc = index.get_loc(day)
        if isinstance(loc, slice):
            return loc.start
        return int(loc)
    except KeyError:
        return None


def _shift_pos(index: pd.DatetimeIndex, base_day: pd.Timestamp, lag: int) -> Optional[int]:
    """
    Given a base trading day, move lag positions forward/backward
    in the index. Returns None if out of bounds.
    """
    base_pos = _get_position(index, base_day)
    if base_pos is None:
        return None
    pos = base_pos + lag
    if pos < 0 or pos >= len(index):
        return None
    return pos


def _pick_estimation_index(
    market_ret: pd.Series,
    event_day: pd.Timestamp,
    estimation_days: int,
    estimation_buffer: int,
) -> pd.DatetimeIndex:
    """
    Choose estimation window indices for the market-model regression.
    """
    market_ret = market_ret.sort_index()
    idx = market_ret.index

    if event_day in idx:
        loc = idx.get_loc(event_day)
        if isinstance(loc, slice):
            loc = loc.start
        end_idx_pos = loc
    else:
        end_idx_pos = idx.searchsorted(event_day)

    end_pos = max(0, end_idx_pos - estimation_buffer)
    est_idx = idx[:end_pos][-estimation_days:]
    return est_idx


def _build_return_series(
    df: pd.DataFrame,
    estimation_return_col: Optional[str] = None,
    default_price_col: str = "close_price",
) -> pd.Series:
    """
    Get the return series used in the estimation window.

    Priority:
      1. If estimation_return_col is not None and exists in df → use it.
      2. Else compute pct_change of default_price_col.
    """
    if estimation_return_col is not None and estimation_return_col in df.columns:
        r = df[estimation_return_col].astype(float)
    else:
        if default_price_col not in df.columns:
            raise ValueError(
                f"Neither estimation_return_col nor {default_price_col} "
                f"found in DataFrame columns {list(df.columns)}"
            )
        prices = df[default_price_col].astype(float)
        r = prices.pct_change()
    return r.sort_index()


def _compute_leg_return(
    df: pd.DataFrame,
    event_day: pd.Timestamp,
    leg: ReturnLeg,
) -> float:
    """
    Compute a single-period return for a given leg:
      (price(end_lag, end_price_col) / price(start_lag, start_price_col)) - 1
    """
    idx = df.index
    base_day = _align_to_trading_day(idx, event_day)
    if base_day is None:
        return np.nan

    start_pos = _shift_pos(idx, base_day, leg.start_lag)
    end_pos = _shift_pos(idx, base_day, leg.end_lag)
    if start_pos is None or end_pos is None:
        return np.nan

    start_price = df.iloc[start_pos].get(leg.start_price_col, np.nan)
    end_price = df.iloc[end_pos].get(leg.end_price_col, np.nan)

    if not (np.isfinite(start_price) and np.isfinite(end_price)):
        return np.nan

    if start_price == 0:
        return np.nan

    return float(end_price / start_price - 1.0)


def market_model_params_on_event(
    firm_ret: pd.Series,
    market_ret: pd.Series,
    event_day: pd.Timestamp,
    estimation_days: int,
    estimation_buffer: int,
    min_estimation_obs: int,
) -> tuple[float, float]:
    """
    Estimate alpha, beta using OLS on the estimation window.

    firm_ret, market_ret should be aligned on Date index.
    """
    firm_ret = firm_ret.sort_index()
    market_ret = market_ret.sort_index()

    est_idx = _pick_estimation_index(
        market_ret=market_ret,
        event_day=event_day,
        estimation_days=estimation_days,
        estimation_buffer=estimation_buffer,
    )
    if len(est_idx) < max(min_estimation_obs, int(0.5 * estimation_days)):
        return np.nan, np.nan

    y = firm_ret.reindex(est_idx)
    x = market_ret.reindex(est_idx)

    mask = y.notna() & x.notna()
    x = x[mask].values
    y = y[mask].values

    if len(x) < max(min_estimation_obs, int(0.5 * estimation_days)):
        return np.nan, np.nan

    X = np.column_stack([np.ones_like(x), x])
    alpha, beta = np.linalg.lstsq(X, y, rcond=None)[0]
    return float(alpha), float(beta)


def abnormal_return_for_event(
    firm_df: pd.DataFrame,
    spy_df: pd.DataFrame,
    event_day: pd.Timestamp,
    leg: ReturnLeg,
    cfg: EventStudyConfig,
) -> dict[str, float]:
    """
    Compute the abnormal return for a single event day and leg.

    Returns a dict with keys:
      - "alpha", "beta"
      - "r_firm_leg", "r_mkt_leg"
      - "ar_leg"
    """
    # estimation returns
    firm_ret = _build_return_series(
        firm_df,
        estimation_return_col=cfg.estimation_return_col,
        default_price_col="close_price",
    )
    mkt_ret = _build_return_series(
        spy_df,
        estimation_return_col=cfg.estimation_return_col,
        default_price_col="close_price",
    )

    # estimate alpha, beta
    alpha, beta = market_model_params_on_event(
        firm_ret=firm_ret,
        market_ret=mkt_ret,
        event_day=event_day,
        estimation_days=cfg.estimation_days,
        estimation_buffer=cfg.estimation_buffer,
        min_estimation_obs=cfg.min_estimation_obs,
    )

    # leg returns (using chosen open/close & start/end lags)
    r_i = _compute_leg_return(firm_df, event_day, leg)
    r_m = _compute_leg_return(spy_df, event_day, leg)

    if not (np.isfinite(r_i) and np.isfinite(r_m) and np.isfinite(alpha) and np.isfinite(beta)):
        return {
            "alpha": alpha,
            "beta": beta,
            "r_firm_leg": r_i,
            "r_mkt_leg": r_m,
            "ar_leg": np.nan,
        }

    # standard market-model AR: r_i - (alpha + beta * r_m)
    ar = r_i - (alpha + beta * r_m)

    return {
        "alpha": alpha,
        "beta": beta,
        "r_firm_leg": r_i,
        "r_mkt_leg": r_m,
        "ar_leg": float(ar),
    }


# ==============================
# Per-firm event profiles
# ==============================

def firm_event_profile(
    firm_df: pd.DataFrame,
    spy_df: pd.DataFrame,
    elections: Sequence[EventSpec],
    cfg: EventStudyConfig,
) -> Dict[str, Any]:
    """
    For a single firm, compute ARs for all events, each with its own leg
    (for now, all use the default overnight leg).
    """
    out: Dict[str, Any] = {}
    all_ars: List[float] = []

    for ev in elections:
        eday = pd.to_datetime(ev.date)
        leg = ev.leg or cfg.default_leg  # here all are None, so use default overnight

        res = abnormal_return_for_event(
            firm_df=firm_df,
            spy_df=spy_df,
            event_day=eday,
            leg=leg,
            cfg=cfg,
        )

        # key combines event name + leg label
        key = f"{ev.name}_{leg.label}"

        out[f"alpha_{key}"] = res["alpha"]
        out[f"beta_{key}"] = res["beta"]
        out[f"r_firm_{key}"] = res["r_firm_leg"]
        out[f"r_mkt_{key}"] = res["r_mkt_leg"]
        out[f"AR_{key}"] = res["ar_leg"]

        if np.isfinite(res["ar_leg"]):
            all_ars.append(res["ar_leg"])

    # optional “overall mean AR across all events”
    out["mean_AR_all_events"] = float(np.mean(all_ars)) if all_ars else np.nan
    return out


# ==============================
# Main driver
# ==============================

def main(cfg: EventStudyConfig = CFG) -> None:
    sector_map = read_firm_sector(cfg)
    spy_df = read_spy(cfg)

    firm_files = [Path(p) for p in glob.glob(str(cfg.returns_dir / cfg.firm_glob))]
    firm_files = [p for p in firm_files if p.name != cfg.spy_file]

    rows = []
    failures = []

    for fp in tqdm(sorted(firm_files)):
        ticker = fp.name.replace("_returns.csv", "")

        # skip weird PK duplicates if present
        if f"{ticker}.PK" in list(sector_map["symbol"]):
            continue

        try:
            fdf = load_firm_returns(fp)

            sector = sector_map.loc[sector_map["ticker"] == ticker, "sector"]
            industry_group = sector_map.loc[sector_map["ticker"] == ticker, "industry_group"]
            industry = sector_map.loc[sector_map["ticker"] == ticker, "industry"]
            sector = sector.iloc[0] if len(sector) else None
            industry_group = industry_group.iloc[0] if len(industry_group) else None
            industry = industry.iloc[0] if len(industry) else None

            stats = firm_event_profile(
                firm_df=fdf,
                spy_df=spy_df,
                elections=cfg.elections,
                cfg=cfg,
            )

            row = {
                "ticker": ticker,
                "sector": sector,
                "industry_group": industry_group,
                "industry": industry,
                **stats,
            }
            rows.append(row)

        except Exception as e:
            print(f"[ERROR] {fp.name}: {e}")
            failures.append((fp.name, str(e)))

    firm_tilts = pd.DataFrame(rows)
    firm_out = cfg.data_dir / "firm_event_full.csv"
    firm_tilts.to_csv(firm_out, index=False)

    if failures:
        with open(cfg.data_dir / "read_failures.log", "w") as f:
            for name, msg in failures:
                f.write(f"{name}\t{msg}\n")

    print("=== Saved Outputs ===")
    print(f"- Per-firm event tilts: {firm_out}")
    if failures:
        print(f"- Read failures logged {cfg.data_dir / 'read_failures.log'}")
    print("\n=== Meta & Parameters ===")
    print(f"Default event leg (all events): {cfg.default_leg}")
    print(
        f"Estimation days: {cfg.estimation_days}, "
        f"Buffer: {cfg.estimation_buffer}, "
        f"Min obs: {cfg.min_estimation_obs}, "
        f"Estimation return col: {cfg.estimation_return_col}"
    )


if __name__ == "__main__":
    main()
