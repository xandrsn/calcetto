import 'dart:math';
import 'package:flutter/material.dart';

/// All power-up card types. To add a new card: add a value here and a [CardDef]
/// entry in [kCardCatalog] — that single entry defines its name, art, rarity,
/// category, effect tag, draw odds, and pack rules. Drop its image at
/// `images/cards/<id>.png` on the hub (or `scripts/card_images/<id>.png` to
/// have the seed script upload it). Nothing else needs editing.
enum CardType {
  redCard,
  yellowCard,
  hacienda,
  fiestero,
  robo,
  escudo,
  subExtra,
  pitchInvader,
  hatTrickHero,
  estreno,
  catenaccio,
  tikitaka,
  goldenGlove,
  elChiringuito, // leader↔last 25% redistribution (rebrand of "Normas FFP")
  retirada,
  tridente,
  francotirador,
  motivacion,
  muralla, // your DEF & GK x1.5
  prima, // one of your players x1.5
  vitamina, // your whole XI +15%
  // ── Funny batch ──
  piscinazo, // a rival player x0.5
  mordisco, // a rival player x0 (red-card twin)
  elVar, // a rival player x0.75
  laGradaPita, // a rival loses 15% of his day total
  cerrojazo, // your DEF & GK x2 AND the targeted one is shielded
  primoZumosol, // your DEF & GK x1.75
  manoDeDios, // one of your players x3 (unconditional)
  chilena, // your forwards x1.5
  siuuu, // one of your players x4 if he scores
  alcoyano, // one of your players x1.3
  jeque, // +1 signing card (FICHAJE EXTRA twin)
  // ── Casual flat-point batch (flatPoints) ──
  calderilla, // +5 to your day total
  propina, // +10
  plus, // +15
  pagaExtra, // +20
  soborno, // +25
  horasExtra, // +30
  loteria, // +50
  multa, // -10 to a rival's day total
  iva, // -15 to a rival
  recorte, // -20 to a rival
  embargo, // -30 to a rival
}

enum CardRarity { common, uncommon, rare, epic, legendary }

enum CardCategory { attack, defense, boost, utility }

/// The complete definition of one card type — the single source of truth.
class CardDef {
  final CardType type;

  /// Stable string id, also the image filename stem (`<id>.png`).
  final String id;
  final String name;
  final String description;
  final CardRarity rarity;
  final CardCategory category;

  /// Emblem shown when no hub image exists.
  final IconData icon;

  /// Compact value tag shown on the card face (e.g. "x3", "+30%").
  final String shortEffect;

  /// Relative draw weight (higher = more likely).
  final int weight;

  /// Max copies of THIS type allowed in one 5-card pack.
  final int maxPerPack;

  /// If set, at most ONE card from this group may appear in a pack. Used to cap
  /// "extra player" cards (steal + espontáneo) at one per day.
  final String? exclusiveGroup;

  /// Flat point swing (the "casual" cards): a positive number added to the
  /// owner's day total when [category] is boost (e.g. PROPINA +10), or
  /// subtracted from a targeted rival's day total when [category] is attack
  /// (e.g. MULTA -10). 0 for cards that use multiplier/other effects.
  final int flatPoints;

  const CardDef({
    required this.type,
    required this.id,
    required this.name,
    required this.description,
    required this.rarity,
    required this.category,
    required this.icon,
    required this.shortEffect,
    required this.weight,
    this.maxPerPack = 2,
    this.exclusiveGroup,
    this.flatPoints = 0,
  });

  String get imageFile => '$id.png';

  /// A casual flat-point card whose only effect is +/- a fixed point total.
  bool get isFlatPoints => flatPoints != 0;
}

/// Group id for the "extra player" cards (a stolen player or a random join):
/// at most one of these per pack.
const String kGroupExtraPlayer = 'extra_player';

