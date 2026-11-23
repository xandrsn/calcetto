import 'package:flutter/material.dart';
import 'pixel_player_painter.dart';

// Representative home-kit colour per 2026-27 La Liga club (matches kLaLigaTeams
// names). Unmapped teams fall back to [_teamColor]'s default.
final Map<String, Color> _teamColors = {
  'Alavés': Color(0xFF0761AF),
  'Athletic Bilbao': Color(0xFFEE2523),
  'Atlético Madrid': Color(0xFFCB3524),
  'Barcelona': Color(0xFFA50044),
  'Celta Vigo': Color(0xFF8AC3EE),
  'Deportivo A Coruña': Color(0xFF0067B1),
  'Elche': Color(0xFF00873C),
  'Espanyol': Color(0xFF007FC8),
  'Getafe': Color(0xFF005999),
  'Levante': Color(0xFF004B9E),
  'Málaga': Color(0xFF0067B2),
  'Osasuna': Color(0xFFD91A21),
  'Racing Santander': Color(0xFF009B48),
  'Rayo Vallecano': Color(0xFFE53027),
  'Real Betis': Color(0xFF00954C),
  'Real Madrid': Color(0xFFDCDCDC),
  'Real Sociedad': Color(0xFF0067B1),
  'Sevilla': Color(0xFFCE1126),
  'Valencia': Color(0xFFF18E00),
  'Villarreal': Color(0xFFFDE100),
};

Color _teamColor(String team) => _teamColors[team] ?? const Color(0xFF444466);

class PixelPlayerWidget extends StatelessWidget {
  final String skinId;
  final double size;
  final String team;
  final bool isCaptain;
  final bool isSelected;

  const PixelPlayerWidget({
    super.key,
    required this.skinId,
    required this.size,
    required this.team,
    this.isCaptain = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: PixelPlayerPainter(
          skinId: skinId,
          kitColor: _teamColor(team),
          isCaptain: isCaptain,
          isSelected: isSelected,
        ),
      ),
    );
  }
}
