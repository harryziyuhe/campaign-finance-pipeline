import argparse

from cook_political_client import CookPoliticalClient  # same folder, direct import

ENDPOINT = "presidential"
FIELDS = ["Title", "State", "Electoral_votes", "Rating", "Cycle", "Rating_date"]


def fetch_presidential_ratings(client: CookPoliticalClient, force: bool = False):
    """
    Fetch current Presidential/Electoral College ratings. Overwrites the prior snapshot each
    run -- see cook_political_client.py's module docstring for why (current-state data, not a
    per-cycle ledger).
    """
    client.check_rate_limit(ENDPOINT, force=force)
    rows = client.fetch_all_pages(ENDPOINT)
    return client.to_csv(rows, FIELDS, f"{client.output_path}presidential_ratings.csv")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Fetch current Cook Political Report Presidential/Electoral College ratings."
    )
    parser.add_argument("--force", action="store_true", help="Bypass the once-a-day rate-limit guard.")
    args = parser.parse_args()

    client = CookPoliticalClient()
    fetch_presidential_ratings(client, force=args.force)
