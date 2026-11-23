import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:calcetto/admin/admin_service.dart';
import 'package:calcetto/models/league.dart';
import 'package:calcetto/providers/github_provider.dart';

void main() {
  group('applyResultsAndScore', () {
    test('refuses to score a matchday twice (would double everyone)', () async {
      var writes = 0;
      final client = MockClient((req) async {
        if (req.method != 'GET') {
          writes++;
          return http.Response('{}', 200);
        }
        final body = {
          'matchday': 5,
          'date': '2026-10-03',
          'scored': true,
          'matches': <dynamic>[],
          'bets': <dynamic>[],
        };
        final content = base64.encode(utf8.encode(jsonEncode(body)));
        return http.Response(
          jsonEncode({'content': content, 'sha': 'sha1'}),
          200,
        );
      });
      final svc = AdminService(GithubService(client));
      await expectLater(
        svc.applyResultsAndScore(
          mdKey: 'md05',
          matchScores: const {},
          goalsAssists: const {},
          ratings: const {},
        ),
        throwsA(isA<Exception>()),
      );
      expect(writes, 0);
    });
  });

  group('simulateLeagueData', () {
    test('produces a fully-played league', () {
      final ld = simulateLeagueData(Random(1));
      expect(ld.matches.length, 380); // 20 teams double round-robin
      expect(ld.matches.every((m) => m.played), isTrue);
      expect(ld.completedMatchdays, kTotalMatchdays);
    });

    test('table has all 20 clubs and consistent games played', () {
      final ld = simulateLeagueData(Random(7));
      final table = ld.computeTable();
      expect(table.length, kLaLigaTeams.length);
      // Every club plays 38 games (19 home + 19 away).
      expect(table.every((s) => s.p == 38), isTrue);
      // Points are ordered descending (table is sorted).
      for (var i = 1; i < table.length; i++) {
        expect(table[i - 1].pts >= table[i].pts, isTrue);
      }
    });

    test('is deterministic for a given seed', () {
      final a = simulateLeagueData(Random(7)).computeTable().first.team;
      final b = simulateLeagueData(Random(7)).computeTable().first.team;
      expect(a, b);
    });
  });

  group('generateRandomCards', () {
    test('returns the requested count', () {
      expect(generateRandomCards(Random(1)).length, 5);
      expect(generateRandomCards(Random(1), count: 3).length, 3);
    });
  });
}
