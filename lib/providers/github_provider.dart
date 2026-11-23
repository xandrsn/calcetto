import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../demo/demo_backend.dart';

final githubServiceProvider = Provider<GithubService>(
  (ref) => kDemoMode ? GithubService(demoHttpClient()) : GithubService(),
);

class GithubFile {
  final dynamic data;
  final String sha;

  const GithubFile(this.data, this.sha);
}

/// Thrown when a conditional write is rejected because the file's sha changed
/// since we read it (optimistic-concurrency conflict). [mutateJson] catches and
/// retries this; if retries are exhausted it surfaces to the caller.
class WriteConflictException implements Exception {
  final String path;
  const WriteConflictException(this.path);
  @override
  String toString() => 'WriteConflictException: concurrent write on $path';
}

class GithubService {
  static const _headers = {
    'Authorization': 'Bearer $kGithubToken',
    'Accept': 'application/vnd.github.v3+json',
    'Content-Type': 'application/json',
  };

  final _cache = <String, GithubFile>{};

  /// The HTTP client. Injectable so tests can supply a `MockClient`; defaults to
  /// the shared global client in production.
  final http.Client _client;

  GithubService([http.Client? client]) : _client = client ?? http.Client();

  Future<GithubFile?> getJson(String path, {bool useCache = true}) async {
    if (useCache && _cache.containsKey(path)) return _cache[path];
    final url = Uri.parse('$kGithubBaseUrl$path');
    final res = await _client.get(url, headers: _headers);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw Exception('GET $path failed: ${res.statusCode}');
    }
    final raw = jsonDecode(res.body) as Map<String, dynamic>;
    final sha = raw['sha'] as String;
    final decoded = utf8.decode(
      base64.decode((raw['content'] as String).replaceAll('\n', '')),
    );
    final parsed = jsonDecode(decoded);
    final file = GithubFile(parsed, sha);
    _cache[path] = file;
    return file;
  }

  Future<String?> getRawText(String path) async {
    final url = Uri.parse('$kGithubBaseUrl$path');
    final res = await _client.get(url, headers: _headers);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw Exception('GET $path failed: ${res.statusCode}');
    }
    final raw = jsonDecode(res.body) as Map<String, dynamic>;
    return utf8.decode(
      base64.decode((raw['content'] as String).replaceAll('\n', '')),
    );
  }

  Future<List<dynamic>?> listDir(String path) async {
    final url = Uri.parse('$kGithubBaseUrl$path');
    final res = await _client.get(url, headers: _headers);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw Exception('LIST $path failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<void> putJson(
    String path,
    dynamic content,
    String sha,
    String message,
  ) async {
    final url = Uri.parse('$kGithubBaseUrl$path');
    final jsonStr = jsonEncode(content);
    final b64 = base64.encode(utf8.encode(jsonStr));
    final body = jsonEncode({'message': message, 'content': b64, 'sha': sha});
    final res = await _client.put(url, headers: _headers, body: body);
    // 409/422 = the sha we sent is stale (someone wrote in between).
    if (res.statusCode == 409 || res.statusCode == 422) {
      _cache.remove(path);
      throw WriteConflictException(path);
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('PUT $path failed: ${res.statusCode} ${res.body}');
    }
    _cache.remove(path);
  }

  Future<void> createJson(String path, dynamic content, String message) async {
    final url = Uri.parse('$kGithubBaseUrl$path');
    final jsonStr = jsonEncode(content);
    final b64 = base64.encode(utf8.encode(jsonStr));
    final body = jsonEncode({'message': message, 'content': b64});
    final res = await _client.put(url, headers: _headers, body: body);
    // 422 here usually means the file already exists (created concurrently) —
    // treat as a conflict so mutateJson re-reads and merges onto it.
    if (res.statusCode == 409 || res.statusCode == 422) {
      _cache.remove(path);
      throw WriteConflictException(path);
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('CREATE $path failed: ${res.statusCode} ${res.body}');
    }
    _cache.remove(path);
  }

  /// Conflict-safe read-modify-write: reads the **freshest** JSON at [path]
  /// (null when absent), applies [transform] to it, and writes the result back
  /// conditionally on its sha. If the write is rejected because the file changed
  /// in between ([WriteConflictException]), it re-reads and re-applies, up to
  /// [maxRetries] with exponential backoff (~150ms, 300, 600, 1200).
  ///
  /// [transform] receives the current decoded JSON (or null) and must return the
  /// new decoded JSON to write. Because it runs against fresh server state on
  /// every attempt, edits **merge** onto reality instead of clobbering it.
  /// Returns the value that was written.
  Future<dynamic> mutateJson(
    String path, {
    required dynamic Function(dynamic current) transform,
    String message = 'app: update',
    int maxRetries = 4,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final file = await getFreshJson(path);
      final next = transform(file?.data);
      try {
        if (file == null) {
          await createJson(path, next, message);
        } else {
          await putJson(path, next, file.sha, message);
        }
        return next;
      } on WriteConflictException {
        if (attempt >= maxRetries) rethrow;
        await Future.delayed(Duration(milliseconds: 150 * (1 << attempt)));
        // loop: re-read fresh and re-apply the transform.
      }
    }
  }

  Future<GithubFile?> getFreshJson(String path) =>
      getJson(path, useCache: false);

  /// Returns just the git blob sha of [path] without decoding its content
  /// (works for binary files), or null if it doesn't exist.
  Future<String?> getSha(String path) async {
    final res = await _client.get(
      Uri.parse('$kGithubBaseUrl$path'),
      headers: _headers,
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw Exception('GET sha $path failed: ${res.statusCode}');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['sha'] as String?;
  }

  /// Writes raw binary [bytes] to [path] (create or overwrite). Pass the
  /// existing [sha] to overwrite, or null to create.
  Future<void> putFileBytes(
    String path,
    List<int> bytes,
    String? sha,
    String message,
  ) async {
    final url = Uri.parse('$kGithubBaseUrl$path');
    final body = jsonEncode({
      'message': message,
      'content': base64.encode(bytes),
      'sha': ?sha,
    });
    final res = await _client.put(url, headers: _headers, body: body);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('PUT(bytes) $path failed: ${res.statusCode} ${res.body}');
    }
    _cache.remove(path);
  }

  /// Deletes a file via the Contents API. [sha] must be the file's current sha.
  Future<void> deleteFile(String path, String sha, String message) async {
    final url = Uri.parse('$kGithubBaseUrl$path');
    final body = jsonEncode({'message': message, 'sha': sha});
    final res = await _client.delete(url, headers: _headers, body: body);
    if (res.statusCode != 200) {
      throw Exception('DELETE $path failed: ${res.statusCode} ${res.body}');
    }
    _cache.remove(path);
  }

  /// Triggers a GitHub Actions workflow_dispatch event. Returns the HTTP
  /// status so the caller can surface success/failure instead of guessing.
  /// [workflowFile] is e.g. 'daily_resolution.yml'. Requires the token to have
  /// the `workflow` scope and the workflow to exist on [ref] of the repo.
  Future<int> dispatchWorkflow({
    required String owner,
    required String repo,
    required String workflowFile,
    String ref = 'main',
    Map<String, dynamic> inputs = const {},
  }) async {
    final url = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/actions/workflows/$workflowFile/dispatches',
    );
    final res = await _client.post(
      url,
      headers: _headers,
      body: jsonEncode({'ref': ref, if (inputs.isNotEmpty) 'inputs': inputs}),
    );
    return res.statusCode;
  }

  void clearCache() => _cache.clear();
  void clearPath(String path) => _cache.remove(path);
}
