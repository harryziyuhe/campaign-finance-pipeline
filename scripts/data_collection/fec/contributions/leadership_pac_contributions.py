import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient
from schedule_a_core import fetch_schedule_a_for_committees  # same folder, direct import

if __name__ == "__main__":
    client = FECClient()
    fetch_schedule_a_for_committees(
        client,
        committee_file=f"{client.committees_path}leadership_pacs.csv",
        output_file=f"{client.contributions_path}leadership_contributions.parquet",
    )
