import '../models/player.dart';
import '../models/powerup_card.dart';
import 'popularity.dart';

/// How a single player's expected-points percentage should be displayed,
/// given the boost/defense cards the owner has played today. See addendum
/// §G.1 (TAB DE EQUIPO).
class PointDisplayMods {
  /// Multiplier applied to the base popularity percentage.
  final double multiplier;

  /// Owner played Hat Trick Hero on this player — points are x3 if he scores,
  /// so the UI shows "x3" instead of a fixed percentage.
  final bool hatTrick;

  /// Owner played Escudo on this player — show a shield indicator.
  final bool shielded;

  /// A rival stole this player (visible after resolution) — show greyed 0%.
  final bool stolen;

  const PointDisplayMods({
    this.multiplier = 1.0,
    this.hatTrick = false,
    this.shielded = false,
    this.stolen = false,
  });

  bool get isIdentity => multiplier == 1.0 && !hatTrick && !shielded && !stolen;

  PointDisplayMods copyWith({double? multiplier, bool? stolen}) =>
      PointDisplayMods(
        multiplier: multiplier ?? this.multiplier,
        hatTrick: hatTrick,
        shielded: shielded,
        stolen: stolen ?? this.stolen,
      );
}

/// Computes per-player [PointDisplayMods] from the cards a user has played.
///
/// Position boosts are blanket — they apply to every owned player in that
/// position and stack multiplicatively, matching the in-game rules:
///   - Tiki-Taka    -> MID x2
///   - Catenaccio   -> DEF & GK x2
///   - Golden Glove -> GK x3   (stacks with Catenaccio -> x6)
/// Hat Trick Hero and Escudo target a specific player.
///
/// When [captainId] is given, the captain's percentage is also multiplied by
/// the flat captain multiplier ([kCaptainMultiplier]), so the captain bonus is
/// visible in the live XI before resolution.
///
/// [playersById] supplies positions; only players that end up with a
/// non-identity modifier get an entry, so an empty result means "no boosts".
Map<String, PointDisplayMods> pointDisplayMods({
  required Iterable<PowerupCard> cardsPlayed,
  required Map<String, Player> playersById,
  String? captainId,
}) {
  var midMul = 1.0;
  var defMul = 1.0;
  var gkMul = 1.0;
  var fwdMul = 1.0;
  var globalMul = 1.0; // Motivación / Vitamina: whole XI
  final hatTrick = <String>{};
  final shielded = <String>{};
  final playerMul = <String, double>{}; // per-player boosts (Francotirador/Prima)

  void boostPlayer(String? pid, double m) {
    if (pid == null) return;
    playerMul[pid] = (playerMul[pid] ?? 1.0) * m;
  }

  for (final c in cardsPlayed) {
    final t = c.type;
    if (t == CardType.tikitaka) {
      midMul *= 2.0;
    } else if (t == CardType.catenaccio) {
      defMul *= 2.0;
      gkMul *= 2.0;
    } else if (t == CardType.goldenGlove) {
      gkMul *= 3.0;
    } else if (t == CardType.tridente) {
      fwdMul *= 2.0;
    } else if (t == CardType.chilena) {
      fwdMul *= 1.5;
    } else if (t == CardType.muralla) {
      defMul *= 1.5;
      gkMul *= 1.5;
    } else if (t == CardType.primoZumosol) {
      defMul *= 1.75;
      gkMul *= 1.75;
    } else if (t == CardType.cerrojazo) {
      // DEF & GK x2 AND the targeted player is shielded from attacks.
      defMul *= 2.0;
      gkMul *= 2.0;
      if (c.targetPlayer != null) shielded.add(c.targetPlayer!);
    } else if (t == CardType.motivacion) {
      globalMul *= 1.3;
    } else if (t == CardType.vitamina) {
      globalMul *= 1.15;
    } else if ((t == CardType.hatTrickHero || t == CardType.siuuu) &&
        c.targetPlayer != null) {
      // Conditional on scoring — shown as a flag, applied at resolution.
      hatTrick.add(c.targetPlayer!);
    } else if (t == CardType.francotirador) {
      boostPlayer(c.targetPlayer, 2.0);
    } else if (t == CardType.prima) {
      boostPlayer(c.targetPlayer, 1.5);
    } else if (t == CardType.alcoyano) {
      boostPlayer(c.targetPlayer, 1.3);
    } else if (t == CardType.manoDeDios) {
      boostPlayer(c.targetPlayer, 3.0);
    } else if (t == CardType.escudo && c.targetPlayer != null) {
      shielded.add(c.targetPlayer!);
    }
  }

  double mulFor(String position) => switch (position) {
    'MID' => midMul,
    'DEF' => defMul,
    'GK' => gkMul,
    'FWD' => fwdMul,
    _ => 1.0,
  };

  final result = <String, PointDisplayMods>{};
  for (final entry in playersById.entries) {
    final mult =
        mulFor(entry.value.position) *
        globalMul *
        (playerMul[entry.key] ?? 1.0);
    final mods = PointDisplayMods(
      multiplier: mult,
      hatTrick: hatTrick.contains(entry.key),
      shielded: shielded.contains(entry.key),
    );
    if (!mods.isIdentity) result[entry.key] = mods;
  }

  if (captainId != null) {
    final cur = result[captainId] ?? const PointDisplayMods();
    result[captainId] = cur.copyWith(
      multiplier: cur.multiplier * kCaptainMultiplier,
    );
  }
  return result;
}

