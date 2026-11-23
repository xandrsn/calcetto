import 'package:flutter/material.dart';
import '../models/player.dart';
import '../theme/app_theme.dart';
import 'player_avatar.dart';

const _posColors = <String, Color>{
  'GK': kAccentYellow,
  'DEF': kAccentBlue,
  'MID': kAccentGreen,
  'FWD': kAccentRed,
};

Color positionColor(String position) => _posColors[position] ?? kTextMuted;

/// A compact "player trading card" used as the header of the player stat /
/// captain menus, matching the power-up card aesthetic: a framed photo window
/// (with the position colour), the player's name/team/position, and a couple of
/// key stat chips. Display-only — actions (captain, replace) sit below it.
class PlayerTradingCard extends StatelessWidget {
  final Player player;
  final String? captainLabel;
  final bool isCaptain;
  final double? ownershipPct;

  const PlayerTradingCard({
    super.key,
    required this.player,
    this.captainLabel,
    this.isCaptain = false,
    this.ownershipPct,
  });

  @override
  Widget build(BuildContext context) {
    final pos = player.position;
    final color = positionColor(pos);

    return Container(
      decoration: BoxDecoration(
        color: kSurface2,
        border: Border.all(color: color.withValues(alpha: 0.7), width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 8,
            spreadRadius: -3,
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          // Framed photo window.
          Container(
            decoration: BoxDecoration(
              color: kBackground,
              border: Border.all(color: color, width: 2),
            ),
            padding: const EdgeInsets.all(3),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PlayerAvatar(player: player, size: 64, isCaptain: isCaptain),
                Positioned(
                  left: -3,
                  top: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    color: color,
                    child: Text(
                      pos,
                      style: const TextStyle(
                        fontFamily: kFontUI,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Name + meta + stat chips.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: kFontUI,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  player.team.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: kFontUI,
                    fontSize: 11,
                    color: kTextMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    _Chip(label: 'PTS', value: player.totalPoints.toStringAsFixed(0)),
                    _Chip(label: 'G', value: player.goals.toString()),
                    _Chip(label: 'A', value: player.assists.toString()),
                    if (ownershipPct != null)
                      _Chip(
                        label: 'OWN',
                        value: '${ownershipPct!.round()}%',
                        color: color,
                      ),
                    if (isCaptain)
                      _Chip(
                        label: '★',
                        value: captainLabel ?? 'CAP',
                        color: kAccentYellow,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Chip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? kAccentBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        border: Border.all(color: c.withValues(alpha: 0.5), width: 1),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                fontFamily: kFontUI,
                fontSize: 13,
                color: kTextMuted,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontFamily: kFontUI,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
