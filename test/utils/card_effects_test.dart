import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/models/player.dart';
import 'package:calcetto/models/powerup_card.dart';
import 'package:calcetto/utils/card_effects.dart';

Player _p(String id, String position) => Player(
  id: id,
  name: id,
  team: 'ESP',
  position: position,
  skin: 'x',
  pointsPerMatch: const {},
  totalPoints: 0,
  goals: 0,
  assists: 0,
);

PowerupCard _played(CardType type, {String? target}) => PowerupCard(
  type: type,
  rarity: CardRarity.uncommon,
  category: CardCategory.boost,
  variant: 'v',
  targetPlayer: target,
  playedAt: DateTime(2026, 6, 11, 14),
);

void main() {
  final players = {
    'gk': _p('gk', 'GK'),
    'def': _p('def', 'DEF'),
    'mid': _p('mid', 'MID'),
    'fwd': _p('fwd', 'FWD'),
  };

  group('pointDisplayMods', () {
    test('no cards -> no modifiers', () {
      final mods = pointDisplayMods(cardsPlayed: [], playersById: players);
      expect(mods, isEmpty);
    });

    test('Tiki-Taka doubles only midfielders', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.tikitaka)],
        playersById: players,
      );
      expect(mods['mid']?.multiplier, 2.0);
      expect(mods.containsKey('def'), isFalse);
      expect(mods.containsKey('fwd'), isFalse);
    });

    test('Catenaccio doubles DEF and GK', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.catenaccio)],
        playersById: players,
      );
      expect(mods['def']?.multiplier, 2.0);
      expect(mods['gk']?.multiplier, 2.0);
      expect(mods.containsKey('mid'), isFalse);
    });

    test('Golden Glove stacks with Catenaccio on the GK (x6)', () {
      final mods = pointDisplayMods(
        cardsPlayed: [
          _played(CardType.catenaccio),
          _played(CardType.goldenGlove),
        ],
        playersById: players,
      );
      expect(mods['gk']?.multiplier, 6.0);
      expect(mods['def']?.multiplier, 2.0);
    });

    test('Hat Trick Hero flags only the targeted player', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.hatTrickHero, target: 'fwd')],
        playersById: players,
      );
      expect(mods['fwd']?.hatTrick, isTrue);
      expect(mods.containsKey('mid'), isFalse);
    });

    test('Escudo flags only the targeted player', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.escudo, target: 'def')],
        playersById: players,
      );
      expect(mods['def']?.shielded, isTrue);
      expect(mods['def']?.multiplier, 1.0);
    });

    test('attack cards do not modify the owner display', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.redCard, target: 'mid')],
        playersById: players,
      );
      expect(mods, isEmpty);
    });

    test('captain gets the flat captain multiplier (x3)', () {
      final mods = pointDisplayMods(
        cardsPlayed: const [],
        playersById: players,
        captainId: 'fwd',
      );
      expect(mods['fwd']?.multiplier, 3.0);
    });

    test('captain multiplier stacks with own boost', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.tikitaka)],
        playersById: players,
        captainId: 'mid',
      );
      // Tiki-Taka x2 on MID * captain x3 = x6
      expect(mods['mid']?.multiplier, 6.0);
    });

    test('Muralla x1.5 on DEF and GK only', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.muralla)],
        playersById: players,
      );
      expect(mods['def']?.multiplier, 1.5);
      expect(mods['gk']?.multiplier, 1.5);
      expect(mods.containsKey('mid'), isFalse);
      expect(mods.containsKey('fwd'), isFalse);
    });

    test('Tridente doubles forwards only', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.tridente)],
        playersById: players,
      );
      expect(mods['fwd']?.multiplier, 2.0);
      expect(mods.containsKey('mid'), isFalse);
    });

    test('Francotirador doubles only the targeted player', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.francotirador, target: 'fwd')],
        playersById: players,
      );
      expect(mods['fwd']?.multiplier, 2.0);
      expect(mods.containsKey('mid'), isFalse);
    });

    test('Prima x1.5 on the targeted player', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.prima, target: 'def')],
        playersById: players,
      );
      expect(mods['def']?.multiplier, 1.5);
    });

    test('Motivación x1.3 on the whole XI', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.motivacion)],
        playersById: players,
      );
      for (final id in players.keys) {
        expect(mods[id]?.multiplier, closeTo(1.3, 1e-9));
      }
    });

    test('Vitamina x1.15 on the whole XI', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.vitamina)],
        playersById: players,
      );
      expect(mods['gk']?.multiplier, closeTo(1.15, 1e-9));
      expect(mods['fwd']?.multiplier, closeTo(1.15, 1e-9));
    });

    test('global + position boosts stack multiplicatively', () {
      // Motivación (x1.3 all) + Tridente (x2 FWD) on a forward = x2.6.
      final mods = pointDisplayMods(
        cardsPlayed: [
          _played(CardType.motivacion),
          _played(CardType.tridente),
        ],
        playersById: players,
      );
      expect(mods['fwd']?.multiplier, closeTo(2.6, 1e-9));
      expect(mods['mid']?.multiplier, closeTo(1.3, 1e-9));
    });

    test('Chilena x1.5 on forwards only', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.chilena)],
        playersById: players,
      );
      expect(mods['fwd']?.multiplier, closeTo(1.5, 1e-9));
      expect(mods.containsKey('mid'), isFalse);
    });

    test('Primo de Zumosol x1.75 on DEF and GK', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.primoZumosol)],
        playersById: players,
      );
      expect(mods['def']?.multiplier, closeTo(1.75, 1e-9));
      expect(mods['gk']?.multiplier, closeTo(1.75, 1e-9));
      expect(mods.containsKey('fwd'), isFalse);
    });

    test('Cerrojazo doubles DEF&GK and shields the target', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.cerrojazo, target: 'def')],
        playersById: players,
      );
      expect(mods['def']?.multiplier, 2.0);
      expect(mods['def']?.shielded, isTrue);
      expect(mods['gk']?.multiplier, 2.0);
    });

    test('Alcoyano +30% and Mano de Dios x3 on the targeted player', () {
      final a = pointDisplayMods(
        cardsPlayed: [_played(CardType.alcoyano, target: 'mid')],
        playersById: players,
      );
      expect(a['mid']?.multiplier, closeTo(1.3, 1e-9));
      final m = pointDisplayMods(
        cardsPlayed: [_played(CardType.manoDeDios, target: 'fwd')],
        playersById: players,
      );
      expect(m['fwd']?.multiplier, 3.0);
    });

    test('Siuuu flags the targeted player (conditional on scoring)', () {
      final mods = pointDisplayMods(
        cardsPlayed: [_played(CardType.siuuu, target: 'fwd')],
        playersById: players,
      );
      expect(mods['fwd']?.hatTrick, isTrue);
    });
  });

  group('foldIncomingAttacks', () {
    Map<String, dynamic> usersWithAttack(String type, String target) => {
      'rival': {
        'active': {
          'cards_played': [
            {'type': type, 'target_user': 'alice', 'target_player': target},
          ],
        },
      },
    };

    test('red card zeroes the targeted player', () {
      final base = foldIncomingAttacks(
        {},
        viewer: 'alice',
        allUsers: usersWithAttack('red_card', 'mid'),
      );
      expect(base['mid']?.multiplier, 0.0);
    });

    test('yellow card halves the targeted player', () {
      final base = foldIncomingAttacks(
        {},
        viewer: 'alice',
        allUsers: usersWithAttack('yellow_card', 'def'),
      );
      expect(base['def']?.multiplier, 0.5);
    });

    test('robo zeroes and flags stolen', () {
      final base = foldIncomingAttacks(
        {},
        viewer: 'alice',
        allUsers: usersWithAttack('robo', 'fwd'),
      );
      expect(base['fwd']?.multiplier, 0.0);
      expect(base['fwd']?.stolen, isTrue);
    });

    test('escudo-shielded player is immune', () {
      final base = <String, PointDisplayMods>{
        'mid': const PointDisplayMods(shielded: true),
      };
      foldIncomingAttacks(
        base,
        viewer: 'alice',
        allUsers: usersWithAttack('red_card', 'mid'),
      );
      expect(base['mid']?.multiplier, 1.0); // unchanged
    });

    test('ignores attacks aimed at other users', () {
      final base = foldIncomingAttacks(
        {},
        viewer: 'bob',
        allUsers: usersWithAttack('red_card', 'mid'),
      );
      expect(base, isEmpty);
    });

    test('mordisco zeroes like a red card', () {
      final base = foldIncomingAttacks(
        {},
        viewer: 'alice',
        allUsers: usersWithAttack('mordisco', 'fwd'),
      );
      expect(base['fwd']?.multiplier, 0.0);
    });

    test('piscinazo halves like a yellow card', () {
      final base = foldIncomingAttacks(
        {},
        viewer: 'alice',
        allUsers: usersWithAttack('piscinazo', 'def'),
      );
      expect(base['def']?.multiplier, 0.5);
    });

    test('el_var applies x0.75 to the targeted player', () {
      final base = foldIncomingAttacks(
        {},
        viewer: 'alice',
        allUsers: usersWithAttack('el_var', 'mid'),
      );
      expect(base['mid']?.multiplier, 0.75);
    });
  });

  group('flatPointSwing', () {
    test('sums own flat bonuses and incoming flat deductions', () {
      final swing = flatPointSwing(
        viewer: 'alice',
        ownCards: [
          PowerupCard.ofType(CardType.propina), // +10
          PowerupCard.ofType(CardType.loteria), // +50
        ],
        allUsers: {
          'rival': {
            'active': {
              'cards_played': [
                {'type': 'multa', 'target_user': 'alice'}, // -10
                {'type': 'embargo', 'target_user': 'bob'}, // not me
              ],
            },
          },
        },
      );
      expect(swing.self, 60);
      expect(swing.incoming, 10);
    });

    test('ignores own deduction cards and non-flat cards', () {
      final swing = flatPointSwing(
        viewer: 'alice',
        ownCards: [
          PowerupCard.ofType(CardType.multa), // attack flat — not a self bonus
          PowerupCard.ofType(CardType.motivacion), // not flat
        ],
        allUsers: const {},
      );
      expect(swing.self, 0);
      expect(swing.incoming, 0);
    });
  });
}
