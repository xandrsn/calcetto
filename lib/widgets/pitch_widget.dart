import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/user_data.dart';
import '../theme/app_theme.dart';
import '../utils/card_effects.dart';
import '../utils/popularity.dart';
import 'pixel_player_widget.dart';
import 'player_avatar.dart';

const _formations = <String, Map<String, List<Map<String, double>>>>{
  '4-3-3': {
    'GK': [
      {'x': 0.5, 'y': 0.1},
    ],
    'DEF': [
      {'x': 0.15, 'y': 0.28},
      {'x': 0.38, 'y': 0.28},
      {'x': 0.62, 'y': 0.28},
      {'x': 0.85, 'y': 0.28},
    ],
    'MID': [
      {'x': 0.2, 'y': 0.55},
      {'x': 0.5, 'y': 0.55},
      {'x': 0.8, 'y': 0.55},
    ],
    'FWD': [
      {'x': 0.2, 'y': 0.78},
      {'x': 0.5, 'y': 0.78},
      {'x': 0.8, 'y': 0.78},
    ],
  },
  '4-4-2': {
    'GK': [
      {'x': 0.5, 'y': 0.1},
    ],
    'DEF': [
      {'x': 0.15, 'y': 0.28},
      {'x': 0.38, 'y': 0.28},
      {'x': 0.62, 'y': 0.28},
      {'x': 0.85, 'y': 0.28},
    ],
    'MID': [
      {'x': 0.15, 'y': 0.55},
      {'x': 0.38, 'y': 0.55},
      {'x': 0.62, 'y': 0.55},
      {'x': 0.85, 'y': 0.55},
    ],
    'FWD': [
      {'x': 0.35, 'y': 0.78},
      {'x': 0.65, 'y': 0.78},
    ],
  },
  '4-2-4': {
    'GK': [
      {'x': 0.5, 'y': 0.1},
    ],
    'DEF': [
      {'x': 0.15, 'y': 0.28},
      {'x': 0.38, 'y': 0.28},
      {'x': 0.62, 'y': 0.28},
      {'x': 0.85, 'y': 0.28},
    ],
    'MID': [
      {'x': 0.35, 'y': 0.55},
      {'x': 0.65, 'y': 0.55},
    ],
    'FWD': [
      {'x': 0.15, 'y': 0.78},
      {'x': 0.38, 'y': 0.78},
      {'x': 0.62, 'y': 0.78},
      {'x': 0.85, 'y': 0.78},
    ],
  },
  '3-5-2': {
    'GK': [
      {'x': 0.5, 'y': 0.1},
    ],
    'DEF': [
      {'x': 0.2, 'y': 0.28},
      {'x': 0.5, 'y': 0.28},
      {'x': 0.8, 'y': 0.28},
    ],
    'MID': [
      {'x': 0.1, 'y': 0.55},
      {'x': 0.3, 'y': 0.55},
      {'x': 0.5, 'y': 0.55},
      {'x': 0.7, 'y': 0.55},
      {'x': 0.9, 'y': 0.55},
    ],
    'FWD': [
      {'x': 0.35, 'y': 0.78},
      {'x': 0.65, 'y': 0.78},
    ],
  },
  '3-4-3': {
    'GK': [
      {'x': 0.5, 'y': 0.1},
    ],
    'DEF': [
      {'x': 0.2, 'y': 0.28},
      {'x': 0.5, 'y': 0.28},
      {'x': 0.8, 'y': 0.28},
    ],
    'MID': [
      {'x': 0.15, 'y': 0.55},
      {'x': 0.38, 'y': 0.55},
      {'x': 0.62, 'y': 0.55},
      {'x': 0.85, 'y': 0.55},
    ],
    'FWD': [
      {'x': 0.2, 'y': 0.78},
      {'x': 0.5, 'y': 0.78},
      {'x': 0.8, 'y': 0.78},
    ],
  },
  '5-3-2': {
    'GK': [
      {'x': 0.5, 'y': 0.1},
    ],
    'DEF': [
      {'x': 0.1, 'y': 0.28},
      {'x': 0.28, 'y': 0.28},
      {'x': 0.5, 'y': 0.28},
      {'x': 0.72, 'y': 0.28},
      {'x': 0.9, 'y': 0.28},
    ],
    'MID': [
      {'x': 0.2, 'y': 0.55},
      {'x': 0.5, 'y': 0.55},
      {'x': 0.8, 'y': 0.55},
    ],
    'FWD': [
      {'x': 0.35, 'y': 0.78},
      {'x': 0.65, 'y': 0.78},
    ],
  },
  '5-4-1': {
    'GK': [
      {'x': 0.5, 'y': 0.1},
    ],
    'DEF': [
      {'x': 0.1, 'y': 0.28},
      {'x': 0.28, 'y': 0.28},
      {'x': 0.5, 'y': 0.28},
      {'x': 0.72, 'y': 0.28},
      {'x': 0.9, 'y': 0.28},
    ],
    'MID': [
      {'x': 0.15, 'y': 0.55},
      {'x': 0.38, 'y': 0.55},
      {'x': 0.62, 'y': 0.55},
      {'x': 0.85, 'y': 0.55},
    ],
    'FWD': [
      {'x': 0.5, 'y': 0.78},
    ],
  },
  '4-5-1': {
    'GK': [
      {'x': 0.5, 'y': 0.1},
    ],
    'DEF': [
      {'x': 0.15, 'y': 0.28},
      {'x': 0.38, 'y': 0.28},
      {'x': 0.62, 'y': 0.28},
      {'x': 0.85, 'y': 0.28},
    ],
    'MID': [
      {'x': 0.1, 'y': 0.55},
      {'x': 0.3, 'y': 0.55},
      {'x': 0.5, 'y': 0.55},
      {'x': 0.7, 'y': 0.55},
      {'x': 0.9, 'y': 0.55},
    ],
    'FWD': [
      {'x': 0.5, 'y': 0.78},
    ],
  },
  '3-3-4': {
    'GK': [
      {'x': 0.5, 'y': 0.1},
    ],
    'DEF': [
      {'x': 0.2, 'y': 0.28},
      {'x': 0.5, 'y': 0.28},
      {'x': 0.8, 'y': 0.28},
    ],
    'MID': [
      {'x': 0.2, 'y': 0.55},
      {'x': 0.5, 'y': 0.55},
      {'x': 0.8, 'y': 0.55},
    ],
    'FWD': [
      {'x': 0.15, 'y': 0.78},
      {'x': 0.38, 'y': 0.78},
      {'x': 0.62, 'y': 0.78},
      {'x': 0.85, 'y': 0.78},
    ],
  },
};

