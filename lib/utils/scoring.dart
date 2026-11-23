import '../models/powerup_card.dart';
import '../models/user_data.dart';
import 'card_effects.dart';
import 'popularity.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Scoring config — the single place to tune the point system (see SCORING.md).
// Target balance for a realistic player: ~40% Quiniela / ~20% bets / ~40% team.
// A league has no knockout rounds, so there is no per-round multiplier.
// ─────────────────────────────────────────────────────────────────────────────

/// Team points = rating × this × ownership% × cardMult × captainMult.
const double kRatingBase = 18.0;

/// Each participant "stakes" this per bet (not deducted); the pot is split among
/// correct guessers.
const double kBetStake = 50.0;

/// Points per correctly predicted 1-X-2 sign in the weekly Quiniela.
const double kQuinielaCorrectPts = 100.0;

/// Bonus for a "pleno" — getting every fixture of the matchday right.
const double kQuinielaPlenoBonus = 500.0;

/// Points per goal (Pichichi pick) / assist (top-assist pick) for the optional
/// season-long picks. Recomputed from cumulative player totals.
const double kSeasonPickPts = 100.0;

/// Lightweight, pure scoring used by the admin testing tools to preview points
/// instantly (NOT the authoritative engine — that's
/// scripts/daily_resolution.py). Full spec in SCORING.md.

/// Team points for one user on one matchday (see SCORING.md §1):
///   Σ over fielded players of  rating × kRatingBase × ownership% × cardMult ×
///   (captain ? kCaptainMultiplier : 1).
///
/// [fieldedIds] are the players who actually played (XI + bench + card extras).
/// [ratings] maps player id → rating (1–10). [mods] is the per-player card
/// multiplier map from the live-% engine (`pointDisplayMods` /
/// `foldIncomingAttacks`); pass null for no card effects.
double teamMatchdayPoints({
  required List<String> fieldedIds,
  required Map<String, double> ratings,
  required Map<String, int> ownershipCounts,
  required int totalUsers,
  required String? captainId,
  Map<String, PointDisplayMods>? mods,
}) {
  var total = 0.0;
  for (final pid in fieldedIds) {
    final rating = ratings[pid];
    if (rating == null) continue;
    final ownership = calculatePopularityPercent(
      ownershipCounts[pid] ?? 1,
      totalUsers,
    );
    final cardMult = (mods?[pid] ?? const PointDisplayMods()).multiplier;
    final captainMult = pid == captainId ? kCaptainMultiplier : 1.0;
    total += rating * kRatingBase * ownership * cardMult * captainMult;
  }
  return total;
}

/// Points one player earns from a single bet (see SCORING.md §3): the pot
/// (`participants × kBetStake`) split equally among the [correctCount] who
/// guessed right. Returns 0 if this player was wrong or nobody was right.
double betPoints({
  required int participants,
  required int correctCount,
  required bool isCorrect,
}) {
  if (!isCorrect || correctCount <= 0) return 0;
  return participants * kBetStake / correctCount;
}

/// Weekly **Quiniela** points for one user (see SCORING.md §2): `kQuinielaCorrectPts`
/// per correctly predicted 1-X-2 sign, plus a `kQuinielaPlenoBonus` if every
/// decided fixture was correct.
///
/// [actualSigns] maps fixture id → the played result's sign (`'1'`/`'X'`/`'2'`);
/// pass only fixtures that have a result (postponed/unplayed excluded), so the
/// pleno bonus reflects the fixtures that actually resolved.
double quinielaPoints({
  required QuinielaPrediction pred,
  required Map<String, String> actualSigns,
}) {
  if (actualSigns.isEmpty) return 0;
  var total = 0.0;
  var correct = 0;
  for (final e in actualSigns.entries) {
    if (pred.picks[e.key] == e.value) {
      total += kQuinielaCorrectPts;
      correct++;
    }
  }
  if (correct == actualSigns.length) total += kQuinielaPlenoBonus;
  return total;
}

/// Day-total card effects, applied AFTER per-player team scoring (these act on a
/// whole user's day rather than a single player). Mirrors daily_resolution.py so
/// the admin manual-scorer matches the authoritative resolver. Order:
///   1. flat self bonuses (CALDERILLA…LOTERÍA): + flatPoints
///   2. percentage hits on a rival (HACIENDA ×0.8, LA GRADA PITA ×0.85) — on the
///      team portion, stacking multiplicatively
///   3. flat deductions on a rival (MULTA…EMBARGO): − flatPoints
///   4. EL CHIRINGUITO redistribution: each leader gives 25% of his day total to
///      the matching tail player (pairwise top↔bottom).
///
/// [teamPts]/[betPts] are per-user; [cardsByUser] their played cards. Returns the
/// final day total per user (team-adjusted + bets + redistribution).
Map<String, double> dayTotalsWithCardEffects({
  required Map<String, double> teamPts,
  required Map<String, double> betPts,
  required Map<String, List<PowerupCard>> cardsByUser,
}) {
  final users = teamPts.keys.toList();

  // Multiplicative deduction factor per victim (HACIENDA / LA GRADA PITA).
  final pctFactor = {for (final u in users) u: 1.0};
  // Flat deduction received per victim (MULTA / IVA / RECORTE / EMBARGO).
  final flatHit = {for (final u in users) u: 0.0};
  var chiringuito = false;

  for (final entry in cardsByUser.entries) {
    for (final c in entry.value) {
      final def = c.def;
      switch (c.type) {
        case CardType.hacienda:
          final v = c.targetUser;
          if (v != null && pctFactor.containsKey(v)) {
            pctFactor[v] = pctFactor[v]! * 0.8;
          }
        case CardType.laGradaPita:
          final v = c.targetUser;
          if (v != null && pctFactor.containsKey(v)) {
            pctFactor[v] = pctFactor[v]! * 0.85;
          }
        case CardType.elChiringuito:
          chiringuito = true;
        default:
          if (def.isFlatPoints &&
              def.category == CardCategory.attack &&
              c.targetUser != null &&
              flatHit.containsKey(c.targetUser)) {
            flatHit[c.targetUser!] = flatHit[c.targetUser!]! + def.flatPoints;
          }
      }
    }
  }

  final totals = <String, double>{};
  for (final u in users) {
    var flatSelf = 0.0;
    for (final c in cardsByUser[u] ?? const <PowerupCard>[]) {
      final def = c.def;
      if (def.isFlatPoints && def.category == CardCategory.boost) {
        flatSelf += def.flatPoints;
      }
    }
    final team = teamPts[u]! * pctFactor[u]! + flatSelf - flatHit[u]!;
    totals[u] = team + (betPts[u] ?? 0);
  }

  if (chiringuito && users.length >= 2) {
    final sorted = users.toList()
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    final n = sorted.length;
    for (var i = 0; i < n ~/ 2; i++) {
      final top = sorted[i], bot = sorted[n - 1 - i];
      if (top == bot) break;
      final transfer = totals[top]! * 0.25;
      totals[top] = totals[top]! - transfer;
      totals[bot] = totals[bot]! + transfer;
    }
  }
  return totals;
}