/// THE catalog. One entry per card type — everything about a card lives here.
///
/// Rarity → typical draw weight: común ~18-24, uncommon ~10-14, rare ~6-8,
/// epic ~4, legendary ~2. Strong effects are deliberately rare; the casual
/// flat-point cards are the common backbone of a pack.
const Map<CardType, CardDef> kCardCatalog = {
  // ── Existing cards (re-tuned so strong effects are rarer) ──
  CardType.redCard: CardDef(
    type: CardType.redCard,
    id: 'red_card',
    name: 'TARJETA ROJA',
    description: 'UN JUGADOR RIVAL VALE 0 PTS HOY',
    rarity: CardRarity.rare,
    category: CardCategory.attack,
    icon: Icons.dangerous,
    shortEffect: '0 PTS',
    weight: 7,
    maxPerPack: 1,
  ),
  CardType.yellowCard: CardDef(
    type: CardType.yellowCard,
    id: 'yellow_card',
    name: 'TARJETA AMARILLA',
    description: 'UN JUGADOR RIVAL VALE 50% PTS HOY',
    rarity: CardRarity.uncommon,
    category: CardCategory.attack,
    icon: Icons.warning_amber_rounded,
    shortEffect: '50%',
    weight: 14,
    maxPerPack: 2,
  ),
  CardType.hacienda: CardDef(
    type: CardType.hacienda,
    id: 'hacienda',
    name: 'HACIENDA',
    description: 'RIVAL PIERDE 20% DE SUS PTS DEL DÍA',
    rarity: CardRarity.rare,
    category: CardCategory.attack,
    icon: Icons.account_balance,
    shortEffect: '-20%',
    weight: 8,
    maxPerPack: 1,
  ),
  CardType.fiestero: CardDef(
    type: CardType.fiestero,
    id: 'fiestero',
    name: 'FIESTERO',
    description: '+50% PTS DE UN JUGADOR RIVAL (SIN PENALIZARLE)',
    rarity: CardRarity.uncommon,
    category: CardCategory.boost,
    icon: Icons.celebration,
    shortEffect: '+50%',
    weight: 12,
    maxPerPack: 2,
  ),
  CardType.robo: CardDef(
    type: CardType.robo,
    id: 'robo',
    name: 'ROBO',
    description: 'ROBA LOS PTS REALES DE UN JUGADOR RIVAL',
    rarity: CardRarity.rare,
    category: CardCategory.attack,
    icon: Icons.front_hand,
    shortEffect: 'ROBO',
    weight: 7,
    maxPerPack: 1,
    exclusiveGroup: kGroupExtraPlayer,
  ),
  CardType.escudo: CardDef(
    type: CardType.escudo,
    id: 'escudo',
    name: 'ESCUDO',
    description: 'PROTEGE UN JUGADOR TUYO DE ATAQUES HOY',
    rarity: CardRarity.uncommon,
    category: CardCategory.defense,
    icon: Icons.shield,
    shortEffect: 'INMUNE',
    weight: 14,
    maxPerPack: 2,
  ),
  CardType.subExtra: CardDef(
    type: CardType.subExtra,
    id: 'sub_extra',
    name: 'FICHAJE EXTRA',
    description: 'GANA UN FICHAJE EXTRA ESTA JORNADA',
    rarity: CardRarity.common,
    category: CardCategory.utility,
    icon: Icons.sync_alt,
    shortEffect: '+1 FICHAJE',
    weight: 18,
    maxPerPack: 5, // you may receive several extra-transfer cards in a day
  ),
  CardType.pitchInvader: CardDef(
    type: CardType.pitchInvader,
    id: 'pitch_invader',
    name: 'ESPONTÁNEO',
    description: 'JUGADOR LIBRE SUMA SUS PTS A TU TOTAL',
    rarity: CardRarity.rare,
    category: CardCategory.attack,
    icon: Icons.directions_run,
    shortEffect: '+1 JUGADOR',
    weight: 7,
    maxPerPack: 1,
    exclusiveGroup: kGroupExtraPlayer,
  ),
  CardType.hatTrickHero: CardDef(
    type: CardType.hatTrickHero,
    id: 'hat_trick_hero',
    name: 'HAT TRICK HERO',
    description: 'UN JUGADOR TUYO x3 PTS SI MARCA HOY',
    rarity: CardRarity.uncommon,
    category: CardCategory.boost,
    icon: Icons.local_fire_department,
    shortEffect: 'x3 SI MARCA',
    weight: 12,
    maxPerPack: 2,
  ),
  CardType.estreno: CardDef(
    type: CardType.estreno,
    id: 'estreno',
    name: 'ESTRENO',
    description: 'PRIMER GOL = PTS EXTRA SEGÚN RONDA',
    rarity: CardRarity.rare,
    category: CardCategory.boost,
    icon: Icons.auto_awesome,
    shortEffect: 'BONUS',
    weight: 8,
    maxPerPack: 1,
  ),
  CardType.catenaccio: CardDef(
    type: CardType.catenaccio,
    id: 'catenaccio',
    name: 'CATENACCIO',
    description: 'TUS DEF Y POR x2 PTS HOY',
    rarity: CardRarity.rare,
    category: CardCategory.defense,
    icon: Icons.security,
    shortEffect: 'DEF x2',
    weight: 8,
    maxPerPack: 1,
  ),
  CardType.tikitaka: CardDef(
    type: CardType.tikitaka,
    id: 'tiki_taka',
    name: 'TIKI-TAKA',
    description: 'TUS MEDIOCAMPISTAS x2 PTS HOY',
    rarity: CardRarity.rare,
    category: CardCategory.boost,
    icon: Icons.hub,
    shortEffect: 'MED x2',
    weight: 8,
    maxPerPack: 1,
  ),
  CardType.goldenGlove: CardDef(
    type: CardType.goldenGlove,
    id: 'golden_glove',
    name: 'GUANTE DE ORO',
    description: 'TU PORTERO x3 PTS HOY',
    rarity: CardRarity.rare,
    category: CardCategory.defense,
    icon: Icons.sports_handball,
    shortEffect: 'POR x3',
    weight: 7,
    maxPerPack: 1,
  ),
  CardType.elChiringuito: CardDef(
    type: CardType.elChiringuito,
    id: 'el_chiringuito',
    name: 'EL CHIRINGUITO',
    description: 'EL LÍDER REGALA 25% AL COLISTA (Y AL REVÉS)',
    rarity: CardRarity.epic,
    category: CardCategory.attack,
    icon: Icons.record_voice_over,
    shortEffect: 'FFP',
    weight: 4,
    maxPerPack: 1,
  ),
  CardType.retirada: CardDef(
    type: CardType.retirada,
    id: 'retirada',
    name: 'RETIRADA',
    description: 'UN JUGADOR QUEDA RETIRADO PARA SIEMPRE',
    rarity: CardRarity.legendary,
    category: CardCategory.attack,
    icon: Icons.elderly,
    shortEffect: 'RETIRO',
    weight: 2,
    maxPerPack: 1,
  ),
  CardType.tridente: CardDef(
    type: CardType.tridente,
    id: 'tridente',
    name: 'TRIDENTE',
    description: 'TUS DELANTEROS x2 PTS HOY',
    rarity: CardRarity.rare,
    category: CardCategory.boost,
    icon: Icons.bolt,
    shortEffect: 'DEL x2',
    weight: 8,
    maxPerPack: 1,
  ),
  CardType.francotirador: CardDef(
    type: CardType.francotirador,
    id: 'francotirador',
    name: 'FRANCOTIRADOR',
    description: 'UN JUGADOR TUYO x2 PTS HOY',
    rarity: CardRarity.uncommon,
    category: CardCategory.boost,
    icon: Icons.my_location,
    shortEffect: 'x2',
    weight: 14,
    maxPerPack: 2,
  ),
  CardType.motivacion: CardDef(
    type: CardType.motivacion,
    id: 'motivacion',
    name: 'MOTIVACIÓN',
    description: 'TODO TU 11 +30% PTS HOY',
    rarity: CardRarity.epic,
    category: CardCategory.boost,
    icon: Icons.trending_up,
    shortEffect: '+30%',
    weight: 4,
    maxPerPack: 1,
  ),
  CardType.muralla: CardDef(
    type: CardType.muralla,
    id: 'muralla',
    name: 'MURALLA',
    description: 'TUS DEFENSAS Y PORTERO +50% PTS HOY',
    rarity: CardRarity.rare,
    category: CardCategory.defense,
    icon: Icons.fort,
    shortEffect: 'DEF +50%',
    weight: 8,
    maxPerPack: 1,
  ),
  CardType.prima: CardDef(
    type: CardType.prima,
    id: 'prima',
    name: 'PRIMA',
    description: '+50% PTS DE UN JUGADOR TUYO HOY',
    rarity: CardRarity.uncommon,
    category: CardCategory.boost,
    icon: Icons.savings,
    shortEffect: '+50%',
    weight: 14,
    maxPerPack: 2,
  ),
  CardType.vitamina: CardDef(
    type: CardType.vitamina,
    id: 'vitamina',
    name: 'VITAMINA',
    description: 'TODO TU 11 +15% PTS HOY',
    rarity: CardRarity.uncommon,
    category: CardCategory.boost,
    icon: Icons.medication,
    shortEffect: '+15%',
    weight: 10,
    maxPerPack: 1,
  ),

  // ── Funny batch ──
  CardType.piscinazo: CardDef(
    type: CardType.piscinazo,
    id: 'piscinazo',
    name: 'PISCINAZO',
    description: 'SE TIRA EN EL ÁREA: UN RIVAL RINDE AL 50%',
    rarity: CardRarity.uncommon,
    category: CardCategory.attack,
    icon: Icons.pool,
    shortEffect: '50%',
    weight: 14,
    maxPerPack: 2,
  ),
  CardType.mordisco: CardDef(
    type: CardType.mordisco,
    id: 'mordisco',
    name: 'MORDISCO',
    description: 'MUERDE A UN RIVAL, ROJA Y A CASA. VALE 0 PTS',
    rarity: CardRarity.rare,
    category: CardCategory.attack,
    icon: Icons.set_meal,
    shortEffect: '0 PTS',
    weight: 7,
    maxPerPack: 1,
  ),
  CardType.elVar: CardDef(
    type: CardType.elVar,
    id: 'el_var',
    name: 'EL VAR TE ODIA',
    description: 'GOL ANULADO POR UN SOBACO: UN RIVAL -25% HOY',
    rarity: CardRarity.uncommon,
    category: CardCategory.attack,
    icon: Icons.videocam,
    shortEffect: '-25%',
    weight: 12,
    maxPerPack: 2,
  ),
  CardType.laGradaPita: CardDef(
    type: CardType.laGradaPita,
    id: 'la_grada_pita',
    name: 'LA GRADA PITA',
    description: 'PITADA MONUMENTAL: UN RIVAL PIERDE 15% DE SUS PTS',
    rarity: CardRarity.uncommon,
    category: CardCategory.attack,
    icon: Icons.campaign,
    shortEffect: '-15%',
    weight: 12,
    maxPerPack: 2,
  ),
  CardType.cerrojazo: CardDef(
    type: CardType.cerrojazo,
    id: 'cerrojazo',
    name: 'CERROJAZO',
    description: 'AUTOBÚS APARCADO: TUS DEF Y POR x2, Y UNO BLINDADO',
    rarity: CardRarity.rare,
    category: CardCategory.defense,
    icon: Icons.directions_bus,
    shortEffect: 'DEF x2 🛡',
    weight: 6,
    maxPerPack: 1,
  ),
  CardType.primoZumosol: CardDef(
    type: CardType.primoZumosol,
    id: 'primo_zumosol',
    name: 'EL PRIMO DE ZUMOSOL',
    description: 'LLEGA EL PRIMO CACHAS: TUS DEF Y POR +75%',
    rarity: CardRarity.rare,
    category: CardCategory.defense,
    icon: Icons.fitness_center,
    shortEffect: 'DEF +75%',
    weight: 8,
    maxPerPack: 1,
  ),
  CardType.manoDeDios: CardDef(
    type: CardType.manoDeDios,
    id: 'mano_de_dios',
    name: 'MANO DE DIOS',
    description: 'GOL CON LA MANO QUE NADIE VE: UN JUGADOR x3',
    rarity: CardRarity.legendary,
    category: CardCategory.boost,
    icon: Icons.back_hand,
    shortEffect: 'x3',
    weight: 2,
    maxPerPack: 1,
  ),
  CardType.chilena: CardDef(
    type: CardType.chilena,
    id: 'chilena',
    name: 'CHILENA',
    description: 'ACROBACIA DE PORTADA: TUS DELANTEROS +50%',
    rarity: CardRarity.rare,
    category: CardCategory.boost,
    icon: Icons.sports_gymnastics,
    shortEffect: 'DEL +50%',
    weight: 8,
    maxPerPack: 1,
  ),
  CardType.siuuu: CardDef(
    type: CardType.siuuu,
    id: 'siuuu',
    name: 'SIUUUU',
    description: 'SALTO, GIRO Y ¡SIUUU! UN JUGADOR x4 SI MARCA',
    rarity: CardRarity.epic,
    category: CardCategory.boost,
    icon: Icons.rocket_launch,
    shortEffect: 'x4 SI MARCA',
    weight: 4,
    maxPerPack: 1,
  ),
  CardType.alcoyano: CardDef(
    type: CardType.alcoyano,
    id: 'alcoyano',
    name: 'ALCOYANO',
    description: 'MÁS MORAL QUE EL ALCOYANO: UN JUGADOR +30%',
    rarity: CardRarity.common,
    category: CardCategory.boost,
    icon: Icons.psychology,
    shortEffect: '+30%',
    weight: 20,
    maxPerPack: 2,
  ),
  CardType.jeque: CardDef(
    type: CardType.jeque,
    id: 'jeque',
    name: 'JEQUE PETROLERO',
    description: 'DINERO DEL GOLFO: GANAS UN FICHAJE EXTRA',
    rarity: CardRarity.uncommon,
    category: CardCategory.utility,
    icon: Icons.oil_barrel,
    shortEffect: '+1 FICHAJE',
    weight: 12,
    maxPerPack: 2,
  ),

  // ── Casual flat-point batch (the common backbone) ──
  CardType.calderilla: CardDef(
    type: CardType.calderilla,
    id: 'calderilla',
    name: 'CALDERILLA',
    description: 'MONEDAS DEL SOFÁ: +5 PTS A TU CUENTA',
    rarity: CardRarity.common,
    category: CardCategory.boost,
    icon: Icons.toll,
    shortEffect: '+5',
    weight: 24,
    maxPerPack: 2,
    flatPoints: 5,
  ),
  CardType.propina: CardDef(
    type: CardType.propina,
    id: 'propina',
    name: 'PROPINA',
    description: 'UNA PROPINA CAÍDA DEL CIELO: +10 PTS',
    rarity: CardRarity.common,
    category: CardCategory.boost,
    icon: Icons.volunteer_activism,
    shortEffect: '+10',
    weight: 22,
    maxPerPack: 2,
    flatPoints: 10,
  ),
  CardType.plus: CardDef(
    type: CardType.plus,
    id: 'plus',
    name: 'PLUS',
    description: 'PLUS DE PRODUCTIVIDAD: +15 PTS',
    rarity: CardRarity.common,
    category: CardCategory.boost,
    icon: Icons.add_circle,
    shortEffect: '+15',
    weight: 20,
    maxPerPack: 2,
    flatPoints: 15,
  ),
  CardType.pagaExtra: CardDef(
    type: CardType.pagaExtra,
    id: 'paga_extra',
    name: 'PAGA EXTRA',
    description: 'LA PAGA EXTRA DE JUNIO: +20 PTS',
    rarity: CardRarity.common,
    category: CardCategory.boost,
    icon: Icons.payments,
    shortEffect: '+20',
    weight: 18,
    maxPerPack: 2,
    flatPoints: 20,
  ),
  CardType.soborno: CardDef(
    type: CardType.soborno,
    id: 'soborno',
    name: 'SOBORNO',
    description: 'UN SOBRE BAJO LA MESA: +25 PTS (NO PREGUNTES)',
    rarity: CardRarity.uncommon,
    category: CardCategory.boost,
    icon: Icons.handshake,
    shortEffect: '+25',
    weight: 14,
    maxPerPack: 2,
    flatPoints: 25,
  ),
  CardType.horasExtra: CardDef(
    type: CardType.horasExtra,
    id: 'horas_extra',
    name: 'HORAS EXTRA',
    description: 'TE QUEDAS CURRANDO HASTA TARDE: +30 PTS',
    rarity: CardRarity.uncommon,
    category: CardCategory.boost,
    icon: Icons.more_time,
    shortEffect: '+30',
    weight: 12,
    maxPerPack: 2,
    flatPoints: 30,
  ),
  CardType.loteria: CardDef(
    type: CardType.loteria,
    id: 'loteria',
    name: 'LOTERÍA DEL NIÑO',
    description: '¡TE TOCA UN PELLIZCO! +50 PTS',
    rarity: CardRarity.rare,
    category: CardCategory.boost,
    icon: Icons.confirmation_number,
    shortEffect: '+50',
    weight: 8,
    maxPerPack: 1,
    flatPoints: 50,
  ),
  CardType.multa: CardDef(
    type: CardType.multa,
    id: 'multa',
    name: 'MULTA DE TRÁFICO',
    description: 'LE PILLA EL RADAR: -10 PTS A UN RIVAL',
    rarity: CardRarity.common,
    category: CardCategory.attack,
    icon: Icons.local_police,
    shortEffect: '-10',
    weight: 20,
    maxPerPack: 2,
    flatPoints: 10,
  ),
  CardType.iva: CardDef(
    type: CardType.iva,
    id: 'iva',
    name: 'IVA',
    description: 'HACIENDA SOMOS TODOS: -15 PTS A UN RIVAL',
    rarity: CardRarity.common,
    category: CardCategory.attack,
    icon: Icons.receipt_long,
    shortEffect: '-15',
    weight: 18,
    maxPerPack: 2,
    flatPoints: 15,
  ),
  CardType.recorte: CardDef(
    type: CardType.recorte,
    id: 'recorte',
    name: 'RECORTE',
    description: 'RECORTE PRESUPUESTARIO: -20 PTS A UN RIVAL',
    rarity: CardRarity.uncommon,
    category: CardCategory.attack,
    icon: Icons.content_cut,
    shortEffect: '-20',
    weight: 12,
    maxPerPack: 2,
    flatPoints: 20,
  ),
  CardType.embargo: CardDef(
    type: CardType.embargo,
    id: 'embargo',
    name: 'EMBARGO',
    description: 'LE EMBARGAN HASTA LAS BOTAS: -30 PTS A UN RIVAL',
    rarity: CardRarity.uncommon,
    category: CardCategory.attack,
    icon: Icons.lock,
    shortEffect: '-30',
    weight: 10,
    maxPerPack: 2,
    flatPoints: 30,
  ),
};

