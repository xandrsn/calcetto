#!/usr/bin/env python3
"""
Fetch La Liga match results from ESPN and update a matchday's JSON in GitHub.

ESPN public API requires no auth and works from GitHub Actions runners.
A La Liga matchday spans Fri–Mon (and occasionally midweek), so this fetches
every date the matchday's fixtures kick off on and matches by team.

Usage:
    python scripts/fetch_scores.py [MATCHDAY_NUMBER] [--dry-run]
If omitted, uses current_matchday from data/app_config.json.
"""

import os, sys, json, base64, time, argparse, unicodedata
import requests

GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
if not GITHUB_TOKEN:
    sys.exit("ERROR: GITHUB_TOKEN env var not set.")
GITHUB_OWNER = "your-github-user"
GITHUB_REPO  = "your-data-repo"
GH_API       = f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents"
GH_HEADERS   = {
    "Authorization": f"token {GITHUB_TOKEN}",
    "Accept":        "application/vnd.github.v3+json",
}

ESPN_LEAGUE  = "esp.1"   # La Liga (Primera División)
ESPN_BASE    = "https://site.api.espn.com/apis/site/v2/sports/soccer"
ESPN_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
    ),
    "Accept": "application/json",
}

# La Liga club name variants that differ between our JSON and ESPN (after
# accent-folding + upper-casing in _norm).
_TEAM_ALIASES = {
    "ATHLETICBILBAO": "ATHLETICCLUB",
    "DEPORTIVOACORUNA": "DEPORTIVOLACORUNA",
    "ATLETICOMADRID": "ATLETICOMADRID",
    "CELTAVIGO": "CELTA",
    "RACINGSANTANDER": "RACINGSANTANDER",
}

PTS_APPEARANCE_FULL  = 2
PTS_APPEARANCE_SHORT = 1
PTS_GOAL = {"GK": 6, "DEF": 6, "MID": 5, "FWD": 4}
PTS_ASSIST           = 3
PTS_CLEAN_SHEET_GK   = 5
PTS_CLEAN_SHEET_DEF  = 4
PTS_CLEAN_SHEET_MID  = 1
PTS_YELLOW           = -1
PTS_RED              = -3


def gh_get(path):
    r = requests.get(f"{GH_API}/{path}", headers=GH_HEADERS, timeout=15)
    if r.status_code == 404:
        return None, None
    r.raise_for_status()
    j = r.json()
    raw = base64.b64decode(j["content"].replace("\\n", "")).decode("utf-8")
    return json.loads(raw), j["sha"]


def gh_put(path, data, sha, message, dry_run=False):
    if dry_run:
        print(f"[dry-run] Would write {path}: {message}")
        return
    content = base64.b64encode(
        json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
    ).decode("ascii")
    payload = {"message": message, "content": content}
    if sha:
        payload["sha"] = sha
    r = requests.put(f"{GH_API}/{path}", headers=GH_HEADERS, json=payload, timeout=15)
    r.raise_for_status()
    time.sleep(0.5)


def espn_get(url):
    try:
        r = requests.get(url, headers=ESPN_HEADERS, timeout=20)
        r.raise_for_status()
        return r.json()
    except Exception as exc:
        print(f"  WARNING: ESPN request failed: {exc}")
        return None


def _norm(name):
    folded = "".join(
        c for c in unicodedata.normalize("NFD", name)
        if unicodedata.category(c) != "Mn"
    )
    n = folded.upper().replace(" ", "").replace(".", "").replace("-", "").replace("\'", "")
    return _TEAM_ALIASES.get(n, n)


def get_events(day):
    """ESPN scoreboard events for a single YYYY-MM-DD."""
    compact = day.replace("-", "")
    data = espn_get(f"{ESPN_BASE}/{ESPN_LEAGUE}/scoreboard?dates={compact}&limit=50")
    if not data:
        return []
    return data.get("events", [])


def get_event_summary(event_id):
    return espn_get(f"{ESPN_BASE}/{ESPN_LEAGUE}/summary?event={event_id}")


