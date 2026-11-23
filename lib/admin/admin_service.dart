import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily.dart';
import '../models/league.dart';
import '../models/player.dart';
import '../models/powerup_card.dart';
import '../models/user_data.dart';
import '../providers/game_state_provider.dart';
import '../utils/card_effects.dart';
import '../utils/scoring.dart';

/// Internal testing/admin operations, kept entirely separate from production
/// gameplay code. Everything here writes to the same GitHub data layer used by
/// the app, so the app picks up changes on its next (cache-invalidated) read.
///
/// Note: authoritative daily scoring / reward distribution lives in the Python
/// scripts (scripts/daily_resolution.py) and runs in CI — it is intentionally
/// NOT duplicated here. Use [dispatchResolution] to trigger that pipeline.
final adminServiceProvider = Provider<AdminService>(
  (ref) => AdminService(ref.read(githubServiceProvider)),
);

/// Generates [count] random powerup cards (for testing the cards UI). Uses the
/// real rarity/category tables; probabilities are uniform, which is fine for a
/// test tool.
List<PowerupCard> generateRandomCards(Random rng, {int count = 5}) {
  // Uniform across all types (admin testing wants every card reachable), built
  // from the catalog. Gameplay packs use the weighted/rule-based generator.
  const types = CardType.values;
  return List.generate(
    count,
    (_) => PowerupCard.ofType(types[rng.nextInt(types.length)], variant: 'admin'),
  );
}

/// Builds a fully-played league with random results, so the table can be
/// exercised end-to-end. Pure (no I/O) and seedable for deterministic tests.
LeagueData simulateLeagueData(Random rng) {
  final base = LeagueData.buildDefault();
  return LeagueData(
    matches: base.matches
        .map(
          (m) =>
              m.copyWith(homeScore: rng.nextInt(4), awayScore: rng.nextInt(4)),
        )
        .toList(),
  );
}

class AdminService {
  final GithubService gh;
  AdminService(this.gh);

  Future<List<String>> listUsernames() async {
    final files = await gh.listDir('users');
    if (files == null) return [];
    return files
        .map((f) => f['name'] as String)
        .where((n) => n.endsWith('.json'))
        .map((n) => n.replaceAll('.json', ''))
        .toList()
      ..sort();
  }

  Future<UserData?> loadUser(String name) async {
    final f = await gh.getFreshJson('users/$name.json');
    if (f == null) return null;
    return UserData.fromJson(f.data as Map<String, dynamic>);
  }

  Future<void> _writeUser(String name, UserData u, String msg) async {
    // Admin overwrite (reset/rename/cards) — conflict-safe via mutateJson, which
    // retries on a stale-sha rejection.
    await gh.mutateJson(
      'users/$name.json',
      message: msg,
      transform: (_) => u.toJson(),
    );
  }

  Future<void> resetUser(String name) =>
      _writeUser(name, UserData.empty(name), 'admin: reset $name');

  Future<void> resetAllUsers() async {
    for (final n in await listUsernames()) {
      await resetUser(n);
    }
  }

  Future<void> renameUser(String oldName, String newName) async {
    if (newName.trim().isEmpty) throw Exception('New name is empty');
    final f = await gh.getFreshJson('users/$oldName.json');
    if (f == null) throw Exception('User "$oldName" not found');
    if (await gh.getFreshJson('users/$newName.json') != null) {
      throw Exception('User "$newName" already exists');
    }
    final data = Map<String, dynamic>.from(f.data as Map<String, dynamic>);
    data['name'] = newName;
    await gh.createJson(
      'users/$newName.json',
      data,
      'admin: rename $oldName -> $newName',
    );
    await gh.deleteFile(
      'users/$oldName.json',
      f.sha,
      'admin: rename remove $oldName',
    );
  }

  Future<void> giveRandomCards(String name, {Random? rng}) async {
    final u = await loadUser(name);
    if (u == null) throw Exception('User "$name" not found');
    final active = ActiveState(
      captain: u.active.captain,
      bets: u.active.bets,
      cardsReceived: generateRandomCards(rng ?? Random()),
      cardsPlayed: u.active.cardsPlayed,
      attacksReceivedToday: u.active.attacksReceivedToday,
    );
    await _writeUser(
      name,
      u.copyWith(active: active),
      'admin: give cards $name',
    );
  }

