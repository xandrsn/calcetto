import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/player.dart';
import '../../models/powerup_card.dart';
import '../../models/user_data.dart';
import '../../providers/game_state_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_clock.dart';
import '../../utils/card_effects.dart';
import '../../utils/lineup.dart';
import '../../widgets/async_states.dart';
import '../../utils/popularity.dart';
import '../../utils/time_utils.dart';
import '../../widgets/pitch_widget.dart';
import '../../widgets/pixel_button.dart';
import '../../widgets/pixel_player_widget.dart';
import '../../widgets/player_avatar.dart';
import '../../widgets/player_card.dart';
import '../../widgets/player_image_upload_button.dart';
import '../../widgets/player_stats_section.dart';
import '../squad_draft_screen.dart';

// ── Position-map helpers ───────────────────────────────────────────────────

Map<String, List<String>> _replaceInMap(
  Map<String, List<String>> src,
  String oldId,
  String newId,
) {
  final out = {for (final e in src.entries) e.key: List<String>.from(e.value)};
  for (final pos in kPositions) {
    final idx = out[pos]?.indexOf(oldId) ?? -1;
    if (idx >= 0) {
      out[pos]![idx] = newId;
      return out;
    }
  }
  return out;
}

Map<String, int> _parseFormation(String f) {
  final p = f.split('-').map(int.parse).toList();
  return {'GK': 1, 'DEF': p[0], 'MID': p[1], 'FWD': p[2]};
}

/// The captain must always be a starter. If [newSquad] no longer contains [u]'s
/// current pick (subbed off, dropped by a formation change, or replaced), clear
/// today's captain so a benched/removed player can never stay captain. Returns
/// null when nothing changes. Computed against [u] — pass the fresh server state
/// from inside a save transform.
Map<String, String?>? _captainPicksClearedIfBenched(
  UserData u,
  Map<String, List<String>> newSquad,
) {
  final today = todayString();
  final cap = u.captainPicks[today];
  if (cap == null) return null;
  final starters = newSquad.values.expand((e) => e).toSet();
  if (starters.contains(cap)) return null;
  return {...u.captainPicks, today: null};
}

(Map<String, List<String>>, Map<String, List<String>>) _autoAssign(
  UserData user,
  List<Player> players,
  String newFormation,
) {
  final counts = _parseFormation(newFormation);
  final playerMap = {for (final p in players) p.id: p};
  final newSquad = <String, List<String>>{};
  final newBench = <String, List<String>>{};
  for (final pos in kPositions) {
    final all = <String>[
      ...(user.squad[pos] ?? []),
      ...(user.bench[pos] ?? []),
    ];
    all.sort((a, b) {
      final pa = playerMap[a]?.basePopularityPct ?? 0.0;
      final pb = playerMap[b]?.basePopularityPct ?? 0.0;
      return pb.compareTo(pa);
    });
    final n = counts[pos] ?? 0;
    newSquad[pos] = all.take(n).toList();
    newBench[pos] = all.skip(n).toList();
  }
  return (newSquad, newBench);
}

// ── SquadTab ───────────────────────────────────────────────────────────────

class SquadTab extends ConsumerWidget {
  const SquadTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);
    final playersAsync = ref.watch(playersProvider);

    return userAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.invalidate(userProvider)),
      data: (user) {
        if (user == null) return const SizedBox();
        if (user.allSquadPlayers.isEmpty) return const _DraftPrompt();
        return playersAsync.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(playersProvider),
          ),
          data: (players) => _SquadBody(user: user, players: players),
        );
      },
    );
  }
}