def parse_espn_rosters(summary):
    """
    Parse player stats from ESPN summary using rosters[] (not boxscore.players[]).

    ESPN rosters structure:
      rosters[i].homeAway = "home" | "away"
      rosters[i].roster[j].athlete.displayName
      rosters[i].roster[j].starter   (bool)
      rosters[i].roster[j].subbedIn  (bool)
      rosters[i].roster[j].subbedOut (bool)
      rosters[i].roster[j].stats     [{abbreviation, value}]
        abbreviations: G, A, YC, RC, APP, SUB
    """
    result = {
        "home_goals": -1, "away_goals": -1,
        "home_players": [], "away_players": [],
    }

    # Scores from header
    header = summary.get("header", {})
    for competition in header.get("competitions", []):
        for comp in competition.get("competitors", []):
            side = "home" if comp.get("homeAway") == "home" else "away"
            try:
                result[f"{side}_goals"] = int(comp.get("score", ""))
            except (ValueError, TypeError):
                pass

    # Player stats from rosters[]
    for roster_block in summary.get("rosters", []):
        side = "home" if roster_block.get("homeAway") == "home" else "away"
        for entry in roster_block.get("roster", []):
            athlete = entry.get("athlete", {})
            name    = athlete.get("displayName", "")
            if not name:
                continue

            starter    = entry.get("starter", False)
            subbed_in  = entry.get("subbedIn", False)
            subbed_out = entry.get("subbedOut", False)

            # ESPN does not give exact minutes — infer from flags.
            # starter + not subbed out  -> played full 90 min
            # starter + subbed out      -> started, at least 45 min; use 60 as estimate
            # not starter + subbed in   -> came on as sub; use 30 as estimate (< 45)
            # neither                   -> did not play
            if starter and not subbed_out:
                minutes = 90
            elif starter and subbed_out:
                minutes = 60
            elif not starter and subbed_in:
                minutes = 30
            else:
                minutes = 0

            stats   = {s["abbreviation"]: int(float(s.get("value", 0) or 0))
                       for s in entry.get("stats", [])}
            goals   = stats.get("G",  0)
            assists = stats.get("A",  0)
            yellow  = stats.get("YC", 0)
            red     = stats.get("RC", 0)

            result[f"{side}_players"].append({
                "name": name, "minutes": minutes,
                "goals": goals, "assists": assists,
                "yellow": yellow, "red": red,
            })

    return result


def calc_player_points(position, goals, assists, minutes, yellow, red, clean_sheet):
    if minutes <= 0:
        return 0.0
    pts  = float(PTS_APPEARANCE_FULL if minutes >= 45 else PTS_APPEARANCE_SHORT)
    pts += goals   * PTS_GOAL.get(position, PTS_GOAL["MID"])
    pts += assists * PTS_ASSIST
    if clean_sheet and minutes >= 88:
        if position == "GK":
            pts += PTS_CLEAN_SHEET_GK
        elif position == "DEF":
            pts += PTS_CLEAN_SHEET_DEF
        elif position == "MID":
            pts += PTS_CLEAN_SHEET_MID
    pts += yellow * PTS_YELLOW
    pts += red    * PTS_RED
    return round(pts, 1)


