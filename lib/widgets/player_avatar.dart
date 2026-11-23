import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player.dart';
import '../services/player_images.dart';
import '../theme/app_theme.dart';
import 'pixel_player_widget.dart';

/// Renders a player's global custom image when one exists, falling back to the
/// generated pixel sprite while loading, on error, or when no image is set.
/// A captain badge is overlaid so it stays visible over custom photos too.
class PlayerAvatar extends ConsumerWidget {
  final Player player;
  final double size;
  final bool isCaptain;
  final bool isSelected;

  const PlayerAvatar({
    super.key,
    required this.player,
    required this.size,
    this.isCaptain = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = PixelPlayerWidget(
      skinId: player.skin,
      size: size,
      team: player.team,
      isCaptain: isCaptain,
      isSelected: isSelected,
    );

    final version = ref.watch(playerImagesProvider).valueOrNull?[player.id];
    final Widget face;
    if (version == null) {
      face = fallback;
    } else {
      final isExternal = version.startsWith('http');
      face = Image.network(
        isExternal ? version : playerImageUrl(player.id, version),
        headers: isExternal ? null : kGithubImageHeaders,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback,
      );
    }

    if (!isCaptain) {
      return SizedBox(width: size, height: size, child: face);
    }

    final badge = (size * 0.42).clamp(12.0, 22.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: face),
          Positioned(
            top: -badge * 0.35,
            left: -badge * 0.2,
            child: Container(
              width: badge,
              height: badge,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: kAccentYellow,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 2)],
              ),
              child: Text(
                'C',
                style: TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: badge * 0.5,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
