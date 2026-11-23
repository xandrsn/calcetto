import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/demo/demo_backend.dart';
import 'package:calcetto/models/daily.dart';
import 'package:calcetto/models/league.dart';
import 'package:calcetto/providers/github_provider.dart';

void main() {
  group('demo backend', () {
    test('serves placeholder players, a matchday and bot users', () async {
      final gh = GithubService(demoHttpClient(now: DateTime.utc(2026, 9, 1)));
      final players = await gh.getJson('data/players.json');
      final list = (players!.data as Map)['players'] as List;
      expect(list.length, kLaLigaTeams.length * 23);

      final md = DailyMatchday.fromJson(
        (await gh.getJson('daily/md01.json'))!.data as Map<String, dynamic>,
      );
      expect(md.matches.first.id,
          LeagueData.buildDefault().matchesForMatchday(1).first.id);
      expect(md.cardsOpenTime!.isBefore(md.lockAtTime!), isTrue);

      expect(await gh.getJson('users/Demo1.json'), isNotNull);
      expect(await gh.listDir('users'), hasLength(3));
    });

    test('writes round-trip and follow GitHub sha rules', () async {
      final client = demoHttpClient(now: DateTime.utc(2026, 9, 1));
      final gh = GithubService(client);
      expect(await gh.getJson('users/New.json'), isNull);

      await gh.createJson('users/New.json', {'name': 'New'}, 'test');
      final created = await gh.getFreshJson('users/New.json');
      expect((created!.data as Map)['name'], 'New');

      // Updating without a sha is refused, as on GitHub.
      final noSha = await client.put(
        Uri.parse('https://api.github.com/repos/demo/demo/contents/users/New.json'),
        body: jsonEncode({'message': 'x', 'content': 'e30='}),
      );
      expect(noSha.statusCode, 422);

      // A stale sha is a conflict (what mutateJson retries on).
      await expectLater(
        gh.putJson('users/New.json', {'name': 'Stale'}, 'stale-sha', 'x'),
        throwsA(isA<WriteConflictException>()),
      );

      await gh.putJson('users/New.json', {'name': 'Edited'}, created.sha, 'x');
      expect(
        ((await gh.getFreshJson('users/New.json'))!.data as Map)['name'],
        'Edited',
      );
    });

    test('unknown routes answer 404 instead of throwing', () async {
      final res = await demoHttpClient().get(
        Uri.parse('https://api.github.com/repos/demo/demo/contents/nope.json'),
      );
      expect(res.statusCode, 404);
    });
  });
}