class _DraftPrompt extends ConsumerWidget {
  const _DraftPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'SIN PLANTILLA',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 12,
                color: kTextPrimary,
              ),
            ),
            const SizedBox(height: 24),
            PixelButton(
              label: 'ARMAR PLANTILLA',
              color: kAccentGreen,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SquadDraftScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SquadBody extends ConsumerWidget {
  final UserData user;
  final List<Player> players;

  const _SquadBody({required this.user, required this.players});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // allUsers (ownership %, rival plays) and the simulated clock are kept fresh
    // for every tab by the central poller in HomeScreen.
    ref.watch(clockProvider); // rebuild when the simulated time changes
    final popMap = ref.watch(popularityMapProvider).value ?? {};
    final allUsers = ref.watch(allUsersProvider).value;
    final daily = ref.watch(currentMatchdayProvider).value;
    final totalUsers = (allUsers?.length ?? 1).clamp(1, 999);
    // ONE lineup view, adaptive to the phase: editable + ownership % in prep,
    // live matchday % (+ incoming attacks at games + flat-points banner) when
    // locked. No more JORNADA/PLANTILLA tabs.
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: _PlantillaView(
          user: user,
          players: players,
          daily: daily,
          popMap: popMap,
          totalUsers: totalUsers,
          allUsers: allUsers,
        ),
      ),
    );
  }
}

/// Live readout of the casual ± point cards in play this window: your own
/// bonuses (PROPINA…LOTERÍA) and incoming deductions (MULTA…EMBARGO).
class _FlatPointsBanner extends StatelessWidget {
  final double self;
  final double incoming;
  const _FlatPointsBanner({required this.self, required this.incoming});

  @override
  Widget build(BuildContext context) {
    final net = self - incoming;
    final netColor = net >= 0 ? kAccentGreen : kAccentRed;
    return Container(
      width: double.infinity,
      color: kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.toll, size: 12, color: kAccentYellow),
          const SizedBox(width: 6),
          const Text(
            'CARTAS DE PUNTOS:',
            style: TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 11,
              color: kTextMuted,
            ),
          ),
          const SizedBox(width: 6),
          if (self != 0) ...[
            Text(
              '+${self.toStringAsFixed(0)}',
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 12,
                color: kAccentGreen,
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (incoming != 0) ...[
            Text(
              '-${incoming.toStringAsFixed(0)}',
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 12,
                color: kAccentRed,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            '(${net >= 0 ? '+' : ''}${net.toStringAsFixed(0)})',
            style: TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 12,
              color: netColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// (The old read-only JORNADA tab was merged into the single phase-adaptive
// _PlantillaView below; _StatOnlySheet is reused there for locked-phase taps.)

class _StatOnlySheet extends StatelessWidget {
  final Player player;
  const _StatOnlySheet({required this.player});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlayerTradingCard(player: player),
          const SizedBox(height: 12),
          PlayerImageUploadButton(player: player),
          const Divider(color: kBorder, height: 20),
          _row('PUNTOS', player.totalPoints.toStringAsFixed(1)),
          _row('GOLES', player.goals.toString()),
          _row('ASISTENCIAS', player.assists.toString()),
          PlayerSeasonSection(player: player),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 11,
              color: kTextMuted,
            ),
          ),
        ),
        Text(
          v,
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 11,
            color: kTextPrimary,
          ),
        ),
      ],
    ),
  );
}

// ── PLANTILLA tab ──────────────────────────────────────────────────────────

class _PlantillaView extends ConsumerStatefulWidget {
  final UserData user;
  final List<Player> players;
  final dynamic daily;
  final Map<String, int> popMap;
  final int totalUsers;
  final Map<String, dynamic>? allUsers;

  const _PlantillaView({
    required this.user,
    required this.players,
    this.daily,
    required this.popMap,
    required this.totalUsers,
    this.allUsers,
  });

  @override
  ConsumerState<_PlantillaView> createState() => _PlantillaViewState();
}

class _PlantillaViewState extends ConsumerState<_PlantillaView> {
  late String _pendingFormation;
  bool _saving = false;
  String? _selectedBenchId;

  @override
  void initState() {
    super.initState();
    _pendingFormation = widget.user.formation;
  }

