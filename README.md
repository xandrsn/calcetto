# Calcetto

Calcetto is a fantasy La Liga game for a small group of friends, built with Flutter.
Players draft a squad, set a weekly lineup, play power-up cards and bet on matchday
results. Points come from real match data, scored by scheduled scripts.

Portfolio: https://charlieandersen.vercel.app

## Features

- Squad draft with a budget, a starting XI and a bench.
- Matchday lineups, quiniela-style predictions and a league table.
- Per-player season stats built from the matchdays the app stores.
- Power-up card collection with its own effects.
- Local notifications for phase changes (Android).
- Player photos from free-licence sources (Wikidata / Wikimedia Commons).

## Demo mode (no backend needed)

The demo build uses an in-memory backend with placeholder players, teams and
users. No token or data repository is needed.

```sh
flutter pub get
flutter run --dart-define=CALCETTO_DEMO=true
```

## Configuring a real backend

The app stores its data as JSON files in a GitHub repository and reads and writes
them through the GitHub Contents API. Create your own private data repository, then:

1. Create a fine-grained GitHub token with read/write access to that repository only.
2. Copy `env.example.json` to `env.json` (gitignored) and fill in the token, owner
   and repository name.
3. Run or build with the file:

```sh
flutter run --dart-define-from-file=env.json
```

The scoring scripts in `scripts/` are meant to run on a schedule (for example GitHub Actions)
inside your data repository, not this one.
Set the `GITHUB_OWNER` and `GITHUB_REPO` placeholders in those files to your own
values before using them.

A token compiled into a client build is visible to anyone with that build. This project
is a proof of concept for a closed group; see `docs/ARCHITECTURE.md` for its limits and
the path to a real backend.

## Development

```sh
flutter analyze
flutter test
```

Scoring rules are described in `SCORING.md`. Architecture and scaling notes are in
`docs/ARCHITECTURE.md`.

## Licence

No licence file yet. All rights reserved until one is added.
