import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../models/league.dart';
import '../models/user_data.dart';

/// In-memory stand-in for the private data repo, used only when `CALCETTO_DEMO`
/// is set (the public web demo; see docs/ARCHITECTURE.md). It answers the same
/// GitHub Contents API shape that `GithubService` already speaks, so the app
/// code path is unchanged. All data is placeholder data generated here: no token,
/// no repo name and no friend-group data is compiled into the demo.
///
/// Writes are kept in memory with GitHub-like sha checks (409 on a stale sha,
/// 422 on a missing one), so merge/retry logic is exercised too. Reloading the
/// page resets everything.
MockClient demoHttpClient({DateTime? now}) {
  final files = demoSeedFiles(now ?? DateTime.now()); // path -> base64 content
  final shas = <String, String>{};
  var shaCounter = 0;
  String nextSha() => 'demo${++shaCounter}';
  for (final p in files.keys) {
    shas[p] = nextSha();
  }

  return MockClient((req) async {
    if (req.url.path.contains('/actions/')) return http.Response('', 204);
    const marker = '/contents/';
    final at = req.url.path.indexOf(marker);
    if (at < 0) return _notFound();
    final path = Uri.decodeComponent(req.url.path.substring(at + marker.length));

    switch (req.method) {
      case 'GET':
        if (files.containsKey(path)) {
          return http.Response(
            jsonEncode({
              'type': 'file',
              'name': path.split('/').last,
              'path': path,
              'sha': shas[path],
              'encoding': 'base64',
              'content': files[path],
            }),
            200,
          );
        }
        final children = _children(files.keys, path, shas);
        return children.isEmpty
            ? _notFound()
            : http.Response(jsonEncode(children), 200);
      case 'PUT':
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final sha = body['sha'] as String?;
        final exists = files.containsKey(path);
        if (!exists && sha != null) return http.Response('{}', 422);
        if (exists && sha == null) return http.Response('{}', 422);
        if (exists && sha != shas[path]) return http.Response('{}', 409);
        files[path] = body['content'] as String;
        shas[path] = nextSha();
        return http.Response(jsonEncode({'content': {'path': path}}), exists ? 200 : 201);
      case 'DELETE':
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        if (!files.containsKey(path) || body['sha'] != shas[path]) {
          return http.Response('{}', 409);
        }
        files.remove(path);
        shas.remove(path);
        return http.Response('{}', 200);
    }
    return http.Response('{}', 405);
  });
}

http.Response _notFound() => http.Response('{"message":"Not Found"}', 404);

/// Immediate children of [dir] (files and sub-folders), in GitHub listing shape.
List<Map<String, dynamic>> _children(
  Iterable<String> paths,
  String dir,
  Map<String, String> shas,
) {
  final out = <String, Map<String, dynamic>>{};
  for (final p in paths) {
    if (!p.startsWith('$dir/')) continue;
    final rest = p.substring(dir.length + 1);
    final slash = rest.indexOf('/');
    final name = slash < 0 ? rest : rest.substring(0, slash);
    out[name] = {
      'name': name,
      'path': '$dir/$name',
      'type': slash < 0 ? 'file' : 'dir',
      'sha': shas[p],
    };
  }
  return out.values.toList();
}

String _b64(Object json) => base64.encode(utf8.encode(jsonEncode(json)));

/// Placeholder data: 20 clubs × 23 generated players, one matchday of fixtures
/// with a bet, and three bot users with squads so the leaderboard isn't empty.
Map<String, String> demoSeedFiles(DateTime now) {
  final teams = kLaLigaTeams;
  const counts = {'GK': 3, 'DEF': 8, 'MID': 8, 'FWD': 4};
  final players = <Map<String, dynamic>>[];
  final byPos = {for (final p in counts.keys) p: <String>[]};
  for (var t = 0; t < teams.length; t++) {
    for (final pos in counts.keys) {
      for (var n = 1; n <= counts[pos]!; n++) {
        final tn = (t + 1).toString().padLeft(2, '0');
        final id = 'demo_${tn}_${pos.toLowerCase()}$n';
        byPos[pos]!.add(id);
        players.add({
          'id': id,
          'name': 'Jugador ${t + 1}-$pos$n',
          'team': teams[t],
          'position': pos,
          'skin': 'light_short_brown',
          'points_per_match': <String, double>{},
          'total_points': 0,
          'goals': 0,
          'assists': 0,
        });
      }
    }
  }

  final kickoff = now.toUtc().add(const Duration(days: 2)).toIso8601String();
  final matches = LeagueData.buildDefault().matchesForMatchday(1);
  final md = {
    'matchday': 1,
    'date': kickoff.substring(0, 10),
    'first_kickoff': kickoff,
    // Manage phase is open now; cards open tomorrow and the games lock after.
    'cards_open': now.toUtc().add(const Duration(days: 1)).toIso8601String(),
    'lock_at': kickoff,
    'matches': [
      for (final m in matches)
        {
          'id': m.id,
          'home': m.home,
          'away': m.away,
          'kickoff': kickoff,
          'score': null,
          'players': <dynamic>[],
        },
    ],
    'bets': [
      {
        'id': 'bet_demo_1',
        'match_id': matches.first.id,
        'question': '¿Habrá más de 2,5 goles?',
        'options': ['Sí', 'No'],
        'answer': null,
      },
    ],
  };

  final files = <String, String>{
    'data/players.json': _b64({'players': players}),
    'data/app_config.json': _b64({
      'current_matchday': 1,
      'predictions_open': true,
    }),
    'daily/md01.json': _b64(md),
  };

  for (var k = 0; k < 3; k++) {
    final name = 'Demo${k + 1}';
    List<String> pick(String pos, int from, int count) =>
        byPos[pos]!.sublist(from, from + count);
    final user = UserData.empty(name).toJson();
    user['formation'] = '4-4-2';
    user['squad'] = {
      'GK': pick('GK', k, 1),
      'DEF': pick('DEF', k * 4, 4),
      'MID': pick('MID', k * 4, 4),
      'FWD': pick('FWD', k * 2, 2),
    };
    user['bench'] = {
      'GK': pick('GK', k + 1, 1),
      'DEF': pick('DEF', k * 4 + 4, 1),
      'MID': pick('MID', k * 4 + 4, 1),
      'FWD': pick('FWD', k * 2 + 2, 2),
    };
    files['users/$name.json'] = _b64(user);
  }
  return files;
}