CardDef cardDef(CardType t) => kCardCatalog[t]!;

// ── Convenience maps derived from the catalog (kept for existing call sites) ──
final Map<CardType, String> kCardName = {
  for (final e in kCardCatalog.entries) e.key: e.value.name,
};
final Map<CardType, String> kCardDescription = {
  for (final e in kCardCatalog.entries) e.key: e.value.description,
};
final Map<CardType, CardRarity> kCardRarity = {
  for (final e in kCardCatalog.entries) e.key: e.value.rarity,
};
final Map<CardType, CardCategory> kCardCategory = {
  for (final e in kCardCatalog.entries) e.key: e.value.category,
};

final Map<CardType, String> _typeToString = {
  for (final e in kCardCatalog.entries) e.key: e.value.id,
};
final Map<String, CardType> _stringToType = {
  for (final e in kCardCatalog.entries) e.value.id: e.key,
};

const _rarityToString = <CardRarity, String>{
  CardRarity.common: 'common',
  CardRarity.uncommon: 'uncommon',
  CardRarity.rare: 'rare',
  CardRarity.epic: 'epic',
  CardRarity.legendary: 'legendary',
};

const _stringToRarity = <String, CardRarity>{
  'common': CardRarity.common,
  'uncommon': CardRarity.uncommon,
  'rare': CardRarity.rare,
  'epic': CardRarity.epic,
  'legendary': CardRarity.legendary,
};

