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
- Player photos from free-licence sources (Wikidata / Wikimedia Commons), or your
  own: pick from gallery or camera, or paste an image URL. A broken URL falls back
  to an initials avatar.
- Per-player season stats: record (W/D/L, win rate), MVPs, scoring and unbeaten
  streaks, head-to-head per opponent and a points-per-matchday chart.

## Demo mode (no backend needed)

The demo build uses an in-memory backend with placeholder players, teams and
users. No token or data repository is needed.

```sh
flutter pub get
flutter run --dart-define=CALCETTO_DEMO=true
```

## Storage backends

All data goes through the `DataStore` interface (`lib/providers/data_store.dart`):

| Backend | When | Notes |
|---|---|---|
| `LocalStore` | default when no `GITHUB_TOKEN` is set | On-device (SharedPreferences), works offline, no account. Seeded with placeholder data. Move data between devices with the export/import (save icon on the home bar: JSON copied to the clipboard / pasted back). Single device = single "league". |
| `GithubService` | `GITHUB_TOKEN` set | Optional shared backend (below) for a group that needs to see each other's squads. |
| in-memory demo | `CALCETTO_DEMO=true` | Resets on reload. |

Why: GitHub-as-database needs a token inside every client build and scheduled
workflows to score matchdays. Local-first removes both for solo use. Sharing
between several phones still needs a real server (or the GitHub backend).

## Configuring a real backend (optional)

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
