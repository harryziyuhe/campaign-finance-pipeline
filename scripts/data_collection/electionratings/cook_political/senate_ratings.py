import argparse

from cook_political_client import CookPoliticalClient  # same folder, direct import

ENDPOINT = "senate"
FIELDS = ["Title", "State", "Incumbent", "Rating", "Cook_PVI"]


def fetch_senate_ratings(client: CookPoliticalClient, force: bool = False):
    """
    Fetch current US Senate race ratings. Overwrites the prior snapshot each run -- see
    cook_political_client.py's module docstring for why (current-state data, not a per-cycle
    ledger).
    """
    client.check_rate_limit(ENDPOINT, force=force)
    rows = client.fetch_all_pages(ENDPOINT)
    return client.to_csv(rows, FIELDS, f"{client.output_path}senate_ratings.csv")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fetch current Cook Political Report US Senate ratings.")
    parser.add_argument("--force", action="store_true", help="Bypass the once-a-day rate-limit guard.")
    args = parser.parse_args()

    client = CookPoliticalClient()
    fetch_senate_ratings(client, force=args.force)
