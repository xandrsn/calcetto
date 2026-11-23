# Player photo drop folder

Drop a photo named `<playerId>.jpg` (or `.png`/`.jpeg`/`.webp`) here, where
`playerId` is the player's `id` in `data/players.json` (e.g. `messi_lionel.jpg`,
`mbappe_kylian.jpg`). Then upload them all at once:

```bash
GITHUB_TOKEN=... python scripts/seed_player_images.py --push
```

Each image is downscaled to ≤256px on the long edge and re-encoded as JPEG (same
as the in-app upload), stored at `images/players/<id>.jpg` on the data hub, and
recorded in `images/players/manifest.json`. The app shows them via
`PlayerAvatar`, falling back to the generated pixel sprite when a player has no
photo.

To find a player's id, open `data/players.json` (ids are `lastname_firstname`,
lowercase, no accents).