const _positionOrder = ['GK', 'DEF', 'MID', 'FWD'];

List<Map<String, double>> _getPositions(String formation) {
  final fDef = _formations[formation] ?? _formations['4-3-3']!;
  final positions = <Map<String, double>>[];
  for (final pos in _positionOrder) {
    if (fDef.containsKey(pos)) {
      positions.addAll(fDef[pos]!);
    }
  }
  return positions;
}

class PitchWidget extends StatelessWidget {
  final UserData user;
  final List<Player> players;
  final String? todayCaptain;
  final Function(Player)? onPlayerTap;
  final List<String>? draftSquad;
  final Function(int slotIndex)? onEmptySlotTap;
  final int? selectedSlotIndex;
  final Map<String, int>? popMap;
  final int totalUsers;

  /// Per-player display modifiers from boost/defense cards the owner played
  /// today. When null, percentages render as plain ownership %.
  final Map<String, PointDisplayMods>? pointMods;

  /// When true, each starter slot is a drag source and drop target so players
  /// can be swapped by dragging (substitutions). Off for read-only pitches.
  final bool enableDrag;

  /// Returns whether dropping [dragged] onto starter [target] is a legal swap.
  final bool Function(String dragged, String target)? canAcceptDrag;

  /// Performs the swap of [dragged] with starter [target].
  final void Function(String dragged, String target)? onAcceptDrag;

