class Player {
  final String id;
  final String name;
  final String team;
  final String position;
  final String skin;
  final Map<String, double> pointsPerMatch;
  final double totalPoints;
  final int goals;
  final int assists;
  final double basePopularityPct;
  final bool retired;
  final String? retiredBy;
  final String? retiredDate;

  const Player({
    required this.id,
    required this.name,
    required this.team,
    required this.position,
    required this.skin,
    required this.pointsPerMatch,
    required this.totalPoints,
    required this.goals,
    required this.assists,
    this.basePopularityPct = 0.0,
    this.retired = false,
    this.retiredBy,
    this.retiredDate,
  });

  factory Player.fromJson(Map<String, dynamic> j) {
    final ppm = <String, double>{};
    final raw = j['points_per_match'];
    if (raw is Map) {
      raw.forEach((k, v) => ppm[k.toString()] = (v as num).toDouble());
    }
    return Player(
      id: j['id'] as String,
      name: j['name'] as String,
      team: j['team'] as String,
      position: j['position'] as String,
      skin: j['skin'] as String? ?? 'light_short_brown',
      pointsPerMatch: ppm,
      totalPoints: (j['total_points'] as num?)?.toDouble() ?? 0.0,
      goals: (j['goals'] as num?)?.toInt() ?? 0,
      assists: (j['assists'] as num?)?.toInt() ?? 0,
      basePopularityPct: (j['base_popularity_pct'] as num?)?.toDouble() ?? 0.0,
      retired: j['retired'] as bool? ?? false,
      retiredBy: j['retired_by'] as String?,
      retiredDate: j['retired_date'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'team': team,
    'position': position,
    'skin': skin,
    'points_per_match': pointsPerMatch,
    'total_points': totalPoints,
    'goals': goals,
    'assists': assists,
    'base_popularity_pct': basePopularityPct,
    'retired': retired,
    if (retiredBy != null) 'retired_by': retiredBy,
    if (retiredDate != null) 'retired_date': retiredDate,
  };
}
