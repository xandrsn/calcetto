/// La Liga 2026-27 league model.
///
/// Replaces the old World-Cup `tournament.dart` (groups + knockout bracket).
/// A single-table, double round-robin league of 20 teams over 38 matchdays.
/// The authoritative fixtures + results live in the backend `data/league.json`
/// (seeded from the real calendar); [LeagueData.buildDefault] provides a
/// structural round-robin fallback so the app is coherent before the backend
/// loads.
library;

/// The 20 clubs in the 2026-27 La Liga season (promoted this year: Racing
/// Santander, Deportivo A Coruña, Málaga).
const kLaLigaTeams = <String>[
  'Alavés',
  'Athletic Bilbao',
  'Atlético Madrid',
  'Barcelona',
  'Celta Vigo',
  'Deportivo A Coruña',
  'Elche',
  'Espanyol',
  'Getafe',
  'Levante',
  'Málaga',
  'Osasuna',
  'Racing Santander',
  'Rayo Vallecano',
  'Real Betis',
  'Real Madrid',
  'Real Sociedad',
  'Sevilla',
  'Valencia',
  'Villarreal',
];

/// Total matchdays in a 20-team double round-robin.
const int kTotalMatchdays = 38;

/// A URL/id-safe slug for a team name (accent-folded, lowercased, `_`-joined).
String teamSlug(String team) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñç';
  const to = 'aaaaeeeeiiiioooouuuunc';
  final buf = StringBuffer();
  for (final ch in team.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  return buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

/// Canonical fixture id, stable across postponements (team-based, not index).
String fixtureId(int matchday, String home, String away) =>
    'md${matchday.toString().padLeft(2, '0')}-${teamSlug(home)}-${teamSlug(away)}';

// ---------- Match ----------

class LeagueMatch {
  final String id;
  final int matchday; // 1..38
  final String home;
  final String away;

  /// ISO-8601 kickoff datetime (with offset), when known. Drives the weekly
  /// phase windows and lets midweek rounds / reschedules be handled per fixture.
  final String? kickoff;

  int? homeScore;
  int? awayScore;

  /// A fixture whose original date passed without being played (rescheduled).
  /// Postponed fixtures are simply "not yet played" for the table until a
  /// result arrives — they never block the rest of the matchday from resolving.
  bool postponed;

  LeagueMatch({
    required this.id,
    required this.matchday,
    required this.home,
    required this.away,
    this.kickoff,
    this.homeScore,
    this.awayScore,
    this.postponed = false,
  });

  bool get played => homeScore != null && awayScore != null;

  /// '1' home win, 'X' draw, '2' away win — the Quiniela sign. Null if unplayed.
  String? get sign {
    if (!played) return null;
    if (homeScore! > awayScore!) return '1';
    if (awayScore! > homeScore!) return '2';
    return 'X';
  }

  String? get winner {
    switch (sign) {
      case '1':
        return home;
      case '2':
        return away;
      default:
        return null;
    }
  }

  DateTime? get kickoffTime =>
      kickoff == null ? null : DateTime.tryParse(kickoff!);

  LeagueMatch copyWith({
    int? homeScore,
    int? awayScore,
    bool? postponed,
    String? kickoff,
  }) => LeagueMatch(
    id: id,
    matchday: matchday,
    home: home,
    away: away,
    kickoff: kickoff ?? this.kickoff,
    homeScore: homeScore ?? this.homeScore,
    awayScore: awayScore ?? this.awayScore,
    postponed: postponed ?? this.postponed,
  );

  factory LeagueMatch.fromJson(Map<String, dynamic> j) => LeagueMatch(
    id: j['id'] as String,
    matchday: (j['md'] as num?)?.toInt() ?? 0,
    home: j['home'] as String,
    away: j['away'] as String,
    kickoff: j['kickoff'] as String?,
    homeScore: (j['hs'] as num?)?.toInt(),
    awayScore: (j['as'] as num?)?.toInt(),
    postponed: j['postponed'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'md': matchday,
    'home': home,
    'away': away,
    if (kickoff != null) 'kickoff': kickoff,
    'hs': homeScore,
    'as': awayScore,
    if (postponed) 'postponed': true,
  };
}

// ---------- Standing ----------

class TeamStanding {
  final String team;
  int p = 0, w = 0, d = 0, l = 0, gf = 0, ga = 0;

  TeamStanding(this.team);

  int get pts => w * 3 + d;
  int get gd => gf - ga;
}

/// Computes the league table from [matches] over the given [teams] (defaults to
/// [kLaLigaTeams]).
///
/// Ordering follows the official **La Liga** tiebreakers: points → head-to-head
/// points among the teams tied on points → head-to-head goal difference →
/// overall goal difference → overall goals for → alphabetical (deterministic
/// stand-in for the fair-play / drawing-of-lots rule). Head-to-head is computed
/// from whatever mutual matches have been played; at season end (all fixtures
/// played) this is exactly the official rule.
List<TeamStanding> computeLeagueTable(
  List<LeagueMatch> matches, {
  List<String> teams = kLaLigaTeams,
}) {
  final map = {for (final t in teams) t: TeamStanding(t)};

  for (final m in matches) {
    if (!m.played) continue;
    final home = map[m.home];
    final away = map[m.away];
    if (home == null || away == null) continue;
    home.p++;
    away.p++;
    home.gf += m.homeScore!;
    home.ga += m.awayScore!;
    away.gf += m.awayScore!;
    away.ga += m.homeScore!;
    if (m.homeScore! > m.awayScore!) {
      home.w++;
      away.l++;
    } else if (m.awayScore! > m.homeScore!) {
      away.w++;
      home.l++;
    } else {
      home.d++;
      away.d++;
    }
  }

  final list = map.values.toList();
  list.sort(_compareOverall);
  _applyHeadToHead(list, matches);
  return list;
}

/// Points → overall GD → overall GF (the non-h2h portion of the ordering).
int _compareOverall(TeamStanding a, TeamStanding b) {
  if (b.pts != a.pts) return b.pts.compareTo(a.pts);
  if (b.gd != a.gd) return b.gd.compareTo(a.gd);
  if (b.gf != a.gf) return b.gf.compareTo(a.gf);
  return a.team.compareTo(b.team);
}

/// Re-orders runs of teams tied on points using head-to-head (points → GD → GF)
/// before falling back to the overall comparison above.
void _applyHeadToHead(List<TeamStanding> list, List<LeagueMatch> matches) {
  var i = 0;
  while (i < list.length) {
    var j = i + 1;
    while (j < list.length && list[j].pts == list[i].pts) {
      j++;
    }
    if (j - i > 1) {
      final tied = list.sublist(i, j);
      final tiedTeams = tied.map((s) => s.team).toSet();
      final mini = _headToHeadTable(tiedTeams, matches);
      tied.sort((a, b) {
        final ha = mini[a.team]!;
        final hb = mini[b.team]!;
        if (hb.pts != ha.pts) return hb.pts.compareTo(ha.pts);
        if (hb.gd != ha.gd) return hb.gd.compareTo(ha.gd);
        if (hb.gf != ha.gf) return hb.gf.compareTo(ha.gf);
        // fall back to overall GD / GF / alphabetical
        if (b.gd != a.gd) return b.gd.compareTo(a.gd);
        if (b.gf != a.gf) return b.gf.compareTo(a.gf);
        return a.team.compareTo(b.team);
      });
      for (var k = i; k < j; k++) {
        list[k] = tied[k - i];
      }
    }
    i = j;
  }
}

/// Mini standings counting only matches played between [teams].
Map<String, TeamStanding> _headToHeadTable(
  Set<String> teams,
  List<LeagueMatch> matches,
) {
  final mini = {for (final t in teams) t: TeamStanding(t)};
  for (final m in matches) {
    if (!m.played) continue;
    if (!teams.contains(m.home) || !teams.contains(m.away)) continue;
    final h = mini[m.home]!;
    final a = mini[m.away]!;
    h.gf += m.homeScore!;
    h.ga += m.awayScore!;
    a.gf += m.awayScore!;
    a.ga += m.homeScore!;
    if (m.homeScore! > m.awayScore!) {
      h.w++;
      a.l++;
    } else if (m.awayScore! > m.homeScore!) {
      a.w++;
      h.l++;
    } else {
      h.d++;
      a.d++;
    }
  }
  return mini;
}

// ---------- League data ----------

class LeagueData {
  /// All season fixtures (up to 380), across the 38 matchdays.
  final List<LeagueMatch> matches;

  LeagueData({required this.matches});

  /// Structural double round-robin fallback (circle method): valid fixtures with
  /// matchday numbers and home/away, but no real dates/scores. The backend
  /// `data/league.json` (real calendar) overrides this when loaded.
  factory LeagueData.buildDefault() =>
      LeagueData(matches: _roundRobin(kLaLigaTeams));

  List<LeagueMatch> matchesForMatchday(int md) =>
      matches.where((m) => m.matchday == md).toList();

  List<TeamStanding> computeTable() => computeLeagueTable(matches);

  /// The highest matchday for which every fixture has been played (the current
  /// completed matchday); 0 if none complete.
  int get completedMatchdays {
    var done = 0;
    for (var md = 1; md <= kTotalMatchdays; md++) {
      final ms = matchesForMatchday(md);
      if (ms.isNotEmpty && ms.every((m) => m.played)) {
        done = md;
      } else {
        break;
      }
    }
    return done;
  }

  LeagueData updateMatch(
    String matchId, {
    int? homeScore,
    int? awayScore,
    bool? postponed,
  }) {
    final idx = matches.indexWhere((m) => m.id == matchId);
    if (idx < 0) return this;
    final list = List<LeagueMatch>.from(matches);
    list[idx] = list[idx].copyWith(
      homeScore: homeScore,
      awayScore: awayScore,
      postponed: postponed,
    );
    return LeagueData(matches: list);
  }

  factory LeagueData.fromJson(Map<String, dynamic> j) {
    final raw = j['matches'] as List<dynamic>? ?? [];
    if (raw.isEmpty) return LeagueData.buildDefault();
    return LeagueData(
      matches: raw
          .map((e) => LeagueMatch.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'matches': matches.map((m) => m.toJson()).toList(),
  };
}

/// Double round-robin schedule via the circle method. First leg matchdays
/// 1..19, mirrored (home/away swapped) as the second leg matchdays 20..38.
List<LeagueMatch> _roundRobin(List<String> teams) {
  final n = teams.length;
  final rot = List<String>.from(teams);
  final out = <LeagueMatch>[];
  final legRounds = n - 1; // 19
  for (var r = 0; r < legRounds; r++) {
    for (var i = 0; i < n ~/ 2; i++) {
      var home = rot[i];
      var away = rot[n - 1 - i];
      // Alternate home/away by round for a fairer split.
      if (r.isOdd) {
        final t = home;
        home = away;
        away = t;
      }
      final md1 = r + 1;
      out.add(
        LeagueMatch(
          id: fixtureId(md1, home, away),
          matchday: md1,
          home: home,
          away: away,
        ),
      );
      final md2 = md1 + legRounds; // second leg, reversed venue
      out.add(
        LeagueMatch(
          id: fixtureId(md2, away, home),
          matchday: md2,
          home: away,
          away: home,
        ),
      );
    }
    // rotate all but the first element
    rot.insert(1, rot.removeLast());
  }
  return out;
}
