import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient

FIELDS = ["committee_id", "committee_type", "committee_type_full",
          "designation", "designation_full", "name", "state"]


def fetch_joint_committees(client: FECClient) -> None:
    """Fetch all committees designated J (joint fundraising committee)."""
    committees = client.scrape_committees({"designation": "J"}, FIELDS)
    committees.to_csv(f"{client.committees_path}joint_committees.csv", index=False)


if __name__ == "__main__":
    fetch_joint_committees(FECClient())
