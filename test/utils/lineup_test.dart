import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/utils/lineup.dart';

void main() {
  final squad = {
    'GK': ['gk1'],
    'DEF': ['d1', 'd2', 'd3', 'd4'],
    'MID': ['m1', 'm2', 'm3'],
    'FWD': ['f1', 'f2', 'f3'],
  };
  final bench = {
    'GK': ['gk2'],
    'DEF': ['d5'],
    'MID': ['m4'],
    'FWD': ['f4'],
  };

  group('positionOfPlayer', () {
    test('finds a starter position', () {
      expect(positionOfPlayer(squad, 'm2'), 'MID');
    });
    test('returns null for unknown', () {
      expect(positionOfPlayer(squad, 'nope'), isNull);
    });
  });

  group('canSwapPlayers', () {
    test('allows starter <-> bench in same position', () {
      expect(canSwapPlayers(squad, bench, 'm1', 'm4'), isTrue);
      expect(canSwapPlayers(squad, bench, 'm4', 'm1'), isTrue);
    });

    test('rejects different positions (keeps formation legal)', () {
      expect(canSwapPlayers(squad, bench, 'm1', 'd5'), isFalse);
      expect(canSwapPlayers(squad, bench, 'f1', 'gk2'), isFalse);
    });

    test('rejects two starters', () {
      expect(canSwapPlayers(squad, bench, 'd1', 'd2'), isFalse);
    });

    test('rejects two bench players', () {
      expect(canSwapPlayers(squad, bench, 'm4', 'f4'), isFalse);
    });

    test('rejects the same player', () {
      expect(canSwapPlayers(squad, bench, 'm1', 'm1'), isFalse);
    });

    test('rejects unknown players', () {
      expect(canSwapPlayers(squad, bench, 'm1', 'ghost'), isFalse);
    });

    test('GK swap works', () {
      expect(canSwapPlayers(squad, bench, 'gk1', 'gk2'), isTrue);
    });
  });
}
