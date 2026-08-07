import os
from pathlib import Path
import time
import random
from typing import List, Iterable, Type, Tuple

import pandas as pd
pd.set_option('future.no_silent_downcasting', True)

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

os.environ["LD_LIB_CONFIG_PATH"] = str(SCRIPT_ROOT / "config")
import lseg.data as ld  # type: ignore

START = "2000-01-01T06:00:00"
END = "2025-10-31T19:30:00"

TRADING_FIELDS = ["TR.OPENPRICE", "TR.CLOSEPRICE"]
MARKET_CAP_FIELDS = ["TR.CompanyMarketCap"]

SECTOR_FIELDS = [
    "TR.TRBCEconomicSectorAll",
    "TR.TRBCBusinessSectorAll",
    "TR.TRBCIndustryGroupAll",
    "TR.TRBCIndustryAll",
    "TR.TRBCActivityAll",
]

RETURNS_DIR = RAW_LSEG_DIR / "returns"
SECTOR_OUTPUT = PROCESSED_MARKET_DIR / "firm_sector.csv"
UNIVERSE_FILE = PROCESSED_MARKET_DIR / "public_firms.csv"
PROCESSED_FILE = PROCESSED_MARKET_DIR / "processed.txt"

# ---- Retry configuration ----
MAX_RETRIES = 5
BASE_DELAY = 1.0   # seconds
BACKOFF = 2.0      # exponential multiplier
JITTER = 0.4       # +/- fraction of delay for jitter
SYMBOL_COOLDOWN = 0.5  # optional sleep between symbols

# If lseg raises named exceptions, add them here for targeted retries.
# Fallback to broad network-ish errors:
RETRY_EXC: Tuple[Type[Exception], ...] = (
    ConnectionError,
    TimeoutError,
    OSError,  # sometimes wraps socket timeouts
    RuntimeError,  # many SDKs wrap transport issues here
)

def _sleep_with_jitter(delay: float) -> None:
    low = delay * (1 - JITTER)
    high = delay * (1 + JITTER)
    time.sleep(random.uniform(low, high))

def retry_call(fn, *args, **kwargs):
    """
    Run fn(*args, **kwargs) with exponential backoff + jitter.
    On final failure, re-raise.
    """
    delay = BASE_DELAY
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            return fn(*args, **kwargs)
        except RETRY_EXC as e:
            if attempt == MAX_RETRIES:
                print(f"[retry] FAILED after {attempt} attempts: {e}")
                raise
            print(f"[retry] {fn.__name__} attempt {attempt} failed: {e} — retrying in ~{delay:.2f}s")
            _sleep_with_jitter(delay)
            delay *= BACKOFF

def ensure_dataframe(data) -> pd.DataFrame:
    if isinstance(data, pd.DataFrame):
        return data
    return pd.DataFrame(data)

def load_universe(path: Path) -> pd.Series:
    # Keep your existing CSV contract
    if path.exists():
        return pd.read_csv(path)["Identifier"]
    return pd.Series(dtype="object")

def read_processed(path: Path) -> List[str]:
    if not path.exists():
        return []
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]

