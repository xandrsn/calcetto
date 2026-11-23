#!/usr/bin/env python3
"""Generate + upload default power-up card images to the data hub.

POC placeholders so each card type has an image on the hub keyed by its type id
(the user will replace them with nicer art later). Mirrors the player-image
layout:
    images/cards/<typeId>.png
    images/cards/manifest.json   -> { "cards": { "<typeId>": "<version>" } }

Usage:
    GITHUB_TOKEN=... python scripts/seed_card_images.py            # write PNGs to build/cards/
    GITHUB_TOKEN=... python scripts/seed_card_images.py --push     # also upload to the repo
"""
import base64
import io
import json
import os
import re
import shutil
import sys
import time
import urllib.request

from PIL import Image, ImageDraw, ImageFont

OWNER = "your-github-user"
REPO = "your-data-repo"
API = f"https://api.github.com/repos/{OWNER}/{REPO}/contents"
FONT = os.path.join(os.path.dirname(__file__), "..", "assets", "fonts",
                    "ChakraPetch-Bold.ttf")

BG = (26, 26, 46)
WHITE = (242, 242, 244)
CAT_COLOR = {
    "attack": (225, 112, 85),
    "defense": (83, 52, 131),
    "boost": (0, 184, 148),
    "utility": (253, 203, 110),
}
RARITY_COLOR = {
    "common": (154, 160, 181),
    "uncommon": (46, 204, 113),
    "rare": (52, 152, 219),
    "epic": (155, 89, 182),
    "legendary": (241, 196, 15),
}

# (typeId, NAME, short effect, category, rarity) — mirrors kCardCatalog.
CARDS = [
    ("red_card", "TARJETA ROJA", "0 PTS", "attack", "rare"),
    ("yellow_card", "TARJETA AMARILLA", "50%", "attack", "uncommon"),
    ("hacienda", "HACIENDA", "-20%", "attack", "rare"),
    ("fiestero", "FIESTERO", "+50%", "boost", "uncommon"),
    ("robo", "ROBO", "ROBO", "attack", "rare"),
    ("escudo", "ESCUDO", "INMUNE", "defense", "uncommon"),
    ("sub_extra", "FICHAJE EXTRA", "+1 FICHAJE", "utility", "common"),
    ("pitch_invader", "ESPONTANEO", "+1 JUGADOR", "attack", "rare"),
    ("hat_trick_hero", "HAT TRICK HERO", "x3", "boost", "uncommon"),
    ("estreno", "ESTRENO", "BONUS", "boost", "rare"),
    ("catenaccio", "CATENACCIO", "DEF x2", "defense", "rare"),
    ("tiki_taka", "TIKI-TAKA", "MED x2", "boost", "rare"),
    ("golden_glove", "GUANTE DE ORO", "POR x3", "defense", "rare"),
    ("el_chiringuito", "EL CHIRINGUITO", "FFP", "attack", "epic"),
    ("retirada", "RETIRADA", "RETIRO", "attack", "legendary"),
    ("tridente", "TRIDENTE", "DEL x2", "boost", "rare"),
    ("francotirador", "FRANCOTIRADOR", "x2", "boost", "uncommon"),
    ("motivacion", "MOTIVACION", "+30%", "boost", "epic"),
    ("muralla", "MURALLA", "DEF +50%", "defense", "rare"),
    ("prima", "PRIMA", "+50%", "boost", "uncommon"),
    ("vitamina", "VITAMINA", "+15%", "boost", "uncommon"),
    ("piscinazo", "PISCINAZO", "50%", "attack", "uncommon"),
    ("mordisco", "MORDISCO", "0 PTS", "attack", "rare"),
    ("el_var", "EL VAR TE ODIA", "-25%", "attack", "uncommon"),
    ("la_grada_pita", "LA GRADA PITA", "-15%", "attack", "uncommon"),
    ("cerrojazo", "CERROJAZO", "DEF x2", "defense", "rare"),
    ("primo_zumosol", "EL PRIMO DE ZUMOSOL", "DEF +75%", "defense", "rare"),
    ("mano_de_dios", "MANO DE DIOS", "x3", "boost", "legendary"),
    ("chilena", "CHILENA", "DEL +50%", "boost", "rare"),
    ("siuuu", "SIUUUU", "x4", "boost", "epic"),
    ("alcoyano", "ALCOYANO", "+30%", "boost", "common"),
    ("jeque", "JEQUE PETROLERO", "+1 FICHAJE", "utility", "uncommon"),
    ("calderilla", "CALDERILLA", "+5", "boost", "common"),
    ("propina", "PROPINA", "+10", "boost", "common"),
    ("plus", "PLUS", "+15", "boost", "common"),
    ("paga_extra", "PAGA EXTRA", "+20", "boost", "common"),
    ("soborno", "SOBORNO", "+25", "boost", "uncommon"),
    ("horas_extra", "HORAS EXTRA", "+30", "boost", "uncommon"),
    ("loteria", "LOTERIA DEL NINO", "+50", "boost", "rare"),
    ("multa", "MULTA DE TRAFICO", "-10", "attack", "common"),
    ("iva", "IVA", "-15", "attack", "common"),
    ("recorte", "RECORTE", "-20", "attack", "uncommon"),
    ("embargo", "EMBARGO", "-30", "attack", "uncommon"),
]

# Drop real artwork here as "<typeId>.png" (same id as in the card catalog,
# e.g. red_card.png) and re-run with --push; it's uploaded as-is instead of the
# generated placeholder. Keeps custom art out of the generated set.
DROP_DIR = os.path.join(os.path.dirname(__file__), "card_images")

