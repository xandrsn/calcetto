# Calcetto architecture and scaling plan

## 1. Today: GitHub as the backend

- The Flutter client reads and writes JSON files in a private GitHub repo through the
  Contents API (`lib/providers/github_provider.dart`, `GithubService`).
- Writes are read-modify-write with the file sha (`mutateJson`). A stale sha gives 409/422
  and the transform is retried on fresh data (up to 4 times with backoff).
- Scoring runs as Python scripts in scheduled GitHub Actions (`scripts/`,
  `.github/workflows/daily_resolution.yml`): `fetch_scores.py` reads ESPN results,
  `daily_resolution.py` scores users once per matchday.
- Identity is a username in `SharedPreferences`. There is no password.
- The client holds a GitHub token, which ends up inside every build.

This is a deliberate POC choice: no server to run, free, and the data is readable
and diffable. It has the properties below.

## 2. Why it does not scale

| Concern | Consequence with GitHub |
|---|---|
| Authorization | Any build contains a token that can write the whole repo. Admin checks are client-side only. |
| Atomicity | Only one file is atomic. A multi-file change (scores + every user + league) can stop halfway. Scoring is guarded by a `scored` marker, but there is no transaction. |
| Concurrency | Optimistic sha retries are fine for a handful of users. Hot files (`chat.json`, `activity_log.json`, `app_config.json`) are a contention point. |
| Rate limits | Each screen fetches many files. The whole league (`listDir` + per-user GET) gets close to the authenticated limit at a few hundred users. |
| Queries | Everything is loaded and filtered in the client (leaderboard, ownership, past matchdays). |
| Scheduling | Cron runs in Actions, with no retries, no per-job state, and the output lives in the same repo as the data. |
| Privacy and ops | The data repo is the database, the audit log is git history, and there are no backups beyond git. |

## 3. Recommended target (if the group grows or goes public)

**Postgres-backed backend, managed auth, scheduled functions.** Supabase is the
closest fit (Postgres, Row Level Security, auth, cron via `pg_cron` or Edge
Functions, realtime for chat). Firebase is the alternative if you prefer NoSQL.

- **Tables**: `users`, `squads` (user, player, slot, bench), `matchdays`, `fixtures`,
  `player_matchday_stats`, `quiniela_picks`, `bets`, `cards`, `activity`, `chat`.
- **Auth**: magic link or Google sign-in per user. Row Level Security: a user writes only
  their own squad, picks and cards; only the admin role writes results.
- **Scoring**: a Postgres function or Edge Function per matchday, run in one transaction,
  idempotent on `(matchday_id)`. This replaces `daily_resolution.py` and the admin
  `applyResultsAndScore` path.
- **Data feed**: the same ESPN fetch, running as a scheduled function that writes
  `fixtures` and `player_matchday_stats`.
- **Client**: no token. The app keeps the public anon key, which RLS protects.

## 4. Migration plan (incremental)

1. **Seam first (done in this branch's demo work).** Everything reads and writes through
   `GithubService`, and the demo already swaps the transport with a `MockClient`. The next
   step is to introduce a small `DataSource` interface (`getJson`, `putJson`, `listDir`,
   `mutate`) and make `GithubService` one implementation. Cost: a few hundred lines,
   no behaviour change.
2. **Stand up the database** (Supabase project, schema from section 3, RLS policies). Write a
   one-off importer that reads the JSON files and loads them into the tables. Keep the
   GitHub repo as a read-only export for a while.
3. **Add a `SupabaseDataSource`** behind the same interface. Behind a build flag, run the
   app against the database while the GitHub source stays available for rollback.
4. **Move scoring** into a database function or scheduled Edge Function. Run it in
   parallel with the Python script on a copy of the data and compare the output
   matchday by matchday before switching.
5. **Auth**: replace the username field with sign-in. Keep usernames as display names.
   Migrate existing users by matching their username on first login.
6. **Retire the token**: remove the GitHub token from the client, rotate it, and stop
   the Actions workflow that wrote to the data repo.
7. **Realtime and cleanup**: replace the 15s polling of chat and the activity feed with
   subscriptions; delete the GitHub code path.

Rollback is possible at every step until step 6, because the GitHub source is kept until
the database has run through at least one full matchday.

## 5. What is in the repo today

- `lib/providers/github_provider.dart`: the transport, the only place that knows about
  GitHub's API shape.
- `lib/demo/demo_backend.dart`: an in-memory implementation of the same API, used by the
  public demo build (`--dart-define=CALCETTO_DEMO=true`). It shows that the transport can
  be replaced without touching screens or providers.
- `scripts/`: the scheduled jobs that the database version would replace.
