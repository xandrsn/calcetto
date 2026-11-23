import 'package:flutter/material.dart';
import '../models/league.dart';
import '../theme/app_theme.dart';

/// The La Liga table: 20 ordered rows with P/W/D/L/GD/PTS. European / relegation
/// zones are colour-coded down the left edge (1–4 Champions League, 5–6 Europa
/// tier, 18–20 relegation).
class LeagueTable extends StatelessWidget {
  final List<TeamStanding> rows;

  /// Optional highlight (e.g. the viewer's context) — currently unused, kept for
  /// future "my players' teams" emphasis.
  final String? highlightTeam;

  const LeagueTable({super.key, required this.rows, this.highlightTeam});

  static Color zoneColor(int index) {
    if (index < 4) return kAccentGreen; // Champions League
    if (index < 6) return kAccentYellow; // Europa / Conference
    if (index >= 17) return kAccentRed; // relegation (bottom 3)
    return kTextMuted;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HeaderRow(),
          const SizedBox(height: 2),
          ...rows.asMap().entries.map(
            (e) => _StandingRow(index: e.key, s: e.value),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    Widget cell(String t, double w) => SizedBox(
      width: w,
      child: Text(
        t,
        style: const TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: 9,
          color: kTextDim,
        ),
        textAlign: TextAlign.center,
      ),
    );
    return Row(
      children: [
        const SizedBox(width: 18),
        const Expanded(child: SizedBox()),
        cell('P', 20),
        cell('G', 18),
        cell('E', 18),
        cell('P', 18),
        cell('DG', 26),
        cell('PTS', 28),
      ],
    );
  }
}

class _StandingRow extends StatelessWidget {
  final int index;
  final TeamStanding s;
  const _StandingRow({required this.index, required this.s});

  @override
  Widget build(BuildContext context) {
    final color = LeagueTable.zoneColor(index);

    Widget num(String t, double w, {Color? c, bool bold = false}) => SizedBox(
      width: w,
      child: Text(
        t,
        style: TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: 9,
          color: c ?? kTextPrimary,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
        textAlign: TextAlign.center,
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              s.team,
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 9,
                color: kTextPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          num('${s.p}', 20),
          num('${s.w}', 18),
          num('${s.d}', 18),
          num('${s.l}', 18),
          num(s.gd >= 0 ? '+${s.gd}' : '${s.gd}', 26),
          num('${s.pts}', 28, bold: true, c: kTextPrimary),
        ],
      ),
    );
  }
}