# Square, full-bleed art tile. The app (PixelCardWidget) already draws the
# frame, rarity band, name and value badge around this, so the image is JUST the
# artwork: a category gradient + the card's real Material icon. Drop a custom
# PNG in scripts/card_images/<id>.png to override any of these.
S = 400


def font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except Exception:
        return ImageFont.load_default()


def _flutter_icons_dart():
    flutter = shutil.which("flutter") or shutil.which("flutter.bat")
    if not flutter:
        return None
    root = os.path.dirname(os.path.dirname(os.path.realpath(flutter)))
    p = os.path.join(root, "packages", "flutter", "lib", "src", "material", "icons.dart")
    return p if os.path.isfile(p) else None


def _material_font_path():
    flutter = shutil.which("flutter") or shutil.which("flutter.bat")
    if not flutter:
        return None
    root = os.path.dirname(os.path.dirname(os.path.realpath(flutter)))
    p = os.path.join(root, "bin", "cache", "artifacts", "material_fonts",
                     "MaterialIcons-Regular.otf")
    return p if os.path.isfile(p) else None


def load_codepoints():
    """name -> codepoint int, parsed from the Flutter SDK's icons.dart."""
    path = _flutter_icons_dart()
    if not path:
        return {}
    txt = open(path, encoding="utf-8").read()
    out = {}
    for name, hexcp in re.findall(
            r"IconData\s+(\w+)\s*=\s*IconData\(0x([0-9a-fA-F]+)", txt):
        out[name] = int(hexcp, 16)
    return out


def load_icon_names():
    """card id -> Material icon identifier, parsed from kCardCatalog."""
    path = os.path.join(os.path.dirname(__file__), "..", "lib", "models",
                        "powerup_card.dart")
    txt = open(path, encoding="utf-8").read()
    out, cur = {}, None
    for m in re.finditer(r"id:\s*'([a-z_]+)'|icon:\s*Icons\.(\w+)", txt):
        if m.group(1):
            cur = m.group(1)
        elif cur and m.group(2):
            out[cur] = m.group(2)
            cur = None
    return out


def _lerp(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def render(type_id, category, rarity, icon_cp, icon_font):
    color = CAT_COLOR[category]
    rcolor = RARITY_COLOR.get(rarity, (154, 160, 181))
    top = _lerp(color, WHITE, 0.18)
    bottom = _lerp(color, BG, 0.62)
    im = Image.new("RGB", (S, S), BG)
    d = ImageDraw.Draw(im)
    # Vertical category gradient.
    for y in range(S):
        d.line([(0, y), (S, y)], fill=_lerp(top, bottom, y / (S - 1)))
    # Soft rarity glow disc behind the icon.
    cx = cy = S / 2
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gr = S * 0.34
    gd.ellipse([cx - gr, cy - gr, cx + gr, cy + gr], fill=rcolor + (60,))
    im = Image.alpha_composite(im.convert("RGBA"), glow).convert("RGB")
    d = ImageDraw.Draw(im)
    # The card's real Material icon (with a soft drop shadow), or a coloured disc.
    if icon_cp and icon_font:
        glyph = chr(icon_cp)
        f = ImageFont.truetype(icon_font, int(S * 0.5))
        l, t, r, b = d.textbbox((0, 0), glyph, font=f)
        gx, gy = cx - (r - l) / 2 - l, cy - (b - t) / 2 - t
        d.text((gx + 4, gy + 5), glyph, font=f, fill=(0, 0, 0, 90))
        d.text((gx, gy), glyph, font=f, fill=WHITE)
    else:
        d.ellipse([cx - 90, cy - 90, cx + 90, cy + 90], fill=color, outline=rcolor, width=5)
    buf = io.BytesIO()
    im.save(buf, format="PNG")
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


def put_file(path, raw, message):
    sha = None
    meta = gh("GET", path)
    if meta:
        sha = meta["sha"]
    payload = {"message": message,
               "content": base64.b64encode(raw).decode("ascii")}
    if sha:
        payload["sha"] = sha
    gh("PUT", path, json.dumps(payload).encode())


if __name__ == "__main__":
    TOKEN = os.environ.get("GITHUB_TOKEN", "")
    push = "--push" in sys.argv
    if push and not TOKEN:
        print("Set GITHUB_TOKEN to push", file=sys.stderr)
        sys.exit(1)

    out_dir = os.path.join(os.path.dirname(__file__), "..", "build", "cards")
    os.makedirs(out_dir, exist_ok=True)
    version = str(int(time.time()))
    codepoints = load_codepoints()
    icon_names = load_icon_names()
    icon_font = _material_font_path()
    if not codepoints or not icon_font:
        print("WARN: Material icon font/codepoints not found — using disc fallback")
    manifest = {}
    for type_id, name, short, category, rarity in CARDS:
        drop = os.path.join(DROP_DIR, f"{type_id}.png")
        if os.path.isfile(drop):
            with open(drop, "rb") as fh:
                png = fh.read()
            source = "custom"
        else:
            icon_cp = codepoints.get(icon_names.get(type_id, ""))
            png = render(type_id, category, rarity, icon_cp, icon_font)
            source = "placeholder"
        with open(os.path.join(out_dir, f"{type_id}.png"), "wb") as fh:
            fh.write(png)
        manifest[type_id] = version
        if push:
            put_file(f"images/cards/{type_id}.png", png,
                     f"cards: {source} image {type_id}")
            print(f"  uploaded {type_id}.png ({source}, {len(png)} bytes)")

    print(f"Generated {len(CARDS)} card images in build/cards/")
    if push:
        put_file("images/cards/manifest.json",
                 json.dumps({"cards": manifest}, indent=2).encode(),
                 "cards: image manifest")
        print("Pushed images + manifest.")
    else:
        print("Dry run. Re-run with --push to upload.")