  /// Remotely signs [name] out: sets the `force_logout` flag (per-key merge, so
  /// their squad/points are untouched). Their app clears its local session on
  /// next load/refresh; the flag auto-clears when they log back in.
  Future<void> forceLogoutUser(String name) async {
    await gh.mutateJson(
      'users/$name.json',
      message: 'admin: force logout $name',
      transform: (current) {
        final data = current is Map
            ? Map<String, dynamic>.from(current)
            : <String, dynamic>{};
        data['force_logout'] = true;
        return data;
      },
    );
  }

  Future<void> clearCards(String name) async {
    final u = await loadUser(name);
    if (u == null) throw Exception('User "$name" not found');
    final active = ActiveState(
      captain: u.active.captain,
      bets: u.active.bets,
      attacksReceivedToday: 0,
    );
    await _writeUser(
      name,
      u.copyWith(active: active),
      'admin: clear cards $name',
    );
  }

  Future<void> simulateLeague({int? seed}) async {
    final ld = simulateLeagueData(
      Random(seed ?? DateTime.now().millisecondsSinceEpoch),
    );
    await _writeLeague(ld, 'admin: simulate league');
  }

  Future<void> resetLeague() =>
      _writeLeague(LeagueData.buildDefault(), 'admin: reset league');

  Future<void> _writeLeague(LeagueData ld, String msg) async {
    await gh.mutateJson(
      'data/league.json',
      message: msg,
      transform: (_) => ld.toJson(),
    );
  }

  /// Sets the active matchday pointer (data/app_config.json `current_matchday`).
  Future<void> setCurrentMatchdayNumber(int n) async {
    await gh.mutateJson(
      'data/app_config.json',
      message: 'admin: current matchday $n',
      transform: (current) {
        final data = current is Map
            ? Map<String, dynamic>.from(current)
            : <String, dynamic>{};
        data['current_matchday'] = n;
        return data;
      },
    );
  }

  /// Loads a matchday by its file key (e.g. 'md05').
  Future<DailyMatchday?> loadDaily(String mdKey) async {
    final f = await gh.getJson('daily/$mdKey.json', useCache: false);
    if (f == null) return null;
    return DailyMatchday.fromJson(f.data as Map<String, dynamic>);
  }

