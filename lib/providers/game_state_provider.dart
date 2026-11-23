import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player.dart';
import '../models/daily.dart';
import '../models/match.dart';
import '../utils/app_clock.dart';
import 'github_provider.dart';

// Single source of truth for the GitHub service provider. Re-exported here so
// every screen (which already imports this file) shares ONE GithubService
// instance — and therefore ONE cache. Previously a second definition in
// user_provider.dart created a divergent cache, so screen-level clearCache()
// calls invalidated the wrong cache and left ownership data stale.
export 'github_provider.dart'
    show githubServiceProvider, GithubService, GithubFile, DataStore;

final playersProvider = FutureProvider<List<Player>>((ref) async {
  final gh = ref.read(githubServiceProvider);
  final file = await gh.getJson('data/players.json');
  if (file == null) return [];
  final list = (file.data['players'] as List<dynamic>);
  return list.map((e) => Player.fromJson(e as Map<String, dynamic>)).toList();
});

String _mdFile(int n) => 'daily/md${n.toString().padLeft(2, '0')}.json';

/// The active league matchday number (1..38). A single pointer in
/// `data/app_config.json` (`current_matchday`), advanced by the resolution
/// script when a matchday fully resolves and settable by the admin. Defaults to
/// 1 (pre-season). Reading a pointer keeps this to one cheap file read rather
/// than scanning all 38 matchday files.
final currentMatchdayNumberProvider = FutureProvider<int>((ref) async {
  final gh = ref.read(githubServiceProvider);
  final file = await gh.getJson('data/app_config.json');
  final n = (file?.data as Map<String, dynamic>?)?['current_matchday'] as num?;
  return n?.toInt() ?? 1;
});

/// The current matchday's fixtures/windows/bets — drives the weekly gameplay and
/// the manage/cards/games phase windows (see `time_utils.dart`).
final currentMatchdayProvider = FutureProvider<DailyMatchday?>((ref) async {
  final n = await ref.watch(currentMatchdayNumberProvider.future);
  final gh = ref.read(githubServiceProvider);
  final file = await gh.getJson(_mdFile(n));
  if (file == null) return null;
  return DailyMatchday.fromJson(file.data as Map<String, dynamic>);
});

/// Matchdays that already have played results — used by the "results" browser to
/// inspect each past match's player stats. Ordered most-recent (highest
/// matchday) first.
final pastMatchdaysProvider = FutureProvider<List<DailyMatchday>>((ref) async {
  final gh = ref.read(githubServiceProvider);
  final files = await gh.listDir('daily');
  if (files == null) return [];
  final names =
      files
          .map((f) => (f['name'] as String))
          .where((n) => n.endsWith('.json'))
          .toList()
        ..sort();
  final out = <DailyMatchday>[];
  for (final name in names) {
    final file = await gh.getJson('daily/$name');
    if (file == null) continue;
    final md = DailyMatchday.fromJson(file.data as Map<String, dynamic>);
    final played = md.matches.any(
      (m) => m.score != null || m.players.any((p) => p.rating != null),
    );
    if (played) out.add(md);
  }
  out.sort((a, b) => b.matchday.compareTo(a.matchday));
  return out;
});

final activityLogProvider = FutureProvider<List<ActivityEvent>>((ref) async {
  final gh = ref.read(githubServiceProvider);
  final file = await gh.getJson('data/activity_log.json');
  if (file == null) return [];
  final list = file.data['events'] as List<dynamic>? ?? [];
  return list
      .map((e) => ActivityEvent.fromJson(e as Map<String, dynamic>))
      .toList();
});

