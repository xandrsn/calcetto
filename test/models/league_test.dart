import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/models/league.dart';

LeagueMatch _m(String home, String away, int hs, int aws) =>
    LeagueMatch(id: '$home-$away', matchday: 1, home: home, away: away,
        homeScore: hs, awayScore: aws);

void main() {
  group('LeagueData.buildDefault (double round-robin)', () {
    final ld = LeagueData.buildDefault();

    test('380 fixtures across 38 matchdays', () {
      expect(ld.matches.length, 380);
      expect(ld.matches.map((m) => m.matchday).toSet().length, 38);
      for (var md = 1; md <= 38; md++) {
        expect(ld.matchesForMatchday(md).length, 10, reason: 'matchday $md');
      }
    });

    test('every club plays 38 games (19 home + 19 away)', () {
      for (final team in kLaLigaTeams) {
        final home = ld.matches.where((m) => m.home == team).length;
        final away = ld.matches.where((m) => m.away == team).length;
        expect(home, 19, reason: '$team home');
        expect(away, 19, reason: '$team away');
      }
    });

    test('no team plays itself; every fixture id is unique', () {
      expect(ld.matches.every((m) => m.home != m.away), isTrue);
      expect(ld.matches.map((m) => m.id).toSet().length, 380);
    });
  });

  group('fixtureId / teamSlug', () {
    test('accent-folds and slugs', () {
      expect(teamSlug('Atlético Madrid'), 'atletico_madrid');
      expect(teamSlug('Deportivo A Coruña'), 'deportivo_a_coruna');
      expect(fixtureId(5, 'Real Madrid', 'Sevilla'),
          'md05-real_madrid-sevilla');
    });
  });

  group('computeLeagueTable', () {
    test('orders by points', () {
      final table = computeLeagueTable(
        [_m('A', 'B', 2, 0), _m('C', 'A', 1, 1)],
        teams: ['A', 'B', 'C'],
      );
      expect(table.first.team, 'A'); // 4 pts
      expect(table.first.pts, 4);
    });

    test('La Liga head-to-head beats overall goal difference', () {
      // A and B both finish on 6 pts. A has a huge overall GD (crushed D 10-0),
      // but B won the head-to-head 1-0 → B must rank ABOVE A.
      final matches = [
        _m('B', 'A', 1, 0), // B beats A (head-to-head)
        _m('A', 'D', 10, 0), // A inflates overall GD
        _m('A', 'C', 1, 0),
        _m('B', 'C', 1, 0),
      ];
      final table = computeLeagueTable(matches, teams: ['A', 'B', 'C', 'D']);
      final order = table.map((s) => s.team).toList();
      expect(order.indexOf('B') < order.indexOf('A'), isTrue,
          reason: 'h2h winner B ranks above A despite A\'s bigger GD');
    });
  });
}
