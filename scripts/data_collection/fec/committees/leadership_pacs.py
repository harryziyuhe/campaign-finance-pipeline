import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient

FIELDS = ["committee_id", "committee_type", "committee_type_full",
          "designation", "designation_full", "name", "state"]


def fetch_leadership_pacs(client: FECClient) -> None:
    """Fetch all committees designated D (leadership PAC)."""
    committees = client.scrape_committees({"designation": "D"}, FIELDS)
    committees.to_csv(f"{client.committees_path}leadership_pacs.csv", index=False)


if __name__ == "__main__":
    fetch_leadership_pacs(FECClient())
