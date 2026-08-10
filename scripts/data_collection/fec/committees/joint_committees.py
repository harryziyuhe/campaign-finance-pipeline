import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient


def fetch_joint_committees(client: FECClient) -> None:
    """
    Fetch committee_id + active_start/active_end (derived from each committee's `cycles`
    field) for committees designated J (joint fundraising committee). Merged into the
    existing file: a never-seen committee_id is inserted, and for a known one only
    active_end can grow.
    """
    active_period = client.scrape_committee_active_periods({"designation": "J"})
    client.merge_active_period(active_period, f"{client.committees_path}joint_committees.csv")


if __name__ == "__main__":
    fetch_joint_committees(FECClient())