/// Draws [count] card types for a pack, honoring each card's draw [weight],
/// [CardDef.maxPerPack], and [CardDef.exclusiveGroup] (e.g. at most one
/// "extra player" card — steal or espontáneo — per pack). Pure & seedable.
List<CardType> generatePackTypes(Random rng, {int count = 5}) {
  final entries = kCardCatalog.values.toList();
  final totalWeight = entries.fold<int>(0, (s, d) => s + d.weight);

  CardType weightedPick() {
    var r = rng.nextInt(totalWeight);
    for (final d in entries) {
      if (r < d.weight) return d.type;
      r -= d.weight;
    }
    return entries.last.type;
  }

  final pack = <CardType>[];
  final counts = <CardType, int>{};
  final usedGroups = <String>{};
  var guard = 0;
  while (pack.length < count && guard < 2000) {
    guard++;
    final t = weightedPick();
    final def = kCardCatalog[t]!;
    if ((counts[t] ?? 0) >= def.maxPerPack) continue;
    final group = def.exclusiveGroup;
    if (group != null && usedGroups.contains(group)) continue;
    pack.add(t);
    counts[t] = (counts[t] ?? 0) + 1;
    if (group != null) usedGroups.add(group);
  }
  return pack;
}

class PowerupCard {
  final CardType type;
  final CardRarity rarity;
  final CardCategory category;
  final String variant;
  final String? targetPlayer;
  final String? targetUser;
  final DateTime? playedAt;

