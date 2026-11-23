#!/usr/bin/env python3
"""
Find free-licence photos for players via Wikidata -> Wikimedia Commons.

Only images whose Commons licence is Creative Commons or public domain are
used; the author and licence are recorded for attribution. The app then loads
the image at runtime from Wikimedia (hot-linked, never bundled or re-hosted).

Two steps, so the network part stays separate from the data repo:

  1) Lookup (no token needed). Reads a local copy of data/players.json:
       python scripts/fetch_player_photos.py --players players.json \
           --out photos.json [--limit N]
     Writes photos.json = {"players": {id: url}, "attribution": {id: {...}}}.
     Players with no unambiguous, free-licence match are left out.

  2) Push (needs GITHUB_TOKEN). Merges the found URLs into
     images/players/manifest.json (existing uploads are kept) and writes
     images/players/attribution.json:
       GITHUB_TOKEN=... python scripts/fetch_player_photos.py --push photos.json

The app treats a manifest value starting with "http" as an external image URL
(see lib/widgets/player_avatar.dart) and falls back to the pixel sprite.
"""

import argparse
import base64
import html
import json
import os
import re
import sys
import time
import unicodedata

import requests

WD_API = "https://www.wikidata.org/w/api.php"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
# Wikimedia asks for an identifying User-Agent; keep it generic.
HEADERS = {"User-Agent": "CalcettoPlayerPhotos/1.0 (private fantasy-league app; batch lookup)"}

Q_FOOTBALLER = "Q937857"  # association football player (occupation)
P_OCCUPATION = "P106"
P_IMAGE = "P18"
PHOTO_WIDTH = 256
MANIFEST_PATH = "images/players/manifest.json"
ATTRIBUTION_PATH = "images/players/attribution.json"
GH_API = "https://api.github.com/repos/{owner}/{repo}/contents"


def _fold(s: str) -> str:
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z ]", "", s.lower()).strip()


def _get(url, params):
    """GET JSON with polite pacing and backoff on 429/5xx (Wikimedia rate limits)."""
    for attempt in range(5):
        time.sleep(1.0)
        r = requests.get(url, params=params, headers=HEADERS, timeout=20)
        if r.status_code not in (429, 500, 502, 503):
            r.raise_for_status()
            return r.json()
        wait = float(r.headers.get("Retry-After", 0) or 0) or 10.0 * (attempt + 1)
        print(f"  HTTP {r.status_code} from {url.split('/')[2]}, waiting {wait:.0f}s")
        time.sleep(wait)
    raise requests.HTTPError(f"still rate-limited after retries: {url}")


def search_entities(name):
    data = _get(WD_API, {
        "action": "wbsearchentities", "search": name, "language": "en",
        "type": "item", "limit": 5, "format": "json",
    })
    return [h["id"] for h in data.get("search", [])]


def get_entity(qid):
    data = _get(WD_API, {
        "action": "wbgetentities", "ids": qid, "props": "claims|labels|aliases",
        "languages": "en", "format": "json",
    })
    return data.get("entities", {}).get(qid, {})


def _claim_ids(entity, prop):
    out = []
    for c in entity.get("claims", {}).get(prop, []):
        v = c.get("mainsnak", {}).get("datavalue", {}).get("value")
        if isinstance(v, dict) and "id" in v:
            out.append(v["id"])
    return out


def _names(entity):
    names = set()
    label = entity.get("labels", {}).get("en", {}).get("value")
    if label:
        names.add(_fold(label))
    for a in entity.get("aliases", {}).get("en", []):
        names.add(_fold(a["value"]))
    return names


def commons_licence(filename):
    """(ok, info) — ok only for CC or public-domain licences."""
    data = _get(COMMONS_API, {
        "action": "query", "titles": "File:" + filename, "prop": "imageinfo",
        "iiprop": "extmetadata", "format": "json",
    })
    pages = data.get("query", {}).get("pages", {})
    page = next(iter(pages.values()), {})
    meta = (page.get("imageinfo") or [{}])[0].get("extmetadata", {})
    short = meta.get("LicenseShortName", {}).get("value", "")
    free = short.startswith("CC") or "Public domain" in short
    artist = re.sub(r"<[^>]+>", "", meta.get("Artist", {}).get("value", "")).strip()
    return free, {"author": html.unescape(artist) or "unknown", "licence": short}


