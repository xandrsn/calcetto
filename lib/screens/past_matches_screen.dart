import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily.dart';
import '../models/player.dart';
import '../providers/game_state_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';

/// Opens the per-match player-stats sheet for a played [DailyMatch].
void showMatchStats(BuildContext context, DailyMatch match) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: kSurface,
    isScrollControlled: true,
    builder: (_) => MatchStatsSheet(match: match),
  );
}

/// Browse past matchdays and tap any match to see its player stats (ratings,
/// scorers, assists) — the per-match detail for finished/simulated games.
class PastMatchesScreen extends ConsumerWidget {
  const PastMatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pastAsync = ref.watch(pastMatchdaysProvider);
    final players = ref.watch(playersProvider).valueOrNull ?? const <Player>[];
    final byId = {for (final p in players) p.id: p};

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'RESULTADOS',
          style: TextStyle(fontFamily: 'ChakraPetch', fontSize: 11),
        ),
      ),
      body: pastAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'No se pudieron cargar los resultados',
          onRetry: () => ref.invalidate(pastMatchdaysProvider),
        ),
        data: (days) {
          if (days.isEmpty) {
            return const Center(
              child: Text(
                'AÚN NO HAY PARTIDOS JUGADOS',
                style: TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 13,
                  color: kTextMuted,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final md in days) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    md.date,
                    style: const TextStyle(
                      fontFamily: 'ChakraPetch',
                      fontSize: 14,
                      color: kAccentGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                for (final m in md.matches)
                  _MatchRow(match: m, byId: byId),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Splits a match's played players (rating != null) into home/away by team.
(List<MatchPlayer>, List<MatchPlayer>) _splitPlayed(
  DailyMatch m,
  Map<String, Player> byId,
) {
  final home = <MatchPlayer>[];
  final away = <MatchPlayer>[];
  for (final mp in m.players) {
    if (mp.rating == null && mp.goals == 0 && mp.assists == 0) continue;
    final team = byId[mp.id]?.team;
    if (team == m.home) {
      home.add(mp);
    } else if (team == m.away) {
      away.add(mp);
    }
  }
  int byRating(MatchPlayer a, MatchPlayer b) =>
      (b.rating ?? 0).compareTo(a.rating ?? 0);
  home.sort(byRating);
  away.sort(byRating);
  return (home, away);
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.byId});
  final DailyMatch match;
  final Map<String, Player> byId;

  @override
  Widget build(BuildContext context) {
    final (home, away) = _splitPlayed(match, byId);
    final hg = home.fold<int>(0, (s, p) => s + p.goals);
    final ag = away.fold<int>(0, (s, p) => s + p.goals);
    final played = home.isNotEmpty || away.isNotEmpty;
    return InkWell(
      onTap: played
          ? () => showMatchStats(context, match)
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                match.home,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'ChakraPetch', fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                played ? '$hg - $ag' : 'vs',
                style: const TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 14,
                  color: kAccentYellow,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: Text(
                match.away,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'ChakraPetch', fontSize: 12),
              ),
            ),
            if (played)
              const Icon(Icons.chevron_right, size: 14, color: kTextMuted),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet with a finished match's player stats (ratings, scorers, assists),
/// split into home/away by player team. Reused by the results browser AND the
/// league table view (tap a match). `showMatchStats` opens it for a [DailyMatch].
class MatchStatsSheet extends ConsumerWidget {
  const MatchStatsSheet({super.key, required this.match});
  final DailyMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = ref.watch(playersProvider).valueOrNull ?? const <Player>[];
    final byId = {for (final p in players) p.id: p};
    final (home, away) = _splitPlayed(match, byId);
    final hg = home.fold<int>(0, (s, p) => s + p.goals);
    final ag = away.fold<int>(0, (s, p) => s + p.goals);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${match.home}  $hg - $ag  ${match.away}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 11,
                  color: kAccentYellow,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _teamBlock(match.home, home, byId),
              const Divider(color: kBorder, height: 20),
              _teamBlock(match.away, away, byId),
            ],
          ),
        ),
      ),
    );
  }

  Widget _teamBlock(
    String team,
    List<MatchPlayer> players,
    Map<String, Player> byId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          team.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 13,
            color: kAccentGreen,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        for (final mp in players) _playerRow(mp, byId),
        if (players.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'sin datos',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 11,
                color: kTextMuted,
              ),
            ),
          ),
      ],
    );
  }

  Widget _playerRow(MatchPlayer mp, Map<String, Player> byId) {
    final name = byId[mp.id]?.name ?? mp.id;
    final rating = mp.rating;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'ChakraPetch', fontSize: 12),
            ),
          ),
          if (mp.goals > 0) ...[
            Text(
              '⚽${mp.goals > 1 ? 'x${mp.goals}' : ''}',
              style: const TextStyle(fontFamily: 'ChakraPetch', fontSize: 12),
            ),
            const SizedBox(width: 6),
          ],
          if (mp.assists > 0) ...[
            Text(
              '🅰${mp.assists > 1 ? 'x${mp.assists}' : ''}',
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 12,
                color: kTextMuted,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            color: _ratingColor(rating),
            child: Text(
              rating?.toStringAsFixed(1) ?? '-',
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 12,
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _ratingColor(double? r) {
    if (r == null) return kTextMuted;
    if (r >= 8) return kAccentGreen;
    if (r >= 6.5) return kAccentYellow;
    if (r >= 5) return const Color(0xFFE08D3C);
    return kAccentRed;
  }
}
