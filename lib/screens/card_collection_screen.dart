import 'package:flutter/material.dart';
import '../models/powerup_card.dart';
import '../theme/app_theme.dart';
import '../widgets/pixel_card_widget.dart';

/// Read-only encyclopedia of every power-up card: art, rarity, effect, and the
/// live draw odds (computed straight from kCardCatalog weights, so it never
/// drifts from the actual pack generator). One sticker pack = 5 cards per day.
class CardCollectionScreen extends StatelessWidget {
  const CardCollectionScreen({super.key});

  static const _rarityOrder = [
    CardRarity.common,
    CardRarity.uncommon,
    CardRarity.rare,
    CardRarity.epic,
    CardRarity.legendary,
  ];

  static const _rarityLabel = {
    CardRarity.common: 'COMÚN',
    CardRarity.uncommon: 'POCO COMÚN',
    CardRarity.rare: 'RARA',
    CardRarity.epic: 'ÉPICA',
    CardRarity.legendary: 'LEGENDARIA',
  };

  Color _rarityColor(CardRarity r) => switch (r) {
    CardRarity.common => Colors.grey,
    CardRarity.uncommon => kAccentGreen,
    CardRarity.rare => kAccentBlue,
    CardRarity.epic => const Color(0xFF9B59B6),
    CardRarity.legendary => kAccentYellow,
  };

  @override
  Widget build(BuildContext context) {
    final all = kCardCatalog.values.toList();
    final totalWeight = all.fold<int>(0, (s, d) => s + d.weight);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'COLECCIÓN DE CARTAS',
          style: TextStyle(fontFamily: 'ChakraPetch', fontSize: 11),
        ),
      ),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          const cols = 3;
          const gap = 8.0;
          const pad = 16.0;
          final cardW =
              (constraints.maxWidth - pad * 2 - gap * (cols - 1)) / cols;
          return ListView(
            padding: const EdgeInsets.all(pad),
            children: [
              Text(
                '${all.length} CARTAS · UN SOBRE TRAE 5 AL DÍA',
                style: const TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 12,
                  color: kAccentGreen,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'El % es el peso de robo de cada carta.',
                style: TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 11,
                  color: kTextMuted,
                ),
              ),
              const SizedBox(height: 16),
              for (final rarity in _rarityOrder) ...[
                _RarityHeader(
                  label: _rarityLabel[rarity]!,
                  color: _rarityColor(rarity),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final def
                        in all.where((d) => d.rarity == rarity).toList()
                          ..sort((a, b) => b.weight.compareTo(a.weight)))
                      _CollectionCard(
                        def: def,
                        width: cardW,
                        odds: 100 * def.weight / totalWeight,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RarityHeader extends StatelessWidget {
  const _RarityHeader({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 14,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: color.withValues(alpha: 0.3))),
      ],
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.def,
    required this.width,
    required this.odds,
  });
  final CardDef def;
  final double width;
  final double odds;

  @override
  Widget build(BuildContext context) {
    final card = PowerupCard.ofType(def.type);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PixelCardWidget(
            card: card,
            width: width,
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => ExpandedCardDialog(
                card: card,
                canUse: false,
                onUse: () {},
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${odds.toStringAsFixed(1)}%',
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 12,
              color: kAccentYellow,
            ),
          ),
          Text(
            def.description,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 6,
              color: kTextMuted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