final chatProvider = FutureProvider<List<ChatMessage>>((ref) async {
  final gh = ref.read(githubServiceProvider);
  final file = await gh.getJson('chat.json');
  if (file == null) return [];
  final list = file.data['messages'] as List<dynamic>? ?? [];
  return list
      .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Every match across all daily files, indexed by fixture id — lets the results
/// browser / league table open a match's player stats on tap. Cached.
final dailyMatchByIdProvider = FutureProvider<Map<String, DailyMatch>>((
  ref,
) async {
  final gh = ref.read(githubServiceProvider);
  final files = await gh.listDir('daily');
  if (files == null) return {};
  final out = <String, DailyMatch>{};
  for (final f in files) {
    final name = f['name'] as String;
    if (!name.endsWith('.json')) continue;
    final file = await gh.getJson('daily/$name');
    if (file == null) continue;
    final md = DailyMatchday.fromJson(file.data as Map<String, dynamic>);
    for (final m in md.matches) {
      out[m.id] = m;
    }
  }
  return out;
});

/// Syncs the admin's simulated clock to THIS device: reads `clock_override` from
/// data/app_config.json (fresh) and applies it via [applyClockOverrideFromRemote]
/// so the day-phase logic matches across all users. Watched at the app root and
/// re-fetched by the home poller, so an admin time change propagates everywhere.
///
/// PURE read — it only returns the backend's `clock_override`. The actual apply
/// (`applyClockOverrideFromRemote`) is done by a `ref.listen` in HomeScreen, so
/// we never mutate clockProvider mid-build (which silently dropped the change and
/// made the admin's phase switch look broken).
final clockSyncProvider = FutureProvider<DateTime?>((ref) async {
  final gh = ref.read(githubServiceProvider);
  final file = await gh.getJson('data/app_config.json', useCache: false);
  final raw = (file?.data as Map<String, dynamic>?)?['clock_override'] as String?;
  return raw == null ? null : DateTime.tryParse(raw);
});

/// Whether users may edit their Quiniela predictions / Pichichi picks.
/// Toggled by the admin; stored in data/app_config.json. Defaults to open.
final predictionsOpenProvider = FutureProvider<bool>((ref) async {
  final gh = ref.read(githubServiceProvider);
  final file = await gh.getJson('data/app_config.json');
  if (file == null) return true;
  return (file.data as Map<String, dynamic>)['predictions_open'] as bool? ??
      true;
});

class AllUsersNotifier extends AsyncNotifier<Map<String, dynamic>> {
  @override
  Future<Map<String, dynamic>> build() => _load();

  Future<Map<String, dynamic>> _load({bool fresh = false}) async {
    final gh = ref.read(githubServiceProvider);
    final files = await gh.listDir('users');
    if (files == null) return {};
    final jsonFiles = files
        .where((f) => (f['name'] as String).endsWith('.json'))
        .toList();
    final results = await Future.wait(
      jsonFiles.map((f) async {
        final name = (f['name'] as String).replaceAll('.json', '');
        // fresh=true bypasses the cache so the live %/points reflect the latest
        // cards everyone has played this window.
        final file = await gh.getJson('users/${f['name']}', useCache: !fresh);
        return MapEntry(name, file?.data);
      }),
    );
    final map = <String, dynamic>{};
    for (final e in results) {
      if (e.value != null) map[e.key] = e.value;
    }
    return map;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _load());
  }

  /// Silent background refresh (keeps current data on screen while re-fetching)
  /// used by the live poller during the cards/games window.
  Future<void> poll() async {
    final fresh = await _load(fresh: true);
    state = AsyncData(fresh);
  }
}

final allUsersProvider =
    AsyncNotifierProvider<AllUsersNotifier, Map<String, dynamic>>(
      AllUsersNotifier.new,
    );

final popularityMapProvider = FutureProvider<Map<String, int>>((ref) async {
  final allUsers = await ref.watch(allUsersProvider.future);
  final counts = <String, int>{};
  for (final userData in allUsers.values) {
    final data = userData as Map<String, dynamic>;
    for (final pos in ['GK', 'DEF', 'MID', 'FWD']) {
      final sqList = (data['squad'] as Map?)?[pos] as List? ?? [];
      final bkList = (data['bench'] as Map?)?[pos] as List? ?? [];
      for (final pid in [...sqList, ...bkList]) {
        counts[pid.toString()] = (counts[pid.toString()] ?? 0) + 1;
      }
    }
  }
  return counts;
});
