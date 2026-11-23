/// A weekly **matchday** (jornada) of La Liga.
///
/// Unlike the old World-Cup daily files (one per calendar day, fixed
/// 08:30/13:00/17:00 phases), a La Liga matchday spans a weekend (or a midweek
/// round) and carries **real fixture datetimes**. The manage → cards → games
/// phase boundaries are data-driven from these datetimes (see
/// `utils/time_utils.dart`), so midweek rounds and postponed matches work
/// without special-casing.
///
/// Backend path: `daily/md<NN>.json` (NN = zero-padded matchday 01..38).
library;

class MatchPlayer {
  final String id;
  final int goals;
  final int assists;
  final double? rating;
  final double points;

  /// Estimated minutes, cards: written by fetch_scores.py. Null/0 on matchdays
  /// that predate these fields (never shown as a real number then).
  final int? minutes;
  final int yellow;
  final int red;

  const MatchPlayer({
    required this.id,
    required this.goals,
    required this.assists,
    this.rating,
    required this.points,
    this.minutes,
    this.yellow = 0,
    this.red = 0,
  });

  factory MatchPlayer.fromJson(Map<String, dynamic> j) => MatchPlayer(
    id: j['id'] as String,
    goals: (j['goals'] as num?)?.toInt() ?? 0,
    assists: (j['assists'] as num?)?.toInt() ?? 0,
    rating: (j['rating'] as num?)?.toDouble(),
    points: (j['points'] as num?)?.toDouble() ?? 0.0,
    minutes: (j['minutes'] as num?)?.toInt(),
    yellow: (j['yellow'] as num?)?.toInt() ?? 0,
    red: (j['red'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'goals': goals,
    'assists': assists,
    if (rating != null) 'rating': rating,
    'points': points,
    if (minutes != null) 'minutes': minutes,
    if (yellow != 0) 'yellow': yellow,
    if (red != 0) 'red': red,
  };
}

class DailyMatch {
  final String id;
  final String home;
  final String away;

  /// ISO-8601 kickoff datetime (with offset), when known.
  final String? kickoff;

  /// Rescheduled to a later date — shown as "APLAZADO" and excluded from
  /// resolution until a result arrives.
  final bool postponed;

  String? score; // "H-A" string, null until played
  final List<MatchPlayer> players;

  DailyMatch({
    required this.id,
    required this.home,
    required this.away,
    this.kickoff,
    this.postponed = false,
    this.score,
    required this.players,
  });

  bool get played => score != null && score!.contains('-');

  /// Parsed [home, away] goals from the "H-A" score, or null if unplayed/bad.
  List<int>? get goals {
    if (!played) return null;
    final parts = score!.split('-');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0].trim());
    final a = int.tryParse(parts[1].trim());
    return (h == null || a == null) ? null : [h, a];
  }

  /// The Quiniela sign: '1' home win, 'X' draw, '2' away win; null if unplayed.
  String? get sign {
    final g = goals;
    if (g == null) return null;
    if (g[0] > g[1]) return '1';
    if (g[1] > g[0]) return '2';
    return 'X';
  }

  factory DailyMatch.fromJson(Map<String, dynamic> j) => DailyMatch(
    id: j['id'] as String,
    home: j['home'] as String,
    away: j['away'] as String,
    kickoff: j['kickoff'] as String?,
    postponed: j['postponed'] as bool? ?? false,
    // Tolerate any legacy shape (string "2-1" or null); never crash on load.
    score: j['score']?.toString(),
    players: (j['players'] as List<dynamic>? ?? [])
        .map((e) => MatchPlayer.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'home': home,
    'away': away,
    if (kickoff != null) 'kickoff': kickoff,
    if (postponed) 'postponed': true,
    'score': score,
    'players': players.map((p) => p.toJson()).toList(),
  };
}

class Bet {
  final String id;
  final String matchId;
  final String question;
  final List<String> options;
  final String? answer;

  const Bet({
    required this.id,
    required this.matchId,
    required this.question,
    required this.options,
    this.answer,
  });

  factory Bet.fromJson(Map<String, dynamic> j) => Bet(
    id: j['id'] as String,
    matchId: j['match_id'] as String,
    question: j['question'] as String,
    options: List<String>.from(j['options'] ?? []),
    answer: j['answer'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'match_id': matchId,
    'question': question,
    'options': options,
    'answer': answer,
  };
}

class DailyMatchday {
  /// League matchday number (1..38).
  final int matchday;

  /// First fixture calendar date (YYYY-MM-DD, Madrid) — used for display and
  /// current-matchday selection.
  final String date;

  /// ISO-8601 datetime of the first kickoff of the matchday.
  final String firstKickoff;

  /// ISO-8601 datetime the **cards** phase opens (manage → cards boundary).
  final String cardsOpen;

  /// ISO-8601 datetime everything **locks** (cards → games boundary). Team,
  /// bets and Quiniela are read-only from here on.
  final String lockAt;

  final List<DailyMatch> matches;
  final List<Bet> bets;

  const DailyMatchday({
    required this.matchday,
    required this.date,
    required this.firstKickoff,
    required this.cardsOpen,
    required this.lockAt,
    required this.matches,
    required this.bets,
  });

  DateTime? get firstKickoffTime => DateTime.tryParse(firstKickoff);
  DateTime? get cardsOpenTime => DateTime.tryParse(cardsOpen);
  DateTime? get lockAtTime => DateTime.tryParse(lockAt);

  /// True once every non-postponed fixture has a result.
  bool get fullyPlayed =>
      matches.where((m) => !m.postponed).every((m) => m.played);

  factory DailyMatchday.fromJson(Map<String, dynamic> j) {
    final date = j['date'] as String? ?? '';
    final firstKickoff = j['first_kickoff'] as String? ?? date;
    return DailyMatchday(
      matchday: (j['matchday'] as num?)?.toInt() ?? 0,
      date: date,
      firstKickoff: firstKickoff,
      cardsOpen: j['cards_open'] as String? ?? firstKickoff,
      lockAt: j['lock_at'] as String? ?? firstKickoff,
      matches: (j['matches'] as List<dynamic>? ?? [])
          .map((e) => DailyMatch.fromJson(e as Map<String, dynamic>))
          .toList(),
      bets: (j['bets'] as List<dynamic>? ?? [])
          .map((e) => Bet.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'matchday': matchday,
    'date': date,
    'first_kickoff': firstKickoff,
    'cards_open': cardsOpen,
    'lock_at': lockAt,
    'matches': matches.map((m) => m.toJson()).toList(),
    'bets': bets.map((b) => b.toJson()).toList(),
  };
}
