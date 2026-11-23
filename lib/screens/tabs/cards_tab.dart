import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/powerup_card.dart';
import '../../models/user_data.dart';
import '../card_collection_screen.dart';
import '../../providers/game_state_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_clock.dart';
import '../../utils/time_utils.dart';
import '../../widgets/async_states.dart';
import '../../widgets/pixel_button.dart';
import '../../widgets/pixel_card_widget.dart';
import '../../widgets/pixel_player_widget.dart';

/// Candidate players for the ESPONTÁNEO (pitch invader) card: a random player
/// who isn't already on your team. Prefers players featuring in today's matches;
/// if none are listed (e.g. a test day with no rosters yet) it falls back to the
/// whole player pool so the card always has someone to add.
Set<String> espontaneoCandidates({
  required Iterable<String> dailyMatchPlayerIds,
  required Iterable<String> allPlayerIds,
  required Set<String> owned,
}) {
  final fromMatches = dailyMatchPlayerIds.toSet()..removeAll(owned);
  if (fromMatches.isNotEmpty) return fromMatches;
  return allPlayerIds.toSet()..removeAll(owned);
}

class CardsTab extends ConsumerStatefulWidget {
  const CardsTab({super.key});

  @override
  ConsumerState<CardsTab> createState() => _CardsTabState();
}

class _CardsTabState extends ConsumerState<CardsTab>
    with TickerProviderStateMixin {
  late final AnimationController _packCtrl;
  late final Animation<double> _packAnim;
  bool _packOpened = false;
  bool _cardsVisible = false;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _packCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _packAnim = CurvedAnimation(parent: _packCtrl, curve: Curves.easeInOut);
    _packCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _cardsVisible = true);
      }
    });
  }

  @override
  void dispose() {
    _packCtrl.dispose();
    super.dispose();
  }

  // Pack generation (weights + per-card pack rules + exclusivity groups) lives
  // in the card catalog, so it's one place to tune.
  List<PowerupCard> _generateCards() => [
    for (final t in generatePackTypes(math.Random())) PowerupCard.ofType(t),
  ];

  Future<void> _drawAndSaveCards() async {
    setState(() => _generating = true);
    try {
      final user = ref.read(userProvider).value;
      if (user == null) return;
      final cards = _generateCards();
      await ref.read(userProvider.notifier).save(
        (cur) => cur.copyWith(
          active: ActiveState(
            captain: cur.active.captain,
            bets: cur.active.bets,
            cardsReceived: cards,
            cardsPlayed: cur.active.cardsPlayed,
            attacksReceivedToday: cur.active.attacksReceivedToday,
          ),
        ),
        'app: draw cards',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ERROR AL GUARDAR CARTAS — REINTENTA')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _openPack() {
    setState(() => _packOpened = true);
    _packCtrl.forward();
    _drawAndSaveCards();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProvider);
    ref.watch(clockProvider); // rebuild when the simulated time changes
    final now = appNow();
    final windowOpen = isCardsWindowOpen(now);
    final expired = isCardsExpired(now);
    final buffer = isPhaseBuffer(now);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        title: const Text(
          'CARTAS',
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 12,
            color: kAccentGreen,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: kBorder, height: 1),
        ),
      ),
      body: userAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(userProvider)),
        data: (user) {
          if (user == null) return const SizedBox();
          return _CardsContent(
            user: user,
            windowOpen: windowOpen,
            expired: expired,
            buffer: buffer,
            packOpened: _packOpened,
            cardsVisible: _cardsVisible,
            generating: _generating,
            packAnim: _packAnim,
            onOpenPack: _openPack,
          );
        },
      ),
    );
  }
}

// ── Main content ────────────────────────────────────────────────────────────

class _CardsContent extends ConsumerWidget {
  final UserData user;
  final bool windowOpen;
  final bool expired;
  final bool buffer;
  final bool packOpened;
  final bool cardsVisible;
  final bool generating;
  final Animation<double> packAnim;
  final VoidCallback onOpenPack;

