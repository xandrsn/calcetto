#!/usr/bin/env python3
"""Hard reset to a clean pre-tournament state — keeps the real DATA (players,
fixtures, bet questions) but wipes all RESULTS and progress:

  * daily/*.json   : clear every match score, player goals/assists/ratings/points
                     and bet answers (fixtures + bet questions kept)
  * data/players.json : goals/assists/total_points/points_per_match → 0, un-retire
  * users/*.json   : points → 0, empty squad/bench, clean active, no cards/bets/
                     predictions/captain/signings (account kept — no re-register)
  * data/league.json : deleted (app rebuilds the empty default)
  * data/app_config.json : clock_override cleared, current_matchday → 1
  * data/activity_log.json + chat.json : emptied

Usage:  GITHUB_TOKEN=... python scripts/reset_all.py [--dry-run]
"""
import base64
import json
import os
import subprocess
import sys
import tempfile

API = "https://api.github.com/repos/your-github-user/your-data-repo/contents"
TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
DRY = "--dry-run" in sys.argv


# All GitHub I/O via curl — urllib IncompleteRead's on the large players.json in
# this environment, curl is reliable.
def _curl(method, path, accept, body_path=None):
    cmd = ["curl", "-s", "-X", method, f"{API}/{path}",
           "-H", f"Authorization: Bearer {TOKEN}", "-H", f"Accept: {accept}"]
    if body_path:
        cmd += ["--data-binary", f"@{body_path}"]
    out = subprocess.run(cmd, capture_output=True).stdout
    return out


def get_json(path):
    out = _curl("GET", path, "application/vnd.github.raw")
    txt = out.decode("utf-8")
    if txt.startswith('{"message":"Not Found"'):
        return None
    return json.loads(txt)


def sha(path):
    out = _curl("GET", path, "application/vnd.github+json").decode("utf-8")
    j = json.loads(out)
    return j.get("sha") if isinstance(j, dict) else None


def listdir(path):
    out = _curl("GET", path, "application/vnd.github+json").decode("utf-8")
    j = json.loads(out)
    return j if isinstance(j, list) else []


def _put_body(payload):
    fd, tmp = tempfile.mkstemp(suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)
    return tmp


def put(path, data, msg):
    if DRY:
        print(f"  [dry] write {path}")
        return
    body = {"message": msg,
            "content": base64.b64encode(
                json.dumps(data, ensure_ascii=False, indent=2).encode()).decode()}
    s = sha(path)
    if s:
        body["sha"] = s
    tmp = _put_body(body)
    try:
        _curl("PUT", path, "application/vnd.github+json", body_path=tmp)
    finally:
        os.remove(tmp)


def delete(path, msg):
    s = sha(path)
    if not s:
        return
    if DRY:
        print(f"  [dry] delete {path}")
        return
    tmp = _put_body({"message": msg, "sha": s})
    try:
        _curl("DELETE", path, "application/vnd.github+json", body_path=tmp)
    finally:
        os.remove(tmp)


def main():
    if not TOKEN:
        sys.exit("Set GITHUB_TOKEN")

    # 1) Clear daily results (keep fixtures + bet questions).
    for f in listdir("daily"):
        if not f["name"].endswith(".json"):
            continue
        d = get_json(f"daily/{f['name']}")
        if not d:
            continue
        for m in d.get("matches", []):
            m["score"] = None
            for p in m.get("players", []):
                p["goals"] = 0
                p["assists"] = 0
                p["points"] = 0
                p.pop("rating", None)
        for b in d.get("bets", []):
            b["answer"] = None
        put(f"daily/{f['name']}", d, f"reset: clear results {f['name']}")
        print(f"  cleared daily/{f['name']}")

    # 2) Zero player cumulative stats.
    players = get_json("data/players.json")
    if players:
        for p in players.get("players", []):
            p["goals"] = 0
            p["assists"] = 0
            p["total_points"] = 0
            p["points_per_match"] = {}
            p["retired"] = False
            p.pop("retired_by", None)
            p.pop("retired_date", None)
        put("data/players.json", players, "reset: zero player stats")
        print("  zeroed player stats")

    # 3) Reset users to a clean slate (keep the account).
    empty_pos = {"GK": [], "DEF": [], "MID": [], "FWD": []}
    for f in listdir("users"):
        if not f["name"].endswith(".json"):
            continue
        u = get_json(f"users/{f['name']}")
        if not u:
            continue
        u["squad"] = dict(empty_pos)
        u["bench"] = dict(empty_pos)
        u["formation"] = "4-3-3"
        u["subs_used_this_round"] = 0
        u["captain_picks"] = {}
        u["quiniela_prediction"] = {"picks": {}}
        u.pop("bracket_prediction", None)  # drop legacy WC key
        u["golden_boot"] = None
        u["top_assister"] = None
        u["points"] = {"total": 0.0, "breakdown": {
            "squad": 0.0, "bets": 0.0, "quiniela": 0.0,
            "golden_boot": 0.0, "steals": 0.0, "cards": 0.0}}
        u["active"] = {"captain": None, "bets": {}, "cards_received": [],
                       "cards_played": [], "attacks_received_today": 0}
        u["signing_cards_available"] = 0
        u["signing_cards_used"] = []
        u["extra_subs_available"] = 0
        put(f"users/{f['name']}", u, f"reset: clean user {f['name']}")
        print(f"  reset user {f['name']}")

    # 4) League → default; clock → real time; matchday → 1; feeds emptied.
    delete("data/league.json", "reset: drop league (rebuild default)")
    print("  deleted league.json")
    cfg = get_json("data/app_config.json") or {}
    cfg["clock_override"] = None
    cfg["current_matchday"] = 1
    put("data/app_config.json", cfg, "reset: clock to real time, matchday 1")
    print("  cleared clock_override, current_matchday → 1")
    put("data/activity_log.json", {"events": []}, "reset: clear activity log")
    put("chat.json", {"messages": []}, "reset: clear chat")
    print("  cleared activity log + chat")
    print("\nDone — clean slate (players + fixtures kept)." if not DRY
          else "\n[dry-run] nothing written.")


if __name__ == "__main__":
    main()