  /// Applies a matchday's results and scores everyone (see SCORING.md):
  ///  - writes per-fixture scorelines, per-player goals/assists + **ratings**,
  ///    and per-bet answers into `daily/<mdKey>.json`, and mirrors the scorelines
  ///    into `data/league.json` so the table updates;
  ///  - **team points**: each user's fielded players (XI + bench + card extras)
  ///    score `rating × base × ownership × cardMult × captain`
  ///    (`teamMatchdayPoints`), folding in their played boosts and incoming
  ///    attacks;
  ///  - **bet points**: each graded bet's pot (`participants × stake`) is split
  ///    among the users who picked the correct answer;
  ///  - **Quiniela points**: 1-X-2 signs derived from the scorelines are graded
  ///    against each user's [QuinielaPrediction].
  /// Accumulates into each user's points and logs the run. Not idempotent — run
  /// once per matchday (postponed fixtures should be included once their result
  /// is known). Returns a summary.
  Future<String> applyResultsAndScore({
    required String mdKey, // e.g. 'md05'
    required Map<String, List<int>> matchScores, // fixtureId -> [home, away]
    required Map<String, List<int>> goalsAssists, // pid -> [goals, assists]
    required Map<String, double> ratings, // pid -> rating (1–10)
    Map<String, String> betAnswers = const {}, // betId -> correct option
  }) async {
    final probe = await gh.getFreshJson('daily/$mdKey.json');
    if (probe == null) throw Exception('No matchday $mdKey');
    // Guard: a second run would add every user's points again (the team points
    // are recomputed from the same squads). Set again only at the very end.
    if ((probe.data as Map)['scored'] == true) {
      throw Exception('$mdKey is already scored');
    }

    // 1. Write scorelines + goals/assists/ratings + bet answers into the matchday.
    await gh.mutateJson(
      'daily/$mdKey.json',
      message: 'admin: results $mdKey',
      transform: (current) {
        final data = Map<String, dynamic>.from(current as Map<String, dynamic>);
        for (final m in (data['matches'] as List)) {
          final mm = m as Map;
          final sc = matchScores[mm['id']];
          if (sc != null && sc.length >= 2) mm['score'] = '${sc[0]}-${sc[1]}';
          for (final p in (mm['players'] as List)) {
            final pp = p as Map;
            final id = pp['id'] as String;
            final ga = goalsAssists[id];
            if (ga != null && ga.isNotEmpty) {
              pp['goals'] = ga[0];
              if (ga.length > 1) pp['assists'] = ga[1];
            }
            final r = ratings[id];
            if (r != null) pp['rating'] = r;
          }
        }
        if (data['bets'] is List) {
          for (final b in (data['bets'] as List)) {
            final ans = betAnswers[(b as Map)['id']];
            if (ans != null) b['answer'] = ans;
          }
        }
        return data;
      },
    );

    // 1b. Mirror the scorelines into data/league.json (drives the table).
    await gh.mutateJson(
      'data/league.json',
      message: 'admin: league scores $mdKey',
      transform: (current) {
        var ld = current == null
            ? LeagueData.buildDefault()
            : LeagueData.fromJson(current as Map<String, dynamic>);
        for (final e in matchScores.entries) {
          if (e.value.length >= 2) {
            ld = ld.updateMatch(
              e.key,
              homeScore: e.value[0],
              awayScore: e.value[1],
            );
          }
        }
        return ld.toJson();
      },
    );
    gh.clearPath('data/league.json');

    // 1c. Quiniela actual signs from the scorelines.
    final actualSigns = <String, String>{};
    matchScores.forEach((id, sc) {
      if (sc.length >= 2) {
        actualSigns[id] = sc[0] > sc[1]
            ? '1'
            : (sc[1] > sc[0] ? '2' : 'X');
      }
    });

    // 2. Load players + users.
    final pf = await gh.getJson('data/players.json', useCache: false);
    final playersById = <String, Player>{
      for (final e in (((pf?.data as Map?)?['players'] as List?) ?? const []))
        (e as Map<String, dynamic>)['id'] as String: Player.fromJson(e),
    };
    final users = <String, UserData>{};
    for (final n in await listUsernames()) {
      final u = await loadUser(n);
      if (u != null) users[n] = u;
    }
    final allUsersRaw = {for (final e in users.entries) e.key: e.value.toJson()};
    final counts = <String, int>{};
    for (final u in users.values) {
      for (final pid in u.allPlayers) {
        counts[pid] = (counts[pid] ?? 0) + 1;
      }
    }
    final totalUsers = users.length.clamp(1, 9999);

    // 3. Grade bets: split each pot among the users who answered correctly.
    final betPointsByUser = <String, double>{};
    final daily = await loadDaily(mdKey);
    for (final bet in daily?.bets ?? const []) {
      final answer = bet.answer;
      if (answer == null) continue;
      var participants = 0, correct = 0;
      for (final u in users.values) {
        final pick = u.active.bets[bet.id];
        if (pick == null) continue;
        participants++;
        if (pick == answer) correct++;
      }
      if (correct == 0) continue;
      for (final e in users.entries) {
        if (e.value.active.bets[bet.id] == answer) {
          betPointsByUser[e.key] = (betPointsByUser[e.key] ?? 0) +
              betPoints(
                participants: participants,
                correctCount: correct,
                isCorrect: true,
              );
        }
      }
    }

    // 4. Team points per user (per-player boosts + incoming attacks).
    final mdDate = daily?.date ?? mdKey; // captain is keyed by the matchday date
    final teamPtsByUser = <String, double>{};
    final cardsByUser = <String, List<PowerupCard>>{};
    for (final entry in users.entries) {
      final u = entry.value;
      final captainId = u.captainFor(today: mdDate, matchdayDate: mdDate);
      var mods = pointDisplayMods(
        cardsPlayed: u.active.cardsPlayed,
        playersById: playersById,
      );
      mods = foldIncomingAttacks(mods, viewer: u.name, allUsers: allUsersRaw);
      final fielded = <String>{...u.allPlayers};
      for (final c in u.active.cardsPlayed) {
        if ((c.type == CardType.robo || c.type == CardType.pitchInvader) &&
            c.targetPlayer != null) {
          fielded.add(c.targetPlayer!);
        }
      }
      teamPtsByUser[entry.key] = teamMatchdayPoints(
        fieldedIds: fielded.toList(),
        ratings: ratings,
        ownershipCounts: counts,
        totalUsers: totalUsers,
        captainId: captainId,
        mods: mods,
      );
      cardsByUser[entry.key] = u.active.cardsPlayed.toList();
    }

    // 4a. Quiniela points per user from the matchday's 1-X-2 results.
    final quinielaByUser = <String, double>{
      for (final entry in users.entries)
        entry.key: quinielaPoints(
          pred: entry.value.quinielaPrediction,
          actualSigns: actualSigns,
        ),
    };

    // 4b. Day-total card effects (flat ±, HACIENDA/GRADA %, EL CHIRINGUITO).
    final betByUser = {for (final n in users.keys) n: betPointsByUser[n] ?? 0.0};
    final dayTotals = dayTotalsWithCardEffects(
      teamPts: teamPtsByUser,
      betPts: betByUser,
      cardsByUser: cardsByUser,
    );

    // 4c. Write each user once — score those with pts > 0, reset active for all.
    var scored = 0;
    for (final entry in users.entries) {
      final teamPts = teamPtsByUser[entry.key] ?? 0;
      final betPts = betByUser[entry.key] ?? 0;
      final quinielaPts = quinielaByUser[entry.key] ?? 0;
      final day = dayTotals[entry.key] ?? (teamPts + betPts);
      final cardsDelta = day - teamPts - betPts;
      final u = entry.value;
      // Mirror daily_resolution.py: clear per-matchday active state.
      // cards_received is preserved so users keep any unplayed cards.
      final clearedActive = ActiveState(
        captain: null,
        bets: {},
        cardsReceived: u.active.cardsReceived,
        cardsPlayed: [],
        attacksReceivedToday: 0,
      );
      final hasPoints =
          teamPts != 0 || betPts != 0 || cardsDelta != 0 || quinielaPts != 0;
      if (!hasPoints) {
        // No points this matchday but still reset active so it's clean next week.
        await _writeUser(
          entry.key,
          u.copyWith(active: clearedActive),
          'admin: reset active $mdKey ${entry.key}',
        );
        continue;
      }
      final pts = u.points;
      await _writeUser(
        entry.key,
        u.copyWith(
          points: UserPoints(
            total: pts.total + day + quinielaPts,
            squad: pts.squad + teamPts,
            bets: pts.bets + betPts,
            quiniela: pts.quiniela + quinielaPts,
            goldenBoot: pts.goldenBoot,
            steals: pts.steals,
            cards: pts.cards + cardsDelta,
          ),
          active: clearedActive,
        ),
        'admin: score $mdKey ${entry.key}',
      );
      scored++;
    }
    await gh.mutateJson(
      'daily/$mdKey.json',
      message: 'admin: scored $mdKey',
      transform: (current) => {...(current as Map<String, dynamic>), 'scored': true},
    );
    await _appendActivityLog('Resultados de $mdKey aplicados ($scored usuarios)');
    return 'Scored $scored users for $mdKey';
  }

