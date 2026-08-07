# ExposureStudy.py
# Abnormal returns around elections & midterms with robust market proxy
# - Market can be SPY or Equal-Weighted (leave-one-out for each firm)
# - Event leg defaults to "overnight_return"

from dataclasses import dataclass, field
import os
from pathlib import Path
from typing import Dict, List, Tuple
from math import isfinite
import glob

import numpy as np
import pandas as pd
from tqdm import tqdm


# ====================== CONFIG ======================

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
class Config:
    data_dir: Path = PROCESSED_MARKET_DIR
    returns_dir: Path = RAW_LSEG_DIR / "returns"
    firm_sector_file: str = "firm_sector.csv"
    spy_file: str = "ASPY_returns.csv"
    firm_glob: str = "*_returns.csv"

    # which return leg to analyze
    event_leg: str = "overnight_return"  # or "intra_day_return"

    # market mode: "SPY" uses SPY file; "EW" builds equal-weighted market from all firms (leave-one-out)
    market_mode: str = "EW"              # "EW" or "SPY"

    # cleaning
    winsor_abs_clip: float = 0.5   # null leg returns with |r| > 50% (overnight) as data errors
    spy_abs_clip: float = 0.2      # SPY should be very tame
    unit_percent_max: float = 50.0 # if p99 > 50 → likely bps; >2 → likely %
    unit_percent_thresh: float = 2.0

    # event dates (information-arrival trading days; midterms included)
    elections: Tuple[str, ...] = (
        # 2000–2024 presidential + midterms (info-arrival = next trading day)
        "2000-12-13",  # Bush v Gore decision (reaction day)
        "2002-11-06",  # midterm
        "2004-11-03",
        "2006-11-08",  # midterm
        "2008-11-05",
        "2010-11-03",  # midterm
        "2012-11-07",
        "2014-11-05",  # midterm
        "2016-11-09",
        "2018-11-07",  # midterm
        "2020-11-04",  # gridlock-tilted market reaction
        "2022-11-09",  # midterm
        "2024-11-06",
    )

CFG = Config()


# ====================== IO HELPERS ======================

def read_spy(cfg: Config) -> pd.DataFrame:
    spy = pd.read_csv(cfg.returns_dir / cfg.spy_file)
    if "Date" not in spy.columns:
        raise ValueError(f"{cfg.spy_file} must contain a 'Date' column")
    spy["Date"] = pd.to_datetime(spy["Date"])
    spy = spy.sort_values("Date").set_index("Date")
    # keep only the legs we could need
    keep = [c for c in spy.columns if c in ("intra_day_return", "overnight_return")]
    return spy[keep].astype(float)


def read_firm_sector(cfg: Config) -> pd.DataFrame:
    df = pd.read_csv(cfg.data_dir / cfg.firm_sector_file)
    df = df[["symbol", "TRBC Business Sector All", "TRBC Industry Group All", "TRBC Industry All"]].drop_duplicates()
    df = df.rename(columns={
        "TRBC Business Sector All": "sector",
        "TRBC Industry Group All": "industry_group",
        "TRBC Industry All": "industry"
    })
    # normalize symbol/ticker
    df["ticker"] = (
        df["symbol"].astype(str).str.upper().str.split(".", n=1).str[0]
    )
    return df


def load_firm_returns(file_path: Path) -> pd.DataFrame:
    df = pd.read_csv(file_path)
    if "Date" not in df.columns:
        raise ValueError(f"{file_path.name} must contain a 'Date' column")
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values("Date").set_index("Date")
    # keep legs if present
    for col in ("intra_day_return", "overnight_return"):
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


# ====================== CLEANING ======================

def normalize_units(s: pd.Series, percent_thresh=2.0, percent_max=50.0) -> pd.Series:
    """Make sure returns are decimals, not % or bps."""
    s = pd.to_numeric(s, errors="coerce")
    q99 = s.abs().quantile(0.99)
    if q99 > percent_max:
        # likely bps
        return s / 10000.0
    if q99 > percent_thresh:
        # likely %
        return s / 100.0
    return s


def null_outliers(s: pd.Series, max_abs=0.5) -> pd.Series:
    s = pd.to_numeric(s, errors="coerce")
    return s.mask(s.abs() > max_abs)


# ====================== MARKET CONSTRUCTION ======================

