import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/providers/data_store.dart';
import 'package:calcetto/providers/local_store.dart';

void main() {
  LocalStore fresh() => LocalStore({});

  test('create, read, update with sha, conflict on stale sha', () async {
    final s = fresh();
    await s.createJson('users/a.json', {'n': 1}, 'm');
    final f = (await s.getJson('users/a.json'))!;
    expect(f.data, {'n': 1});
    await s.putJson('users/a.json', {'n': 2}, f.sha, 'm');
    expect(
      s.putJson('users/a.json', {'n': 3}, f.sha, 'm'),
      throwsA(isA<WriteConflictException>()),
    );
    expect(() => s.createJson('users/a.json', {}, 'm'),
        throwsA(isA<WriteConflictException>()));
  });

  test('mutateJson creates then merges; listDir lists children', () async {
    final s = fresh();
    for (var i = 0; i < 2; i++) {
      await s.mutateJson('chat.json', transform: (c) {
        final l = List<dynamic>.from((c as Map?)?['messages'] ?? []);
        return {'messages': l..add(i)};
      });
    }
    expect((await s.getJson('chat.json'))!.data, {'messages': [0, 1]});
    await s.createJson('users/x.json', {}, 'm');
    await s.putFileBytes('images/players/p.jpg', [1, 2, 3], null, 'm');
    expect((await s.listDir('users'))!.single['name'], 'x.json');
    expect((await s.listDir('images'))!.single['type'], 'dir');
    expect(await s.listDir('nope'), isNull);
  });

  test('export/import round-trips and rejects garbage', () async {
    final a = fresh();
    await a.createJson('data/p.json', {'k': 'v'}, 'm');
    final b = fresh();
    await b.importJson(a.exportJson());
    expect((await b.getJson('data/p.json'))!.data, {'k': 'v'});

    await expectLater(b.importJson('not json'), throwsFormatException);
    await expectLater(
      b.importJson(jsonEncode({'format': 'other', 'files': {}})),
      throwsFormatException,
    );
    // failed import leaves data intact
    expect((await b.getJson('data/p.json'))!.data, {'k': 'v'});
  });

  test('persists on every write', () async {
    String? saved;
    final s = LocalStore({}, (j) async => saved = j);
    await s.createJson('a.json', {'z': 1}, 'm');
    expect(saved, contains('a.json'));
  });
}
