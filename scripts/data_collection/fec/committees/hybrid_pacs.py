import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient

FIELDS = ["committee_id", "committee_type", "committee_type_full",
          "designation", "designation_full", "name", "state"]
# FEC committee_type codes for hybrid (Carey) PACs: V = nonqualified, W = qualified.
TYPE_CODES = ["V", "W"]


def fetch_hybrid_pacs(client: FECClient) -> None:
    frames = [client.scrape_committees({"committee_type": code}, FIELDS) for code in TYPE_CODES]
    pd.concat(frames, ignore_index=True).to_csv(f"{client.committees_path}hybrid_pacs.csv", index=False)


if __name__ == "__main__":
    fetch_hybrid_pacs(FECClient())