  Future<void> _saveFormation() async {
    setState(() => _saving = true);
    final formation = _pendingFormation;
    final players = widget.players;
    try {
      await ref
          .read(userProvider.notifier)
          .save((cur) {
            final (newSquad, newBench) = _autoAssign(cur, players, formation);
            return cur.copyWith(
              formation: formation,
              squad: newSquad,
              bench: newBench,
              captainPicks: _captainPicksClearedIfBenched(cur, newSquad),
            );
          }, 'app: formation change');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('NO SE PUDO GUARDAR')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _trySubFromPitch(Player p) {
    if (_selectedBenchId == null) {
      _showManageSheet(context, p.id, p, isTeamLocked(appNow()));
      return;
    }
    final starterPos = positionOfPlayer(widget.user.squad, p.id);
    final benchPos = positionOfPlayer(widget.user.bench, _selectedBenchId!);
    if (starterPos == null || benchPos == null || starterPos != benchPos) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('POSICIÓN INCOMPATIBLE')));
      setState(() => _selectedBenchId = null);
      return;
    }
    final bid = _selectedBenchId!;
    _makeSub(p.id, bid, starterPos);
  }

  Future<void> _makeSub(String starterId, String benchId, String pos) async {
    setState(() {
      _saving = true;
      _selectedBenchId = null;
    });
    // Best-effort UX: predict whether this sub benches the captain, for the
    // snackbar. The authoritative change is applied against fresh state below.
    final wouldClearCaptain = () {
      final cap = widget.user.captainPicks[todayString()];
      return cap != null && cap == starterId;
    }();
    try {
      await ref
          .read(userProvider.notifier)
          .save((cur) {
            final sq = List<String>.from(cur.squad[pos] ?? []);
            final bk = List<String>.from(cur.bench[pos] ?? []);
            final si = sq.indexOf(starterId);
            final bi = bk.indexOf(benchId);
            if (si < 0 || bi < 0) return cur; // no-op if state moved on
            sq[si] = benchId;
            bk[bi] = starterId;
            final newSquad = {...cur.squad, pos: sq};
            final newBench = {...cur.bench, pos: bk};
            return cur.copyWith(
              squad: newSquad,
              bench: newBench,
              captainPicks: _captainPicksClearedIfBenched(cur, newSquad),
            );
          }, 'app: substitution');
      if (wouldClearCaptain && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('EL CAPITÁN SALIÓ DEL 11 — ELIGE OTRO')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('NO SE PUDO GUARDAR')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  String? get _captainId => widget.user.captainFor(
    today: todayString(),
    matchdayDate: widget.daily?.date as String?,
  );

  bool _canSwap(String a, String b) =>
      canSwapPlayers(widget.user.squad, widget.user.bench, a, b);

  void _performSwap(String a, String b) {
    if (_saving || !_canSwap(a, b)) return;
    final starter = playerInMap(widget.user.squad, a) ? a : b;
    final bench = starter == a ? b : a;
    final pos = positionOfPlayer(widget.user.squad, starter)!;
    _makeSub(starter, bench, pos);
  }

  @override
  Widget build(BuildContext context) {
    final now = appNow();
    final teamLocked = isTeamLocked(now);
    final buffer = isPhaseBuffer(now);
    final phase = dayPhase(now);
    // Phase-adaptive single view: in prep you edit (ownership %); once the
    // matchday is live (cards/games) the pitch shows the live matchday % (with
    // card effects + the flat-points banner) and editing is off.
    final showMatchday = widget.daily != null && phase != DayPhase.manage;
    final atMatches = phase == DayPhase.games;

    Map<String, PointDisplayMods>? pointMods;
    var swing = (self: 0.0, incoming: 0.0);
    final extras = <(Player, String)>[];
    if (showMatchday) {
      var mods = pointDisplayMods(
        cardsPlayed: widget.user.active.cardsPlayed,
        playersById: {for (final p in widget.players) p.id: p},
      );
      final users = widget.allUsers;
      // Own flat +points visible immediately; rival attacks/deductions only at
      // matches (so a seen attack can't be pre-shielded).
      swing = flatPointSwing(
        viewer: widget.user.name,
        ownCards: widget.user.active.cardsPlayed,
        allUsers: atMatches && users != null ? users : const {},
      );
      if (users != null && atMatches) {
        mods = foldIncomingAttacks(
          mods,
          viewer: widget.user.name,
          allUsers: users,
        );
      }
      pointMods = mods;
      // Extra players from cards (robo/espontáneo) — shown in the top-right.
      final byId = {for (final p in widget.players) p.id: p};
      for (final c in widget.user.active.cardsPlayed) {
        final pid = c.targetPlayer;
        if (pid == null) continue;
        final label = c.type == CardType.robo
            ? 'ROBADO'
            : c.type == CardType.pitchInvader
            ? 'AÑADIDO'
            : null;
        if (label == null) continue;
        final p = byId[pid];
        if (p != null) extras.add((p, label));
      }
    }

    return Column(
      children: [
        // Formation can only change while you can still edit (prep window).
        if (!teamLocked)
          _FormationPicker(
            current: _pendingFormation,
            onChange: (f) {
              if (_saving) return;
              setState(() => _pendingFormation = f);
              _saveFormation();
            },
          ),
        if (_saving)
          const LinearProgressIndicator(color: kAccentGreen, minHeight: 3),
        if (buffer)
          const _BufferBanner()
        else if (teamLocked)
          _LockBanner(signingCards: widget.user.signingCardsAvailable),
        if (showMatchday && (swing.self != 0 || swing.incoming != 0))
          _FlatPointsBanner(self: swing.self, incoming: swing.incoming),
        if (_selectedBenchId != null && !teamLocked)
          _SubHintBar(onCancel: () => setState(() => _selectedBenchId = null)),
        Expanded(
          child: Stack(
            children: [
              PitchWidget(
                user: widget.user,
                players: widget.players,
                todayCaptain: _captainId,
                // Ownership % while building; live matchday % once locked.
                popMap: showMatchday ? null : widget.popMap,
                pointMods: showMatchday ? pointMods : null,
                flatPercent: showMatchday,
                totalUsers: widget.totalUsers,
                onPlayerTap: showMatchday ? _showStatSheet : _trySubFromPitch,
                enableDrag: !_saving && !teamLocked,
                canAcceptDrag: teamLocked ? null : _canSwap,
                onAcceptDrag: teamLocked ? null : _performSwap,
              ),
              if (extras.isNotEmpty)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Column(
                    children: [
                      for (final e in extras)
                        _ExtraPlayerSquare(player: e.$1, label: e.$2),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _BenchStrip(
          user: widget.user,
          players: widget.players,
          selectedBenchId: _selectedBenchId,
          saving: _saving,
          captain: _captainId,
          canAcceptDrag: teamLocked ? null : _canSwap,
          onAcceptDrag: teamLocked ? null : _performSwap,
          onSelect: (pid) {
            final p = widget.players.where((x) => x.id == pid).firstOrNull;
            if (showMatchday) {
              if (p != null) _showStatSheet(p);
            } else {
              _showManageSheet(context, pid, p, isTeamLocked(appNow()));
            }
          },
        ),
      ],
    );
  }

  void _showStatSheet(Player p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      builder: (_) => _StatOnlySheet(player: p),
    );
  }

  void _showManageSheet(
    BuildContext context,
    String pid,
    Player? player,
    bool teamLocked,
  ) {
    if (player == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      builder: (_) => _PlayerBottomSheet(
        player: player,
        user: widget.user,
        popMap: widget.popMap,
        totalUsers: widget.totalUsers,
        daily: widget.daily,
        teamLocked: teamLocked,
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────

class _FormationPicker extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChange;

  const _FormationPicker({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) {
    const options = [
      '4-3-3',
      '4-4-2',
      '4-2-4',
      '3-5-2',
      '3-4-3',
      '5-3-2',
      '5-4-1',
      '4-5-1',
      '3-3-4',
    ];
    return Container(
      color: kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: options
              .map(
                (f) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: PixelButton(
                    label: f,
                    selected: f == current,
                    onTap: () => onChange(f),
                    fontSize: 11,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

/// Bench display + interaction surface. Read-only when no drag callbacks are
/// supplied (HOY tab); interactive (tap-to-select + drag-and-drop swaps) in the
/// PLANTILLA editor. Players render as cards in a wrapping grid so the strip
/// never overflows on narrow windows.
class _BenchStrip extends StatelessWidget {
  final UserData user;
  final List<Player> players;
  final String? captain;
  final String? selectedBenchId;
  final bool saving;
  final void Function(String pid)? onSelect;
  final bool Function(String dragged, String target)? canAcceptDrag;
  final void Function(String dragged, String target)? onAcceptDrag;

  const _BenchStrip({
    required this.user,
    required this.players,
    this.captain,
    this.selectedBenchId,
    this.saving = false,
    this.onSelect,
    this.canAcceptDrag,
    this.onAcceptDrag,
  });

  bool get _interactive => onAcceptDrag != null;

  @override
  Widget build(BuildContext context) {
    final playerMap = {for (final p in players) p.id: p};
    final benchIds = user.allBenchPlayers;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kBorder, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.event_seat, size: 12, color: kTextMuted),
              const SizedBox(width: 6),
              const Text(
                'BANQUILLO',
                style: TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 11,
                  color: kTextMuted,
                ),
              ),
              const Spacer(),
              if (_interactive)
                const Text(
                  'ARRASTRA PARA CAMBIAR',
                  style: TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 5,
                    color: kTextDim,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (benchIds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'SIN SUPLENTES',
                style: TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 11,
                  color: kTextMuted,
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pid in benchIds) _slot(pid, playerMap[pid]),
              ],
            ),
        ],
      ),
    );
  }

  Widget _slot(String pid, Player? p) {
    final card = _BenchCard(
      player: p,
      pid: pid,
      isCaptain: pid == captain,
      isSelected: pid == selectedBenchId,
      onTap: (_interactive && !saving && onSelect != null)
          ? () => onSelect!(pid)
          : null,
    );

    if (!_interactive) return card;

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          d.data != pid && (canAcceptDrag?.call(d.data, pid) ?? false),
      onAcceptWithDetails: (d) => onAcceptDrag?.call(d.data, pid),
      builder: (ctx, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        final content = (p == null || saving)
            ? card
            : Draggable<String>(
                data: pid,
                feedback: PixelPlayerWidget(
                  skinId: p.skin,
                  size: 48,
                  team: p.team,
                  isCaptain: pid == captain,
                ),
                childWhenDragging: Opacity(opacity: 0.25, child: card),
                child: card,
              );
        return AnimatedScale(
          scale: hovering ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: hovering
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: kAccentGreen, width: 2),
                  ),
                  child: content,
                )
              : content,
        );
      },
    );
  }
}

class _BenchCard extends StatelessWidget {
  final Player? player;
  final String pid;
  final bool isCaptain;
  final bool isSelected;
  final VoidCallback? onTap;

  const _BenchCard({
    required this.player,
    required this.pid,
    required this.isCaptain,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = player;
    final retired = p?.retired ?? false;
    final name = p == null ? pid : p.name.split(' ').last.toUpperCase();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: kSurface2,
          border: Border.all(
            color: isSelected
                ? kAccentGreen
                : kAccentBlue.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: retired ? 0.35 : 1.0,
                    child: p != null
                        ? PlayerAvatar(
                            player: p,
                            size: 38,
                            isCaptain: isCaptain,
                          )
                        : const Icon(
                            Icons.help_outline,
                            color: kTextMuted,
                            size: 38,
                          ),
                  ),
                  if (p != null)
                    Positioned(
                      top: -2,
                      left: -2,
                      child: _PosChip(position: p.position),
                    ),
                  if (retired)
                    const Positioned(
                      bottom: -2,
                      child: _StatusTag(label: 'RET', color: kAccentRed),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 5,
                color: isSelected ? kAccentGreen : kTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosChip extends StatelessWidget {
  final String position;
  const _PosChip({required this.position});

  @override
  Widget build(BuildContext context) {
    const colors = {
      'GK': kAccentYellow,
      'DEF': kAccentBlue,
      'MID': kAccentGreen,
      'FWD': kAccentRed,
    };
    final color = colors[position] ?? kTextMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      color: color,
      child: Text(
        position,
        style: const TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: 4,
          color: Colors.black,
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      color: color,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: 4,
          color: Colors.black,
        ),
      ),
    );
  }
}

// ── Player bottom sheet ────────────────────────────────────────────────────

class _PlayerBottomSheet extends ConsumerStatefulWidget {
  final Player player;
  final UserData user;
  final Map<String, int> popMap;
  final int totalUsers;
  final dynamic daily;
  final bool teamLocked;

  const _PlayerBottomSheet({
    required this.player,
    required this.user,
    required this.popMap,
    required this.totalUsers,
    this.daily,
    required this.teamLocked,
  });

  @override
  ConsumerState<_PlayerBottomSheet> createState() => _PlayerBottomSheetState();
}

class _PlayerBottomSheetState extends ConsumerState<_PlayerBottomSheet> {
  bool _saving = false;
  bool _showReplace = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _isOnBench => playerInMap(widget.user.bench, widget.player.id);
  bool get _isCaptain =>
      widget.user.captainPicks[todayString()] == widget.player.id;
  bool get _captainLocked => widget.daily != null && isCaptainLocked();

  Future<void> _setCaptain() async {
    setState(() => _saving = true);
    final today = todayString();
    final pid = widget.player.id;
    try {
      await ref.read(userProvider.notifier).save((cur) {
        final newPicks = Map<String, String?>.from(cur.captainPicks);
        // Toggle against the fresh server pick so it stays consistent.
        newPicks[today] = cur.captainPicks[today] == pid ? null : pid;
        return cur.copyWith(captainPicks: newPicks);
      }, 'app: set captain');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ERROR: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _replace(
    Player newPlayer, {
    bool withSigningCard = false,
  }) async {
    setState(() => _saving = true);
    final oldId = widget.player.id;
    final newId = newPlayer.id;
    try {
      await ref
          .read(userProvider.notifier)
          .save((cur) {
            var newSquad = cur.squad;
            var newBench = cur.bench;
            if (playerInMap(newSquad, oldId)) {
              newSquad = _replaceInMap(newSquad, oldId, newId);
            } else {
              newBench = _replaceInMap(newBench, oldId, newId);
            }
            // Replacing the captain (or otherwise removing them from the XI)
            // clears today's captain pick so it never dangles on a player who
            // is no longer in the team.
            var updated = cur.copyWith(
              squad: newSquad,
              bench: newBench,
              captainPicks: _captainPicksClearedIfBenched(cur, newSquad),
            );
            if (withSigningCard) {
              updated = updated.copyWith(
                signingCardsAvailable: cur.signingCardsAvailable - 1,
                signingCardsUsed: [...cur.signingCardsUsed, oldId],
              );
            }
            return updated;
          }, withSigningCard ? 'app: signing card' : 'app: replace player');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ERROR: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pop = calculatePopularityPercent(
      widget.popMap[widget.player.id] ?? 1,
      widget.totalUsers,
    );
    final allPlayers = ref.watch(playersProvider).value ?? [];
    final taken = widget.user.allPlayers.toSet()..remove(widget.player.id);
    // Replacements are free & unlimited before the season; once it starts they
    // cost a signing card and are only doable in Mi Plantilla (manage phase),
    // same position.
    final preSeason = isPreSeason();
    final canEdit = !isTeamLocked();
    final canReplace = preSeason;
    final canSign =
        !preSeason && canEdit && widget.user.signingCardsAvailable > 0;

    List<Player> replacements = allPlayers
        .where((p) {
          if (taken.contains(p.id)) return false;
          // A replacement must always be the SAME position — you can't field a
          // forward in goal. (This holds for free pre-season swaps and
          // signing-card replacements alike.)
          return p.position == widget.player.position;
        })
        .where((p) {
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return p.name.toLowerCase().contains(q) ||
              p.team.toLowerCase().contains(q);
        })
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: _showReplace ? 0.85 : 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, ctrl) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: kTextMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                PlayerTradingCard(
                  player: widget.player,
                  isCaptain: _isCaptain,
                  ownershipPct: pop * 100,
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _isOnBench ? 'SUPLENTE' : 'TITULAR',
                    style: TextStyle(
                      fontFamily: kFontUI,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: _isOnBench ? kAccentYellow : kAccentGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                PlayerImageUploadButton(player: widget.player),
                const SizedBox(height: 12),
                _statRow('POPULARIDAD', '${(pop * 100).toStringAsFixed(1)}%'),
                PlayerSeasonSection(player: widget.player),
                const Divider(color: kBorder, height: 20),
                if (!_isOnBench) ...[
                  if (!_captainLocked) ...[
                    PixelButton(
                      label: _isCaptain
                          ? '★ QUITAR CAPITAN'
                          : '☆ HACER CAPITAN',
                      color: _isCaptain ? kAccentYellow : kTextMuted,
                      onTap: _saving ? null : _setCaptain,
                    ),
                    const SizedBox(height: 8),
                  ] else if (_isCaptain) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: kAccentYellow.withValues(alpha: 0.12),
                      child: const Row(
                        children: [
                          Text(
                            '★',
                            style: TextStyle(
                              fontSize: 16,
                              color: kAccentYellow,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'CAPITAN HOY',
                            style: TextStyle(
                              fontFamily: 'ChakraPetch',
                              fontSize: 11,
                              color: kAccentYellow,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                if (canReplace) ...[
                  PixelButton(
                    label: _showReplace ? 'CANCELAR' : 'REEMPLAZAR',
                    color: _showReplace ? kAccentRed : kAccentBlue,
                    onTap: () => setState(() {
                      _showReplace = !_showReplace;
                      if (!_showReplace) {
                        _searchCtrl.clear();
                        _searchQuery = '';
                      }
                    }),
                  ),
                ] else if (canSign) ...[
                  PixelButton(
                    label: _showReplace
                        ? 'CANCELAR'
                        : 'FICHAR (${widget.user.signingCardsAvailable} cartas)',
                    color: _showReplace ? kAccentRed : kAccentYellow,
                    onTap: () => setState(() {
                      _showReplace = !_showReplace;
                      if (!_showReplace) {
                        _searchCtrl.clear();
                        _searchQuery = '';
                      }
                    }),
                  ),
                ] else if (!preSeason && canEdit) ...[
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'SIN CARTAS DE FICHAJE',
                      style: TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 11,
                        color: kTextMuted,
                      ),
                    ),
                  ),
                ] else if (!canEdit) ...[
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'EQUIPO BLOQUEADO (SOLO 08:00–13:00)',
                      style: TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 6,
                        color: kTextMuted,
                      ),
                    ),
                  ),
                ],
                if (_showReplace) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'SOLO POSICIÓN: ${widget.player.position}',
                      style: const TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 6,
                        color: kAccentYellow,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: kSurface2,
                      border: Border.all(color: kAccentBlue, width: 1),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 12,
                        color: kTextPrimary,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'buscar jugador...',
                        hintStyle: TextStyle(
                          fontFamily: 'ChakraPetch',
                          fontSize: 11,
                          color: kTextMuted,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: kTextMuted,
                          size: 16,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        counterText: '',
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (replacements.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'SIN JUGADORES',
                        style: TextStyle(
                          fontFamily: 'ChakraPetch',
                          fontSize: 11,
                          color: kTextMuted,
                        ),
                      ),
                    )
                  else
                    ...replacements
                        .take(20)
                        .map(
                          (p) => _ReplacementRow(
                            player: p,
                            popMap: widget.popMap,
                            totalUsers: widget.totalUsers,
                            onTap: _saving
                                ? null
                                : () => _replace(
                                    p,
                                    withSigningCard: !preSeason,
                                  ),
                          ),
                        ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 11,
              color: kTextMuted,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 12,
            color: kTextPrimary,
          ),
        ),
      ],
    ),
  );
}

// ── New PLANTILLA helper widgets ───────────────────────────────────────────

/// Shown during the 5-minute pre-phase buffer while server scripts run.
class _BufferBanner extends StatelessWidget {
  const _BufferBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: kAccentBlue.withValues(alpha: 0.15),
      child: const Row(
        children: [
          Icon(Icons.sync, color: kAccentBlue, size: 12),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'ACTUALIZANDO… VUELVE EN ~5 MIN',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 5,
                color: kAccentBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LockBanner extends StatelessWidget {
  final int signingCards;
  const _LockBanner({required this.signingCards});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: kAccentRed.withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(Icons.lock, color: kAccentRed, size: 12),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'EQUIPO BLOQUEADO',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 5,
                color: kAccentRed,
              ),
            ),
          ),
          if (signingCards > 0)
            Text(
              '$signingCards FICHAJES',
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 5,
                color: kAccentYellow,
              ),
            ),
        ],
      ),
    );
  }
}

class _SubHintBar extends StatelessWidget {
  final VoidCallback onCancel;
  const _SubHintBar({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: kAccentGreen.withValues(alpha: 0.15),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz, color: kAccentGreen, size: 14),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'TOCA UN TITULAR PARA CAMBIAR',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 5,
                color: kAccentGreen,
              ),
            ),
          ),
          GestureDetector(
            onTap: onCancel,
            child: const Icon(Icons.close, color: kAccentGreen, size: 14),
          ),
        ],
      ),
    );
  }
}

