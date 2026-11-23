#!/usr/bin/env python3
"""
reseed_players_laliga.py — REPLACE data/players.json with the 2026-27 La Liga
squads.

Real rosters are a curated dataset (like the artwork), so this script ingests a
drop file rather than fabricating names. Provide `scripts/laliga_squads.json`:

    {
      "Real Madrid":   [{"name": "Kylian Mbappé", "position": "FWD"}, ...],
      "Barcelona":     [{"name": "Pedri", "position": "MID"}, ...],
      ... one entry per club (team names must match kLaLigaTeams) ...
    }

Each player becomes:
    {id, name, team, position (GK/DEF/MID/FWD), skin, goals:0, assists:0,
     total_points:0, points_per_match:{}, base_popularity_pct, retired:false}

Ids are a slug of the name (deduped with a numeric suffix). Positions are
normalised to GK/DEF/MID/FWD.

Usage:
    python scripts/reseed_players_laliga.py            # dry run (validates)
    GITHUB_TOKEN=... python scripts/reseed_players_laliga.py --push
"""
import argparse
import base64
import json
import os
import sys
import unicodedata

import requests

API = "https://api.github.com/repos/your-github-user/your-data-repo/contents"
TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
HERE = os.path.dirname(os.path.abspath(__file__))
SQUADS_FILE = os.path.join(HERE, "laliga_squads.json")

TEAMS = {
    "Alavés", "Athletic Bilbao", "Atlético Madrid", "Barcelona", "Celta Vigo",
    "Deportivo A Coruña", "Elche", "Espanyol", "Getafe", "Levante", "Málaga",
    "Osasuna", "Racing Santander", "Rayo Vallecano", "Real Betis", "Real Madrid",
    "Real Sociedad", "Sevilla", "Valencia", "Villarreal",
}
POS = {"GK", "DEF", "MID", "FWD"}
SKINS = ["skin1", "skin2", "skin3", "skin4"]


def slug(name: str) -> str:
    s = "".join(
        c for c in unicodedata.normalize("NFD", name.lower())
        if unicodedata.category(c) != "Mn"
    )
    return "".join(ch if ch.isalnum() else "_" for ch in s).strip("_")


def build(squads: dict) -> list:
    players = []
    seen = {}
    unknown = set(squads) - TEAMS
    if unknown:
        print(f"WARNING: unknown teams (ignored): {sorted(unknown)}")
    for team in sorted(squads):
        if team not in TEAMS:
            continue
        for i, p in enumerate(squads[team]):
            name = p["name"].strip()
            position = p.get("position", "MID").upper()
            if position not in POS:
                position = "MID"
            base = slug(name)
            seen[base] = seen.get(base, 0) + 1
            pid = base if seen[base] == 1 else f"{base}_{seen[base]}"
            players.append({
                "id": pid, "name": name, "team": team, "position": position,
                "skin": SKINS[i % len(SKINS)],
                "goals": 0, "assists": 0, "total_points": 0,
                "points_per_match": {}, "base_popularity_pct": 50,
                "retired": False,
            })
    return players


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--push", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(SQUADS_FILE):
        sys.exit(
            f"Missing {SQUADS_FILE}.\nCreate it with the 20 La Liga squads "
            "(see the module docstring for the schema), then re-run."
        )
    with open(SQUADS_FILE, encoding="utf-8") as f:
        squads = json.load(f)

    players = build(squads)
    counts = {}
    for p in players:
        counts[p["team"]] = counts.get(p["team"], 0) + 1
    print(f"Built {len(players)} players across {len(counts)} clubs.")
    missing = TEAMS - set(counts)
    if missing:
        print(f"WARNING: no players for: {sorted(missing)}")

    if not args.push:
        print("[dry-run] nothing written. Re-run with --push to replace players.json.")
        return
    if not TOKEN:
        sys.exit("Set GITHUB_TOKEN to push.")

    r = requests.get(f"{API}/data/players.json",
                     headers={"Authorization": f"Bearer {TOKEN}"}, timeout=15)
    sha = r.json().get("sha") if r.status_code == 200 else None
    payload = {
        "message": "reseed: La Liga 2026-27 squads",
        "content": base64.b64encode(
            json.dumps({"players": players}, ensure_ascii=False, indent=2).encode()
        ).decode(),
    }
    if sha:
        payload["sha"] = sha
    r = requests.put(f"{API}/data/players.json",
                     headers={"Authorization": f"Bearer {TOKEN}"},
                     json=payload, timeout=30)
    r.raise_for_status()
    print("Replaced data/players.json.")


if __name__ == "__main__":
    main()
