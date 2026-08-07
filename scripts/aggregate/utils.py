import re

def validate_frame(df, required_columns, name, min_rows=1):
    """Raise a clear error if `df` is missing expected columns or has too few rows.

    Meant to be called right after reading an upstream file and right before
    writing a final output, so a silent upstream schema change (e.g. an FEC
    field renamed or dropped) or an empty-result join/filter bug surfaces as
    one clear error at the pipeline stage boundary, not a confusing KeyError
    or an empty file discovered downstream.
    """
    missing = [c for c in required_columns if c not in df.columns]
    if missing:
        raise ValueError(f"{name}: missing expected columns {missing} (got {df.columns})")
    if df.height < min_rows:
        raise ValueError(f"{name}: expected at least {min_rows} row(s), got {df.height}")

def remove_punc(text):
    pattern = r'[^a-zA-Z0-9]'
    cleaned_text = re.sub(pattern, '', text)
    return cleaned_text

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