import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient

FIELDS = ["committee_id", "committee_type", "committee_type_full",
          "designation", "designation_full", "name", "state"]
# FEC committee_type codes for independent-expenditure-only PACs: O = super PAC, U = single-candidate.
TYPE_CODES = ["O", "U"]


def fetch_super_pacs(client: FECClient) -> None:
    frames = [client.scrape_committees({"committee_type": code}, FIELDS) for code in TYPE_CODES]
    pd.concat(frames, ignore_index=True).to_csv(f"{client.committees_path}super_pacs.csv", index=False)


if __name__ == "__main__":
    fetch_super_pacs(FECClient())
