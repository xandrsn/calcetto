import 'dart:math';

double calculatePopularityPercent(int nSelections, int totalUsers) {
  if (nSelections <= 1) return 1.0;
  final ratio = (nSelections - 1) / totalUsers;
  return 0.33 + 0.67 * (1 - sqrt(ratio));
}

/// The captain's contribution is multiplied by this. A league has no knockout
/// rounds, so it is a single flat value (matches the 300% live preview). Single
/// source of truth for both the live-% display (`card_effects.dart`) and
/// scoring (`scoring.dart`).
const double kCaptainMultiplier = 3.0;
