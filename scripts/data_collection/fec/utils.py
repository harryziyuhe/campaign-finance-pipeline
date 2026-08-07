from collections.abc import Mapping
import pandas as pd
import polars as pl

US_states = {
    'AL': 'Alabama',
    'AK': 'Alaska',
    'AZ': 'Arizona',
    'AR': 'Arkansas',
    'CA': 'California',
    'CO': 'Colorado',
    'CT': 'Connecticut',
    'DE': 'Delaware',
    'FL': 'Florida',
    'GA': 'Georgia',
    'HI': 'Hawaii',
    'ID': 'Idaho',
    'IL': 'Illinois',
    'IN': 'Indiana',
    'IA': 'Iowa',
    'KS': 'Kansas',
    'KY': 'Kentucky',
    'LA': 'Louisiana',
    'ME': 'Maine',
    'MD': 'Maryland',
    'MA': 'Massachusetts',
    'MI': 'Michigan',
    'MN': 'Minnesota',
    'MS': 'Mississippi',
    'MO': 'Missouri',
    'MT': 'Montana',
    'NE': 'Nebraska',
    'NV': 'Nevada',
    'NH': 'New Hampshire',
    'NJ': 'New Jersey',
    'NM': 'New Mexico',
    'NY': 'New York',
    'NC': 'North Carolina',
    'ND': 'North Dakota',
    'OH': 'Ohio',
    'OK': 'Oklahoma',
    'OR': 'Oregon',
    'PA': 'Pennsylvania',
    'RI': 'Rhode Island',
    'SC': 'South Carolina',
    'SD': 'South Dakota',
    'TN': 'Tennessee',
    'TX': 'Texas',
    'UT': 'Utah',
    'VT': 'Vermont',
    'VA': 'Virginia',
    'WA': 'Washington',
    'WV': 'West Virginia',
    'WI': 'Wisconsin',
    'WY': 'Wyoming',
    'DC': 'District of Columbia'
}

ELECTION_DAYS: dict[int, tuple[int, int]] = {
    2004: (11, 2),
    2006: (11, 7),
    2008: (11, 4),
    2010: (11, 2),
    2012: (11, 6),
    2014: (11, 4),
    2016: (11, 8),
    2018: (11, 6),
    2020: (11, 3),
    2022: (11, 8),
    2024: (11, 5),
}

def calc_hedge(data, column1, column2):
    """
    Calculate Hedging Index
    Args:
        - data
        - column1
        - column2
    Return:
        Hedging score
    """
    a = data[column1]
    b = data[column2]
    return (1 - abs((a-b)/(a+b)))

def calc_balance(data, column1, column2):
    """
    Calculate Balance Index
    Args:
        - data
        - column1
        - column2
    Return:
        Balance score
    """
    a = data[column1]
    b = data[column2]
    return ((a-b)/(a+b))

def count_unique(x):
    """
    Count unique values
    """
    return len(set(x))

def exclude_territory(df, st_column):
    return df[df[st_column].isin(US_states.keys())]

def parse_last_name(x):
    suffixes = {"JR", "SR", "II", "III", "IV", "V"}

    before_comma = x.split(",")[0].strip()
    parts = before_comma.split()
    while parts and parts[-1].upper().strip(".") in suffixes:
        parts.pop()
    if not parts:
        return ""
    last = parts[-1].split("-")[-1]
    last_clean = ''.join(c for c in last if c.isalpha())

    return last_clean

