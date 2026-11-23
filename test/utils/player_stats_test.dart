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

  group('detailed stats', () {
    DailyMatch m(String id, String home, String away, String score,
            List<MatchPlayer> ps) =>
        DailyMatch(id: id, home: home, away: away, score: score, players: ps);
    MatchPlayer mp(String id, int g, double pts) =>
        MatchPlayer(id: id, goals: g, assists: 0, points: pts);

    final mds = [
      _md(1, [m('1', 'A', 'B', '2-0', [mp('p1', 1, 8), mp('p2', 0, 5)])]),
      _md(2, [m('2', 'C', 'A', '1-1', [mp('p1', 2, 10), mp('p2', 0, 6)])]),
      _md(3, [m('3', 'A', 'B', '0-1', [mp('p1', 0, 4), mp('p2', 0, 6)])]),
    ];
    final st = playerSeasonStats('p1', mds, team: 'A');

    test('results, win rate, mvps', () {
      expect([st.wins, st.draws, st.losses], [1, 1, 1]);
      expect(st.winRate, closeTo(1 / 3, 1e-9));
      expect(st.mvps, 2);
      expect(st.bestPoints, 10);
      expect(st.avgPoints, closeTo(22 / 3, 1e-9));
    });

    test('streaks', () {
      expect(st.scoringStreak, 2);
      expect(st.unbeatenStreak, 2);
    });

    test('head to head', () {
      final h = st.headToHead;
      expect(h.first.opponent, 'B');
      expect([h.first.played, h.first.wins, h.first.losses], [2, 1, 1]);
      expect(h.first.goals, 1);
    });

    test('no team: no results, existing totals unchanged', () {
      final n = playerSeasonStats('p1', mds);
      expect(n.wins + n.draws + n.losses, 0);
      expect(n.winRate, 0);
      expect(n.goals, 3);
    });
  });
}