/// Folds player-level incoming attacks into [base]. These are only revealed
/// after resolution (everyone's plays become public), so call this only when
/// the resolution time has passed.
///
/// Red Card -> 0, Yellow Card -> x0.5, Robo -> 0 + stolen flag. A player the
/// owner protected with Escudo is immune. [allUsers] is the raw users map.
/// Mutates and returns [base].
Map<String, PointDisplayMods> foldIncomingAttacks(
  Map<String, PointDisplayMods> base, {
  required String viewer,
  required Map<String, dynamic> allUsers,
}) {
  for (final entry in allUsers.entries) {
    if (entry.key == viewer) continue;
    final active = (entry.value as Map)['active'];
    final played =
        (active is Map ? active['cards_played'] : null) as List? ?? [];
    for (final cp in played) {
      if (cp is! Map) continue;
      if (cp['target_user'] != viewer) continue;
      final pid = cp['target_player'] as String?;
      if (pid == null) continue;
      final cur = base[pid] ?? const PointDisplayMods();
      if (cur.shielded) continue; // Escudo immunity
      double mul;
      var stolen = cur.stolen;
      switch (cp['type'] as String?) {
        case 'red_card':
        case 'mordisco':
          mul = 0.0;
        case 'yellow_card':
        case 'piscinazo':
          mul = 0.5;
        case 'el_var':
          mul = 0.75;
        case 'robo':
          mul = 0.0;
          stolen = true;
        default:
          continue;
      }
      base[pid] = cur.copyWith(
        multiplier: mul < cur.multiplier ? mul : cur.multiplier,
        stolen: stolen,
      );
    }
  }
  return base;
}

/// Live flat-point swing for [viewer] from the casual ± point cards currently in
/// play: [self] = your own flat self-bonuses (PROPINA…LOTERÍA), [incoming] =
/// flat deductions a rival aimed at you (MULTA…EMBARGO). These act on the day
/// total (not a single player), so they're surfaced separately from the per-
/// player % mods. [ownCards] are the viewer's played cards; [allUsers] the raw
/// users map (for incoming attacks).
({double self, double incoming}) flatPointSwing({
  required String viewer,
  required Iterable<PowerupCard> ownCards,
  required Map<String, dynamic> allUsers,
}) {
  var self = 0.0;
  for (final c in ownCards) {
    final d = c.def;
    if (d.isFlatPoints && d.category == CardCategory.boost) self += d.flatPoints;
  }
  var incoming = 0.0;
  for (final entry in allUsers.entries) {
    if (entry.key == viewer) continue;
    final active = (entry.value as Map)['active'];
    final played =
        (active is Map ? active['cards_played'] : null) as List? ?? [];
    for (final cp in played) {
      if (cp is! Map) continue;
      if (cp['target_user'] != viewer) continue;
      final d = PowerupCard.fromJson(Map<String, dynamic>.from(cp)).def;
      if (d.isFlatPoints && d.category == CardCategory.attack) {
        incoming += d.flatPoints;
      }
    }
  }
  return (self: self, incoming: incoming);
}