  const PowerupCard({
    required this.type,
    required this.rarity,
    required this.category,
    required this.variant,
    this.targetPlayer,
    this.targetUser,
    this.playedAt,
  });

  /// Builds a fresh, unplayed card of [type] straight from the catalog.
  factory PowerupCard.ofType(CardType type, {String variant = 'default'}) {
    final def = kCardCatalog[type]!;
    return PowerupCard(
      type: type,
      rarity: def.rarity,
      category: def.category,
      variant: variant,
    );
  }

  bool get isPlayed => playedAt != null;

  CardDef get def => kCardCatalog[type]!;
  String get name => def.name;
  String get description => def.description;

  /// Stable string key for this card type (e.g. 'red_card'), used for the
  /// card-image filenames on the hub.
  String get typeId => def.id;

  factory PowerupCard.fromJson(Map<String, dynamic> j) {
    final typeStr = j['type'] as String? ?? 'sub_extra';
    final cardType = _stringToType[typeStr] ?? CardType.subExtra;
    return PowerupCard(
      type: cardType,
      rarity:
          _stringToRarity[j['rarity'] as String? ?? 'common'] ??
          CardRarity.common,
      category: kCardCategory[cardType]!,
      variant: j['variant'] as String? ?? 'default',
      targetPlayer: j['target_player'] as String?,
      targetUser: j['target_user'] as String?,
      playedAt: j['played_at'] != null
          ? DateTime.tryParse(j['played_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': _typeToString[type],
    'rarity': _rarityToString[rarity],
    'variant': variant,
    if (targetPlayer != null) 'target_player': targetPlayer,
    if (targetUser != null) 'target_user': targetUser,
    if (playedAt != null) 'played_at': playedAt!.toIso8601String(),
  };

  PowerupCard withPlay({String? targetPlayer, String? targetUser}) =>
      PowerupCard(
        type: type,
        rarity: rarity,
        category: category,
        variant: variant,
        targetPlayer: targetPlayer ?? this.targetPlayer,
        targetUser: targetUser ?? this.targetUser,
        playedAt: DateTime.now(),
      );
}
