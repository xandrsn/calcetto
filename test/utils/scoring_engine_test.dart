import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/models/user_data.dart';
import 'package:calcetto/utils/card_effects.dart';
import 'package:calcetto/utils/popularity.dart';
import 'package:calcetto/utils/scoring.dart';

void main() {
  group('teamMatchdayPoints', () {
    test('rating × base × ownership, single owner', () {
      final pts = teamMatchdayPoints(
        fieldedIds: ['p1'],
        ratings: {'p1': 8.0},
        ownershipCounts: {'p1': 1},
        totalUsers: 1,
        captainId: null,
      );
      expect(pts, 8.0 * kRatingBase); // 8 × 18 = 144
    });

    test('captain multiplies by kCaptainMultiplier', () {
      final pts = teamMatchdayPoints(
        fieldedIds: ['p1'],
        ratings: {'p1': 8.0},
        ownershipCounts: {'p1': 1},
        totalUsers: 1,
        captainId: 'p1',
      );
      expect(pts, 8.0 * kRatingBase * kCaptainMultiplier);
    });

    test('card multiplier (e.g. ×2 boost) is applied', () {
      final pts = teamMatchdayPoints(
        fieldedIds: ['p1'],
        ratings: {'p1': 6.0},
        ownershipCounts: {'p1': 1},
        totalUsers: 1,
        captainId: null,
        mods: {'p1': const PointDisplayMods(multiplier: 2.0)},
      );
      expect(pts, 6.0 * kRatingBase * 2.0);
    });

    test('players without a rating are skipped', () {
      final pts = teamMatchdayPoints(
        fieldedIds: ['p1', 'p2'],
        ratings: {'p1': 7.0}, // p2 didn't play
        ownershipCounts: {'p1': 1, 'p2': 1},
        totalUsers: 1,
        captainId: null,
      );
      expect(pts, 7.0 * kRatingBase);
    });
  });

  group('betPoints', () {
    test('splits the pot among correct guessers', () {
      // 15 participants, 5 correct → pot 750 / 5 = 150 each.
      expect(betPoints(participants: 15, correctCount: 5, isCorrect: true), 150.0);
    });
    test('zero when wrong or nobody right', () {
      expect(betPoints(participants: 15, correctCount: 5, isCorrect: false), 0);
      expect(betPoints(participants: 15, correctCount: 0, isCorrect: true), 0);
    });
  });

  group('quinielaPoints (1-X-2)', () {
    const actual = {'m1': '1', 'm2': 'X', 'm3': '2'};

    test('per correct sign', () {
      final pred = const QuinielaPrediction(picks: {'m1': '1', 'm2': '2', 'm3': '2'});
      // m1 + m3 correct = 2 × 100.
      expect(quinielaPoints(pred: pred, actualSigns: actual), 2 * kQuinielaCorrectPts);
    });

    test('pleno bonus when every fixture is correct', () {
      final pred = const QuinielaPrediction(picks: {'m1': '1', 'm2': 'X', 'm3': '2'});
      expect(
        quinielaPoints(pred: pred, actualSigns: actual),
        3 * kQuinielaCorrectPts + kQuinielaPlenoBonus,
      );
    });

    test('no fixtures decided → 0', () {
      final pred = const QuinielaPrediction(picks: {'m1': '1'});
      expect(quinielaPoints(pred: pred, actualSigns: const {}), 0);
    });

    test('empty prediction → 0', () {
      expect(
        quinielaPoints(pred: const QuinielaPrediction(), actualSigns: actual),
        0,
      );
    });
  });
}
