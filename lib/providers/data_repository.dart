import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/match.dart';
import 'game_state_provider.dart';

/// Centralized, conflict-safe writes to the **shared** data files (chat,
/// activity log, app config). Each operation is a `mutateJson` transform that
/// runs against the freshest server state and retries on write conflicts, so
/// concurrent appends from multiple users are never lost.
///
/// User-owned writes go through `userProvider.save` (also merge-safe); admin
/// writes go through `AdminService`. This repository owns the rest.
final dataRepositoryProvider = Provider<DataRepository>(
  (ref) => DataRepository(ref.read(githubServiceProvider)),
);

/// Activity log is capped to the most recent N events (newest first).
const int kActivityLogMax = 500;

class DataRepository {
  final GithubService _gh;
  DataRepository(this._gh);

  /// Appends a chat message to `chat.json` (merge: append to the current list).
  Future<void> appendChatMessage(ChatMessage message) async {
    await _gh.mutateJson(
      'chat.json',
      message: 'app: chat ${message.user}',
      transform: (current) {
        final messages = List<dynamic>.from(
          (current is Map ? current['messages'] : null) as List? ?? const [],
        )..add(message.toJson());
        return {'messages': messages};
      },
    );
  }

  /// Prepends an event to `data/activity_log.json` (newest first), capped.
  Future<void> appendActivityEvent(ActivityEvent event) async {
    await _gh.mutateJson(
      'data/activity_log.json',
      message: 'app: activity',
      transform: (current) {
        final events = List<dynamic>.from(
          (current is Map ? current['events'] : null) as List? ?? const [],
        )..insert(0, event.toJson());
        if (events.length > kActivityLogMax) {
          events.removeRange(kActivityLogMax, events.length);
        }
        final data = current is Map
            ? Map<String, dynamic>.from(current)
            : <String, dynamic>{};
        data['events'] = events;
        return data;
      },
    );
  }

  /// Sets a single key in `data/app_config.json`, **preserving other keys**.
  Future<void> setAppConfig(String key, dynamic value) async {
    await _gh.mutateJson(
      'data/app_config.json',
      message: 'app: config $key',
      transform: (current) {
        final data = current is Map
            ? Map<String, dynamic>.from(current)
            : <String, dynamic>{};
        data[key] = value;
        return data;
      },
    );
  }
}
