import re

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