def find_photo(name):
    """A single, unambiguous footballer with a free-licence image, or None."""
    wanted = _fold(name)
    hits = []
    for qid in search_entities(name):
        ent = get_entity(qid)
        if Q_FOOTBALLER not in _claim_ids(ent, P_OCCUPATION):
            continue
        if wanted not in _names(ent):
            continue
        images = [c["mainsnak"]["datavalue"]["value"]
                  for c in ent.get("claims", {}).get(P_IMAGE, [])
                  if c.get("mainsnak", {}).get("datavalue")]
        if images:
            hits.append((qid, images[0]))
    if len(hits) != 1:  # none, or ambiguous: do not guess
        return None
    _, filename = hits[0]
    free, info = commons_licence(filename)
    if not free:
        return None
    url = (f"https://commons.wikimedia.org/wiki/Special:FilePath/"
           f"{requests.utils.quote(filename)}?width={PHOTO_WIDTH}")
    info["file_page"] = "https://commons.wikimedia.org/wiki/File:" + requests.utils.quote(filename)
    return url, info


def lookup(players_path, out_path, limit):
    with open(players_path, encoding="utf-8") as f:
        raw = json.load(f)
    players = raw.get("players", raw) if isinstance(raw, dict) else raw
    if limit:
        players = players[:limit]
    result = {"players": {}, "attribution": {}}
    for i, p in enumerate(players, 1):
        try:
            found = find_photo(p["name"])
        except requests.RequestException as exc:
            print(f"  skipped {p['name']}: {exc}")
            found = None
        if found:
            url, info = found
            result["players"][p["id"]] = url
            result["attribution"][p["id"]] = info
        print(f"[{i}/{len(players)}] {p['name']}: {'found' if found else '-'}")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f"{len(result['players'])} of {len(players)} matched -> {out_path}")


def _gh(owner, repo):
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        sys.exit("ERROR: GITHUB_TOKEN env var not set (needed only for --push).")
    headers = {"Authorization": f"token {token}", "Accept": "application/vnd.github.v3+json"}
    base = GH_API.format(owner=owner, repo=repo)

    def read(path):
        r = requests.get(f"{base}/{path}", headers=headers, timeout=20)
        if r.status_code == 404:
            return None, None
        r.raise_for_status()
        j = r.json()
        return json.loads(base64.b64decode(j["content"]).decode("utf-8")), j["sha"]

    def write(path, data, sha, message):
        body = {"message": message,
                "content": base64.b64encode(json.dumps(data, ensure_ascii=False, indent=2).encode()).decode()}
        if sha:
            body["sha"] = sha
        requests.put(f"{base}/{path}", headers=headers, json=body, timeout=20).raise_for_status()

    return read, write


def push(photos_path, owner, repo):
    with open(photos_path, encoding="utf-8") as f:
        found = json.load(f)
    read, write = _gh(owner, repo)
    manifest, msha = read(MANIFEST_PATH)
    manifest = manifest or {"players": {}}
    manifest["players"].update(found["players"])
    write(MANIFEST_PATH, manifest, msha, "script: free-licence player photos (Wikimedia Commons)")
    attr, ash = read(ATTRIBUTION_PATH)
    attr = attr or {}
    attr.update(found["attribution"])
    write(ATTRIBUTION_PATH, attr, ash, "script: photo attribution")
    print(f"pushed {len(found['players'])} photo URLs")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--players", help="local copy of data/players.json")
    ap.add_argument("--out", default="photos.json")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--push", metavar="PHOTOS_JSON")
    ap.add_argument("--data-repo", metavar="OWNER/REPO",
                    help="private data repo, required with --push")
    args = ap.parse_args()
    if args.push:
        if not args.data_repo or "/" not in args.data_repo:
            ap.error("--push needs --data-repo OWNER/REPO")
        owner, repo = args.data_repo.split("/", 1)
        push(args.push, owner, repo)
    elif args.players:
        lookup(args.players, args.out, args.limit)
    else:
        ap.error("use --players FILE (lookup) or --push PHOTOS_JSON")


if __name__ == "__main__":
    main()
