import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/models/powerup_card.dart';

void main() {
  group('generatePackTypes rules', () {
    test('always returns the requested count', () {
      for (var seed = 0; seed < 200; seed++) {
        expect(generatePackTypes(Random(seed)).length, 5);
      }
    });

    test('at most ONE extra-player card per pack (robo + espontáneo)', () {
      for (var seed = 0; seed < 500; seed++) {
        final pack = generatePackTypes(Random(seed));
        final extras = pack
            .where(
              (t) =>
                  t == CardType.robo || t == CardType.pitchInvader,
            )
            .length;
        expect(extras, lessThanOrEqualTo(1), reason: 'seed $seed: $pack');
      }
    });

    test('respects each card maxPerPack', () {
      for (var seed = 0; seed < 500; seed++) {
        final pack = generatePackTypes(Random(seed));
        final counts = <CardType, int>{};
        for (final t in pack) {
          counts[t] = (counts[t] ?? 0) + 1;
        }
        counts.forEach((t, n) {
          expect(
            n,
            lessThanOrEqualTo(kCardCatalog[t]!.maxPerPack),
            reason: 'seed $seed: $t x$n exceeds max',
          );
        });
      }
    });

    test('FICHAJE EXTRA is allowed to repeat (maxPerPack > 1)', () {
      expect(kCardCatalog[CardType.subExtra]!.maxPerPack, greaterThan(1));
      // Over many packs we should see at least one with 2+ FICHAJE EXTRA.
      var sawMultiple = false;
      for (var seed = 0; seed < 1000 && !sawMultiple; seed++) {
        final n = generatePackTypes(
          Random(seed),
        ).where((t) => t == CardType.subExtra).length;
        if (n >= 2) sawMultiple = true;
      }
      expect(sawMultiple, isTrue);
    });

    test('every catalog entry has a unique id and image filename', () {
      final ids = kCardCatalog.values.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final d in kCardCatalog.values) {
        expect(d.imageFile, '${d.id}.png');
      }
    });

    test('catalog covers every CardType', () {
      for (final t in CardType.values) {
        expect(kCardCatalog.containsKey(t), isTrue, reason: '$t missing');
      }
    });
  });
}