def write_processed(path: Path, symbol: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as f:
        f.write(symbol + "\n")

# ---- API wrappers routed through retry_call ----
def fetch_trading_history(symbol: str) -> pd.DataFrame:
    return ensure_dataframe(
        retry_call(
            ld.get_history,
            universe=symbol,
            fields=TRADING_FIELDS,
            interval="daily",
            start=START,
            end=END,
        )
    )

def fetch_sector_snapshot(symbol: str) -> pd.DataFrame:
    return ensure_dataframe(
        retry_call(
            ld.get_data,
            universe=symbol,
            fields=SECTOR_FIELDS,
        )
    )

def fetch_market_cap_history(symbol: str) -> pd.DataFrame:
    return ensure_dataframe(
        retry_call(
            ld.get_history,
            universe=symbol,
            fields=MARKET_CAP_FIELDS,
            interval="daily",
            start=START,
            end=END,
        )
    )

def calculate_returns(trading_df: pd.DataFrame) -> pd.DataFrame:
    if trading_df.empty:
        return trading_df.copy()

    ordered = trading_df.sort_index().copy()
    result = (
        ordered[["Open Price", "Close Price"]]
        .rename(columns={"Open Price": "open_price", "Close Price": "close_price"})
    )
    result["intra_day_return"] = (result["close_price"] - result["open_price"]) / result["open_price"]
    result["overnight_return"] = (result["open_price"] - result["close_price"].shift(1)) / result["close_price"].shift(1)
    result = result.dropna(subset=["overnight_return"])
    return result

def save_returns(symbol: str, returns_df: pd.DataFrame) -> None:
    if returns_df.empty:
        return
    RETURNS_DIR.mkdir(parents=True, exist_ok=True)
    sanitized = symbol.split(".")[0]
    output_path = RETURNS_DIR / f"{sanitized}_returns.csv"
    returns_df.to_csv(output_path, index=True)

def append_sector_data(symbol: str, sector_df: pd.DataFrame) -> None:
    if sector_df is None or sector_df.empty:
        return
    SECTOR_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    payload = sector_df.reset_index(drop=True).copy()
    payload.insert(0, "symbol", symbol)
    write_header = not SECTOR_OUTPUT.exists()
    mode = "w" if write_header else "a"
    payload.to_csv(SECTOR_OUTPUT, mode=mode, header=write_header, index=False)

def process_symbol(symbol: str) -> bool:
    """
    Returns True on success. Any exception bubbles out (caught by caller),
    so 'processed' is only written on True.
    """
    # trading + returns
    trading_df = fetch_trading_history(symbol).dropna()
    returns_df = calculate_returns(trading_df)

    # market cap merge (best-effort)
    market_cap_df = fetch_market_cap_history(symbol)
    if not market_cap_df.empty:
        market_cap_df = market_cap_df.sort_index()
        returns_df = returns_df.merge(
            market_cap_df[["Company Market Cap"]].rename(columns={"Company Market Cap": "market_cap"}),
            left_index=True,
            right_index=True,
            how="left",
        )

    save_returns(symbol, returns_df)

    # sector snapshot
    sector_df = fetch_sector_snapshot(symbol)
    append_sector_data(symbol, sector_df)

    return True

def _refresh_session() -> None:
    """Optional: tear down and reopen the session if a batch starts failing."""
    try:
        ld.close_session()
    except Exception:
        pass
    time.sleep(0.5)
    ld.open_session()

def main(ticker=None) -> None:
    start = time.time()
    ld.open_session()
    print(f"session loaded successful in {time.time() - start:.2f} seconds")

    try:
        if ticker:
            print(f"processing single ticker: {ticker}")
            # Try a few times at the outer level in case the *whole* symbol fails repeatedly
            for outer_try in range(1, 3):
                try:
                    ok = process_symbol(ticker)
                    if ok:
                        print(f"done: {ticker}")
                        break
                except Exception as e:
                    print(f"[outer] {ticker} failed on try {outer_try}: {e}")
                    _refresh_session()
            return

        universe = load_universe(UNIVERSE_FILE)
        processed_set = set(read_processed(PROCESSED_FILE))

        for idx, symbol in enumerate(universe, 1):
            if symbol in processed_set:
                continue

            print(f"[{idx}/{len(universe)}] {symbol} …")
            try:
                ok = process_symbol(symbol)
            except Exception as e:
                # If a symbol repeatedly fails inside inner retries, refresh once and try again
                print(f"[symbol] {symbol} failed once: {e} — refreshing session and retrying once")
                _refresh_session()
                try:
                    ok = process_symbol(symbol)
                except Exception as e2:
                    print(f"[symbol] {symbol} final failure: {e2} — skipping (not marking processed)")
                    # do NOT write to processed; move to next symbol
                    # Optional: write to a failures file for later inspection
                    continue

            if ok:
                write_processed(PROCESSED_FILE, symbol)
                processed_set.add(symbol)

            if SYMBOL_COOLDOWN:
                time.sleep(SYMBOL_COOLDOWN)

    finally:
        try:
            ld.close_session()
        except AttributeError:
            pass


if __name__ == "__main__":
    main()