  const _CardsContent({
    required this.user,
    required this.windowOpen,
    required this.expired,
    required this.buffer,
    required this.packOpened,
    required this.cardsVisible,
    required this.generating,
    required this.packAnim,
    required this.onOpenPack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = user.active.cardsReceived;
    final hasCards = cards.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(githubServiceProvider).clearCache();
        ref.read(userProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _WindowStatusBar(
            windowOpen: windowOpen,
            expired: expired,
            buffer: buffer,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CardCollectionScreen(),
                ),
              ),
              icon: const Icon(Icons.menu_book, size: 14, color: kAccentBlue),
              label: const Text(
                'COLECCIÓN',
                style: TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 12,
                  color: kAccentBlue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (!hasCards && !packOpened)
            _StickerPackSection(windowOpen: windowOpen, onOpenPack: onOpenPack)
          else if (packOpened && !cardsVisible)
            _StickerPackAnimation(animation: packAnim)
          else if (packOpened && cardsVisible && generating)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: CircularProgressIndicator(),
              ),
            )
          else if (!hasCards)
            _NoCardsMessage(windowOpen: windowOpen)
          else ...[
            const Text(
              'TUS CARTAS DE HOY',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 13,
                color: kAccentGreen,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${cards.where((c) => c.isPlayed).length}/${cards.length} JUGADAS',
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 6,
                color: kTextMuted,
              ),
            ),
            const SizedBox(height: 12),
            // 3 cards per row, sized to fill the width so there's no dead space
            // on the right.
            LayoutBuilder(
              builder: (ctx, constraints) {
                const cols = 3;
                const gap = 8.0;
                final cardW = (constraints.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: cards
                      .map(
                        (card) => PixelCardWidget(
                          card: card,
                          width: cardW,
                          onTap: () => _showExpandedCard(
                            context,
                            ref,
                            card,
                            user,
                            windowOpen && !card.isPlayed && !expired,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 20),
            const Divider(color: kBorder, height: 1),
            const SizedBox(height: 16),
            _PlayedCardsSummary(cards: user.active.cardsPlayed),
          ],
        ],
      ),
    );
  }

  static const _noTargetCards = {
    CardType.subExtra,
    CardType.catenaccio,
    CardType.tikitaka,
    CardType.estreno,
    CardType.goldenGlove,
    CardType.elChiringuito,
    CardType.pitchInvader,
    CardType.tridente,
    CardType.motivacion,
    CardType.muralla,
    CardType.vitamina,
    // Funny / casual no-target cards.
    CardType.chilena,
    CardType.primoZumosol,
    CardType.jeque,
    CardType.calderilla,
    CardType.propina,
    CardType.plus,
    CardType.pagaExtra,
    CardType.soborno,
    CardType.horasExtra,
    CardType.loteria,
  };
  static const _ownPlayerCards = {
    CardType.escudo,
    CardType.hatTrickHero,
    CardType.francotirador,
    CardType.prima,
    CardType.cerrojazo, // shields the chosen player (on top of DEF&GK x2)
    CardType.alcoyano,
    CardType.manoDeDios,
    CardType.siuuu,
  };
  // Cards that hit a whole rival (a user, not one of their players).
  static const _rivalUserOnlyCards = {
    CardType.hacienda,
    CardType.laGradaPita,
    CardType.multa,
    CardType.iva,
    CardType.recorte,
    CardType.embargo,
  };
  static const _attackOnCaptainBlocked = {
    CardType.redCard,
    CardType.yellowCard,
    CardType.robo,
    CardType.retirada,
    CardType.mordisco,
    CardType.piscinazo,
    CardType.elVar,
  };

  void _showExpandedCard(
    BuildContext context,
    WidgetRef ref,
    PowerupCard card,
    UserData user,
    bool canUse,
  ) {
    showDialog<void>(
      context: context,
      builder: (dctx) => ExpandedCardDialog(
        card: card,
        canUse: canUse,
        onUse: () {
          Navigator.of(dctx).pop();
          _showPlayDialog(context, ref, card, user);
        },
      ),
    );
  }

  void _showPlayDialog(
    BuildContext context,
    WidgetRef ref,
    PowerupCard card,
    UserData user,
  ) {
    // At most ONE extra player per matchday: a robo (steal) and an espontáneo
    // (random join) both add a player, so you can't play a second one.
    final isExtraPlayerCard =
        card.type == CardType.robo || card.type == CardType.pitchInvader;
    if (isExtraPlayerCard) {
      final alreadyHasExtra = user.active.cardsPlayed.any(
        (c) => c.type == CardType.robo || c.type == CardType.pitchInvader,
      );
      if (alreadyHasExtra) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'YA TIENES UN JUGADOR EXTRA HOY',
              style: TextStyle(fontFamily: 'ChakraPetch', fontSize: 11),
            ),
          ),
        );
        return;
      }
    }
    if (card.type == CardType.pitchInvader) {
      // Espontáneo: a random player who plays today (and isn't already yours)
      // joins your team. Picked here and stored as the card's target.
      final daily = ref.read(currentMatchdayProvider).value;
      final pool = espontaneoCandidates(
        dailyMatchPlayerIds: [
          for (final m in daily?.matches ?? const [])
            ...m.players.map((p) => p.id),
        ],
        allPlayerIds: (ref.read(playersProvider).value ?? const [])
            .map((p) => p.id),
        owned: user.allPlayers.toSet(),
      );
      if (pool.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'NO HAY JUGADORES DISPONIBLES HOY',
              style: TextStyle(fontFamily: 'ChakraPetch', fontSize: 11),
            ),
          ),
        );
        return;
      }
      final pick = (pool.toList()..shuffle()).first;
      _confirmPlay(context, ref, card, user, pick, null);
      return;
    }
    if (_noTargetCards.contains(card.type)) {
      _confirmPlay(context, ref, card, user, null, null);
    } else if (_ownPlayerCards.contains(card.type)) {
      _showOwnPlayerDialog(context, ref, card, user);
    } else if (_rivalUserOnlyCards.contains(card.type)) {
      _showUserOnlyDialog(context, ref, card, user);
    } else {
      _showUserThenPlayerDialog(context, ref, card, user);
    }
  }

  void _showOwnPlayerDialog(
    BuildContext context,
    WidgetRef ref,
    PowerupCard card,
    UserData user,
  ) {
    final players = ref.read(playersProvider).value ?? [];
    final playerMap = {for (final p in players) p.id: p};

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        children: [
          Text(
            '${kCardName[card.type]}: ELIGE TU JUGADOR',
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 12,
              color: kAccentGreen,
            ),
          ),
          const SizedBox(height: 12),
          if (user.allSquadPlayers.isEmpty)
            const Text(
              'SIN JUGADORES EN EL 11',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 11,
                color: kTextMuted,
              ),
            )
          else
            ...user.allSquadPlayers.map((pid) {
              final p = playerMap[pid];
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _confirmPlay(context, ref, card, user, pid, null);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  color: kSurface2,
                  child: Row(
                    children: [
                      if (p != null) ...[
                        PixelPlayerWidget(
                          skinId: p.skin,
                          size: 28,
                          team: p.team,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        p?.name ?? pid,
                        style: const TextStyle(
                          fontFamily: 'ChakraPetch',
                          fontSize: 11,
                          color: kTextPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showUserOnlyDialog(
    BuildContext context,
    WidgetRef ref,
    PowerupCard card,
    UserData user,
  ) {
    final allUsers = ref.read(allUsersProvider).value ?? {};
    final username = ref.read(usernameProvider) ?? '';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        children: [
          Text(
            '${kCardName[card.type]}: ELIGE RIVAL',
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 12,
              color: kAccentGreen,
            ),
          ),
          const SizedBox(height: 12),
          ...allUsers.keys
              .where((u) => u != username)
              .map(
                (u) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: PixelButton(
                    label: u.toUpperCase(),
                    color: kAccentRed,
                    onTap: () {
                      Navigator.pop(context);
                      _confirmPlay(context, ref, card, user, null, u);
                    },
                  ),
                ),
              ),
        ],
      ),
    );
  }

  void _showUserThenPlayerDialog(
    BuildContext context,
    WidgetRef ref,
    PowerupCard card,
    UserData user,
  ) {
    final allUsers = ref.read(allUsersProvider).value ?? {};
    final players = ref.read(playersProvider).value ?? [];
    final playerMap = {for (final p in players) p.id: p};
    final username = ref.read(usernameProvider) ?? '';
    final today = todayString();

    String? selectedUser;
    List<String> rivalPlayers = [];
    String? rivalCaptain;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setSheetState) {
          if (selectedUser == null) {
            return ListView(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              children: [
                Text(
                  '${kCardName[card.type]}: ELIGE RIVAL',
                  style: const TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 12,
                    color: kAccentGreen,
                  ),
                ),
                const SizedBox(height: 12),
                ...allUsers.keys
                    .where((u) => u != username)
                    .map(
                      (u) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: PixelButton(
                          label: u.toUpperCase(),
                          color: kAccentRed,
                          onTap: () {
                            final ud = allUsers[u] as Map<String, dynamic>?;
                            if (ud == null) return;
                            final rawSquad = ud['squad'] as Map? ?? {};
                            final pids = <String>[];
                            for (final pos in ['GK', 'DEF', 'MID', 'FWD']) {
                              final list = rawSquad[pos];
                              if (list is List) {
                                pids.addAll(list.map((e) => e.toString()));
                              }
                            }
                            final cpRaw =
                                ud['captain_picks'] as Map<String, dynamic>? ??
                                {};
                            setSheetState(() {
                              selectedUser = u;
                              rivalPlayers = pids;
                              rivalCaptain = cpRaw[today] as String?;
                            });
                          },
                        ),
                      ),
                    ),
              ],
            );
          }

          final blockCaptain = _attackOnCaptainBlocked.contains(card.type);
          return ListView(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => setSheetState(() {
                      selectedUser = null;
                      rivalPlayers = [];
                      rivalCaptain = null;
                    }),
                    child: const Icon(
                      Icons.arrow_back,
                      color: kTextMuted,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'JUGADOR DE ${selectedUser!.toUpperCase()}',
                      style: const TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 11,
                        color: kAccentGreen,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (rivalPlayers.isEmpty)
                const Text(
                  'SIN JUGADORES EN EL 11',
                  style: TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 11,
                    color: kTextMuted,
                  ),
                )
              else
                ...rivalPlayers.map((pid) {
                  final p = playerMap[pid];
                  final isCaptain = pid == rivalCaptain;
                  final blocked = blockCaptain && isCaptain;
                  return GestureDetector(
                    onTap: blocked
                        ? null
                        : () {
                            Navigator.pop(sheetCtx);
                            _confirmPlay(
                              context,
                              ref,
                              card,
                              user,
                              pid,
                              selectedUser,
                            );
                          },
                    child: Opacity(
                      opacity: blocked ? 0.4 : 1.0,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        color: kSurface2,
                        child: Row(
                          children: [
                            if (p != null) ...[
                              PixelPlayerWidget(
                                skinId: p.skin,
                                size: 28,
                                team: p.team,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                p?.name ?? pid,
                                style: TextStyle(
                                  fontFamily: 'ChakraPetch',
                                  fontSize: 11,
                                  color: blocked ? kTextMuted : kTextPrimary,
                                ),
                              ),
                            ),
                            if (isCaptain)
                              const Text(
                                '★',
                                style: TextStyle(
                                  fontFamily: 'ChakraPetch',
                                  fontSize: 12,
                                  color: kAccentYellow,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  void _confirmPlay(
    BuildContext context,
    WidgetRef ref,
    PowerupCard card,
    UserData user,
    String? targetPlayer,
    String? targetUser,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: kBorder, width: 1),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        title: Text(
          card.name,
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 13,
            color: kTextPrimary,
          ),
        ),
        content: () {
          final allPlayers = ref.read(playersProvider).value ?? [];
          String? playerName;
          if (targetPlayer != null) {
            for (final p in allPlayers) {
              if (p.id == targetPlayer) {
                playerName = p.name;
                break;
              }
            }
            playerName ??= targetPlayer;
          }
          return Text(
            '¿JUGAR ESTA CARTA?${targetUser != null ? '\nOBJETIVO: ${targetUser.toUpperCase()}' : ''}${playerName != null ? '\nJUGADOR: $playerName' : ''}',
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 11,
              color: kTextMuted,
              height: 1.3,
            ),
          );
        }(),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'CANCELAR',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 6,
                color: kTextMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _playCard(
                context,
                ref,
                card,
                user,
                targetPlayer,
                targetUser,
              );
            },
            child: const Text(
              'JUGAR',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 6,
                color: kAccentGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _playCard(
    BuildContext context,
    WidgetRef ref,
    PowerupCard card,
    UserData user,
    String? targetPlayer,
    String? targetUser,
  ) async {
    // Hard guard: cards can only be played during the cards window (13:00–17:00).
    if (!isCardsWindowOpen() || card.isPlayed) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'LAS CARTAS SOLO SE JUEGAN DE 13:00 A 17:00',
              style: TextStyle(fontFamily: 'ChakraPetch', fontSize: 11),
            ),
          ),
        );
      }
      return;
    }
    final played = card.withPlay(
      targetPlayer: targetPlayer,
      targetUser: targetUser,
    );
    // FICHAJE EXTRA / JEQUE PETROLERO grant one extra transfer (signing) today.
    final grantsTransfer =
        card.type == CardType.subExtra || card.type == CardType.jeque;
    try {
      await ref.read(userProvider.notifier).save((cur) {
        // Replace only the FIRST matching unplayed card on the fresh server
        // state — otherwise holding two of the same type would mark both
        // played while only one is recorded.
        final newReceived = <PowerupCard>[];
        var replaced = false;
        for (final c in cur.active.cardsReceived) {
          if (!replaced && c.type == card.type && !c.isPlayed) {
            newReceived.add(played);
            replaced = true;
          } else {
            newReceived.add(c);
          }
        }
        return cur.copyWith(
          active: ActiveState(
            captain: cur.active.captain,
            bets: cur.active.bets,
            cardsReceived: newReceived,
            cardsPlayed: [...cur.active.cardsPlayed, played],
            attacksReceivedToday: cur.active.attacksReceivedToday,
          ),
          signingCardsAvailable: grantsTransfer
              ? cur.signingCardsAvailable + 1
              : null,
        );
      }, 'app: play card ${card.type.name}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${card.name} JUGADA',
              style: const TextStyle(fontFamily: 'ChakraPetch', fontSize: 11),
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ERROR AL GUARDAR')));
      }
    }
  }
}

// ── Status bar ──────────────────────────────────────────────────────────────

class _WindowStatusBar extends StatelessWidget {
  final bool windowOpen;
  final bool expired;
  final bool buffer;
  const _WindowStatusBar({
    required this.windowOpen,
    required this.expired,
    this.buffer = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = buffer
        ? kAccentBlue
        : expired
        ? kAccentRed
        : windowOpen
        ? kAccentGreen
        : kAccentYellow;
    final label = buffer
        ? 'ACTUALIZANDO… (~5 MIN)'
        : expired
        ? 'VENTANA CERRADA'
        : windowOpen
        ? 'VENTANA ABIERTA: 13:00 – 17:00'
        : 'VENTANA ABRE A LAS 13:00';
    return Container(
      padding: const EdgeInsets.all(10),
      color: color.withValues(alpha: 0.15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(buffer ? Icons.sync : Icons.style, color: color, size: 14),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 6,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sticker pack section (sealed) ───────────────────────────────────────────

class _StickerPackSection extends StatelessWidget {
  final bool windowOpen;
  final VoidCallback onOpenPack;
  const _StickerPackSection({
    required this.windowOpen,
    required this.onOpenPack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        GestureDetector(
          onTap: windowOpen ? onOpenPack : null,
          child: Opacity(
            opacity: windowOpen ? 1.0 : 0.55,
            child: const CustomPaint(
              size: Size(110, 165),
              painter: _StickerPackPainter(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          windowOpen ? 'TOCA PARA ABRIR' : 'DISPONIBLE A LAS 13:00',
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 12,
            color: windowOpen ? kAccentGreen : kTextMuted,
          ),
        ),
        if (windowOpen) ...[
          const SizedBox(height: 8),
          const Text(
            '5 CARTAS DE PODER',
            style: TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 6,
              color: kTextMuted,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Sticker pack opening animation ──────────────────────────────────────────

class _StickerPackAnimation extends AnimatedWidget {
  const _StickerPackAnimation({required Animation<double> animation})
    : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Transform.translate(
          offset: Offset(0, -90 * t),
          child: Opacity(
            opacity: (1.0 - t * 0.7).clamp(0.0, 1.0),
            child: CustomPaint(
              size: const Size(110, 165),
              painter: _StickerPackPainter(openProgress: t),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sticker pack painter ─────────────────────────────────────────────────────

class _StickerPackPainter extends CustomPainter {
  final double openProgress;
  const _StickerPackPainter({this.openProgress = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Body background
    _fill(canvas, 0, 0, w, h, kSurface);

    // Header band (top 28%)
    final headerH = h * 0.28;
    _fill(canvas, 0, 0, w, headerH, kAccentBlue);

    // Footer band (bottom 20%)
    final footerH = h * 0.20;
    _fill(canvas, 0, h - footerH, w, footerH, kAccentGreen);

    // Band separator lines
    _fill(canvas, 0, headerH, w, 2, kAccentYellow);
    _fill(canvas, 0, h - footerH - 2, w, 2, kAccentYellow);

    // Stars in the middle
    final midY = headerH + (h - headerH - footerH) / 2;
    _star(canvas, w * 0.22, midY - 12, 5.0, kAccentYellow);
    _star(canvas, w * 0.50, midY - 12, 7.5, kAccentYellow);
    _star(canvas, w * 0.78, midY - 12, 5.0, kAccentYellow);

    // "5 CARTAS" label
    _fill(canvas, w * 0.12, midY + 4, w * 0.76, 20, kSurface2);
    _text(canvas, '5 CARTAS', Offset(w / 2, midY + 14), kAccentGreen, 6.0);

    // Header label
    _text(canvas, 'CARTAS', Offset(w / 2, headerH / 2), kAccentYellow, 7.0);

    // Footer label
    _text(
      canvas,
      'CALCETTO',
      Offset(w / 2, h - footerH / 2),
      kAccentYellow,
      5.5,
    );

    // Tear-open animation: slide the header up out of view
    if (openProgress > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, w, headerH + 2));
      final dy = -(headerH + 4) * openProgress * 1.4;
      _fill(canvas, 0, dy, w, headerH, kAccentBlue);
      _fill(canvas, 0, dy + headerH, w, 2, kAccentYellow);
      _text(
        canvas,
        'CARTAS',
        Offset(w / 2, dy + headerH / 2),
        kAccentYellow,
        7.0,
      );
      canvas.restore();
    } else {
      // Dashed tear line when sealed
      final tearY = headerH + 1;
      final dash = Paint()
        ..color = kAccentYellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (double x = 5; x < w - 5; x += 9) {
        canvas.drawLine(
          Offset(x, tearY),
          Offset(math.min(x + 5, w - 5), tearY),
          dash,
        );
      }
    }

    // Outer border
    canvas.drawRect(
      Rect.fromLTWH(1.5, 1.5, w - 3, h - 3),
      Paint()
        ..color = kAccentYellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _fill(Canvas canvas, double x, double y, double w, double h, Color c) {
    canvas.drawRect(
      Rect.fromLTWH(x, y, w, h),
      Paint()
        ..color = c
        ..style = PaintingStyle.fill,
    );
  }

  void _star(Canvas canvas, double cx, double cy, double r, Color c) {
    final p = Path()
      ..moveTo(cx, cy - r)
      ..lineTo(cx + r * 0.38, cy - r * 0.38)
      ..lineTo(cx + r, cy)
      ..lineTo(cx + r * 0.38, cy + r * 0.38)
      ..lineTo(cx, cy + r)
      ..lineTo(cx - r * 0.38, cy + r * 0.38)
      ..lineTo(cx - r, cy)
      ..lineTo(cx - r * 0.38, cy - r * 0.38)
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..color = c
        ..style = PaintingStyle.fill,
    );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    double size,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: 'ChakraPetch',
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_StickerPackPainter old) =>
      old.openProgress != openProgress;
}

// ── Empty states ────────────────────────────────────────────────────────────

class _NoCardsMessage extends StatelessWidget {
  final bool windowOpen;
  const _NoCardsMessage({required this.windowOpen});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      children: [
        const SizedBox(height: 32),
        const Icon(Icons.inbox, color: kTextMuted, size: 48),
        const SizedBox(height: 12),
        Text(
          windowOpen ? 'SIN CARTAS HOY' : 'CARTAS DISPONIBLES A LAS 13:00',
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 12,
            color: kTextMuted,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

// ── Played cards summary ────────────────────────────────────────────────────

class _PlayedCardsSummary extends StatelessWidget {
  final List<PowerupCard> cards;
  const _PlayedCardsSummary({required this.cards});

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CARTAS JUGADAS HOY',
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 12,
            color: kTextMuted,
          ),
        ),
        const SizedBox(height: 8),
        ...cards.map(
          (c) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: kSurface,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    c.name,
                    style: const TextStyle(
                      fontFamily: 'ChakraPetch',
                      fontSize: 6,
                      color: kTextMuted,
                    ),
                  ),
                ),
                if (c.targetUser != null)
                  Text(
                    '→ ${c.targetUser!.toUpperCase()}',
                    style: const TextStyle(
                      fontFamily: 'ChakraPetch',
                      fontSize: 5,
                      color: kAccentRed,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
