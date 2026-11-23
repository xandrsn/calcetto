import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/models/daily.dart';
import 'package:calcetto/utils/player_stats.dart';

DailyMatchday _md(int n, List<DailyMatch> matches) => DailyMatchday(
  matchday: n,
  date: '2026-10-0$n',
  firstKickoff: '2026-10-0${n}T13:00:00Z',
  cardsOpen: '2026-10-0${n}T11:00:00Z',
  lockAt: '2026-10-0${n}T13:00:00Z',
  matches: matches,
  bets: const [],
);

DailyMatch _match(String id, List<MatchPlayer> players) => DailyMatch(
  id: id,
  home: 'A',
  away: 'B',
  score: '1-0',
  players: players,
);

void main() {
  group('playerSeasonStats', () {
    final mdOld = _md(2, [
      _match('md02-a-b', [
        const MatchPlayer(
          id: 'p1',
          goals: 1,
          assists: 0,
          points: 9,
          minutes: 90,
          yellow: 1,
        ),
      ]),
    ]);
    final mdNew = _md(3, [
      _match('md03-a-b', [
        const MatchPlayer(id: 'p1', goals: 0, assists: 2, points: 6.5),
        const MatchPlayer(id: 'p2', goals: 3, assists: 0, points: 12),
      ]),
    ]);

    test('totals only what the matchdays recorded, oldest first', () {
      // Matchdays passed newest-first on purpose.
      final s = playerSeasonStats('p1', [mdNew, mdOld]);
      expect(s.appearances, 2);
      expect(s.goals, 1);
      expect(s.assists, 2);
      expect(s.yellow, 1);
      expect(s.red, 0);
      expect(s.points, 15.5);
      expect(s.lines.map((l) => l.matchday), [2, 3]);
    });

    test('minutes are null unless some matchday recorded them', () {
      expect(playerSeasonStats('p1', [mdOld, mdNew]).minutes, 90);
      expect(playerSeasonStats('p2', [mdNew]).minutes, isNull);
    });

    test('form is the last five points, oldest first', () {
      final many = [
        for (var n = 1; n <= 7; n++)
          _md(n, [
            _match('md0$n-a-b', [
              MatchPlayer(id: 'p1', goals: 0, assists: 0, points: n.toDouble()),
            ]),
          ]),
      ];
      expect(playerSeasonStats('p1', many).form(), [3.0, 4.0, 5.0, 6.0, 7.0]);
    });

    test('a player with no rows has no appearances', () {
      final s = playerSeasonStats('nobody', [mdOld, mdNew]);
      expect(s.appearances, 0);
      expect(s.form(), isEmpty);
    });
  });
}
