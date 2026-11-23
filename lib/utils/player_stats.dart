import '../models/daily.dart';

/// One player's row in one played matchday (from `daily/mdNN.json`).
class PlayerMatchLine {
  final int matchday;
  final String fixtureId;
  final MatchPlayer stats;

  /// Opponent club, 'W' / 'D' / 'L' for the player's team, and whether he was
  /// the top scorer of points in that fixture. Null / false when the player's
  /// team or the score is unknown.
  final String? opponent;
  final String? result;
  final bool mvp;

  const PlayerMatchLine({
    required this.matchday,
    required this.fixtureId,
    required this.stats,
    this.opponent,
    this.result,
    this.mvp = false,
  });
}

/// Aggregate record against one opponent club.
class HeadToHead {
  final String opponent;
  final int played, wins, draws, losses, goals, assists;
  const HeadToHead(this.opponent, this.played, this.wins, this.draws,
      this.losses, this.goals, this.assists);
}

/// A player's season picture, built only from the matchdays the app already
/// stores. Nothing here is invented: a matchday without a row for the player
/// simply does not count.
class PlayerSeasonStats {
  /// Chronological (oldest matchday first).
  final List<PlayerMatchLine> lines;

  const PlayerSeasonStats(this.lines);

  int get appearances => lines.length;
  int get goals => lines.fold(0, (s, l) => s + l.stats.goals);
  int get assists => lines.fold(0, (s, l) => s + l.stats.assists);
  int get yellow => lines.fold(0, (s, l) => s + l.stats.yellow);
  int get red => lines.fold(0, (s, l) => s + l.stats.red);
  double get points => lines.fold(0.0, (s, l) => s + l.stats.points);

  /// Estimated minutes played (ESPN gives no exact minutes), or null when no
  /// matchday recorded them.
  int? get minutes {
    final known = lines.where((l) => l.stats.minutes != null).toList();
    if (known.isEmpty) return null;
    return known.fold<int>(0, (s, l) => s + (l.stats.minutes ?? 0));
  }

  int _count(String r) => lines.where((l) => l.result == r).length;
  int get wins => _count('W');
  int get draws => _count('D');
  int get losses => _count('L');

  /// Win rate (0..1) over appearances with a known result; 0 with none.
  double get winRate {
    final n = wins + draws + losses;
    return n == 0 ? 0 : wins / n;
  }

  int get mvps => lines.where((l) => l.mvp).length;
  double get avgPoints => appearances == 0 ? 0 : points / appearances;
  double get bestPoints =>
      lines.isEmpty ? 0 : lines.map((l) => l.stats.points).reduce((a, b) => a > b ? a : b);

  /// Longest run of consecutive appearances satisfying [test].
  int _streak(bool Function(PlayerMatchLine) test) {
    var best = 0, cur = 0;
    for (final l in lines) {
      cur = test(l) ? cur + 1 : 0;
      if (cur > best) best = cur;
    }
    return best;
  }

  int get scoringStreak => _streak((l) => l.stats.goals > 0);
  int get unbeatenStreak => _streak((l) => l.result == 'W' || l.result == 'D');

  /// Records per opponent, most played first (ties: alphabetical).
  List<HeadToHead> get headToHead {
    final by = <String, List<PlayerMatchLine>>{};
    for (final l in lines) {
      if (l.opponent != null) (by[l.opponent!] ??= []).add(l);
    }
    int c(List<PlayerMatchLine> ls, String r) =>
        ls.where((l) => l.result == r).length;
    final out = [
      for (final e in by.entries)
        HeadToHead(
          e.key,
          e.value.length,
          c(e.value, 'W'),
          c(e.value, 'D'),
          c(e.value, 'L'),
          e.value.fold(0, (s, l) => s + l.stats.goals),
          e.value.fold(0, (s, l) => s + l.stats.assists),
        ),
    ]..sort((a, b) {
        final d = b.played.compareTo(a.played);
        return d != 0 ? d : a.opponent.compareTo(b.opponent);
      });
    return out;
  }

  /// Points of the last [n] matchdays, oldest first ("form").
  List<double> form([int n = 5]) {
    final start = lines.length > n ? lines.length - n : 0;
    return [for (final l in lines.sublist(start)) l.stats.points];
  }
}

/// Collects [playerId]'s rows across [matchdays] (any order, played only).
/// Pass the player's [team] to also get results, opponents and MVPs.
PlayerSeasonStats playerSeasonStats(
  String playerId,
  Iterable<DailyMatchday> matchdays, {
  String? team,
}) {
  final lines = <PlayerMatchLine>[];
  for (final md in matchdays) {
    for (final m in md.matches) {
      for (final p in m.players) {
        if (p.id != playerId) continue;
        final home = team != null && m.home == team;
        final away = team != null && m.away == team;
        final g = m.goals;
        String? result;
        if (g != null && (home || away)) {
          final mine = home ? g[0] : g[1], theirs = home ? g[1] : g[0];
          result = mine > theirs ? 'W' : (mine == theirs ? 'D' : 'L');
        }
        final top = m.players.fold<double>(
          double.negativeInfinity,
          (a, x) => x.points > a ? x.points : a,
        );
        lines.add(
          PlayerMatchLine(
            matchday: md.matchday,
            fixtureId: m.id,
            stats: p,
            opponent: home ? m.away : (away ? m.home : null),
            result: result,
            mvp: m.players.length > 1 && p.points >= top && p.points > 0,
          ),
        );
      }
    }
  }
  lines.sort((a, b) => a.matchday.compareTo(b.matchday));
  return PlayerSeasonStats(lines);
}