def _md_totals(daily: dict) -> dict:
    """Per-player goals/assists/points summed over one matchday's match rows."""
    out: dict = {}
    for m in daily.get("matches", []):
        for p in m.get("players", []) or []:
            t = out.setdefault(p["id"], {"goals": 0, "assists": 0, "pts": 0.0})
            t["goals"] += p.get("goals", 0)
            t["assists"] += p.get("assists", 0)
            t["pts"] += float(p.get("points", 0.0))
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("matchday", nargs="?", type=int)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    dry_run = args.dry_run

    app_config, _ = gh_get("data/app_config.json")
    md_num = args.matchday or int((app_config or {}).get("current_matchday", 1))
    md_key = f"md{md_num:02d}"
    print(f"=== fetch_scores.py  matchday={md_num} ({md_key})  dry_run={dry_run} ===")

    name_map_data, name_map_sha = gh_get("data/player_name_map.json")
    name_map = {}
    if name_map_data:
        name_map = name_map_data.get("mappings", {})
    unmapped_names = []
    print(f"  Name map: {len(name_map)} entries")

    players_data, players_sha = gh_get("data/players.json")
    if players_data is None:
        sys.exit("ERROR: data/players.json not found")
    players_list   = players_data.get("players", [])
    player_by_id   = {p["id"]: p for p in players_list}
    position_by_id = {p["id"]: p.get("position", "MID").upper() for p in players_list}
    print(f"  Players: {len(players_list)}")

    daily_data, daily_sha = gh_get(f"daily/{md_key}.json")
    if daily_data is None:
        sys.exit(f"ERROR: daily/{md_key}.json not found")

    # Gather every calendar date the matchday's fixtures kick off on.
    md_dates = sorted({
        (m.get("kickoff") or "")[:10]
        for m in daily_data.get("matches", [])
        if m.get("kickoff")
    })
    print(f"Fetching ESPN events for dates: {md_dates} ...")
    espn_events = []
    for day in md_dates:
        espn_events.extend(get_events(day))
    print(f"  Found {len(espn_events)} event(s)")
    if not espn_events:
        print("No events on ESPN — nothing to update")
        return

    espn_by_teams = {}
    for ev in espn_events:
        comps     = ev.get("competitions", [{}])[0].get("competitors", [])
        home_name = next((c["team"]["displayName"] for c in comps if c.get("homeAway") == "home"), "")
        away_name = next((c["team"]["displayName"] for c in comps if c.get("homeAway") == "away"), "")
        key = (_norm(home_name), _norm(away_name))
        espn_by_teams[key] = ev
        print(f"    ESPN event: {home_name} vs {away_name}  [{key}]")

    # Player career totals are moved by the DELTA against what this matchday
    # already contributed, so re-running the (daily) job never double-counts.
    old_totals = _md_totals(daily_data)

    for match in daily_data.get("matches", []):
        home_team = match.get("home", "")
        away_team = match.get("away", "")
        print(f"\\n  Match: {home_team} vs {away_team}")

        h = _norm(home_team)
        a = _norm(away_team)
        espn_ev = (
            espn_by_teams.get((h, a)) or
            espn_by_teams.get((a, h))
        )
        if espn_ev is None:
            for (eh, ea), ev in espn_by_teams.items():
                if (h in eh or eh in h) and (a in ea or ea in a):
                    espn_ev = ev
                    break

        if espn_ev is None:
            print(f"    WARNING: No ESPN event found (tried norm={h}/{a})")
            print(f"    ESPN keys: {list(espn_by_teams.keys())}")
            continue

        completed = espn_ev.get("status", {}).get("type", {}).get("completed", False)
        if not completed:
            state = espn_ev.get("status", {}).get("type", {}).get("name", "unknown")
            print(f"    Match not completed (status={state}) — skipping")
            continue

        event_id = espn_ev["id"]
        print(f"    ESPN event_id={event_id}")
        summary = get_event_summary(event_id)
        if not summary:
            print("    WARNING: No summary from ESPN")
            continue

        boxscore   = parse_espn_rosters(summary)
        home_goals = boxscore["home_goals"]
        away_goals = boxscore["away_goals"]

        if home_goals >= 0 and away_goals >= 0:
            match["score"] = f"{home_goals}-{away_goals}"
            print(f"    Score: {home_goals}-{away_goals}")

        total_home = len(boxscore["home_players"])
        total_away = len(boxscore["away_players"])
        print(f"    Players parsed: home={total_home} away={total_away}")

        new_match_players = []

        for side, goals_conceded in [("home", away_goals), ("away", home_goals)]:
            for p_info in boxscore[f"{side}_players"]:
                name     = p_info["name"]
                minutes  = p_info["minutes"]
                goals_s  = p_info["goals"]
                assists  = p_info["assists"]
                yellow   = p_info["yellow"]
                red      = p_info["red"]
                clean_sh = goals_conceded == 0

                player_id = name_map.get(name)
                if player_id is None:
                    last = name.split()[-1] if name else ""
                    for k, v in name_map.items():
                        if k.split()[-1] == last:
                            player_id = v
                            break

                if player_id is None:
                    if minutes > 0 and name not in unmapped_names:
                        unmapped_names.append(name)
                    continue

                our_pos = position_by_id.get(player_id, "MID")
                pts = calc_player_points(
                    position=our_pos, goals=goals_s, assists=assists,
                    minutes=minutes, yellow=yellow, red=red, clean_sheet=clean_sh,
                )
                print(f"      {name} ({player_id}): {goals_s}G {assists}A min={minutes} -> {pts}pts")

                new_match_players.append({
                    "id": player_id, "goals": goals_s, "assists": assists,
                    "minutes": minutes, "yellow": yellow, "red": red,
                    "rating": None, "points": pts,
                })

        match["players"] = new_match_players

    print(f"\\nWriting daily/{md_key}.json ...")
    gh_put(f"daily/{md_key}.json", daily_data, daily_sha,
           f"bot: fetch scores {md_key} (ESPN)", dry_run)

    print("Updating data/players.json ...")
    new_totals = _md_totals(daily_data)
    zero = {"goals": 0, "assists": 0, "pts": 0.0}
    for pid in set(old_totals) | set(new_totals):
        if pid not in player_by_id:
            continue
        old = old_totals.get(pid, zero)
        new = new_totals.get(pid, zero)
        p = player_by_id[pid]
        p["goals"]        = p.get("goals", 0) + new["goals"] - old["goals"]
        p["assists"]      = p.get("assists", 0) + new["assists"] - old["assists"]
        p["total_points"] = round(p.get("total_points", 0.0) + new["pts"] - old["pts"], 1)
        ppm = p.setdefault("points_per_match", {})
        if new["pts"] or md_key in ppm:
            ppm[md_key] = round(new["pts"], 1)

    players_data["players"] = list(player_by_id.values())
    gh_put("data/players.json", players_data, players_sha,
           f"bot: update player stats {md_key}", dry_run)

    if unmapped_names:
        print(f"\\nUnmapped players (add to data/player_name_map.json):")
        for n in unmapped_names:
            print(f'    "{n}": "PLAYER_ID_HERE",')
        if name_map_data:
            existing = name_map_data.get("unmapped", [])
            for n in unmapped_names:
                if n not in existing:
                    existing.append(n)
            name_map_data["unmapped"] = existing
            gh_put("data/player_name_map.json", name_map_data, name_map_sha,
                   f"bot: record unmapped players {md_key}", dry_run)

    print("\\n=== fetch_scores.py DONE ===")


if __name__ == "__main__":
    main()