def build_equal_weight_market(cfg: Config, leg: str, sector_map: pd.DataFrame) -> Tuple[pd.Series, Dict[str, pd.Series]]:
    """
    Two-pass: aggregate per-date sums and counts across firms to form EW market.
    Return (ew_market_series, cleaned_firm_series_dict).
    """
    sum_series = pd.Series(dtype=float)
    cnt_series = pd.Series(dtype=float)
    firm_series: Dict[str, pd.Series] = {}

    firm_files = [Path(p) for p in glob.glob(str(cfg.returns_dir / cfg.firm_glob))]
    # skip SPY file if it's in the same folder pattern
    firm_files = [p for p in firm_files if p.name != Path(cfg.spy_file).name]

    for fp in tqdm(firm_files, desc="Pass 1: building EW market"):
        ticker = fp.name.replace("_returns.csv", "")
        if f"{ticker}.PK" in list(sector_map["symbol"]):
            continue
        # optional: filter out OTC suffix ".PK" via sector_map symbols if needed
        try:
            df = load_firm_returns(fp)
            if leg not in df.columns:
                continue
            r = df[leg]
            # normalize & clip
            r = normalize_units(r, CFG.unit_percent_thresh, CFG.unit_percent_max)
            r = null_outliers(r, CFG.winsor_abs_clip)
            # store cleaned series
            firm_series[ticker] = r

            # aggregate sum & count on overlapping dates
            # align indexes on the fly
            if sum_series.empty:
                sum_series = r.copy()
                cnt_series = r.notna().astype(float)
            else:
                # add aligned (reindex union)
                sum_series = sum_series.add(r, fill_value=0.0)
                cnt_series = cnt_series.add(r.notna().astype(float), fill_value=0.0)
        except Exception as e:
            # keep going; we'll simply exclude this ticker
            print(f"[WARN] {fp.name}: {e}")

    ew = sum_series / cnt_series.replace(0.0, np.nan)
    ew.name = f"EW_{leg}"
    return ew, firm_series


def get_market_series(cfg: Config, leg: str, sector_map: pd.DataFrame) -> Tuple[pd.Series, Dict[str, pd.Series]]:
    """
    Returns (market_series, firm_series_dict).
    If market_mode == 'SPY' -> use SPY leg.
    If 'EW' -> build equal-weighted market and return leave-one-out later when computing AR.
    """
    if cfg.market_mode.upper() == "SPY":
        spy = read_spy(cfg)
        mkt = spy[leg].copy() if leg in spy.columns else pd.Series(dtype=float)
        mkt = normalize_units(mkt, CFG.unit_percent_thresh, CFG.unit_percent_max)
        mkt = null_outliers(mkt, CFG.spy_abs_clip)
        mkt.name = f"SPY_{leg}"
        return mkt, {}  # firm_series not needed
    else:
        return build_equal_weight_market(cfg, leg, sector_map)


# ====================== EVENT & AR LOGIC ======================

def align_event_day_to_market(event_day: pd.Timestamp, market_index: pd.DatetimeIndex) -> pd.Timestamp:
    """Return the first trading day on/after event_day based on market index."""
    if event_day in market_index:
        return event_day
    pos = market_index.searchsorted(event_day)
    if pos >= len(market_index):
        return pd.NaT
    return market_index[pos]


def compute_ar_market_adjusted(
    r_i_at_t: float,
    r_m_at_t: float
) -> float:
    """AR = r_i - r_m (alpha=0, beta=1)."""
    if not (isfinite(r_i_at_t) and isfinite(r_m_at_t)):
        return np.nan
    return float(r_i_at_t - r_m_at_t)


def per_firm_event_ars(
    ticker: str,
    s: pd.Series,
    market_series: pd.Series,
    elections: Tuple[str, ...],
) -> Dict[str, float]:
    out = {}
    # ensure firm series aligns to market calendar for lookups
    s_aligned = s.reindex(market_series.index)

    for day_str in elections:
        eday = pd.to_datetime(day_str)
        t = align_event_day_to_market(eday, market_series.index)
        if pd.isna(t):
            out[f"AR_{day_str}"] = np.nan
            continue
        r_i = s_aligned.get(t, np.nan)
        r_m = market_series.get(t, np.nan)
        out[f"AR_{day_str}"] = compute_ar_market_adjusted(r_i, r_m)
    return out


def per_firm_event_ars_leave_one_out(
    ticker: str,
    s: pd.Series,
    sum_series: pd.Series,
    cnt_series: pd.Series,
    elections: Tuple[str, ...],
) -> Dict[str, float]:
    """
    For EW market, use leave-one-out: r_m_ex_i(t) = (sum(t) - r_i(t)) / (cnt(t) - 1)
    """
    out = {}
    # Align firm s to the sum/count calendars
    s = s.copy()
    s = s.astype(float)
    # union index of sum_series and cnt_series (they should match already)
    idx = sum_series.index

    # leave-one-out market for firm
    num = sum_series.sub(s.reindex(idx), fill_value=np.nan)
    den = cnt_series.sub(s.reindex(idx).notna().astype(float), fill_value=np.nan)
    loo = num / den.replace(0.0, np.nan)

    for day_str in elections:
        eday = pd.to_datetime(day_str)
        t = align_event_day_to_market(eday, idx)
        if pd.isna(t):
            out[f"AR_{day_str}"] = np.nan
            continue
        r_i = s.reindex(idx).get(t, np.nan)
        r_m = loo.get(t, np.nan)
        out[f"AR_{day_str}"] = compute_ar_market_adjusted(r_i, r_m)
    return out


