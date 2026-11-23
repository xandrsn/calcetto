#!/usr/bin/env python3
"""
daily_resolution.py — automatic card + points resolution (see SCORING.md).

Run order each morning (Madrid time; CI crons in .github/workflows/):
  1. fetch_scores.py     (~07:30) — fills goals/assists/RATING into the matchday
  2. daily_resolution.py (~08:25, the pre-prep buffer) — resolves cards and scores

Scoring (kept in sync with lib/utils/scoring.dart):
  team points = rating × RATING_BASE × ownership% × cardMult × captain
  bets        = pot (participants × 50) split among correct guessers
  quiniela    = 100 per correct 1-X-2 sign + 500 pleno bonus (all correct)

La Liga is a single league (no knockout rounds), resolved one **matchday** at a
time. Matchday files are `daily/md<NN>.json`. Resolving a matchday also mirrors
its scorelines into `data/league.json` (the table) and advances the
`current_matchday` pointer in `data/app_config.json`.

Usage:
    python scripts/daily_resolution.py [MATCHDAY_NUMBER] [--dry-run]

If the matchday number is omitted, resolves the `current_matchday` from
app_config.
"""

import os
import sys
import json
import base64
import math
import time
import random
import uuid
import argparse
from datetime import date, timedelta, datetime, timezone
from typing import Optional

import requests

# ── GitHub config ──────────────────────────────────────────────────────────
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

# ── Scoring config (see SCORING.md — keep in sync with lib/utils/scoring.dart) ─
# Team points = rating × RATING_BASE × ownership% × cardMult × captain.
RATING_BASE          = 18.0   # points per rating point
CAPTAIN_MULT         = 3.0    # captain's rating worth ×3 (matches the 300% preview)
BET_POT_CONTRIBUTION = 50.0   # each participant stakes 50 (not deducted)
QUINIELA_CORRECT_PTS = 100.0  # per correct 1-X-2 sign
QUINIELA_PLENO_BONUS = 500.0  # bonus for getting every fixture right
MAX_AUTO_SUBS        = 3
ACTIVITY_LOG_MAX     = 500
POSITIONS            = ["GK", "DEF", "MID", "FWD"]

ESTRENO_BONUS = 50            # flat bonus when a picked player scores their first

# Cards that target a rival (subject to the max-3-attacks-per-victim limit, and
# captain immunity for the ones that target a specific rival player).
ATTACK_CARD_TYPES = {
    "red_card", "yellow_card", "hacienda", "fiestero", "robo",
    "mordisco", "piscinazo", "el_var", "la_grada_pita",
    "multa", "iva", "recorte", "embargo",
}

# Casual flat-point cards (mirror flatPoints in lib/models/powerup_card.dart).
FLAT_SELF = {  # added to the owner's day total
    "calderilla": 5, "propina": 10, "plus": 15, "paga_extra": 20,
    "soborno": 25, "horas_extra": 30, "loteria": 50,
}
FLAT_RIVAL = {  # subtracted from a targeted rival's day total
    "multa": 10, "iva": 15, "recorte": 20, "embargo": 30,
}


def ownership_pct(n_selections: int, total_users: int) -> float:
    """Popularity curve (matches calculatePopularityPercent in Dart): fewer
    owners → higher share, floor 0.33, cap 1.0."""
    if n_selections <= 1 or total_users <= 0:
        return 1.0
    ratio = (n_selections - 1) / total_users
    return 0.33 + 0.67 * (1 - math.sqrt(min(1.0, ratio)))


# ── Card tables ────────────────────────────────────────────────────────────
# Card catalog — mirrors lib/models/powerup_card.dart (kCardCatalog).
# (type, weight, max_per_pack, exclusive_group). EXTRA_PLAYER caps steal +
# espontáneo at one per pack; sub_extra (FICHAJE EXTRA) may repeat.
EXTRA_PLAYER = "extra_player"
# (weight, max_per_pack, exclusive_group) — mirrors kCardCatalog in
# lib/models/powerup_card.dart. Strong effects are rare; casual flat-point cards
# are the common backbone.
CARD_RULES = {
    "red_card":       (7,  1, None),
    "yellow_card":    (14, 2, None),
    "hacienda":       (8,  1, None),
    "fiestero":       (12, 2, None),
    "robo":           (7,  1, EXTRA_PLAYER),
    "escudo":         (14, 2, None),
    "sub_extra":      (18, 5, None),
    "pitch_invader":  (7,  1, EXTRA_PLAYER),
    "hat_trick_hero": (12, 2, None),
    "estreno":        (8,  1, None),
    "catenaccio":     (8,  1, None),
    "tiki_taka":      (8,  1, None),
    "golden_glove":   (7,  1, None),
    "el_chiringuito": (4,  1, None),
    "retirada":       (2,  1, None),
    "tridente":       (8,  1, None),
    "francotirador":  (14, 2, None),
    "motivacion":     (4,  1, None),
    "muralla":        (8,  1, None),
    "prima":          (14, 2, None),
    "vitamina":       (10, 1, None),
    # Funny batch
    "piscinazo":      (14, 2, None),
    "mordisco":       (7,  1, None),
    "el_var":         (12, 2, None),
    "la_grada_pita":  (12, 2, None),
    "cerrojazo":      (6,  1, None),
    "primo_zumosol":  (8,  1, None),
    "mano_de_dios":   (2,  1, None),
    "chilena":        (8,  1, None),
    "siuuu":          (4,  1, None),
    "alcoyano":       (20, 2, None),
    "jeque":          (12, 2, None),
    # Casual flat-point batch
    "calderilla":     (24, 2, None),
    "propina":        (22, 2, None),
    "plus":           (20, 2, None),
    "paga_extra":     (18, 2, None),
    "soborno":        (14, 2, None),
    "horas_extra":    (12, 2, None),
    "loteria":        (8,  1, None),
    "multa":          (20, 2, None),
    "iva":            (18, 2, None),
    "recorte":        (12, 2, None),
    "embargo":        (10, 2, None),
}

