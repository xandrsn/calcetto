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
        final s = playerSeasonStats(player.id, matchdays, team: player.team);
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
            _row('MEDIA / MEJOR', '${s.avgPoints.toStringAsFixed(1)} / ${s.bestPoints.toStringAsFixed(1)}'),
            _row('V / E / D (EQUIPO)', '${s.wins} / ${s.draws} / ${s.losses}'),
            _row('% VICTORIAS', '${(s.winRate * 100).round()}%'),
            _row('MVP DEL PARTIDO', '${s.mvps}'),
            _row('RACHA GOLEADORA', '${s.scoringStreak}'),
            _row('RACHA SIN PERDER', '${s.unbeatenStreak}'),
            _row('FORMA (ULT. 5)', form),
            const SizedBox(height: 8),
            PointsBarChart(values: [for (final l in s.lines) l.stats.points]),
            const SizedBox(height: 8),
            for (final h in s.headToHead.take(5))
              _row(
                'VS ${h.opponent.toUpperCase()}',
                '${h.played}P ${h.wins}V ${h.draws}E ${h.losses}D · '
                    '${h.goals}G ${h.assists}A',
              ),
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

/// Tiny bar chart of points per played matchday (oldest left); no dependency.
class PointsBarChart extends StatelessWidget {
  final List<double> values;
  const PointsBarChart({super.key, required this.values});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: CustomPaint(painter: _BarPainter(values), size: Size.infinite),
  );
}

class _BarPainter extends CustomPainter {
  final List<double> values;
  _BarPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.fold<double>(1, (a, v) => v.abs() > a ? v.abs() : a);
    final w = size.width / values.length;
    final base = size.height * 0.75;
    for (var i = 0; i < values.length; i++) {
      final h = values[i] / maxV * base;
      final paint = Paint()
        ..color = values[i] >= 0 ? kAccentBlue : kAccentYellow;
      canvas.drawRect(
        Rect.fromLTRB(i * w + w * 0.15, h >= 0 ? base - h : base,
            (i + 1) * w - w * 0.15, h >= 0 ? base : base - h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.values != values;
}
