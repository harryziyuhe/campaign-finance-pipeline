import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fec_client import FECClient

FIELDS = ["committee_id", "name", "organization_type", "organization_type_full",
          "affiliated_committee_name", "committee_type", "committee_type_full",
          "designation", "designation_full", "state"]


def fetch_corporate_pacs(client: FECClient) -> None:
    """
    Fetch all committees with organization_type=C (corporation), replacing
    FECtidy.get_corporate_pacs()'s bulk committee-master dependency.
    `affiliated_committee_name` is the API-native equivalent of the bulk
    committee master file's CONNECTED_ORG_NM field.

    This captures each committee's current organization_type/affiliated name
    only, not the per-cycle history the bulk data provided (used by
    FECtidy.agg_corporate_pacs()'s exact-match merge against the hand-curated
    corporate_pacs_2004_2024.csv). That per-cycle backfill would use
    committee/{id}/history/ per committee and is a separate, heavier follow-up.
    """
    committees = client.scrape_committees({"organization_type": "C"}, FIELDS)
    committees.to_csv(f"{client.committees_path}corporate_pacs.csv", index=False)


if __name__ == "__main__":
    fetch_corporate_pacs(FECClient())
