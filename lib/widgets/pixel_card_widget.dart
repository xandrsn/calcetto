import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/powerup_card.dart';
import '../services/card_images.dart';
import '../theme/app_theme.dart';
import '../utils/time_utils.dart';

Color _rarityColor(CardRarity r) {
  switch (r) {
    case CardRarity.common:
      return Colors.grey;
    case CardRarity.uncommon:
      return kAccentGreen;
    case CardRarity.rare:
      return kAccentBlue;
    case CardRarity.epic:
      return const Color(0xFF9B59B6);
    case CardRarity.legendary:
      return kAccentYellow;
  }
}

String _rarityLabel(CardRarity r) {
  switch (r) {
    case CardRarity.common:
      return 'COMÚN';
    case CardRarity.uncommon:
      return 'POCO COMÚN';
    case CardRarity.rare:
      return 'RARA';
    case CardRarity.epic:
      return 'ÉPICA';
    case CardRarity.legendary:
      return 'LEGENDARIA';
  }
}

String _categoryLabel(CardCategory c) {
  switch (c) {
    case CardCategory.attack:
      return 'ATAQUE';
    case CardCategory.defense:
      return 'DEFENSA';
    case CardCategory.boost:
      return 'IMPULSO';
    case CardCategory.utility:
      return 'UTILIDAD';
  }
}

Color _categoryColor(CardCategory c) {
  switch (c) {
    case CardCategory.attack:
      return kAccentRed;
    case CardCategory.defense:
      return kAccentBlue;
    case CardCategory.boost:
      return kAccentGreen;
    case CardCategory.utility:
      return kAccentYellow;
  }
}

// Icon + value tag come from the single card catalog (powerup_card.dart).
IconData _iconFor(CardType t) => cardDef(t).icon;
String _shortEffectFor(CardType t) => cardDef(t).shortEffect;

/// A single power-up rendered as a compact trading card: rarity frame, an art
/// window with the card's emblem, its name, and a value badge. Tap to open the
/// large [ExpandedCardDialog].
class PixelCardWidget extends ConsumerWidget {
  final PowerupCard card;
  final VoidCallback? onTap;

  /// Card width; the height keeps the trading-card aspect (104×148). The cards
  /// tab passes a width computed to fill the row, so there's no dead space.
  final double width;

  const PixelCardWidget({
    super.key,
    required this.card,
    this.onTap,
    this.width = 104,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imgVersion = ref.watch(cardImagesProvider).valueOrNull?[card.typeId];
    final expired = isCardsExpired();
    final dimmed = card.isPlayed || expired;
    final rColor = _rarityColor(card.rarity);
    final catColor = _categoryColor(card.category);
    final legendary = card.rarity == CardRarity.legendary;

    final status = card.isPlayed
        ? 'JUGADA'
        : expired
        ? 'EXPIRADA'
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: dimmed ? 0.5 : 1.0,
        child: Container(
          width: width,
          height: width * 148 / 104,
          decoration: BoxDecoration(
            color: kSurface,
            border: Border.all(color: rColor, width: legendary ? 3 : 2),
            boxShadow: [
              BoxShadow(
                color: rColor.withValues(alpha: 0.35),
                blurRadius: 6,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Rarity header band. (Category is conveyed by the card colour +
              // the bottom badge, so only the rarity label sits here — keeping
              // it to one line avoids overflow on narrow cards.)
              Container(
                color: rColor,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                width: double.infinity,
                child: Text(
                  _rarityLabel(card.rarity),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: kFontUI,
                    fontWeight: FontWeight.w700,
                    fontSize: 7,
                    color: Colors.black,
                  ),
                ),
              ),
              if (legendary) _LegendaryShimmer(color: rColor),
              // Art window — shows the card's hub image (bigger, edge-to-edge),
              // falling back to the emblem icon while loading / if none is set.
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(3, 3, 3, 3),
                  decoration: BoxDecoration(
                    color: kBackground,
                    border: Border.all(
                      color: catColor.withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: ClipRect(
                    child: _CardArt(
                      card: card,
                      version: imgVersion,
                      catColor: catColor,
                      iconSize: 52,
                    ),
                  ),
                ),
              ),
              // Name.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(
                  card.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: kFontUI,
                    fontWeight: FontWeight.w700,
                    fontSize: 9,
                    height: 1.05,
                    color: kTextPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              // Value badge or play status.
              Container(
                width: double.infinity,
                color: status != null
                    ? Colors.black.withValues(alpha: 0.4)
                    : catColor.withValues(alpha: 0.18),
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  status ?? _shortEffectFor(card.type),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: kFontUI,
                    fontWeight: FontWeight.w700,
                    fontSize: 8,
                    color: status != null
                        ? (expired ? kAccentRed : kTextMuted)
                        : catColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Large, readable view of a card with USE and close (X) actions.
class ExpandedCardDialog extends ConsumerWidget {
  final PowerupCard card;
  final bool canUse;
  final VoidCallback onUse;

  const ExpandedCardDialog({
    super.key,
    required this.card,
    required this.canUse,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rColor = _rarityColor(card.rarity);
    final catColor = _categoryColor(card.category);
    final imgVersion = ref.watch(cardImagesProvider).valueOrNull?[card.typeId];
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(
            color: rColor,
            width: card.rarity == CardRarity.legendary ? 4 : 3,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _rarityLabel(card.rarity),
                    style: TextStyle(
                      fontFamily: kFontUI,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      color: rColor,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, color: kTextMuted, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Art window (hub image, or emblem fallback).
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: kBackground,
                border: Border.all(color: catColor, width: 2),
              ),
              child: ClipRect(
                child: _CardArt(
                  card: card,
                  version: imgVersion,
                  catColor: catColor,
                  iconSize: 84,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              card.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: kFontUI,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.2,
                color: rColor,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: catColor.withValues(alpha: 0.18),
              child: Text(
                '${_categoryLabel(card.category)} · ${_shortEffectFor(card.type)}',
                style: TextStyle(
                  fontFamily: kFontUI,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  color: catColor,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              card.description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: kFontUI,
                fontSize: 12,
                color: kTextPrimary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            if (card.isPlayed)
              const Text(
                'YA JUGADA',
                style: TextStyle(
                  fontFamily: kFontUI,
                  fontSize: 11,
                  color: kTextMuted,
                ),
              )
            else if (canUse)
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: onUse,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    color: rColor,
                    child: const Text(
                      'USAR CARTA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: kFontUI,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              )
            else
              const Text(
                'FUERA DE LA VENTANA (13:00–17:00)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: kFontUI,
                  fontSize: 10,
                  color: kTextMuted,
                  height: 1.4,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The card art: the hub image scaled to fill, with the emblem icon as the
/// loading / no-image fallback.
class _CardArt extends StatelessWidget {
  final PowerupCard card;
  final String? version;
  final Color catColor;
  final double iconSize;

  const _CardArt({
    required this.card,
    required this.version,
    required this.catColor,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Icon(_iconFor(card.type), color: catColor, size: iconSize),
    );
    final v = version;
    if (v == null) return fallback;
    return Image.network(
      cardImageUrl(card.typeId, v),
      headers: kCardImageHeaders,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (_, child, p) => p == null ? child : fallback,
    );
  }
}

class _LegendaryShimmer extends StatefulWidget {
  final Color color;
  const _LegendaryShimmer({required this.color});

  @override
  State<_LegendaryShimmer> createState() => _LegendaryShimmerState();
}

class _LegendaryShimmerState extends State<_LegendaryShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        height: 3,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              widget.color.withValues(alpha: _ctrl.value),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}