CARD_RARITY = {
    "red_card": "rare", "yellow_card": "uncommon", "hacienda": "rare",
    "fiestero": "uncommon", "robo": "rare", "escudo": "uncommon",
    "sub_extra": "common", "pitch_invader": "rare", "hat_trick_hero": "uncommon",
    "estreno": "rare", "catenaccio": "rare", "tiki_taka": "rare",
    "golden_glove": "rare", "el_chiringuito": "epic", "retirada": "legendary",
    "tridente": "rare", "francotirador": "uncommon", "motivacion": "epic",
    "muralla": "rare", "prima": "uncommon", "vitamina": "uncommon",
    "piscinazo": "uncommon", "mordisco": "rare", "el_var": "uncommon",
    "la_grada_pita": "uncommon", "cerrojazo": "rare", "primo_zumosol": "rare",
    "mano_de_dios": "legendary", "chilena": "rare", "siuuu": "epic",
    "alcoyano": "common", "jeque": "uncommon",
    "calderilla": "common", "propina": "common", "plus": "common",
    "paga_extra": "common", "soborno": "uncommon", "horas_extra": "uncommon",
    "loteria": "rare", "multa": "common", "iva": "common",
    "recorte": "uncommon", "embargo": "uncommon",
}

CARD_VARIANTS = {
    "red_card":       ["Tarjeta Roja", "Expulsión Directa", "Doble Amarilla", "Patada por Detrás"],
    "yellow_card":    ["Tarjeta Amarilla", "Amonestación", "Protestas al Árbitro", "Simulación"],
    "hacienda":       ["Hacienda", "Gestha", "Inspección Fiscal", "El 1-J"],
    "fiestero":       ["Fiestero", "Noche de Ibiza", "Rumba Catalana", "Afterparty"],
    "robo":           ["Robo", "Topo en el Vestuario", "Tapping Up Ilegal", "Oferta de la Premier"],
    "escudo":         ["Escudo", "Abogados al Teléfono", "Cláusula Blindada", "Sin Comentarios"],
    "sub_extra":      ["Fichaje Extra", "Bono de Fichaje", "Refuerzo de Invierno"],
    "pitch_invader":  ["Espontáneo", "El 12º Hombre", "Hincha en el Campo"],
    "hat_trick_hero": ["Hat Trick Hero", "Noche Mágica", "En Estado de Gracia"],
    "estreno":        ["Estreno", "Primera Vez", "El Que Nadie Esperaba", "Despertó el Gigante"],
    "catenaccio":     ["Catenaccio", "El Muro", "Defensa Italiana"],
    "tiki_taka":      ["Tiki Taka", "La Pausa", "Juego de Posición", "Pep Mode"],
    "golden_glove":   ["Guante de Oro", "El Muro Bajo Palos", "Para Todo"],
    "el_chiringuito": ["El Chiringuito", "Tertulia a Gritos", "Debate Eterno", "Hasta las 2am"],
    "retirada":       ["Retirada", "Retirada MLS", "Retirada Saudi", "Lesión de Cruzados",
                       "Se Fue al Retiro", "Llamada de Inter Miami", "Adiós al Fútbol"],
    "tridente":       ["Tridente", "BBC", "MSN", "Galácticos"],
    "francotirador":  ["Francotirador", "El Elegido", "Punto de Mira"],
    "motivacion":     ["Motivación", "Charla del Míster", "Discurso Épico"],
    "muralla":        ["Muralla", "Cerrojo", "Autobús Aparcado"],
    "prima":          ["Prima", "Bonus", "Plus de Victoria"],
    "vitamina":       ["Vitamina", "Suplementos", "Energía Extra"],
    "piscinazo":      ["Piscinazo", "Clavado Olímpico", "Teatro en el Área"],
    "mordisco":       ["Mordisco", "Estilo Suárez", "A Dentelladas"],
    "el_var":         ["El VAR te Odia", "Revisión Eterna", "Sobaco Adelantado"],
    "la_grada_pita":  ["La Grada Pita", "Pitada Monumental", "Bronca en el Estadio"],
    "cerrojazo":      ["Cerrojazo", "Autobús de Dos Pisos", "Murallón"],
    "primo_zumosol":  ["El Primo de Zumosol", "El Primo Cachas", "Refuerzo de Gimnasio"],
    "mano_de_dios":   ["Mano de Dios", "La Zurda Divina", "El Línier No Vio Nada"],
    "chilena":        ["Chilena", "Tijera de Portada", "Acrobacia"],
    "siuuu":          ["Siuuu", "Salto y Giro", "540 Grados"],
    "alcoyano":       ["Alcoyano", "Más Moral que Nadie", "Nunca se Rinde"],
    "jeque":          ["Jeque Petrolero", "Dinero del Golfo", "Fondo Soberano"],
    "calderilla":     ["Calderilla", "Monedas del Sofá", "Suelto"],
    "propina":        ["Propina", "Caída del Cielo", "Detalle"],
    "plus":           ["Plus", "Plus de Productividad", "Incentivo"],
    "paga_extra":     ["Paga Extra", "Paga de Junio", "Doble Paga"],
    "soborno":        ["Soborno", "Sobre Bajo la Mesa", "No Preguntes"],
    "horas_extra":    ["Horas Extra", "Curro Nocturno", "Doblar Turno"],
    "loteria":        ["Lotería del Niño", "El Gordo", "Un Pellizco"],
    "multa":          ["Multa de Tráfico", "El Radar", "Pillado a 180"],
    "iva":            ["IVA", "Hacienda Somos Todos", "El 21%"],
    "recorte":        ["Recorte", "Recorte Presupuestario", "Tijeretazo"],
    "embargo":        ["Embargo", "Hasta las Botas", "El Desahucio"],
}


# ── GitHub helpers ─────────────────────────────────────────────────────────

