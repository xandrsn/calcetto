# Custom card artwork drop folder

Drop a PNG named `<typeId>.png` here to use it as that card's image instead of
the generated placeholder. The `typeId` is the card's `id` in the catalog
(`lib/models/powerup_card.dart`), e.g.:

- `red_card.png`, `yellow_card.png`, `hacienda.png`, `fiestero.png`, `robo.png`,
  `escudo.png`, `sub_extra.png`, `pitch_invader.png`, `hat_trick_hero.png`,
  `estreno.png`, `catenaccio.png`, `tiki_taka.png`, `golden_glove.png`,
  `normas_ffp.png`, `retirada.png`, `tridente.png`, `francotirador.png`,
  `motivacion.png`, `muralla.png`, `prima.png`, `vitamina.png`

Then upload everything (custom art + placeholders for the rest):

```bash
GITHUB_TOKEN=... python scripts/seed_card_images.py --push
```

The app shows these via `images/cards/<typeId>.png` on the data hub, falling back
to the card's emblem icon if an image is missing. Square images (~240×300 or any
ratio — they're shown `cover`) look best.
