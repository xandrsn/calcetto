import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:calcetto/providers/github_provider.dart';

/// Encodes a JSON map the way the GitHub Contents API returns it.
http.Response _contents(Map<String, dynamic> data, String sha) {
  final content = base64.encode(utf8.encode(jsonEncode(data)));
  return http.Response(jsonEncode({'content': content, 'sha': sha}), 200);
}

void main() {
  group('mutateJson', () {
    test('merges onto fresh state and retries once on conflict', () async {
      // Simulated server state. Starts with the engine-written value.
      Map<String, dynamic> server = {'points': 100, 'captain': 'a'};
      var sha = 'sha0';
      var getCount = 0;
      var putCount = 0;

      final client = MockClient((req) async {
        if (req.method == 'GET') {
          getCount++;
          return _contents(server, sha);
        }
        // PUT
        putCount++;
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final sentSha = body['sha'] as String?;
        final next = jsonDecode(
          utf8.decode(base64.decode(body['content'] as String)),
        );
        // First PUT: simulate a conflicting write landed in between → 409,
        // and the server moved on (points bumped, sha changed).
        if (putCount == 1) {
          server = <String, dynamic>{'points': 250, 'captain': 'a'};
          sha = 'sha1';
          return http.Response('conflict', 409);
        }
        // Second PUT: accept only if the caller sent the current sha.
        expect(sentSha, 'sha1');
        server = Map<String, dynamic>.from(next as Map);
        sha = 'sha2';
        return http.Response('{}', 200);
      });

      final gh = GithubService(client);

      // The user only changes `captain`; `points` must be preserved from
      // whatever the server currently has at write time.
      final written = await gh.mutateJson(
        'users/x.json',
        message: 'set captain',
        transform: (current) {
          final m = Map<String, dynamic>.from(current as Map);
          m['captain'] = 'b';
          return m;
        },
      );

      // Retried exactly once (two PUTs, two+ GETs).
      expect(putCount, 2);
      expect(getCount, greaterThanOrEqualTo(2));
      // Final written value merged the user's edit onto the *bumped* points.
      expect((written as Map)['captain'], 'b');
      expect(written['points'], 250);
      // And the server ended up with the merged value.
      expect(server['points'], 250);
      expect(server['captain'], 'b');
    });

    test('creates the file when absent', () async {
      Map<String, dynamic>? server;
      final client = MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response('not found', 404);
        }
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body.containsKey('sha'), isFalse); // create, not update
        server = jsonDecode(
          utf8.decode(base64.decode(body['content'] as String)),
        );
        return http.Response('{}', 201);
      });

      final gh = GithubService(client);
      await gh.mutateJson(
        'data/new.json',
        transform: (current) {
          expect(current, isNull);
          return {'created': true};
        },
      );
      expect(server, {'created': true});
    });

    test('throws WriteConflictException after exhausting retries', () async {
      final client = MockClient((req) async {
        if (req.method == 'GET') {
          return _contents({'v': 1}, 'sha');
        }
        return http.Response('conflict', 409); // always conflicts
      });
      final gh = GithubService(client);
      expect(
        () => gh.mutateJson(
          'users/x.json',
          maxRetries: 2,
          transform: (c) => {'v': 2},
        ),
        throwsA(isA<WriteConflictException>()),
      );
    });
  });
}
