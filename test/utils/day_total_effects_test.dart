import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/models/powerup_card.dart';
import 'package:calcetto/utils/scoring.dart';

PowerupCard _c(CardType t, {String? user}) =>
    PowerupCard.ofType(t).withPlay(targetUser: user);

void main() {
  group('dayTotalsWithCardEffects', () {
    test('flat self bonus adds to the owner only', () {
      final r = dayTotalsWithCardEffects(
        teamPts: {'alice': 100, 'bob': 100},
        betPts: {'alice': 0, 'bob': 0},
        cardsByUser: {
          'alice': [_c(CardType.propina)], // +10
          'bob': const [],
        },
      );
      expect(r['alice'], 110);
      expect(r['bob'], 100);
    });

    test('flat rival deduction subtracts from the target', () {
      final r = dayTotalsWithCardEffects(
        teamPts: {'alice': 100, 'bob': 100},
        betPts: {'alice': 0, 'bob': 0},
        cardsByUser: {
          'alice': [_c(CardType.embargo, user: 'bob')], // -30 to bob
          'bob': const [],
        },
      );
      expect(r['bob'], 70);
      expect(r['alice'], 100);
    });

    test('hacienda scales only the team portion, not bets', () {
      final r = dayTotalsWithCardEffects(
        teamPts: {'alice': 100, 'bob': 200},
        betPts: {'alice': 0, 'bob': 50},
        cardsByUser: {
          'alice': [_c(CardType.hacienda, user: 'bob')], // x0.8 on bob team
          'bob': const [],
        },
      );
      expect(r['bob'], 210); // 200*0.8 + 50
    });

    test('la grada pita scales the team portion by 0.85', () {
      final r = dayTotalsWithCardEffects(
        teamPts: {'alice': 100, 'bob': 200},
        betPts: {'alice': 0, 'bob': 0},
        cardsByUser: {
          'alice': [_c(CardType.laGradaPita, user: 'bob')],
          'bob': const [],
        },
      );
      expect(r['bob'], closeTo(170, 1e-9));
    });

    test('el chiringuito moves 25% from the leader to the tail', () {
      final r = dayTotalsWithCardEffects(
        teamPts: {'alice': 200, 'bob': 100},
        betPts: {'alice': 0, 'bob': 0},
        cardsByUser: {
          'alice': [_c(CardType.elChiringuito)],
          'bob': const [],
        },
      );
      expect(r['alice'], 150);
      expect(r['bob'], 150);
    });
  });
}
