#!/usr/bin/env python3
"""Bulk-upload player photos to the data hub (mirror of seed_card_images.py).

Drop photos in scripts/player_images/<playerId>.<jpg|jpeg|png> (the id is the
player's id in data/players.json, e.g. messi_lionel.jpg) and run this to
compress + upload them all and update the manifest — instead of uploading one
by one in the admin Player Images screen.

Layout written (matches lib/services/player_images.dart):
    images/players/<id>.jpg        — compressed bytes (≤256px, JPEG q85)
    images/players/manifest.json   — { "players": { "<id>": "<version>" } }

Usage:
    GITHUB_TOKEN=... python scripts/seed_player_images.py            # dry run
    GITHUB_TOKEN=... python scripts/seed_player_images.py --push     # upload
"""
import base64
import io
import json
import os
import sys
import time
import urllib.request

from PIL import Image

OWNER, REPO = "your-github-user", "your-data-repo"
API = f"https://api.github.com/repos/{OWNER}/{REPO}/contents"
MANIFEST = "images/players/manifest.json"
DROP_DIR = os.path.join(os.path.dirname(__file__), "player_images")
EXTS = (".jpg", ".jpeg", ".png", ".webp")


def compress(path: str) -> bytes:
    """Downscale to ≤256px on the long edge, re-encode JPEG q85 (as the app does)."""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    if max(w, h) > 256:
        if w >= h:
            im = im.resize((256, round(h * 256 / w)))
        else:
            im = im.resize((round(w * 256 / h), 256))
    buf = io.BytesIO()
    im.save(buf, format="JPEG", quality=85)
    return buf.getvalue()


def gh(method, path, body=None):
    req = urllib.request.Request(
        f"{API}/{path}", data=body, method=method,
        headers={"Authorization": f"Bearer {TOKEN}",
                 "Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def gh_raw_json(path):
    req = urllib.request.Request(
        f"{API}/{path}", headers={"Authorization": f"Bearer {TOKEN}",
                                  "Accept": "application/vnd.github.raw"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def put_file(path, raw, message, b64_is_text=False):
    meta = gh("GET", path)
    payload = {"message": message,
               "content": base64.b64encode(raw).decode("ascii")}
    if meta:
        payload["sha"] = meta["sha"]
    gh("PUT", path, json.dumps(payload).encode())


if __name__ == "__main__":
    TOKEN = os.environ.get("GITHUB_TOKEN", "")
    push = "--push" in sys.argv
    if push and not TOKEN:
        sys.exit("Set GITHUB_TOKEN to push")

    if not os.path.isdir(DROP_DIR):
        os.makedirs(DROP_DIR, exist_ok=True)
    drops = {}  # id -> path
    for f in sorted(os.listdir(DROP_DIR)):
        stem, ext = os.path.splitext(f)
        if ext.lower() in EXTS:
            drops[stem] = os.path.join(DROP_DIR, f)
    if not drops:
        print(f"No images in {DROP_DIR}/ — drop <playerId>.jpg files there.")
        sys.exit(0)

    # Validate ids against the live player pool (warn only).
    if TOKEN:
        pdata = gh_raw_json("data/players.json")
        known = {p["id"] for p in (pdata or {}).get("players", [])}
        for pid in drops:
            if known and pid not in known:
                print(f"  WARNING: '{pid}' not found in players.json")

    print(f"{len(drops)} image(s) to upload:")
    for pid in drops:
        print(f"  {pid}")
    if not push:
        print("\nDry run. Re-run with --push to upload.")
        sys.exit(0)

    version = str(int(time.time()))
    manifest = gh_raw_json(MANIFEST) or {"players": {}}
    players = manifest.setdefault("players", {})
    for pid, path in drops.items():
        raw = compress(path)
        put_file(f"images/players/{pid}.jpg", raw, f"images: player {pid}")
        players[pid] = version
        print(f"  uploaded {pid}.jpg ({len(raw)} bytes)")

    put_file(MANIFEST,
             json.dumps(manifest, ensure_ascii=False, indent=2).encode("utf-8"),
             "images: player manifest")
    print(f"Pushed {len(drops)} player image(s) + manifest.")
