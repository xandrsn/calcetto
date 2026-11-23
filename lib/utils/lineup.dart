/// Pure helpers for reasoning about a squad's lineup (starters + bench),
/// independent of any widget. Position maps are keyed 'GK'/'DEF'/'MID'/'FWD'.
const _positions = ['GK', 'DEF', 'MID', 'FWD'];

/// Whether [pid] appears anywhere in the given position map.
bool playerInMap(Map<String, List<String>> map, String pid) =>
    _positions.any((pos) => (map[pos] ?? const []).contains(pid));

/// The position [pid] occupies in [map], or null if absent.
String? positionOfPlayer(Map<String, List<String>> map, String pid) {
  for (final pos in _positions) {
    if ((map[pos] ?? const []).contains(pid)) return pos;
  }
  return null;
}

/// Whether substituting [a] with [b] is legal: exactly one must be a starter
/// and the other a bench player, both in the same position. This is what keeps
/// the formation valid during drag-and-drop or tap substitutions.
bool canSwapPlayers(
  Map<String, List<String>> squad,
  Map<String, List<String>> bench,
  String a,
  String b,
) {
  if (a == b) return false;
  final aStarter = playerInMap(squad, a);
  final bStarter = playerInMap(squad, b);
  if (aStarter == bStarter) return false;
  final posA = aStarter
      ? positionOfPlayer(squad, a)
      : positionOfPlayer(bench, a);
  final posB = bStarter
      ? positionOfPlayer(squad, b)
      : positionOfPlayer(bench, b);
  return posA != null && posA == posB;
}
