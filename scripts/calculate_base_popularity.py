#!/usr/bin/env python3
"""
One-time admin script: calculate base_popularity_pct for every player and write
it back to data/players.json on GitHub.

Run ONCE before the tournament starts, after all users have drafted their squads.

Formula:
    n  = number of users who have this player in their squad or bench
    total_users = total number of users in the game
    if n <= 1: popularity = 1.0
    else:      popularity = 0.33 + 0.67 * (1 - sqrt((n - 1) / total_users))

Usage:
    python scripts/calculate_base_popularity.py [--dry-run]
"""

import os
import sys
import json
import math
import base64
import argparse

import requests

# ── GitHub config ─────────────────────────────────────────────────────────
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


def gh_get(path: str) -> dict:
    r = requests.get(f"{GH_API}/{path}", headers=GH_HEADERS, timeout=20)
    r.raise_for_status()
    return r.json()


def gh_put(path: str, content: dict, sha: str, message: str) -> None:
    payload = {
        "message": message,
        "content": base64.b64encode(
            json.dumps(content, ensure_ascii=False, indent=2).encode()
        ).decode(),
        "sha": sha,
    }
    r = requests.put(f"{GH_API}/{path}", headers=GH_HEADERS,
                     json=payload, timeout=20)
    r.raise_for_status()


def load_json(path: str) -> tuple[dict | list, str]:
    """Returns (parsed_json, sha)."""
    raw = gh_get(path)
    data = json.loads(base64.b64decode(raw["content"]).decode())
    return data, raw["sha"]


def list_users() -> list[str]:
    items = gh_get("users")
    return [
        item["name"].replace(".json", "")
        for item in items
        if item["name"].endswith(".json")
    ]


def flatten_pos_map(pos_map: dict) -> list[str]:
    out = []
    for pos in ("GK", "DEF", "MID", "FWD"):
        out.extend(pos_map.get(pos, []))
    return out


def popularity(n: int, total_users: int) -> float:
    if n <= 1:
        return 1.0
    return 0.33 + 0.67 * (1.0 - math.sqrt((n - 1) / total_users))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true",
                        help="Print results without writing to GitHub")
    args = parser.parse_args()

    print("Loading users...")
    usernames = list_users()
    total_users = len(usernames)
    if total_users == 0:
        print("No users found — aborting.")
        sys.exit(1)
    print(f"  {total_users} users found: {usernames}")

    # Count selections per player across all users
    selection_count: dict[str, int] = {}

    for uname in usernames:
        try:
            ud, _ = load_json(f"users/{uname}.json")
        except Exception as e:
            print(f"  WARNING: could not load users/{uname}.json: {e}")
            continue

        squad_map = ud.get("squad", {})
        bench_map = ud.get("bench", {})

        # Support both flat list (legacy) and position-map (current) formats
        if isinstance(squad_map, dict):
            squad_players = flatten_pos_map(squad_map)
        else:
            squad_players = squad_map or []

        if isinstance(bench_map, dict):
            bench_players = flatten_pos_map(bench_map)
        else:
            bench_players = bench_map or []

        all_players = set(squad_players) | set(bench_players)
        for pid in all_players:
            if pid:
                selection_count[pid] = selection_count.get(pid, 0) + 1

    print(f"\nFound {len(selection_count)} unique players selected across all squads.")

    # Load players.json
    print("\nLoading data/players.json...")
    players_data, players_sha = load_json("data/players.json")

    # players.json can be a list or a dict keyed by player_id
    if isinstance(players_data, list):
        players_list = players_data
    else:
        players_list = list(players_data.values())

    updated = 0
    for player in players_list:
        pid = player.get("id") or player.get("player_id") or player.get("sofascore_id")
        if not pid:
            continue
        n = selection_count.get(str(pid), 0)
        pct = round(popularity(n, total_users), 4)
        old = player.get("base_popularity_pct")
        player["base_popularity_pct"] = pct
        if old != pct:
            updated += 1
        print(f"  {pid}: n={n}/{total_users}  pct={pct:.4f}"
              + (f"  (was {old})" if old is not None and old != pct else ""))

    # Also set pct=1.0 for any player NOT in any squad (n=0, treated as n<=1)
    print(f"\nUpdated base_popularity_pct for {updated} players.")

    if args.dry_run:
        print("\n[DRY RUN] No changes written to GitHub.")
        return

    print("\nWriting updated players.json to GitHub...")
    if isinstance(players_data, list):
        out_data = players_list
    else:
        # Rebuild dict form with same keys
        keys = list(players_data.keys())
        out_data = {keys[i]: players_list[i] for i in range(len(keys))}

    gh_put(
        "data/players.json",
        out_data,
        players_sha,
        "admin: calculate base_popularity_pct for all players",
    )
    print("Done.")


if __name__ == "__main__":
    main()
