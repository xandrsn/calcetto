import 'powerup_card.dart';

class UserPoints {
  double total;
  double squad;
  double bets;
  double quiniela;
  double goldenBoot;
  double steals;
  double cards;

  UserPoints({
    this.total = 0,
    this.squad = 0,
    this.bets = 0,
    this.quiniela = 0,
    this.goldenBoot = 0,
    this.steals = 0,
    this.cards = 0,
  });

  factory UserPoints.fromJson(Map<String, dynamic> j) {
    final bd = (j['breakdown'] as Map<String, dynamic>?) ?? {};
    return UserPoints(
      total: (j['total'] as num?)?.toDouble() ?? 0,
      squad: (bd['squad'] as num?)?.toDouble() ?? 0,
      bets: (bd['bets'] as num?)?.toDouble() ?? 0,
      quiniela: (bd['quiniela'] as num?)?.toDouble() ?? 0,
      goldenBoot: (bd['golden_boot'] as num?)?.toDouble() ?? 0,
      steals: (bd['steals'] as num?)?.toDouble() ?? 0,
      cards: (bd['cards'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'total': total,
    'breakdown': {
      'squad': squad,
      'bets': bets,
      'quiniela': quiniela,
      'golden_boot': goldenBoot,
      'steals': steals,
      'cards': cards,
    },
  };
}

class ActiveState {
  String? captain;
  Map<String, String> bets;
  List<PowerupCard> cardsReceived;
  List<PowerupCard> cardsPlayed;
  int attacksReceivedToday;

  ActiveState({
    this.captain,
    Map<String, String>? bets,
    List<PowerupCard>? cardsReceived,
    List<PowerupCard>? cardsPlayed,
    this.attacksReceivedToday = 0,
  }) : bets = bets ?? {},
       cardsReceived = cardsReceived ?? [],
       cardsPlayed = cardsPlayed ?? [];

  factory ActiveState.fromJson(Map<String, dynamic> j) {
    final betsRaw = j['bets'] as Map<String, dynamic>? ?? {};
    return ActiveState(
      captain: j['captain'] as String?,
      bets: betsRaw.map((k, v) => MapEntry(k, v.toString())),
      cardsReceived: (j['cards_received'] as List<dynamic>? ?? [])
          .map((e) => PowerupCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      cardsPlayed: (j['cards_played'] as List<dynamic>? ?? [])
          .map((e) => PowerupCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      attacksReceivedToday: (j['attacks_received_today'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'captain': captain,
    'bets': bets,
    'cards_received': cardsReceived.map((c) => c.toJson()).toList(),
    'cards_played': cardsPlayed.map((c) => c.toJson()).toList(),
    'attacks_received_today': attacksReceivedToday,
  };
}

/// A user's weekly **Quiniela** prediction: a 1-X-2 sign per fixture id
/// (`'1'` home win, `'X'` draw, `'2'` away win). Keyed by [LeagueMatch.id] so
/// the same ids drive the matchday view, the league table, and scoring.
class QuinielaPrediction {
  final Map<String, String> picks;

  const QuinielaPrediction({Map<String, String>? picks})
    : picks = picks ?? const {};

  bool get isEmpty => picks.isEmpty;

  QuinielaPrediction withPick(String fixtureId, String sign) {
    final m = Map<String, String>.from(picks)..[fixtureId] = sign;
    return QuinielaPrediction(picks: m);
  }

  factory QuinielaPrediction.fromJson(Map<String, dynamic> j) {
    final p = <String, String>{};
    final raw = j['picks'] as Map<String, dynamic>? ?? {};
    raw.forEach((k, v) => p[k] = v.toString());
    return QuinielaPrediction(picks: p);
  }

  Map<String, dynamic> toJson() => {'picks': picks};
}

const kPlantillaTotal = {'GK': 2, 'DEF': 5, 'MID': 5, 'FWD': 4};
const kPositions = ['GK', 'DEF', 'MID', 'FWD'];

class UserData {
  final String name;
  final Map<String, List<String>> squad;
  final Map<String, List<String>> bench;
  final String formation;
  final int subsUsedThisRound;
  final Map<String, String?> captainPicks;
  final QuinielaPrediction quinielaPrediction;
  final String? goldenBoot;
  final String? topAssister;
  final UserPoints points;
  final ActiveState active;
  final int signingCardsAvailable;
  final List<String> signingCardsUsed;
  final int extraSubsAvailable;

  /// Admin "kick" flag. When true, the client logs itself out (clears its local
  /// session) on next load/refresh. Cleared automatically when the user logs
  /// back in. Lets the admin remotely sign someone out — there is no other
  /// logout in the app. See `userProvider`.
  final bool forceLogout;

  const UserData({
    required this.name,
    required this.squad,
    required this.bench,
    required this.formation,
    required this.subsUsedThisRound,
    required this.captainPicks,
    required this.quinielaPrediction,
    this.goldenBoot,
    this.topAssister,
    required this.points,
    required this.active,
    this.signingCardsAvailable = 0,
    List<String>? signingCardsUsed,
    this.extraSubsAvailable = 0,
    this.forceLogout = false,
  }) : signingCardsUsed = signingCardsUsed ?? const [];

  List<String> get allSquadPlayers => [
    ...squad['GK'] ?? [],
    ...squad['DEF'] ?? [],
    ...squad['MID'] ?? [],
    ...squad['FWD'] ?? [],
  ];

  List<String> get allBenchPlayers => [
    ...bench['GK'] ?? [],
    ...bench['DEF'] ?? [],
    ...bench['MID'] ?? [],
    ...bench['FWD'] ?? [],
  ];

  List<String> get allPlayers => [...allSquadPlayers, ...allBenchPlayers];

  /// Resolves the player id this user has designated as captain.
  ///
  /// Captain is stored in two places: [captainPicks] (date-keyed, set in-app)
  /// and [ActiveState.captain] (a single value mirrored server-side at daily
  /// resolution). This reconciles both so every view — own team, rival team,
  /// rankings — shows the same captain. Prefers the explicit pick for [today],
  /// then the pick for the current [matchdayDate], then the server value.
  String? captainFor({required String today, String? matchdayDate}) {
    return captainPicks[today] ??
        (matchdayDate != null ? captainPicks[matchdayDate] : null) ??
        active.captain;
  }

  static Map<String, List<String>> _parsePositionMap(dynamic raw) {
    final result = <String, List<String>>{};
    for (final pos in kPositions) {
      result[pos] = [];
    }
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is List) result[k.toString()] = List<String>.from(v);
      });
    }
    return result;
  }

  factory UserData.fromJson(Map<String, dynamic> j) {
    final cpRaw = j['captain_picks'] as Map<String, dynamic>? ?? {};
    final cp = <String, String?>{};
    cpRaw.forEach((k, v) => cp[k] = v as String?);
    return UserData(
      name: j['name'] as String,
      squad: _parsePositionMap(j['squad']),
      bench: _parsePositionMap(j['bench']),
      formation: j['formation'] as String? ?? '4-3-3',
      subsUsedThisRound: (j['subs_used_this_round'] as num?)?.toInt() ?? 0,
      captainPicks: cp,
      quinielaPrediction: QuinielaPrediction.fromJson(
        j['quiniela_prediction'] as Map<String, dynamic>? ?? {},
      ),
      goldenBoot: j['golden_boot'] as String?,
      topAssister: j['top_assister'] as String?,
      points: UserPoints.fromJson(j['points'] as Map<String, dynamic>? ?? {}),
      active: ActiveState.fromJson(j['active'] as Map<String, dynamic>? ?? {}),
      signingCardsAvailable:
          (j['signing_cards_available'] as num?)?.toInt() ?? 0,
      signingCardsUsed: List<String>.from(j['signing_cards_used'] ?? []),
      extraSubsAvailable: (j['extra_subs_available'] as num?)?.toInt() ?? 0,
      forceLogout: j['force_logout'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'fcm_token': '',
    'squad': squad,
    'bench': bench,
    'formation': formation,
    'subs_used_this_round': subsUsedThisRound,
    'captain_picks': captainPicks,
    'quiniela_prediction': quinielaPrediction.toJson(),
    'golden_boot': goldenBoot,
    'top_assister': topAssister,
    'points': points.toJson(),
    'active': active.toJson(),
    'signing_cards_available': signingCardsAvailable,
    'signing_cards_used': signingCardsUsed,
    'extra_subs_available': extraSubsAvailable,
    'force_logout': forceLogout,
  };

  UserData copyWith({
    Map<String, List<String>>? squad,
    Map<String, List<String>>? bench,
    String? formation,
    int? subsUsedThisRound,
    Map<String, String?>? captainPicks,
    QuinielaPrediction? quinielaPrediction,
    String? goldenBoot,
    String? topAssister,
    UserPoints? points,
    ActiveState? active,
    int? signingCardsAvailable,
    List<String>? signingCardsUsed,
    int? extraSubsAvailable,
    bool? forceLogout,
  }) {
    return UserData(
      name: name,
      squad: squad ?? this.squad,
      bench: bench ?? this.bench,
      formation: formation ?? this.formation,
      subsUsedThisRound: subsUsedThisRound ?? this.subsUsedThisRound,
      captainPicks: captainPicks ?? this.captainPicks,
      quinielaPrediction: quinielaPrediction ?? this.quinielaPrediction,
      goldenBoot: goldenBoot ?? this.goldenBoot,
      topAssister: topAssister ?? this.topAssister,
      points: points ?? this.points,
      active: active ?? this.active,
      signingCardsAvailable:
          signingCardsAvailable ?? this.signingCardsAvailable,
      signingCardsUsed: signingCardsUsed ?? this.signingCardsUsed,
      extraSubsAvailable: extraSubsAvailable ?? this.extraSubsAvailable,
      forceLogout: forceLogout ?? this.forceLogout,
    );
  }

  static Map<String, List<String>> _emptyPositionMap() => {
    'GK': [],
    'DEF': [],
    'MID': [],
    'FWD': [],
  };

  static UserData empty(String name) => UserData(
    name: name,
    squad: _emptyPositionMap(),
    bench: _emptyPositionMap(),
    formation: '4-3-3',
    subsUsedThisRound: 0,
    captainPicks: {},
    quinielaPrediction: QuinielaPrediction(),
    goldenBoot: null,
    points: UserPoints(),
    active: ActiveState(),
    signingCardsAvailable: 0,
    signingCardsUsed: [],
    extraSubsAvailable: 0,
  );
}
