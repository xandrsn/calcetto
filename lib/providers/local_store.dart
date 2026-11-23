import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../demo/demo_backend.dart';
import 'data_store.dart';

const _prefsKey = 'calcetto_local_store_v1';
const _exportFormat = 'calcetto-local';

/// Local-first [DataStore]: every file lives on this device (base64 per path,
/// persisted as one JSON string in SharedPreferences). Needs no token or
/// network. First launch is seeded with the placeholder demo league. Share data
/// between devices with [exportJson] / [importJson] (a plain JSON file/text).
class LocalStore extends DataStore {
  final Map<String, String> _files;
  final Map<String, String> _shas = {};
  final Future<void> Function(String json)? _persist;
  var _counter = 0;

  LocalStore(Map<String, String> files, [this._persist])
    : _files = Map.of(files) {
    for (final p in _files.keys) {
      _shas[p] = _nextSha();
    }
  }

  /// Loads the saved store, or seeds placeholder data on first run.
  static Future<LocalStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    Future<void> persist(String j) => prefs.setString(_prefsKey, j);
    final saved = prefs.getString(_prefsKey);
    if (saved != null) {
      try {
        return LocalStore(_parse(saved), persist);
      } catch (_) {
        // Corrupt data: keep it aside rather than silently overwrite.
        await prefs.setString('${_prefsKey}_corrupt', saved);
      }
    }
    final s = LocalStore(demoSeedFiles(DateTime.now()), persist);
    await s._save();
    return s;
  }

  @override
  bool get isLocal => true;

  String _nextSha() => 'l${++_counter}';

  Future<void> _save() async => _persist?.call(exportJson());

  /// Whole store as a shareable JSON document.
  String exportJson() => jsonEncode({
    'format': _exportFormat,
    'version': 1,
    'files': _files,
  });

  /// Replaces ALL local data with an export. Throws [FormatException] (and
  /// changes nothing) if [text] is not a valid export.
  Future<void> importJson(String text) async {
    final files = _parse(text);
    _files
      ..clear()
      ..addAll(files);
    _shas
      ..clear()
      ..addEntries(files.keys.map((p) => MapEntry(p, _nextSha())));
    await _save();
  }

  static Map<String, String> _parse(String text) {
    final j = jsonDecode(text);
    if (j is! Map || j['format'] != _exportFormat || j['files'] is! Map) {
      throw const FormatException('Not a Calcetto export');
    }
    final files = <String, String>{};
    (j['files'] as Map).forEach((k, v) {
      if (v is! String) throw const FormatException('Bad file entry');
      base64.decode(v); // validates
      files[k as String] = v;
    });
    return files;
  }

  @override
  Future<GithubFile?> getJson(String path, {bool useCache = true}) async {
    final c = _files[path];
    if (c == null) return null;
    return GithubFile(jsonDecode(utf8.decode(base64.decode(c))), _shas[path]!);
  }

  @override
  Future<String?> getRawText(String path) async {
    final c = _files[path];
    return c == null ? null : utf8.decode(base64.decode(c));
  }

  @override
  Future<List<dynamic>?> listDir(String path) async {
    final out = <String, Map<String, dynamic>>{};
    for (final p in _files.keys) {
      if (!p.startsWith('$path/')) continue;
      final rest = p.substring(path.length + 1);
      final slash = rest.indexOf('/');
      final name = slash < 0 ? rest : rest.substring(0, slash);
      out[name] = {
        'name': name,
        'path': '$path/$name',
        'type': slash < 0 ? 'file' : 'dir',
        'sha': _shas[p],
      };
    }
    return out.isEmpty ? null : out.values.toList();
  }

  Future<void> _write(String path, List<int> bytes) async {
    _files[path] = base64.encode(bytes);
    _shas[path] = _nextSha();
    await _save();
  }

  @override
  Future<void> putJson(
    String path,
    dynamic content,
    String sha,
    String message,
  ) async {
    if (_shas[path] != sha) throw WriteConflictException(path);
    await _write(path, utf8.encode(jsonEncode(content)));
  }

  @override
  Future<void> createJson(String path, dynamic content, String message) async {
    if (_files.containsKey(path)) throw WriteConflictException(path);
    await _write(path, utf8.encode(jsonEncode(content)));
  }

  @override
  Future<String?> getSha(String path) async => _shas[path];

  @override
  Future<void> putFileBytes(
    String path,
    List<int> bytes,
    String? sha,
    String message,
  ) => _write(path, bytes);

  @override
  Future<void> deleteFile(String path, String sha, String message) async {
    if (_shas[path] != sha) throw WriteConflictException(path);
    _files.remove(path);
    _shas.remove(path);
    await _save();
  }

  /// No workflows exist locally; 204 mimics GitHub's "accepted".
  @override
  Future<int> dispatchWorkflow({
    required String owner,
    required String repo,
    required String workflowFile,
    String ref = 'main',
    Map<String, dynamic> inputs = const {},
  }) async => 204;

  @override
  void clearCache() {}

  @override
  void clearPath(String path) {}
}
