import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/utils/card_effects.dart';
import 'package:calcetto/utils/scoring.dart';

/// Exact end-to-end checks of the per-matchday team calculation:
/// rating × base × ownership% × cardMult × captain — all stacking correctly.
void main() {
  group('full matchday calculation', () {
    test('all multipliers stack to the exact expected total', () {
      final pts = teamMatchdayPoints(
        fieldedIds: ['gk', 'mid', 'fwd'],
        ratings: {'gk': 6, 'mid': 8, 'fwd': 7},
        ownershipCounts: {'gk': 1, 'mid': 1, 'fwd': 1}, // all 100%
        totalUsers: 4,
        captainId: 'fwd',
        mods: {
          'mid': const PointDisplayMods(multiplier: 2.0), // e.g. Tiki-Taka
          'fwd': const PointDisplayMods(multiplier: 1.5), // e.g. Chilena
        },
      );
      // gk  6*18*1*1   = 108
      // mid 8*18*2*1   = 288
      // fwd 7*18*1.5*3 = 567  (captain ×3)
      expect(pts, closeTo(108 + 288 + 567, 1e-6));
    });

    test('captain ×3 stacks on top of a card boost', () {
      final plain = teamMatchdayPoints(
        fieldedIds: ['p'],
        ratings: {'p': 5},
        ownershipCounts: {'p': 1},
        totalUsers: 4,
        captainId: null,
        mods: {'p': const PointDisplayMods(multiplier: 2.0)},
      );
      final capt = teamMatchdayPoints(
        fieldedIds: ['p'],
        ratings: {'p': 5},
        ownershipCounts: {'p': 1},
        totalUsers: 4,
        captainId: 'p',
        mods: {'p': const PointDisplayMods(multiplier: 2.0)},
      );
      expect(plain, closeTo(180, 1e-6)); // 5*18*2
      expect(capt, closeTo(540, 1e-6)); // ×3 captain
    });

    test('ownership is monotonic — fewer owners, higher share', () {
      double withCount(int c) => teamMatchdayPoints(
        fieldedIds: ['p'],
        ratings: {'p': 7},
        ownershipCounts: {'p': c},
        totalUsers: 10,
        captainId: null,
      );
      expect(withCount(1), greaterThan(withCount(3)));
      expect(withCount(3), greaterThan(withCount(10)));
    });

    test('a stolen/zeroed player (mult 0) contributes nothing', () {
      final pts = teamMatchdayPoints(
        fieldedIds: ['a', 'b'],
        ratings: {'a': 8, 'b': 8},
        ownershipCounts: {'a': 1, 'b': 1},
        totalUsers: 4,
        captainId: null,
        mods: {'b': const PointDisplayMods(multiplier: 0.0)},
      );
      expect(pts, closeTo(144, 1e-6)); // only a: 8*18
    });
  });
}
