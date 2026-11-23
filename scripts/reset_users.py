#!/usr/bin/env python3
"""
Admin script: delete all user files from users/ on GitHub.
Run this to reset the game so every player must re-register and re-draft.

Usage:
    python scripts/reset_users.py [--dry-run]
"""

import os
import sys
import argparse
import requests

GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
if not GITHUB_TOKEN:
    sys.exit("ERROR: GITHUB_TOKEN env var not set. Export it locally, "
             "or have CI provide it via the GH_DATA_TOKEN secret.")
GITHUB_OWNER = "your-github-user"
GITHUB_REPO  = "your-data-repo"
GH_API       = f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents"
GH_HEADERS   = {
    "Authorization": f"token {GITHUB_TOKEN}",
    "Accept":        "application/vnd.github.v3+json",
}


def list_users() -> list[dict]:
    r = requests.get(f"{GH_API}/users", headers=GH_HEADERS, timeout=20)
    if r.status_code == 404:
        print("No users/ directory found.")
        return []
    r.raise_for_status()
    return [f for f in r.json() if f["name"].endswith(".json")]


def delete_file(path: str, sha: str, message: str) -> None:
    r = requests.delete(
        f"{GH_API}/{path}",
        headers=GH_HEADERS,
        json={"message": message, "sha": sha},
        timeout=20,
    )
    r.raise_for_status()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true",
                        help="Print what would be deleted without actually deleting")
    args = parser.parse_args()

    files = list_users()
    if not files:
        print("No user files found — nothing to do.")
        sys.exit(0)

    print(f"Found {len(files)} user file(s):")
    for f in files:
        print(f"  {f['name']}  (sha: {f['sha'][:8]}...)")

    if args.dry_run:
        print("\n[DRY RUN] No files deleted.")
        return

    print("\nDeleting...")
    for f in files:
        path = f"users/{f['name']}"
        try:
            delete_file(path, f["sha"], f"admin: reset — delete {f['name']}")
            print(f"  ✓ deleted {f['name']}")
        except Exception as e:
            print(f"  ✗ failed to delete {f['name']}: {e}")

    print("\nDone. All users reset.")

    # Also wipe chat.json so the conversation starts fresh
    r = requests.get(f"{GH_API}/chat.json", headers=GH_HEADERS, timeout=20)
    if r.status_code == 200:
        sha = r.json().get("sha")
        try:
            requests.delete(
                f"{GH_API}/chat.json",
                headers=GH_HEADERS,
                json={"message": "admin: reset — delete chat.json", "sha": sha},
                timeout=20,
            ).raise_for_status()
            print("  ✓ deleted chat.json")
        except Exception as e:
            print(f"  ✗ failed to delete chat.json: {e}")
    else:
        print("  (no chat.json found)")


if __name__ == "__main__":
    main()