# ====================== MAIN ======================

def main(cfg: Config = CFG):
    # 1) sector map
    sector_map = read_firm_sector(cfg)

    # 2) market series (and firm series if EW)
    if cfg.market_mode.upper() == "SPY":
        market_series, firm_series_dict = get_market_series(cfg, cfg.event_leg, sector_map)
        sum_series = pd.Series(dtype=float)
        cnt_series = pd.Series(dtype=float)
    else:
        # For EW we also need sum & count to build leave-one-out for each firm
        # We can reconstruct them from the returned ew & firm series:
        ew, firm_series_dict = get_market_series(cfg, cfg.event_leg, sector_map)
        # rebuild sum & count from firm dict to ensure consistency
        sum_series = pd.Series(dtype=float)
        cnt_series = pd.Series(dtype=float)
        for r in firm_series_dict.values():
            if sum_series.empty:
                sum_series = r.copy()
                cnt_series = r.notna().astype(float)
            else:
                sum_series = sum_series.add(r, fill_value=0.0)
                cnt_series = cnt_series.add(r.notna().astype(float), fill_value=0.0)
        market_series = ew  # used only for date alignment in EW path

    # 3) iterate firms and compute ARs
    firm_files = [Path(p) for p in glob.glob(str(cfg.returns_dir / cfg.firm_glob))]
    firm_files = [p for p in firm_files if p.name != Path(cfg.spy_file).name]

    rows: List[Dict[str, float]] = []
    failures: List[Tuple[str, str]] = []

    # prepare symbol/ticker lookup
    sym_lookup = dict(zip(sector_map["ticker"], sector_map["sector"]))
    ig_lookup = dict(zip(sector_map["ticker"], sector_map["industry_group"]))
    ind_lookup = dict(zip(sector_map["ticker"], sector_map["industry"]))

    for fp in tqdm(sorted(firm_files), desc="Pass 2: computing ARs"):
        ticker = fp.name.replace("_returns.csv", "")
        if f"{ticker}.PK" in list(sector_map["symbol"]):
            continue

        try:
            df = load_firm_returns(fp)
            if cfg.event_leg not in df.columns:
                continue
            r = df[cfg.event_leg]
            # normalize + clip to ensure sane units/data
            r = normalize_units(r, CFG.unit_percent_thresh, CFG.unit_percent_max)
            r = null_outliers(r, CFG.winsor_abs_clip)

            sector = sym_lookup.get(ticker, None)
            ig = ig_lookup.get(ticker, None)
            ind = ind_lookup.get(ticker, None)

            if cfg.market_mode.upper() == "SPY":
                stats = per_firm_event_ars(
                    ticker=ticker,
                    s=r,
                    market_series=market_series,
                    elections=cfg.elections,
                )
            else:
                # leave-one-out EW
                stats = per_firm_event_ars_leave_one_out(
                    ticker=ticker,
                    s=r,
                    sum_series=sum_series,
                    cnt_series=cnt_series,
                    elections=cfg.elections,
                )

            rows.append({"ticker": ticker, "sector": sector, "industry_group": ig, "industry": ind, **stats})
        except Exception as e:
            failures.append((fp.name, str(e)))

    firm_tilts = pd.DataFrame(rows)
    out_firms = cfg.data_dir / "firm_event_ARs.csv"
    firm_tilts.to_csv(out_firms, index=False)

    # 4) sector summary for quick diagnostics
    #    avg AR by sector and by event (helps see whether EW fixes the "all negative" issue)
    id_cols = ["sector", "industry_group", "industry"]
    event_cols = [c for c in firm_tilts.columns if c.startswith("AR_")]
    sector_avg = (firm_tilts
                  .groupby(id_cols, dropna=False)[event_cols]
                  .mean()
                  .reset_index())
    out_sector = cfg.data_dir / "sector_event_ARs.csv"
    sector_avg.to_csv(out_sector, index=False)

    # 5) simple console summary
    print("=== Saved Outputs ===")
    print(f"- Per-firm ARs:    {out_firms}")
    print(f"- Sector averages: {out_sector}")
    if failures:
        logf = cfg.data_dir / "read_failures.log"
        with open(logf, "w") as f:
            for name, msg in failures:
                f.write(f"{name}\t{msg}\n")
        print(f"- Read failures logged: {logf}")

    # quick overall check: mean AR across all firms per event
    print("\n=== Overall mean AR across firms (diagnostic) ===")
    with pd.option_context("display.float_format", "{: .5f}".format):
        print(firm_tilts[event_cols].mean(numeric_only=True))


if __name__ == "__main__":
    main()
