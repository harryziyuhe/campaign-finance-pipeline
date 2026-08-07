from math import isfinite
import os
import glob
from pathlib import Path
from dataclasses import dataclass
from tqdm import tqdm

import numpy as np
import pandas as pd

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
    data_dir = PROCESSED_MARKET_DIR
    returns_dir = RAW_LSEG_DIR / "returns"
    firm_sector_file = "firm_sector.csv"
    spy_file = "ASPY_returns.csv"
    firm_glob = "*_returns.csv"

    event_leg = "overnight_return"

    estimation_days = 120
    estimation_buffer = 5

    elections = [
        # info-arrival day : label used to average means
        "2000-12-13",  # Bush v. Gore decision → reaction 12/13
        "2002-11-06",
        "2004-11-03",
        "2006-11-08",
        "2008-11-05",
        "2010-11-03",
        "2012-11-07",
        "2014-11-05",
        "2016-11-09",
        "2018-11-07",
        "2020-11-04",  # label as GOP-tilted reaction (gridlock), per your note
        "2022-11-09",
        "2024-11-06",  # markets surged after Trump victory on Nov 6 open
    ]

CFG = Config()

def read_spy(cfg: Config):
    spy = pd.read_csv(cfg.returns_dir / cfg.spy_file)
    if "Date" not in spy.columns:
        raise ValueError(f"{cfg.spy_file} must contain a 'Date' column")
    spy["Date"] = pd.to_datetime(spy["Date"])
    spy = spy.sort_values("Date").set_index("Date")
    return spy

def read_firm_sector(cfg: Config):
    df = pd.read_csv(cfg.data_dir / cfg.firm_sector_file)
    df = df[["symbol", "TRBC Business Sector All", "TRBC Industry Group All", "TRBC Industry All"]].drop_duplicates()
    df = df.rename(columns = {
        "TRBC Business Sector All": "sector",
        "TRBC Industry Group All": "industry_group",
        "TRBC Industry All": "industry"})
    df["ticker"] = df["symbol"].astype(str).str.upper().str.split(".", n=1).str[0]
    return df

def load_firm_returns(file_path: Path):
    name = file_path.name
    df = pd.read_csv(file_path)
    if "Date" not in df.columns:
        raise ValueError(f"{name} must contain a 'Date' column")
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values("Date").set_index("Date")
    return df

def _pick_estimation_index(market, event_day, 
                           estimation_days, estimation_buffer):
    market = market.sort_index()
    if event_day in market.index:
        end_idx_pos = market.index.get_loc(event_day)
        if isinstance(end_idx_pos, slice):
            end_idx_pos = end_idx_pos.start
    else:
        end_idx_pos = market.index.searchsorted(event_day)
    
    end_pos = max(0, end_idx_pos - estimation_buffer)
    est_idx = market.index[:end_pos][-estimation_days:]
    return est_idx

def market_model_ar_on_event(firm,
                             market,
                             event_day,
                             estimation_days,
                             estimation_buffer):
    firm = firm.sort_index()
    market = market.sort_index()

    est_idx = _pick_estimation_index(market, event_day, estimation_days, estimation_buffer)
    if len(est_idx) < max(30, int(0.5 * estimation_days)):
        return np.nan, np.nan, np.nan
    
    y = firm.reindex(est_idx)
    x= market.reindex(est_idx)
    mask = y.notna() & x.notna()
    x = x[mask].values
    y = y[mask].values
    if len(x) < max(30, int(0.5 * estimation_days)):
        return np.nan, np.nan, np.nan
    
    X = np.column_stack([np.ones_like(x), x])
    alpha, beta = np.linalg.lstsq(X, y, rcond=None)[0]
    
    if event_day in market.index:
        t = event_day
    else:
        pos = market.index.searchsorted(event_day)
        if pos >= len(market.index):
            return alpha, beta, np.nan
        t = market.index[pos]

    r_i = firm.get(t, np.nan)
    r_m = market.get(t, np.nan)
    if not (np.isfinite(r_i) and np.isfinite(r_m)):
        return alpha, beta, np.nan
    
    ar = r_i - (beta * r_m)
    return alpha, beta, float(ar)

def firm_event_profile(firm_df,
                       spy_df,
                       elections,
                       event_leg,
                       estimation_days,
                       estimation_buffer):
    ars = []
    dem_ars, gop_ars = [], []
    out = {}

    for day_str in elections:
        eday = pd.to_datetime(day_str)

        _, _, ar = market_model_ar_on_event(
            firm = firm_df[event_leg],
            market = spy_df[event_leg],
            event_day = eday,
            estimation_days = estimation_days,
            estimation_buffer = estimation_buffer
        )
        out[f"AR_{day_str}"] = ar
        if np.isfinite(ar):
            ars.append(ar)
    return out

def main(cfg: Config = CFG):
    sector_map = read_firm_sector(cfg)
    spy_df = read_spy(cfg)

    firm_files = [Path(p) for p in glob.glob(str(cfg.returns_dir / cfg.firm_glob))]
    firm_files = [p for p in firm_files if p.name != cfg.spy_file]
    
    rows = []
    failures = []

    for fp in tqdm(sorted(firm_files)):
        ticker = fp.name.replace("_returns.csv", "")
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
                firm_df = fdf,
                spy_df = spy_df,
                elections = cfg.elections,
                event_leg = cfg.event_leg,
                estimation_days = cfg.estimation_days,
                estimation_buffer = cfg.estimation_buffer
            )
            rows.append({"ticker": ticker, "sector": sector, "industry_group": industry_group, "industry": industry, **stats})
        except Exception as e:
            print(e)
            failures.append((fp.name, str(e)))

    firm_tilts = pd.DataFrame(rows)
    firm_out = cfg.data_dir / "firm_event_tilts.csv"
    firm_tilts.to_csv(firm_out, index = False)

    if failures:
        with open(cfg.data_dir / "read_failures.log", "w") as f:
            for name, msg in failures:
                f.write(f"{name}\t{msg}\n")

    print("=== Saved Outputs ===")
    print(f"- Per-firm event tilts: {firm_out}")
    if failures:
        print(f"- Read failures logged {cfg.data_dir / 'read_failures.log'}")
    print("\n=== Meta & Parameters ===")
    print(f"Event leg: {cfg.event_leg}, Estimation days: {cfg.estimation_days} Buffer: {cfg.estimation_buffer}")

if __name__ == "__main__":
    main()
