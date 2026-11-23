import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/league.dart';
import 'game_state_provider.dart';

/// The live La Liga season (all fixtures + results → the table). Backend file
/// `data/league.json`; falls back to a structural round-robin before it loads.
class LeagueNotifier extends AsyncNotifier<LeagueData> {
  @override
  Future<LeagueData> build() => _load();

  Future<LeagueData> _load() async {
    final gh = ref.read(githubServiceProvider);
    final file = await gh.getJson('data/league.json');
    if (file == null) return LeagueData.buildDefault();
    return LeagueData.fromJson(file.data as Map<String, dynamic>);
  }

  Future<void> refresh() async {
    ref.read(githubServiceProvider).clearPath('data/league.json');
    state = const AsyncLoading();
    state = AsyncData(await _load());
  }

  Future<void> updateMatchScore({
    required String matchId,
    int? homeScore,
    int? awayScore,
    bool? postponed,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.updateMatch(
      matchId,
      homeScore: homeScore,
      awayScore: awayScore,
      postponed: postponed,
    );
    // Optimistic update.
    state = AsyncData(updated);

    // Persist — conflict-safe: re-apply this single match edit onto the freshest
    // league so a concurrent score entry isn't clobbered.
    final gh = ref.read(githubServiceProvider);
    await gh.mutateJson(
      'data/league.json',
      message: 'admin: score $matchId ${homeScore ?? '-'}-${awayScore ?? '-'}',
      transform: (server) {
        if (server == null) return updated.toJson();
        return LeagueData.fromJson(server as Map<String, dynamic>)
            .updateMatch(
              matchId,
              homeScore: homeScore,
              awayScore: awayScore,
              postponed: postponed,
            )
            .toJson();
      },
    );
    gh.clearPath('data/league.json');
  }
}

final leagueProvider = AsyncNotifierProvider<LeagueNotifier, LeagueData>(
  LeagueNotifier.new,
);
