import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/screens/tabs/cards_tab.dart';

void main() {
  group('espontaneoCandidates', () {
    test('uses today\'s match players, excluding owned', () {
      final pool = espontaneoCandidates(
        dailyMatchPlayerIds: ['a', 'b', 'c', 'd'],
        allPlayerIds: ['a', 'b', 'c', 'd', 'e', 'f'],
        owned: {'a', 'b'},
      );
      expect(pool, {'c', 'd'});
    });

    test('falls back to the whole pool when no match players are listed', () {
      final pool = espontaneoCandidates(
        dailyMatchPlayerIds: const [],
        allPlayerIds: ['a', 'b', 'c'],
        owned: {'a'},
      );
      expect(pool, {'b', 'c'});
    });

    test('falls back when all match players are already owned', () {
      final pool = espontaneoCandidates(
        dailyMatchPlayerIds: ['a', 'b'],
        allPlayerIds: ['a', 'b', 'c', 'd'],
        owned: {'a', 'b'},
      );
      expect(pool, {'c', 'd'});
    });

    test('empty only when every player is owned', () {
      final pool = espontaneoCandidates(
        dailyMatchPlayerIds: ['a'],
        allPlayerIds: ['a', 'b'],
        owned: {'a', 'b'},
      );
      expect(pool, isEmpty);
    });
  });
}
