#!/usr/bin/env python3
"""Reset every user's game-state to a clean slate, keeping their account.

After reseeding players.json + the real WC2026 draw, existing user squads/bracket
predictions reference deleted player ids and old team names (orphaned). This
clears the per-user game-state (squad, bench, captain, cards, bracket, points)
so each user simply re-drafts on next open — without deleting the account, so
nobody has to re-register. Username / fcm_token / force_logout are preserved.

Usage (from repo root):
    python scripts/reset_user_squads.py                  # dry run
    GITHUB_TOKEN=... python scripts/reset_user_squads.py --push
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

OWNER, REPO = "your-github-user", "your-data-repo"
API = f"https://api.github.com/repos/{OWNER}/{REPO}/contents"

# Fields reset to their fresh-registration defaults. Everything else on the user
# (name, fcm_token, force_logout) is kept as-is.
RESET = {
    "squad": {"GK": [], "DEF": [], "MID": [], "FWD": []},
    "bench": {"GK": [], "DEF": [], "MID": [], "FWD": []},
    "formation": "4-3-3",
    "subs_used_this_round": 0,
    "captain_picks": {},
    "quiniela_prediction": {"picks": {}},
    "golden_boot": None,
    "top_assister": None,
    "points": {"total": 0.0, "breakdown": {
        "squad": 0.0, "bets": 0.0, "quiniela": 0.0,
        "golden_boot": 0.0, "steals": 0.0, "cards": 0.0}},
    "active": {"captain": None, "bets": {}, "cards_received": [],
               "cards_played": [], "attacks_received_today": 0},
    "signing_cards_available": 0,
    "signing_cards_used": [],
    "extra_subs_available": 0,
}


def api(path, method="GET", data=None, accept="application/vnd.github+json"):
    req = urllib.request.Request(
        f"{API}/{path}", data=data, method=method,
        headers={"Authorization": f"Bearer {TOKEN}", "Accept": accept})
    return urllib.request.urlopen(req)


def list_users():
    try:
        with api("users") as r:
            return [f for f in json.load(r) if f["name"].endswith(".json")]
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return []
        raise


if __name__ == "__main__":
    push = "--push" in sys.argv
    TOKEN = os.environ.get("GITHUB_TOKEN", "")
    if not TOKEN:
        print("Set GITHUB_TOKEN", file=sys.stderr)
        sys.exit(1)

    files = list_users()
    print(f"{len(files)} user file(s): {[f['name'] for f in files]}")
    if not push:
        print("\nDry run. Re-run with --push to reset (keeps accounts).")
        sys.exit(0)

    for f in files:
        path = f"users/{f['name']}"
        with api(path, accept="application/vnd.github.raw") as r:
            user = json.load(r)
        user.update(RESET)
        payload = {
            "message": f"admin: reset squad/state for {user.get('name', f['name'])}",
            "content": base64.b64encode(
                json.dumps(user, ensure_ascii=False, indent=2).encode()).decode(),
            "sha": f["sha"],
        }
        api(path, method="PUT", data=json.dumps(payload).encode()).read()
        print(f"  reset {f['name']}")
    print("Done.")
