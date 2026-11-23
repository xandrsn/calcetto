import 'dart:async';

/// A JSON document and its version tag (git blob sha for GitHub).
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


/// Storage the app reads and writes. Paths mirror the data repo layout
/// (`users/x.json`, `daily/md01.json`, `images/players/..`). Implementations:
/// `GithubService` (optional remote repo) and `LocalStore` (on-device,
/// default when no token is configured). Writes are optimistic: [putJson]
/// throws [WriteConflictException] on a stale [sha].
abstract class DataStore {
  Future<GithubFile?> getJson(String path, {bool useCache = true});
  Future<String?> getRawText(String path);
  Future<List<dynamic>?> listDir(String path);
  Future<void> putJson(String path, dynamic content, String sha, String message);
  Future<void> createJson(String path, dynamic content, String message);
  Future<String?> getSha(String path);
  Future<void> putFileBytes(
    String path,
    List<int> bytes,
    String? sha,
    String message,
  );
  Future<void> deleteFile(String path, String sha, String message);
  Future<int> dispatchWorkflow({
    required String owner,
    required String repo,
    required String workflowFile,
    String ref = 'main',
    Map<String, dynamic> inputs = const {},
  });
  void clearCache();
  void clearPath(String path);

  /// True when data lives only on this device (photos are then stored inline).
  bool get isLocal => false;

  Future<GithubFile?> getFreshJson(String path) =>
      getJson(path, useCache: false);

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
}