  /// Recomputes every user's season **Pichichi / top-assist** pick points from
  /// the current player goal/assist totals: `kSeasonPickPts` per goal of the
  /// chosen Pichichi and per assist of the chosen top-assister. Recomputed (not
  /// accumulated) into `points.goldenBoot`.
  Future<String> scoreSeasonPicksAllUsers() async {
    final pf = await gh.getJson('data/players.json', useCache: false);
    final players = (((pf?.data as Map?)?['players'] as List?) ?? const [])
        .map((e) => Player.fromJson(e as Map<String, dynamic>))
        .toList();
    final playerGoals = {for (final p in players) p.id: p.goals};
    final playerAssists = {for (final p in players) p.id: p.assists};
    var scored = 0;
    for (final n in await listUsernames()) {
      final u = await loadUser(n);
      if (u == null) continue;
      var picks = 0.0;
      if (u.goldenBoot != null) {
        picks += kSeasonPickPts * (playerGoals[u.goldenBoot] ?? 0);
      }
      if (u.topAssister != null) {
        picks += kSeasonPickPts * (playerAssists[u.topAssister] ?? 0);
      }
      final pts = u.points;
      await _writeUser(
        n,
        u.copyWith(
          points: UserPoints(
            total:
                pts.squad +
                pts.bets +
                pts.quiniela +
                picks +
                pts.steals +
                pts.cards,
            squad: pts.squad,
            bets: pts.bets,
            quiniela: pts.quiniela,
            goldenBoot: picks,
            steals: pts.steals,
            cards: pts.cards,
          ),
        ),
        'admin: season picks score $n',
      );
      scored++;
    }
    await _appendActivityLog('Pichichi/asistencias puntuadas ($scored usuarios)');
    return 'Season-picks-scored $scored users';
  }