def gh_get(path: str) -> tuple[Optional[dict], Optional[str]]:
    r = requests.get(f"{GH_API}/{path}", headers=GH_HEADERS, timeout=15)
    if r.status_code == 404:
        return None, None
    r.raise_for_status()
    j = r.json()
    raw = base64.b64decode(j["content"].replace("\n", "")).decode("utf-8")
    return json.loads(raw), j["sha"]


def gh_list_dir(path: str) -> list[dict]:
    r = requests.get(f"{GH_API}/{path}", headers=GH_HEADERS, timeout=15)
    if r.status_code == 404:
        return []
    r.raise_for_status()
    return r.json()


def gh_put(path: str, data: dict, sha: Optional[str], message: str, dry_run: bool = False):
    if dry_run:
        print(f"  [dry-run] SKIP write: {path}")
        return
    content = base64.b64encode(
        json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
    ).decode("ascii")
    payload: dict = {"message": message, "content": content}
    if sha:
        payload["sha"] = sha
    r = requests.put(f"{GH_API}/{path}", headers=GH_HEADERS, json=payload, timeout=15)
    r.raise_for_status()
    time.sleep(0.4)


# ── Helpers ────────────────────────────────────────────────────────────────

def flatten_pos_map(pos_map: dict) -> list[str]:
    result: list[str] = []
    for pos in POSITIONS:
        result.extend(pos_map.get(pos, []))
    return result


def generate_card_pack(n: int = 5) -> list[dict]:
    """Return n card dicts honoring weights + per-card max_per_pack + exclusive
    groups (mirrors generatePackTypes in Dart)."""
    types   = list(CARD_RULES.keys())
    weights = [CARD_RULES[t][0] for t in types]
    cards: list[dict] = []
    counts: dict[str, int] = {}
    used_groups: set[str] = set()
    guard = 0
    while len(cards) < n and guard < 2000:
        guard += 1
        card_type = random.choices(types, weights=weights, k=1)[0]
        _, max_per_pack, group = CARD_RULES[card_type]
        if counts.get(card_type, 0) >= max_per_pack:
            continue
        if group is not None and group in used_groups:
            continue
        counts[card_type] = counts.get(card_type, 0) + 1
        if group is not None:
            used_groups.add(group)
        cards.append({
            "id":        str(uuid.uuid4()),
            "type":      card_type,
            "variant":   random.choice(CARD_VARIANTS[card_type]),
            "rarity":    CARD_RARITY[card_type],
            "played":    False,
            "play_data": None,
        })
    return cards


def resolve_bets(bets: list[dict], users: dict[str, dict]) -> dict[str, float]:
    earnings: dict[str, float] = {u: 0.0 for u in users}
    for bet in bets:
        correct = bet.get("answer")
        if not correct:
            continue
        bet_id   = bet["id"]
        bettors: dict[str, str] = {}
        for username, ud in users.items():
            active_bets = ud.get("active", {}).get("bets", {})
            if bet_id in active_bets:
                bettors[username] = active_bets[bet_id]
        if not bettors:
            continue
        total_pot     = BET_POT_CONTRIBUTION * len(bettors)
        correct_users = [u for u, choice in bettors.items() if choice == correct]
        if not correct_users:
            continue
        per_winner = round(total_pot / len(correct_users), 2)
        for u in correct_users:
            earnings[u] = round(earnings[u] + per_winner, 2)
    return earnings


def make_event(event_type: str, username: str, description: str,
               matchday_date: str, extra: Optional[dict] = None) -> dict:
    return {
        "type":        event_type,
        "user":        username,
        "message":     description,
        "timestamp":   datetime.now(timezone.utc).isoformat(),
        "matchday":    matchday_date,
        **(extra or {}),
    }


# ── Main ───────────────────────────────────────────────────────────────────

