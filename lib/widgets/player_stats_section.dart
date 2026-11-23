import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player.dart';
import '../providers/game_state_provider.dart';
import '../theme/app_theme.dart';
import '../utils/player_stats.dart';

/// Season stats for [player] in the player sheet: totals, form and a line per
/// played matchday. Built from the matchdays already in the backend
/// (see utils/player_stats.dart); minutes are ESPN-based estimates.
class PlayerSeasonSection extends ConsumerWidget {
  final Player player;
  const PlayerSeasonSection({super.key, required this.player});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pastMatchdaysProvider);
    return async.when(
      loading: () => _note('CARGANDO ESTADISTICAS…'),
      error: (_, _) => _note('NO SE PUDIERON CARGAR LAS ESTADISTICAS'),
      data: (matchdays) {
        final s = playerSeasonStats(player.id, matchdays);
        if (s.appearances == 0) return _note('SIN PARTIDOS JUGADOS');
        final minutes = s.minutes;
        final form = s.form().map((p) => p.toStringAsFixed(1)).join(' · ');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row('PARTIDOS', '${s.appearances}'),
            _row('GOLES', '${s.goals}'),
            _row('ASISTENCIAS', '${s.assists}'),
            _row('AMARILLAS / ROJAS', '${s.yellow} / ${s.red}'),
            _row('MINUTOS (EST.)', minutes == null ? '—' : '$minutes'),
            _row('PUNTOS', s.points.toStringAsFixed(1)),
            _row('FORMA (ULT. 5)', form),
            const SizedBox(height: 8),
            for (final l in s.lines.reversed)
              _row(
                'J${l.matchday.toString().padLeft(2, '0')}',
                '${l.stats.goals}G ${l.stats.assists}A · '
                    '${l.stats.points.toStringAsFixed(1)} pts',
              ),
          ],
        );
      },
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: kFontUI,
        fontSize: 11,
        color: kTextMuted,
      ),
    ),
  );

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(
              fontFamily: kFontUI,
              fontSize: 11,
              color: kTextMuted,
            ),
          ),
        ),
        Text(
          v,
          style: const TextStyle(
            fontFamily: kFontUI,
            fontSize: 11,
            color: kTextPrimary,
          ),
        ),
      ],
    ),
  );
}