  /// Appends a server-side activity-log entry (read by the home feed on open).
  /// Conflict-safe prepend so concurrent log writes aren't lost.
  Future<void> _appendActivityLog(String message) async {
    await gh.mutateJson(
      'data/activity_log.json',
      message: 'admin: log',
      transform: (current) {
        final data = current is Map
            ? Map<String, dynamic>.from(current)
            : <String, dynamic>{};
        final events = List<dynamic>.from(data['events'] as List? ?? const [])
          ..insert(0, {
            'timestamp': DateTime.now().toIso8601String(),
            'type': 'admin',
            'message': message,
          });
        data['events'] = events;
        return data;
      },
    );
  }

  /// Opens/closes Quiniela predictions for all users (data/app_config.json).
  /// Per-key merge so other config keys are preserved.
  Future<void> setPredictionsOpen(bool open) async {
    await gh.mutateJson(
      'data/app_config.json',
      message: 'admin: predictions ${open ? "open" : "closed"}',
      transform: (current) {
        final data = current is Map
            ? Map<String, dynamic>.from(current)
            : <String, dynamic>{};
        data['predictions_open'] = open;
        return data;
      },
    );
  }

  /// Creates (or overwrites) a one-match test matchday [mdNumber] (file
  /// `daily/md<NN>.json`) so users can set squads/captains, play cards, and bet
  /// against a fixture. The roster is both teams' players, pre-resolution.
  /// Windows are derived from [firstKickoff] (cards open −6h, lock −2h).
  Future<void> createTestMatchday({
    required int mdNumber,
    required String homeTeam,
    required String awayTeam,
    required List<Player> allPlayers,
    DateTime? firstKickoff,
  }) async {
    final ko = firstKickoff ?? DateTime.now().add(const Duration(hours: 8));
    final id = fixtureId(mdNumber, homeTeam, awayTeam);
    final roster = allPlayers
        .where((p) => p.team == homeTeam || p.team == awayTeam)
        .map((p) => {'id': p.id, 'goals': 0, 'assists': 0, 'points': 0.0})
        .toList();
    final md = {
      'matchday': mdNumber,
      'date':
          '${ko.year}-${ko.month.toString().padLeft(2, '0')}-${ko.day.toString().padLeft(2, '0')}',
      'first_kickoff': ko.toIso8601String(),
      'cards_open': ko.subtract(const Duration(hours: 6)).toIso8601String(),
      'lock_at': ko.subtract(const Duration(hours: 2)).toIso8601String(),
      'matches': [
        {
          'id': id,
          'home': homeTeam,
          'away': awayTeam,
          'kickoff': ko.toIso8601String(),
          'score': null,
          'players': roster,
        },
      ],
      'bets': const [],
    };
    await gh.mutateJson(
      'daily/md${mdNumber.toString().padLeft(2, '0')}.json',
      message: 'admin: test matchday $mdNumber',
      transform: (_) => md,
    );
  }

  /// Triggers the CI resolution pipeline via workflow_dispatch. Returns the
  /// HTTP status (204 = accepted). Configurable because the workflow may live
  /// in a different repo than the data repo.
  Future<int> dispatchResolution({
    required String owner,
    required String repo,
    required String workflowFile,
    Map<String, dynamic> inputs = const {},
  }) {
    return gh.dispatchWorkflow(
      owner: owner,
      repo: repo,
      workflowFile: workflowFile,
      inputs: inputs,
    );
  }
}
