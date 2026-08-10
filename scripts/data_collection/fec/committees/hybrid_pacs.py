import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient

# FEC committee_type codes for hybrid (Carey) PACs: V = nonqualified, W = qualified.
TYPE_CODES = ["V", "W"]


def fetch_hybrid_pacs(client: FECClient) -> None:
    """
    Fetch committee_id + active_start/active_end (derived from each committee's `cycles`
    field) for hybrid PACs. Merged into the existing file: a never-seen committee_id is
    inserted, and for a known one only active_end can grow.
    """
    frames = [client.scrape_committee_active_periods({"committee_type": code}) for code in TYPE_CODES]
    active_period = pd.concat(frames, ignore_index=True)
    client.merge_active_period(active_period, f"{client.committees_path}hybrid_pacs.csv")


if __name__ == "__main__":
    fetch_hybrid_pacs(FECClient())