def _sign(hs: int, aws: int) -> str:
    return "1" if hs > aws else ("2" if aws > hs else "X")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("matchday", nargs="?", type=int,
                        help="matchday number to resolve (default: current_matchday)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true",
                        help="resolve even if not every fixture is scored")
    args = parser.parse_args()
    dry_run = args.dry_run

    # Resolve which matchday: explicit arg, else the app_config pointer.
    app_config, app_config_sha = gh_get("data/app_config.json")
    app_config = app_config or {}
    md_num = args.matchday or int(app_config.get("current_matchday", 1))
    md_key = f"md{md_num:02d}"
    print(f"=== daily_resolution.py  matchday={md_num} ({md_key})  dry_run={dry_run} ===\n")

    # ── Step 1: Load state ─────────────────────────────────────────────────
    print("── Step 1: Load state ─────────────────────────────────────────────")

    daily_data, daily_sha = gh_get(f"daily/{md_key}.json")
    if daily_data is None:
        print(f"ERROR: daily/{md_key}.json not found — nothing to resolve")
        sys.exit(1)

    # captain_picks + events are keyed by the matchday's calendar date (matches
    # how the app writes captain_picks[daily.date]).
    md_date = daily_data.get("date", md_key)
    print(f"Matchday {md_num}  date: {md_date}  captain_mult: {CAPTAIN_MULT}x")

    # Build player stats from the matchday JSON. Team points are RATING-based:
    #   player_raw = rating × RATING_BASE  (before ownership/boosts).
    player_raw:          dict[str, float] = {}  # rating × base
    player_played:       set[str]         = set()
    player_goals_today:  dict[str, int]   = {}  # goals scored this matchday

    # Quiniela actual signs from each fixture's scoreline (postponed/unplayed
    # fixtures are simply omitted).
    actual_signs: dict[str, str] = {}
    match_scores: dict[str, tuple[int, int]] = {}  # fixtureId -> (home, away)

    for match in daily_data.get("matches", []):
        score = match.get("score")
        if isinstance(score, str) and "-" in score:
            try:
                hs, aws = (int(x.strip()) for x in score.split("-", 1))
                actual_signs[match.get("id", "")] = _sign(hs, aws)
                match_scores[match.get("id", "")] = (hs, aws)
            except ValueError:
                pass
        for mp in match.get("players", []):
            pid    = mp.get("id", "")
            rating = mp.get("rating")
            goals  = int(mp.get("goals", 0))
            if rating is not None:
                player_played.add(pid)
                player_raw[pid] = round(float(rating) * RATING_BASE, 2)
            player_goals_today[pid] = player_goals_today.get(pid, 0) + goals

    print(f"Players rated: {len(player_raw)}  played: {len(player_played)}  "
          f"fixtures scored: {len(actual_signs)}")

    # Completeness guard — points accumulate, so we resolve a matchday exactly
    # ONCE, only when every non-postponed fixture has a scoreline. This makes the
    # daily CI cron safe (it self-skips until the matchday is complete). --force
    # overrides for manual/partial runs.
    non_postponed = [m for m in daily_data.get("matches", []) if not m.get("postponed")]
    all_scored = bool(non_postponed) and all(
        isinstance(m.get("score"), str) and "-" in m.get("score", "")
        for m in non_postponed
    )
    if not all_scored and not args.force:
        print(f"Matchday {md_num} not complete "
              f"({len(actual_signs)}/{len(non_postponed)} fixtures scored) — "
              f"skipping. Use --force to resolve anyway.")
        return

    # Load players.json for positions + cumulative goals.
    players_data, players_sha = gh_get("data/players.json")
    player_positions:    dict[str, str]   = {}  # position string
    player_prior_goals:  dict[str, int]   = {}  # goals BEFORE today (cumulative - today)

    if players_data:
        for p in players_data.get("players", []):
            pid = p.get("id", "")
            player_positions[pid]   = p.get("position", "MID").upper()
            cumulative_goals = int(p.get("goals", 0))
            today_goals      = player_goals_today.get(pid, 0)
            player_prior_goals[pid] = max(0, cumulative_goals - today_goals)

    # Load all users
    user_files = [f for f in gh_list_dir("users") if f["name"].endswith(".json")]
    print(f"Loading {len(user_files)} user(s) …")

    users:      dict[str, dict] = {}
    user_shas:  dict[str, str]  = {}

    for f in user_files:
        username = f["name"].replace(".json", "")
        ud, sha  = gh_get(f"users/{f['name']}")
        if ud is not None:
            users[username]     = ud
            user_shas[username] = sha
            print(f"  Loaded: {username}")

    if not users:
        print("No users found — nothing to do")
        return

    # Dynamic ownership: how many users roster each player (squad + bench).
    total_users = len(users)
    ownership_count: dict[str, int] = {}
    for ud in users.values():
        owned = set(flatten_pos_map(ud.get("squad", {}))) | \
                set(flatten_pos_map(ud.get("bench", {})))
        for pid in owned:
            ownership_count[pid] = ownership_count.get(pid, 0) + 1

    # ── Step 2: Validate attacks ───────────────────────────────────────────
    print("\n── Step 2: Validate attacks ───────────────────────────────────────")

    # Collect all card plays across all users, sorted by timestamp
    all_plays: list[tuple[str, str, dict]] = []  # (timestamp, attacker, card_play)
    for username, ud in users.items():
        for cp in ud.get("active", {}).get("cards_played", []):
            ts = cp.get("timestamp", "")
            all_plays.append((ts, username, cp))
    all_plays.sort(key=lambda x: x[0])

    # Validate attacks: captain immunity + max 3 attacks per target_user
    attack_counts: dict[str, int] = {}  # {target_user: valid_attack_count}
    valid_plays:   list[tuple[str, str, dict]] = []

    for ts, attacker, cp in all_plays:
        card_type     = cp.get("type", "")
        target_user   = cp.get("target_user")
        target_player = cp.get("target_player")

        if card_type in ATTACK_CARD_TYPES and target_user:
            # Check captain immunity
            if target_player and target_user in users:
                target_captain = users[target_user].get("captain_picks", {}).get(md_date)
                if target_captain and target_player == target_captain:
                    print(f"  BLOCKED (captain): {attacker}'s {card_type} → {target_player} of {target_user}")
                    continue

            # Check attack limit
            count = attack_counts.get(target_user, 0)
            if count >= 3:
                print(f"  DISCARDED (limit): {attacker}'s {card_type} → {target_user} (already 3 attacks)")
                continue

            attack_counts[target_user] = count + 1

        valid_plays.append((ts, attacker, cp))

    print(f"  Valid plays: {len(valid_plays)} of {len(all_plays)} total")

    # ── Step 3: Resolve defense cards ─────────────────────────────────────
    print("\n── Step 3: Resolve defense (escudo) ──────────────────────────────")

    # user_shields[username] = set of player_ids their escudo (or cerrojazo)
    # protects from incoming attacks.
    user_shields: dict[str, set[str]] = {}
    for ts, attacker, cp in valid_plays:
        if cp.get("type") in ("escudo", "cerrojazo"):
            tp = cp.get("target_player")
            if tp:
                user_shields.setdefault(attacker, set()).add(tp)
                print(f"  SHIELD: {attacker} → {tp} ({cp.get('type')})")

    # ── Step 4: Resolve attack cards ──────────────────────────────────────
    print("\n── Step 4: Resolve attack cards ──────────────────────────────────")

    zero_pts_players: dict[str, set[str]]  = {}  # red_card/mordisco: {victim: {player_ids}}
    half_pts_players: dict[str, set[str]]  = {}  # yellow_card/piscinazo
    var_pts_players:  dict[str, set[str]]  = {}  # el_var: player x0.75
    hacienda_factors: dict[str, float]     = {}  # {victim: multiplicative factor (hacienda 0.8, grada 0.85)}
    flat_rival_hits:  dict[str, float]     = {}  # {victim: flat pts subtracted (multa/iva/recorte/embargo)}
    fiestero_bonuses: dict[str, float]     = {}  # {attacker: extra pts}
    robo_map:         dict[str, dict[str, str]] = {}  # {victim: {player_id: attacker}}

    for ts, attacker, cp in valid_plays:
        card_type     = cp.get("type", "")
        target_user   = cp.get("target_user")
        target_player = cp.get("target_player")

        if card_type in ("red_card", "mordisco") and target_player and target_user:
            shields = user_shields.get(target_user, set())
            if target_player not in shields:
                zero_pts_players.setdefault(target_user, set()).add(target_player)
                print(f"  {card_type.upper()}: {attacker} → {target_player} of {target_user} (0 pts)")

        elif card_type in ("yellow_card", "piscinazo") and target_player and target_user:
            shields = user_shields.get(target_user, set())
            if target_player not in shields:
                half_pts_players.setdefault(target_user, set()).add(target_player)
                print(f"  {card_type.upper()}: {attacker} → {target_player} of {target_user} (50% pts)")

        elif card_type == "el_var" and target_player and target_user:
            shields = user_shields.get(target_user, set())
            if target_player not in shields:
                var_pts_players.setdefault(target_user, set()).add(target_player)
                print(f"  EL VAR: {attacker} → {target_player} of {target_user} (75% pts)")

        elif card_type == "hacienda" and target_user:
            current = hacienda_factors.get(target_user, 1.0)
            hacienda_factors[target_user] = round(current * 0.80, 6)
            print(f"  HACIENDA: {attacker} → {target_user} (day total *0.8)")

        elif card_type == "la_grada_pita" and target_user:
            current = hacienda_factors.get(target_user, 1.0)
            hacienda_factors[target_user] = round(current * 0.85, 6)
            print(f"  LA GRADA PITA: {attacker} → {target_user} (day total *0.85)")

        elif card_type in FLAT_RIVAL and target_user:
            amount = FLAT_RIVAL[card_type]
            flat_rival_hits[target_user] = round(
                flat_rival_hits.get(target_user, 0.0) + amount, 2)
            print(f"  {card_type.upper()}: {attacker} → {target_user} (-{amount} pts)")

        elif card_type == "fiestero" and target_player and target_user:
            real = player_raw.get(target_player, 0.0)
            bonus = round(real * 0.5, 2)
            fiestero_bonuses[attacker] = round(fiestero_bonuses.get(attacker, 0.0) + bonus, 2)
            print(f"  FIESTERO: {attacker} copies {target_player} from {target_user}: +{bonus}")

        elif card_type == "robo" and target_player and target_user:
            shields = user_shields.get(target_user, set())
            if target_player not in shields:
                # First valid robo for this player wins
                if target_user not in robo_map or target_player not in robo_map[target_user]:
                    robo_map.setdefault(target_user, {})[target_player] = attacker
                    real = player_raw.get(target_player, 0.0)
                    print(f"  ROBO: {attacker} steals {target_player} from {target_user} ({real} pts)")

    # ── Step 5: Resolve boost cards ────────────────────────────────────────
    print("\n── Step 5: Resolve boost cards ───────────────────────────────────")

    hat_trick_map:     dict[str, set[str]] = {}  # {username: {player_ids}} x3 if scores
    siuuu_map:         dict[str, set[str]] = {}  # x4 if scores
    estreno_map:       dict[str, set[str]] = {}
    doubled_map:       dict[str, set[str]] = {}  # francotirador: player x2
    prima_map:         dict[str, set[str]] = {}  # prima: player x1.5
    alcoyano_map:      dict[str, set[str]] = {}  # alcoyano: player x1.3
    mano_map:          dict[str, set[str]] = {}  # mano_de_dios: player x3
    catenaccio_users:  set[str]            = set()  # DEF & GK x2
    tiki_taka_users:   set[str]            = set()  # MID x2
    golden_glove_users: set[str]           = set()  # GK x3
    muralla_users:     set[str]            = set()  # DEF & GK x1.5
    zumosol_users:     set[str]            = set()  # DEF & GK x1.75
    cerrojazo_users:   set[str]            = set()  # DEF & GK x2 (shield handled in Step 3)
    tridente_users:    set[str]            = set()  # FWD x2
    chilena_users:     set[str]            = set()  # FWD x1.5
    global_mult:       dict[str, float]    = {}     # motivacion/vitamina: whole XI
    flat_self_bonus:   dict[str, float]    = {}     # casual +N cards (calderilla…loteria)

    for ts, attacker, cp in valid_plays:
        card_type     = cp.get("type", "")
        target_player = cp.get("target_player")

        if card_type == "hat_trick_hero" and target_player:
            hat_trick_map.setdefault(attacker, set()).add(target_player)
        elif card_type == "siuuu" and target_player:
            siuuu_map.setdefault(attacker, set()).add(target_player)
        elif card_type == "francotirador" and target_player:
            doubled_map.setdefault(attacker, set()).add(target_player)
        elif card_type == "prima" and target_player:
            prima_map.setdefault(attacker, set()).add(target_player)
        elif card_type == "alcoyano" and target_player:
            alcoyano_map.setdefault(attacker, set()).add(target_player)
        elif card_type == "mano_de_dios" and target_player:
            mano_map.setdefault(attacker, set()).add(target_player)
        elif card_type == "estreno" and target_player:
            estreno_map.setdefault(attacker, set()).add(target_player)
        elif card_type == "catenaccio":
            catenaccio_users.add(attacker)
        elif card_type == "tiki_taka":
            tiki_taka_users.add(attacker)
        elif card_type == "golden_glove":
            golden_glove_users.add(attacker)
        elif card_type == "muralla":
            muralla_users.add(attacker)
        elif card_type == "primo_zumosol":
            zumosol_users.add(attacker)
        elif card_type == "cerrojazo":
            cerrojazo_users.add(attacker)
        elif card_type == "tridente":
            tridente_users.add(attacker)
        elif card_type == "chilena":
            chilena_users.add(attacker)
        elif card_type == "motivacion":
            global_mult[attacker] = global_mult.get(attacker, 1.0) * 1.3
        elif card_type == "vitamina":
            global_mult[attacker] = global_mult.get(attacker, 1.0) * 1.15
        elif card_type in FLAT_SELF:
            flat_self_bonus[attacker] = round(
                flat_self_bonus.get(attacker, 0.0) + FLAT_SELF[card_type], 2)

    # ── Step 6: Resolve pitch_invader ──────────────────────────────────────
    print("\n── Step 6: Resolve pitch_invader ─────────────────────────────────")

    # All players currently in any user's squad or bench
    all_rostered: set[str] = set()
    for ud in users.values():
        all_rostered.update(flatten_pos_map(ud.get("squad", {})))
        all_rostered.update(flatten_pos_map(ud.get("bench", {})))

    free_played = [pid for pid in player_played if pid not in all_rostered]

    pitch_invader_bonuses: dict[str, float] = {}

    for ts, attacker, cp in valid_plays:
        if cp.get("type") == "pitch_invader":
            if free_played:
                chosen = random.choice(free_played)
            elif list(player_played):
                # Fallback: least popular player who played
                chosen = min(player_played, key=lambda p: ownership_count.get(p, 0))
            else:
                chosen = None

            if chosen:
                real = player_raw.get(chosen, 0.0)
                pitch_invader_bonuses[attacker] = round(
                    pitch_invader_bonuses.get(attacker, 0.0) + real, 2)
                print(f"  PITCH INVADER: {attacker} gets {chosen} ({real} real pts)")

    # ── Squad scoring (rating × base × ownership × roundMult × cards × cap) ─
    print("\n── Squad scoring ─────────────────────────────────────────────────")

    result_squad_pts: dict[str, float] = {}
    result_card_pts:  dict[str, float] = {}
    result_subs:      dict[str, list]  = {}
    new_events:       list[dict]       = []

    for username, ud in users.items():
        squad_map  = ud.get("squad", {})
        bench_map  = ud.get("bench", {})
        # Use captain_picks for the target date, fall back to active.captain
        captain_id = ud.get("captain_picks", {}).get(md_date) or \
                     ud.get("active", {}).get("captain")

        robbed_from_me = set(robo_map.get(username, {}).keys())

        # Every fielded player scores: XI + bench. Only those with a rating (who
        # played) contribute; the rest are 0. Card extras (robo/espontáneo) are
        # added separately as bonuses (Steps 6–7) to avoid double-counting.
        effective_squad = list(dict.fromkeys(
            flatten_pos_map(squad_map) + flatten_pos_map(bench_map)
        ))
        subs_made: list[str] = []

        # ── Score each player ──────────────────────────────────────────────
        squad_pts  = 0.0
        card_bonus = 0.0

        for pid in effective_squad:
            # ── Step 7: Robo check — skip robbed players for victim ────────
            if pid in robbed_from_me:
                continue

            real = player_raw.get(pid, 0.0)

            # ── Step 4 effects on player (most punishing wins) ─────────────
            if pid in zero_pts_players.get(username, set()):
                real = 0.0
            elif pid in half_pts_players.get(username, set()):
                real = round(real * 0.5, 2)
            elif pid in var_pts_players.get(username, set()):
                real = round(real * 0.75, 2)

            # Ownership scaling (dynamic — fewer owners, higher share).
            pop = ownership_pct(ownership_count.get(pid, 1), total_users)
            pos = player_positions.get(pid, "MID")

            # ── Step 5: Boost multipliers (accumulate multiplicatively) ───
            multiplier = global_mult.get(username, 1.0)  # motivacion/vitamina
            if pos in ("DEF", "GK"):
                if username in catenaccio_users:
                    multiplier *= 2.0
                if username in cerrojazo_users:
                    multiplier *= 2.0
                if username in muralla_users:
                    multiplier *= 1.5
                if username in zumosol_users:
                    multiplier *= 1.75
            if username in tiki_taka_users and pos == "MID":
                multiplier *= 2.0
            if username in golden_glove_users and pos == "GK":
                multiplier *= 3.0
            if pos == "FWD":
                if username in tridente_users:
                    multiplier *= 2.0
                if username in chilena_users:
                    multiplier *= 1.5
            if pid in doubled_map.get(username, set()):
                multiplier *= 2.0
            if pid in prima_map.get(username, set()):
                multiplier *= 1.5
            if pid in alcoyano_map.get(username, set()):
                multiplier *= 1.3
            if pid in mano_map.get(username, set()):
                multiplier *= 3.0
            if pid in hat_trick_map.get(username, set()):
                if player_goals_today.get(pid, 0) > 0:
                    multiplier *= 3.0
            if pid in siuuu_map.get(username, set()):
                if player_goals_today.get(pid, 0) > 0:
                    multiplier *= 4.0

            # Estreno: flat bonus added to card_bonus
            if pid in estreno_map.get(username, set()):
                prior = player_prior_goals.get(pid, 0)
                if prior == 0 and player_goals_today.get(pid, 0) > 0:
                    estreno_pts = ESTRENO_BONUS
                    card_bonus = round(card_bonus + estreno_pts, 2)
                    new_events.append(make_event(
                        "card_played", username,
                        f"{username} activó Estreno — {pid} marcó por primera vez (+{estreno_pts} pts)",
                        md_date,
                    ))

            player_contribution = round(real * pop * multiplier, 2)

            # Captain multiplier (×3)
            if pid == captain_id:
                player_contribution = round(player_contribution * CAPTAIN_MULT, 2)

            squad_pts = round(squad_pts + player_contribution, 2)

        # ── Step 7: Robo attacker gains real points ───────────────────────
        for stolen_pid, attacker in robo_map.get(username, {}).items():
            real        = player_raw.get(stolen_pid, 0.0)
            # Attacker gains real points (no popularity)
            result_card_pts[attacker] = round(result_card_pts.get(attacker, 0.0) + real, 2)
            # Victim event (added once per victim, below)

        # Accumulate card bonuses for this user (fiestero copy + espontáneo +
        # casual flat self-bonuses like PROPINA/LOTERÍA).
        card_bonus = round(card_bonus
                           + fiestero_bonuses.get(username, 0.0)
                           + pitch_invader_bonuses.get(username, 0.0)
                           + flat_self_bonus.get(username, 0.0), 2)

        result_squad_pts[username] = squad_pts
        result_card_pts[username]  = round(result_card_pts.get(username, 0.0) + card_bonus, 2)
        result_subs[username]      = subs_made

        print(f"  {username:20s}  squad={squad_pts:.1f}  "
              f"cap={captain_id or 'none'}  subs={subs_made or []}")

    # ── Step 8: Fiestero bonuses already applied above ─────────────────────

    # ── Step 9: Hacienda + La Grada Pita (% of day) ────────────────────────
    print("\n── Step 9: Hacienda / La Grada Pita ──────────────────────────────")
    hacienda_deductions: dict[str, float] = {}
    for victim, factor in hacienda_factors.items():
        if victim not in users:
            continue
        subtotal = (result_squad_pts.get(victim, 0.0) +
                    result_card_pts.get(victim, 0.0))
        deduction = round(subtotal * (1.0 - factor), 2)
        hacienda_deductions[victim] = deduction
        result_card_pts[victim] = round(result_card_pts.get(victim, 0.0) - deduction, 2)
        print(f"  {victim} loses {deduction:.1f} pts (% factor {factor:.4f})")

    # ── Step 9b: Flat rival deductions (multa/iva/recorte/embargo) ─────────
    for victim, amount in flat_rival_hits.items():
        if victim not in users:
            continue
        result_card_pts[victim] = round(result_card_pts.get(victim, 0.0) - amount, 2)
        print(f"  {victim} loses {amount:.1f} pts (flat deduction)")

    # ── Bet resolution ─────────────────────────────────────────────────────
    print("\n── Bet resolution ────────────────────────────────────────────────")
    bet_earnings = resolve_bets(daily_data.get("bets", []), users)
    for username, earned in bet_earnings.items():
        if earned > 0:
            print(f"  {username:20s}  bets=+{earned:.1f}")

    # ── Step 10: El Chiringuito (leader↔last 25% redistribution) ───────────
    print("\n── Step 10: El Chiringuito ───────────────────────────────────────")
    ffp_transfers: dict[str, float] = {}

    ffp_active = any(cp.get("type") == "el_chiringuito" for _, _, cp in valid_plays)
    if ffp_active:
        day_totals_pre_ffp = {
            u: round(result_squad_pts.get(u, 0.0) +
                     result_card_pts.get(u, 0.0) +
                     bet_earnings.get(u, 0.0), 2)
            for u in users
        }
        sorted_users = sorted(users.keys(),
                               key=lambda u: day_totals_pre_ffp.get(u, 0.0),
                               reverse=True)
        n = len(sorted_users)
        for i in range(n // 2):
            top_u = sorted_users[i]
            bot_u = sorted_users[n - 1 - i]
            if top_u == bot_u:
                break
            transfer = round(day_totals_pre_ffp[top_u] * 0.25, 2)
            ffp_transfers[top_u] = round(ffp_transfers.get(top_u, 0.0) - transfer, 2)
            ffp_transfers[bot_u] = round(ffp_transfers.get(bot_u, 0.0) + transfer, 2)
            print(f"  FFP: {top_u} → {bot_u}: {transfer:.1f} pts")

        attacker_of_ffp = next(
            (a for _, a, cp in valid_plays if cp.get("type") == "el_chiringuito"), "")
        new_events.append(make_event(
            "card_played", attacker_of_ffp,
            "El Chiringuito — transferencia de puntos entre primero y último",
            md_date,
        ))

    # ── Step 11: Retirada ──────────────────────────────────────────────────
    print("\n── Step 11: Retirada ─────────────────────────────────────────────")
    retired_players: dict[str, str] = {}  # {player_id: attacker_username}

    for ts, attacker, cp in valid_plays:
        if cp.get("type") == "retirada":
            tp = cp.get("target_player")
            if tp and tp not in retired_players:
                retired_players[tp] = attacker
                print(f"  RETIRADA: {tp} (by {attacker})")
                new_events.append(make_event(
                    "card_played", attacker,
                    f"RETIRADA: {tp} — 0 puntos para siempre",
                    md_date,
                    extra={"player_id": tp},
                ))

    if retired_players and players_data and not dry_run:
        for p in players_data.get("players", []):
            if p.get("id") in retired_players:
                p["retired"]      = True
                p["retired_by"]   = retired_players[p["id"]]
                p["retired_date"] = md_date
        gh_put("data/players.json", players_data, players_sha,
               f"bot: retirada {md_date}", dry_run)
    elif retired_players and dry_run:
        print(f"  [dry-run] Would mark {list(retired_players.keys())} as retired")

    # ── Step 12: Sub Extra ─────────────────────────────────────────────────
    print("\n── Step 12: Sub Extra ────────────────────────────────────────────")
    sub_extra_users: set[str] = set()
    for ts, attacker, cp in valid_plays:
        if cp.get("type") in ("sub_extra", "jeque"):
            sub_extra_users.add(attacker)
            print(f"  {cp.get('type').upper()}: {attacker} +1 signing card")

    # ── Step 12b: Quiniela (1-X-2) grading ─────────────────────────────────
    print("\n── Step 12b: Quiniela ────────────────────────────────────────────")
    quiniela_pts: dict[str, float] = {}
    for username, ud in users.items():
        picks = ud.get("quiniela_prediction", {}).get("picks", {})
        if not actual_signs:
            quiniela_pts[username] = 0.0
            continue
        correct = sum(1 for fid, sign in actual_signs.items()
                      if picks.get(fid) == sign)
        pts_q = correct * QUINIELA_CORRECT_PTS
        if correct == len(actual_signs):
            pts_q += QUINIELA_PLENO_BONUS
        quiniela_pts[username] = round(pts_q, 2)
        if pts_q:
            print(f"  {username:20s}  quiniela=+{pts_q:.1f} ({correct}/{len(actual_signs)})")

    # ── Step 13: Calculate final matchday points ───────────────────────────
    print("\n── Step 13: Final matchday points ────────────────────────────────")

    result_day_pts: dict[str, float] = {}
    for username in users:
        sq  = result_squad_pts.get(username, 0.0)
        bet = bet_earnings.get(username, 0.0)
        card = result_card_pts.get(username, 0.0)
        ffp  = ffp_transfers.get(username, 0.0)
        quin = quiniela_pts.get(username, 0.0)
        day  = round(sq + bet + card + ffp + quin, 2)
        result_day_pts[username] = day

        desc = f"+{sq:.1f} squad"
        if bet  > 0:  desc += f"  +{bet:.1f} bets"
        if quin > 0:  desc += f"  +{quin:.1f} quiniela"
        if card > 0:  desc += f"  +{card:.1f} cartas"
        elif card < 0: desc += f"  {card:.1f} cartas"
        if ffp  != 0: desc += f"  {ffp:+.1f} FFP"

        new_events.append(make_event(
            "matchday_resolved", username,
            f"[J{md_num}] {desc}  TOTAL={day:.1f}",
            md_date,
            extra={"squad_pts": sq, "bet_pts": bet, "card_pts": card,
                   "quiniela_pts": quin, "ffp_delta": ffp, "day_total": day},
        ))
        print(f"  {username:20s}  squad={sq:.1f}  bets={bet:.1f}  "
              f"quiniela={quin:.1f}  card={card:.1f}  ffp={ffp:.1f}  day={day:+.1f}")

    # ── Step 14: Mirror scorelines into league.json + advance pointer ──────
    print("\n── Step 14: League table + matchday pointer ──────────────────────")

    if match_scores:
        league_data, league_sha = gh_get("data/league.json")
        if league_data and isinstance(league_data.get("matches"), list):
            by_id = {m["id"]: m for m in league_data["matches"]}
            for fid, (hs, aws) in match_scores.items():
                if fid in by_id:
                    by_id[fid]["hs"] = hs
                    by_id[fid]["as"] = aws
            gh_put("data/league.json", league_data, league_sha,
                   f"bot: league scores {md_key}", dry_run)
            print(f"  Mirrored {len(match_scores)} scoreline(s) into league.json")

    next_md = md_num + 1
    next_key = f"md{next_md:02d}"
    next_daily, _ = gh_get(f"daily/{next_key}.json")
    generate_next = next_daily is not None
    print(f"  Next matchday ({next_key}) {'found' if generate_next else 'not found'}; "
          f"all scored: {all_scored}")

    # ── Step 15: Write user files + reset active ───────────────────────────
    print("\n── Step 15: Write user files ─────────────────────────────────────")

    for username, ud in users.items():
        day_pts = result_day_pts[username]
        sq_pts  = result_squad_pts.get(username, 0.0)
        bet_pts = bet_earnings.get(username, 0.0)
        card_pts = result_card_pts.get(username, 0.0)
        quin_pts = quiniela_pts.get(username, 0.0)

        # Update points breakdown
        pts       = ud.setdefault("points", {})
        breakdown = pts.setdefault("breakdown", {})
        pts["total"]          = round(pts.get("total", 0.0) + day_pts, 2)
        breakdown["squad"]    = round(breakdown.get("squad", 0.0) + sq_pts,   2)
        breakdown["bets"]     = round(breakdown.get("bets",  0.0) + bet_pts,  2)
        breakdown["quiniela"] = round(breakdown.get("quiniela", 0.0) + quin_pts, 2)
        breakdown["cards"]    = round(breakdown.get("cards", 0.0) + card_pts, 2)
        breakdown.pop("bracket", None)  # remove legacy WC key
        breakdown.pop("steals", None)   # remove legacy key

        # FICHAJE EXTRA — grants a signing card (extra transfer), not a sub.
        if username in sub_extra_users:
            ud["signing_cards_available"] = ud.get("signing_cards_available", 0) + 1

        # Generate the next matchday's card pack (or empty if none scheduled).
        next_cards = generate_card_pack(5) if generate_next else []

        # Reset active state
        ud["active"] = {
            "captain":               None,
            "bets":                  {},
            "cards_received":        next_cards,
            "cards_played":          [],
            "attacks_received_today": 0,
        }

        sha = user_shas[username]
        gh_put(f"users/{username}.json", ud, sha,
               f"bot: resolve {md_key} ({day_pts:+.1f} pts)", dry_run)
        print(f"  {username:20s}  day={day_pts:+.1f}  total={pts['total']:.1f}")

    # Advance the current_matchday pointer once every fixture is scored.
    if all_scored:
        app_config["current_matchday"] = next_md
        gh_put("data/app_config.json", app_config, app_config_sha,
               f"bot: advance to matchday {next_md}", dry_run)
        print(f"  current_matchday → {next_md}")

    # ── Step 16: Append to activity log ───────────────────────────────────
    print("\n── Step 16: Activity log ─────────────────────────────────────────")

    log_data, log_sha = gh_get("data/activity_log.json")
    if log_data is None:
        log_data = {"events": []}

    events: list[dict] = log_data.get("events", [])
    events = new_events + events
    events = events[:ACTIVITY_LOG_MAX]
    log_data["events"] = events

    gh_put("data/activity_log.json", log_data, log_sha,
           f"bot: activity log {md_key}", dry_run)
    print(f"  Wrote {len(new_events)} new event(s) (log total: {len(events)})")

    # ── Step 17: Done ──────────────────────────────────────────────────────
    print(f"\n=== daily_resolution.py DONE — {md_key} ===")


if __name__ == "__main__":
    main()