  /// Manage-phase flat display: every starter shows 100%, the captain 300%,
  /// ignoring popularity and cards (none are in play yet).
  final bool flatPercent;

  const PitchWidget({
    super.key,
    required this.user,
    required this.players,
    this.todayCaptain,
    this.onPlayerTap,
    this.draftSquad,
    this.onEmptySlotTap,
    this.selectedSlotIndex,
    this.popMap,
    this.totalUsers = 1,
    this.pointMods,
    this.enableDrag = false,
    this.canAcceptDrag,
    this.onAcceptDrag,
    this.flatPercent = false,
  });

  @override
  Widget build(BuildContext context) {
    final playerMap = {for (final p in players) p.id: p};
    final positions = _getPositions(user.formation);
    final squad = draftSquad ?? user.allSquadPlayers;
    final slotCount = positions.length;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return Stack(
          children: [
            Container(color: kPitchGreen),
            CustomPaint(size: Size(w, h), painter: _PitchMarkingsPainter()),
            for (var i = 0; i < slotCount; i++) ...[
              _buildPlayerSlot(
                ctx,
                i < squad.length ? squad[i] : '',
                positions[i],
                playerMap,
                w,
                h,
                i,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildPlayerSlot(
    BuildContext ctx,
    String pid,
    Map<String, double> pos,
    Map<String, Player> playerMap,
    double w,
    double h,
    int slotIndex,
  ) {
    final player = pid.isNotEmpty ? playerMap[pid] : null;
    final isEmpty = player == null;
    final isCaptain = pid == todayCaptain;
    final isSelected = slotIndex == selectedSlotIndex;
    final spriteSize = (w * 0.12).clamp(36.0, 54.0);
    // The slot column is as wide as its name label, so it must be positioned by
    // half the label width (not half the sprite) to stay centred on the
    // formation point — otherwise every player drifts to the right.
    final slotW = spriteSize * 1.9;

    final x = pos['x']! * w - slotW / 2;
    final y = pos['y']! * h - spriteSize / 2;

    VoidCallback? tapCb;
    if (!isEmpty && onPlayerTap != null) {
      tapCb = () => onPlayerTap!(player);
    } else if (isEmpty && onEmptySlotTap != null) {
      tapCb = () => onEmptySlotTap!(slotIndex);
    }

    final slotChild = GestureDetector(
      onTap: tapCb,
      child: Column(
        children: [
          isEmpty
              ? _EmptySlotSprite(size: spriteSize, isSelected: isSelected)
              : PlayerAvatar(
                  player: player,
                  size: spriteSize,
                  isCaptain: isCaptain,
                  isSelected: isSelected,
                ),
          const SizedBox(height: 3),
          Container(
            width: slotW,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Player name on top …
                Text(
                  isEmpty ? '—' : _shortName(player.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontWeight: FontWeight.w600,
                    fontSize: (spriteSize * 0.26).clamp(9.0, 12.0),
                    height: 1.1,
                    color: isSelected
                        ? kAccentGreen
                        : isCaptain
                        ? kAccentYellow
                        : Colors.white,
                  ),
                ),
                // … and the percentage directly beneath it, centered.
                if (!isEmpty && (popMap != null || flatPercent))
                  _PitchPercent(
                    isCaptain: isCaptain,
                    flatPercent: flatPercent,
                    mods: pointMods?[player.id] ?? const PointDisplayMods(),
                    ownership: popMap == null
                        ? 0
                        : calculatePopularityPercent(
                            popMap![player.id] ?? 0,
                            totalUsers,
                          ),
                    fontSize: (spriteSize * 0.24).clamp(9.0, 11.0),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!enableDrag || isEmpty) {
      return Positioned(left: x, top: y, child: slotChild);
    }

    final target = DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          d.data != pid && (canAcceptDrag?.call(d.data, pid) ?? false),
      onAcceptWithDetails: (d) => onAcceptDrag?.call(d.data, pid),
      builder: (ctx, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Draggable<String>(
          data: pid,
          feedback: PixelPlayerWidget(
            skinId: player.skin,
            size: spriteSize * 1.25,
            team: player.team,
            isCaptain: isCaptain,
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: slotChild),
          child: AnimatedScale(
            scale: hovering ? 1.12 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: hovering
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: kAccentGreen, width: 2),
                    ),
                    child: slotChild,
                  )
                : slotChild,
          ),
        );
      },
    );

    return Positioned(left: x, top: y, child: target);
  }

  // Last name in Title case (e.g. "Messi"), capped so it can't overflow.
  String _shortName(String name) {
    final parts = name.trim().split(' ');
    final base = parts.isEmpty ? name : parts.last;
    if (base.isEmpty) return base;
    final t = base.length > 11 ? base.substring(0, 11) : base;
    return t[0].toUpperCase() + t.substring(1).toLowerCase();
  }
}

/// The percentage shown directly under a player's name on the pitch.
///
/// In the manage phase it's a flat preview (100%, captain 300%); otherwise it's
/// the ownership % scaled by the owner's boost/captain modifiers, with special
/// rendering for stolen (0%), hat-trick (x3) and shielded players.
class _PitchPercent extends StatelessWidget {
  final bool isCaptain;
  final bool flatPercent;
  final PointDisplayMods mods;
  final double ownership;
  final double fontSize;

  const _PitchPercent({
    required this.isCaptain,
    required this.flatPercent,
    required this.mods,
    required this.ownership,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    // Matchday (flat) view: base 100% (captain 300%) scaled by the owner's
    // played card boosts — e.g. a goalkeeper with a x2 card shows 200%.
    // Editor view: ownership % scaled by mods.
    final base = isCaptain ? 300 : 100;
    final pctInt = flatPercent
        ? (base * mods.multiplier).round()
        : (ownership * mods.multiplier * 100).round();
    final boosted = mods.multiplier > 1.0 || (flatPercent && isCaptain);
    final label = mods.stolen
        ? '0%'
        : mods.hatTrick
        ? 'x3'
        : '$pctInt%';
    final col = mods.stolen
        ? kTextMuted
        : mods.hatTrick || boosted
        ? kAccentYellow
        : pctInt >= 80
        ? kAccentGreen
        : pctInt >= 50
        ? kAccentYellow
        : kAccentRed;

    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (mods.shielded)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(Icons.shield, size: fontSize + 1, color: kAccentBlue),
            ),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'ChakraPetch',
              fontWeight: FontWeight.w700,
              fontSize: fontSize,
              color: col,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySlotSprite extends StatelessWidget {
  final double size;
  final bool isSelected;
  const _EmptySlotSprite({required this.size, this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        border: Border.all(
          color: isSelected
              ? kAccentGreen
              : Colors.white.withValues(alpha: 0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Icon(
        Icons.add,
        color: isSelected ? kAccentGreen : Colors.white.withValues(alpha: 0.5),
        size: size * 0.5,
      ),
    );
  }
}

class _PitchMarkingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = false;

    final w = size.width;
    final h = size.height;

    // Halfway line
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.5 - 1, w, 2),
      paint..style = PaintingStyle.fill,
    );

    // Centre circle (pixel square approximation)
    for (double r = 0; r < 20; r += 4) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(w / 2, h / 2),
          width: r * 2,
          height: r * 2,
        ),
        paint..style = PaintingStyle.stroke,
      );
    }

    // Top penalty box
    canvas.drawRect(
      Rect.fromLTWH(w * 0.2, 0, w * 0.6, h * 0.16),
      paint..style = PaintingStyle.stroke,
    );

    // Bottom penalty box
    canvas.drawRect(
      Rect.fromLTWH(w * 0.2, h * 0.84, w * 0.6, h * 0.16),
      paint..style = PaintingStyle.stroke,
    );

    // Corner marks
    final corner = 12.0;
    for (final cx in [0.0, w]) {
      for (final cy in [0.0, h]) {
        canvas.drawRect(
          Rect.fromLTWH(
            cx == 0 ? 0 : w - corner,
            cy == 0 ? 0 : h - corner,
            corner,
            corner,
          ),
          paint..style = PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PitchMarkingsPainter _) => false;
}