/// A small square shown in the top-right of the matchday pitch for a player
/// added by a card — ROBADO (robo) or AÑADIDO (espontáneo). Immune to attacks.
class _ExtraPlayerSquare extends StatelessWidget {
  final Player player;
  final String label;
  const _ExtraPlayerSquare({required this.player, this.label = 'ROBADO'});

  @override
  Widget build(BuildContext context) {
    final added = label == 'AÑADIDO';
    final color = added ? kAccentGreen : kAccentRed;
    return Container(
      width: 58,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'ChakraPetch',
              fontWeight: FontWeight.w700,
              fontSize: 5,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          PlayerAvatar(player: player, size: 34),
          const SizedBox(height: 2),
          Text(
            player.name.split(' ').last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 5,
              color: kTextPrimary,
            ),
          ),
          const Text(
            'INMUNE',
            style: TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 4,
              color: kTextMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplacementRow extends StatelessWidget {
  final Player player;
  final Map<String, int> popMap;
  final int totalUsers;
  final VoidCallback? onTap;

  const _ReplacementRow({
    required this.player,
    required this.popMap,
    required this.totalUsers,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pop = calculatePopularityPercent(popMap[player.id] ?? 1, totalUsers);
    final pct = (pop * 100).toStringAsFixed(0);
    final popColor = pop >= 0.8
        ? kAccentGreen
        : pop >= 0.5
        ? kAccentYellow
        : kAccentRed;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: kSurface2,
          border: Border.all(
            color: kAccentBlue.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            PixelPlayerWidget(skinId: player.skin, size: 28, team: player.team),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    style: const TextStyle(
                      fontFamily: 'ChakraPetch',
                      fontSize: 6,
                      color: kTextPrimary,
                      height: 1.3,
                    ),
                  ),
                  Text(
                    '${player.team} · ${player.position}',
                    style: const TextStyle(
                      fontFamily: 'ChakraPetch',
                      fontSize: 5,
                      color: kTextMuted,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 6,
                    color: popColor,
                  ),
                ),
                Text(
                  player.totalPoints.toStringAsFixed(1),
                  style: const TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 11,
                    color: kAccentGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
