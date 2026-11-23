import '../models/daily.dart';

/// One player's row in one played matchday (from `daily/mdNN.json`).
class PlayerMatchLine {
  final int matchday;
  final String fixtureId;
  final MatchPlayer stats;

  const PlayerMatchLine({
    required this.matchday,
    required this.fixtureId,
    required this.stats,
  });
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

  /// Points of the last [n] matchdays, oldest first ("form").
  List<double> form([int n = 5]) {
    final start = lines.length > n ? lines.length - n : 0;
    return [for (final l in lines.sublist(start)) l.stats.points];
  }
}

/// Collects [playerId]'s rows across [matchdays] (any order, played only).
PlayerSeasonStats playerSeasonStats(
  String playerId,
  Iterable<DailyMatchday> matchdays,
) {
  final lines = <PlayerMatchLine>[];
  for (final md in matchdays) {
    for (final m in md.matches) {
      for (final p in m.players) {
        if (p.id == playerId) {
          lines.add(
            PlayerMatchLine(
              matchday: md.matchday,
              fixtureId: m.id,
              stats: p,
            ),
          );
        }
      }
    }
  }
  lines.sort((a, b) => a.matchday.compareTo(b.matchday));
  return PlayerSeasonStats(lines);
}
