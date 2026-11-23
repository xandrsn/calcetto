# Calcetto — Scoring Spec (source of truth)

> The point system for the **La Liga 2026-27** season. All values are named
> constants in `lib/utils/scoring.dart` (`kRatingBase`, `kBetStake`,
> `kQuinielaCorrectPts`, `kQuinielaPlenoBonus`, `kSeasonPickPts`) and mirrored in
> `scripts/daily_resolution.py`. Points accrue **per matchday** (jornada) — a
> league has no knockout rounds, so there is **no per-round multiplier**.

---

## 1. Team / squad points

Each **matchday**, every player you **field who plays a real match** scores.
Fielded = your starting XI + bench + any card-added extras (ESPONTÁNEO random
join, ROBO stolen player). A player's points:

```
points = rating × RATING_BASE × ownership% × cardMult × captainMult
```

- **rating** — 1.0–10.0 (one decimal), entered by the admin / fetched.
- **RATING_BASE** = **18**.
- **ownership%** — popularity curve (0.33–1.0); fewer owners → higher %.
- **cardMult** — boost/defense cards on your players, and incoming attacks, from
  the same engine that drives the live-% display (`card_effects.dart`):
  tiki-taka ×2, catenaccio ×2, golden glove ×3, tridente ×2, muralla ×1.5,
  francotirador ×2, prima ×1.5, motivación ×1.3, vitamina ×1.15 (stack
  multiplicatively); incoming red ×0, yellow ×0.5, robo ×0 (unless shielded).
- **captainMult** — **×3** for your captain (`kCaptainMultiplier`, matches the
  300% live preview).

Plus **day-total cards** applied after the per-player sum
(`dayTotalsWithCardEffects`): flat self bonuses (CALDERILLA…LOTERÍA), flat rival
deductions (MULTA…EMBARGO), HACIENDA ×0.8 / LA GRADA PITA ×0.85 on a rival, and
EL CHIRINGUITO leader↔last 25% redistribution.

## 2. Quiniela (weekly 1-X-2 prediction)

Each matchday, predict the sign of every fixture — **1** home win, **X** draw,
**2** away win.

- **`kQuinielaCorrectPts` = 100** per correctly predicted fixture.
- **`kQuinielaPlenoBonus` = 500** if you get **every** fixture of the matchday
  right (a "pleno").

Scored from the fixtures' scorelines at matchday resolution (postponed/unplayed
fixtures are excluded, so the pleno reflects the fixtures that actually resolved).

## 3. Bets (prop bets)

- **One creative prop bet per match.** Each participant "stakes" **`kBetStake` =
  50** (not deducted). Pot = `participants × 50`, split **equally among everyone
  who picked the correct option**. Nobody correct → no payout.
- Example: 10 pick X, 5 pick Y, result is Y → pot = 15 × 50 = 750, each of the 5
  winners gets 150.

## 4. Season picks (Pichichi / top assists) — optional

- Pick a **Pichichi** (top scorer) and a **top-assist** player for the season.
- **`kSeasonPickPts` = 100** per goal of your Pichichi / per assist of your
  top-assist pick, recomputed from cumulative player totals
  (`scoreSeasonPicksAllUsers`).

## 5. Powerups (folded into the above)

- Multiplier cards fold into **cardMult** / **captainMult** (§1) — same engine as
  the live-% display, so what you see is what you score.
- Direct +/− point cards and redistribution apply at the day-total level (§1).
- Attack cards (red/yellow/robo/hacienda…) reduce the *target's* team points and
  are resolved at matchday close (captain immune; max 3 attacks/victim/matchday).

## 6. Where it runs

- **Authoritative:** `scripts/daily_resolution.py` resolves one matchday
  (`daily/md<NN>.json`) — team + bets + quiniela + cards — writes each user's
  points, mirrors scorelines into `data/league.json`, and advances
  `current_matchday`. It **self-skips** until every fixture is scored (safe to run
  daily on a cron); `--force` overrides.
- **Admin preview:** `lib/utils/scoring.dart` + `AdminService.applyResultsAndScore`
  score a matchday in-app (results-entry screen), matching the Python engine.