def house_cycle_series(
    df: pd.DataFrame,
    *,
    year_col: str,
    month_col: str,
    day_col: str,
    chamber_col: str,
    election_days: Mapping[int, tuple[int, int]] = ELECTION_DAYS,
    dtype: str = "Int32"
) -> pd.Series:
    """
    Return a Pandas Series assigning House election cycle.

    Rules:
    1. Odd year -> year + 1.
    2. Even year:
       - before election day -> year
       - on/after election day -> year + 2

    Missing/non-House rows return null.
    Even years missing from election_days return null.
    """
    election_mmdd_map = {
        int(y): int(m) * 100 + int(d)
        for y, (m, d) in election_days.items()
    }

    year = pd.to_numeric(df[year_col], errors="coerce")
    month = pd.to_numeric(df[month_col], errors="coerce")
    day = pd.to_numeric(df[day_col], errors="coerce")

    row_mmdd = month * 100 + day

    election_mmdd_map = {
        int(y): int(m) * 100 + int(d)
        for y, (m, d) in election_days.items()
    }
    election_mmdd = year.map(election_mmdd_map)

    valid_date = year.notna() & month.notna() & day.notna()

    is_odd_year = (year % 2).eq(1)
    has_election_day = election_mmdd.notna()
    before_election_day = row_mmdd < election_mmdd

    cycle = pd.Series(pd.NA, index=df.index, dtype=dtype)

    odd_mask = valid_date & is_odd_year
    even_before_mask = valid_date & ~is_odd_year & has_election_day & before_election_day
    even_after_mask = valid_date & ~is_odd_year & has_election_day & ~before_election_day

    cycle.loc[odd_mask] = (year.loc[odd_mask] + 1).astype(dtype)
    cycle.loc[even_before_mask] = year.loc[even_before_mask].astype(dtype)
    cycle.loc[even_after_mask] = (year.loc[even_after_mask] + 2).astype(dtype)

    return cycle

def add_cycle(
    df: pd.DataFrame,
    *,
    year_col: str = "year",
    month_col: str = "month",
    day_col: str = "day",
    chamber_col: str = "chamber",
    output_col: str = "cycle",
    election_days: Mapping[int, tuple[int, int]] = ELECTION_DAYS,
    copy: bool = False,
) -> pd.DataFrame:
    """
    Add House election cycle column to a pandas DataFrame.

    Set copy=True if you do not want to mutate the input DataFrame.
    """

    if copy:
        df = df.copy()

    df[output_col] = house_cycle_series(
        df,
        year_col=year_col,
        month_col=month_col,
        day_col=day_col,
        chamber_col=chamber_col,
        election_days=election_days,
    )

    return df

def senate_cycle_join(
    A: pl.DataFrame | pl.LazyFrame,
    B: pl.DataFrame | pl.LazyFrame,
    *,
    left_match_cols: str | list[str],
    right_match_cols: str | list[str],
    left_cycle_col: str = "cycle",
    right_cycle_col: str = "cycle",
    tolerance: int = 4,
    suffix: str = "_B",
    keep_right_cycle_col: str = "matched_cycle_B",
    restore_left_order: bool = True,
) -> pl.DataFrame | pl.LazyFrame:
    """
    Left join A to B using exact-match columns plus forward cycle matching.

    Exact match:
        A[left_match_cols[i]] == B[right_match_cols[i]]

    Cycle match:
        B[right_cycle_col] >= A[left_cycle_col]
        B[right_cycle_col] <= A[left_cycle_col] + tolerance

    Among eligible B rows, chooses the lowest B[right_cycle_col].
    """

    if isinstance(left_match_cols, str):
        left_by = [left_match_cols]
    else:
        left_by = list(left_match_cols)

    if isinstance(right_match_cols, str):
        right_by = [right_match_cols]
    else:
        right_by = list(right_match_cols)

    if len(left_by) != len(right_by):
        raise ValueError(
            "`left_match_cols` and `right_match_cols` must have the same length."
        )

    A_work = A
    B_work = B

    if restore_left_order:
        A_work = A_work.with_row_index("_a_row_order")

    # Keep the right-side cycle value, because asof joins usually keep only
    # the left as-of key column in the final result.
    B_work = B_work.with_columns(
        pl.col(right_cycle_col).alias(keep_right_cycle_col)
    )

    # Make sure the cycle columns have compatible numeric types.
    A_work = A_work.with_columns(
        pl.col(left_cycle_col).cast(pl.Int32)
    )

    B_work = B_work.with_columns(
        pl.col(right_cycle_col).cast(pl.Int32)
    )

    # Polars requires sorted inputs for asof joins.
    A_sorted = A_work.sort([*left_by, left_cycle_col])
    B_sorted = B_work.sort([*right_by, right_cycle_col])

    out = A_sorted.join_asof(
        B_sorted,
        left_on=left_cycle_col,
        right_on=right_cycle_col,
        by_left=left_by,
        by_right=right_by,
        strategy="forward",
        tolerance=tolerance,
        suffix=suffix,
    )

    if restore_left_order:
        out = out.sort("_a_row_order").drop("_a_row_order")

    return out