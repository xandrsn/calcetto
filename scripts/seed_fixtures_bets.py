#!/usr/bin/env python3
"""
seed_fixtures_bets.py — seed the 2026-27 La Liga season into the backend.

Produces:
  * data/league.json      — all 380 fixtures (double round-robin), no scores yet.
  * daily/md<NN>.json      — one file per matchday (1..38): fixtures with real
                             kickoff datetimes + phase windows + one Spanish prop
                             bet per match. Fixture ids match lib/models/league.dart
                             (`fixtureId` = md<NN>-<homeslug>-<awayslug>).
  * data/app_config.json   — current_matchday = 1 (per-key merge).

Schedule note: the pairings come from a deterministic circle-method round-robin
(same as LeagueData.buildDefault in Dart), and kickoff datetimes are laid out on
weekend slots from the season opener. This is a coherent, seedable schedule — the
real asymmetric LaLiga calendar (incl. midweek rounds / reschedules) can overwrite
individual matchday files later; the data model already supports per-fixture
`kickoff` + `postponed`.

Usage:
    GITHUB_TOKEN=... python scripts/seed_fixtures_bets.py [--push]
Without --push it is a dry run (prints a summary, writes nothing).
"""
import argparse
import base64
import json
import os
import random
import sys
import unicodedata
from datetime import datetime, timedelta, timezone

import requests

API = "https://api.github.com/repos/your-github-user/your-data-repo/contents"
TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()

TEAMS = [
    "Alavés", "Athletic Bilbao", "Atlético Madrid", "Barcelona", "Celta Vigo",
    "Deportivo A Coruña", "Elche", "Espanyol", "Getafe", "Levante", "Málaga",
    "Osasuna", "Racing Santander", "Rayo Vallecano", "Real Betis", "Real Madrid",
    "Real Sociedad", "Sevilla", "Valencia", "Villarreal",
]

# Season opener weekend (Madrid). Matchday k starts k-1 weeks later.
SEASON_START = datetime(2026, 8, 15, tzinfo=timezone(timedelta(hours=2)))  # CEST
# Weekend kickoff slots (day offset from the Saturday, hour, minute) — 10 per md.
SLOTS = [
    (-1, 21, 0), (0, 14, 0), (0, 16, 15), (0, 18, 30), (0, 21, 0),
    (1, 14, 0), (1, 16, 15), (1, 18, 30), (1, 21, 0), (2, 21, 0),
]

# Spanish prop-bet templates (one per fixture, chosen deterministically).
BET_TEMPLATES = [
    ("¿Cuántos goles en total?", ["0-1", "2-3", "4+"]),
    ("¿Habrá tarjeta roja?", ["Sí", "No"]),
    ("¿Ambos equipos marcan?", ["Sí", "No"]),
    ("¿Quién gana?", ["Local", "Empate", "Visitante"]),
    ("¿Gol en los primeros 15 min?", ["Sí", "No"]),
    ("¿Habrá penalti?", ["Sí", "No"]),
    ("¿Más de 9 córners?", ["Sí", "No"]),
    ("¿Marca el delantero estrella local?", ["Sí", "No"]),
]


def slug(team: str) -> str:
    s = "".join(
        c for c in unicodedata.normalize("NFD", team.lower())
        if unicodedata.category(c) != "Mn"
    )
    out = ["".join(ch if ch.isalnum() else "_" for ch in s)]
    return out[0].strip("_").replace("__", "_")


def fixture_id(md: int, home: str, away: str) -> str:
    return f"md{md:02d}-{slug(home)}-{slug(away)}"


