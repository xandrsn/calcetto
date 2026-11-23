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

  /// First letters of the first and last name, for a broken/unreachable photo.
  String get initials {
    final parts = player.name.trim().split(RegExp(r'\s+'))..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    final a = parts.first[0];
    return (parts.length > 1 ? a + parts.last[0] : a).toUpperCase();
  }

  Widget _initials() => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: kSurface2, shape: BoxShape.circle),
    child: Text(
      initials,
      style: TextStyle(
        fontFamily: 'ChakraPetch',
        fontSize: size * 0.4,
        color: kTextPrimary,
      ),
    ),
  );

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
    } else if (version.startsWith('data:')) {
      face = Image.memory(
        UriData.parse(version).contentAsBytes(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _initials(),
      );
    } else {
      final isExternal = version.startsWith('http');
      face = Image.network(
        isExternal ? version : playerImageUrl(player.id, version),
        headers: isExternal ? null : kGithubImageHeaders,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _initials(),
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