def round_robin(teams):
    """Double round-robin via the circle method (mirrors _roundRobin in Dart).
    Returns list of (matchday, home, away)."""
    n = len(teams)
    rot = list(teams)
    out = []
    leg_rounds = n - 1  # 19
    for r in range(leg_rounds):
        for i in range(n // 2):
            home, away = rot[i], rot[n - 1 - i]
            if r % 2 == 1:
                home, away = away, home
            md1 = r + 1
            out.append((md1, home, away))
            out.append((md1 + leg_rounds, away, home))  # second leg, venue swap
        rot.insert(1, rot.pop())  # rotate all but the first
    return out


def build():
    fixtures = round_robin(TEAMS)
    by_md = {}
    for md, home, away in fixtures:
        by_md.setdefault(md, []).append((home, away))

    league_matches = []
    daily_files = {}
    rng = random.Random(2627)

    for md in sorted(by_md):
        sat = SEASON_START + timedelta(days=7 * (md - 1))
        games = by_md[md]
        matches, bets, kickoffs = [], [], []
        for i, (home, away) in enumerate(games):
            day_off, hh, mm = SLOTS[i % len(SLOTS)]
            ko = (sat + timedelta(days=day_off)).replace(hour=hh, minute=mm)
            kickoffs.append(ko)
            fid = fixture_id(md, home, away)
            matches.append({
                "id": fid, "home": home, "away": away,
                "kickoff": ko.isoformat(), "score": None, "players": [],
            })
            q, opts = rng.choice(BET_TEMPLATES)
            bets.append({
                "id": f"{fid}-bet", "match_id": fid,
                "question": f"{home} vs {away}: {q}", "options": opts,
                "answer": None,
            })
            league_matches.append({
                "id": fid, "md": md, "home": home, "away": away,
                "kickoff": ko.isoformat(), "hs": None, "as": None,
            })
        first_ko = min(kickoffs)
        daily_files[f"md{md:02d}"] = {
            "matchday": md,
            "date": first_ko.strftime("%Y-%m-%d"),
            "first_kickoff": first_ko.isoformat(),
            "cards_open": (first_ko - timedelta(hours=6)).isoformat(),
            "lock_at": (first_ko - timedelta(hours=2)).isoformat(),
            "matches": matches,
            "bets": bets,
        }

    return {"matches": league_matches}, daily_files


def gh_put(path, data, message):
    r = requests.get(f"{API}/{path}",
                     headers={"Authorization": f"Bearer {TOKEN}"}, timeout=15)
    sha = r.json().get("sha") if r.status_code == 200 else None
    payload = {
        "message": message,
        "content": base64.b64encode(
            json.dumps(data, ensure_ascii=False, indent=2).encode()).decode(),
    }
    if sha:
        payload["sha"] = sha
    r = requests.put(f"{API}/{path}",
                     headers={"Authorization": f"Bearer {TOKEN}"},
                     json=payload, timeout=20)
    r.raise_for_status()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--push", action="store_true", help="write to the backend")
    args = ap.parse_args()

    league, daily_files = build()
    print(f"Built {len(league['matches'])} fixtures across {len(daily_files)} matchdays.")
    print(f"Example md01 first kickoff: {daily_files['md01']['first_kickoff']}")

    if not args.push:
        print("[dry-run] nothing written. Re-run with --push to seed the backend.")
        return
    if not TOKEN:
        sys.exit("Set GITHUB_TOKEN to push.")

    gh_put("data/league.json", league, "seed: La Liga 2026-27 fixtures")
    print("  wrote data/league.json")
    for key, md in daily_files.items():
        gh_put(f"daily/{key}.json", md, f"seed: matchday {md['matchday']}")
        print(f"  wrote daily/{key}.json")
    r = requests.get(f"{API}/data/app_config.json",
                     headers={"Authorization": f"Bearer {TOKEN}"}, timeout=15)
    cfg = {}
    if r.status_code == 200:
        cfg = json.loads(base64.b64decode(r.json()["content"]).decode())
    cfg["current_matchday"] = 1
    gh_put("data/app_config.json", cfg, "seed: current_matchday = 1")
    print("  set current_matchday = 1")
    print("Done.")


if __name__ == "__main__":
    main()
