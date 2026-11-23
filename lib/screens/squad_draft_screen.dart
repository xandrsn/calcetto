import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player.dart';
import '../models/user_data.dart';
import '../providers/game_state_provider.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import '../utils/popularity.dart';
import '../widgets/pixel_button.dart';
import '../widgets/pixel_player_widget.dart';

const _kFormations = [
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

Map<String, int> _parseFormation(String f) {
  final p = f.split('-').map(int.parse).toList();
  return {'GK': 1, 'DEF': p[0], 'MID': p[1], 'FWD': p[2]};
}

class SquadDraftScreen extends ConsumerStatefulWidget {
  const SquadDraftScreen({super.key});

  @override
  ConsumerState<SquadDraftScreen> createState() => _SquadDraftScreenState();
}

class _SquadDraftScreenState extends ConsumerState<SquadDraftScreen> {
  final _picks = <String, List<String>>{
    'GK': [],
    'DEF': [],
    'MID': [],
    'FWD': [],
  };
  String _posFilter = 'GK';
  String _formation = '4-3-3';
  bool _showFormation = false;
  bool _saving = false;
  bool _initialized = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _allPicked => kPositions.every(
    (pos) => (_picks[pos]?.length ?? 0) >= (kPlantillaTotal[pos] ?? 0),
  );

  void _initFromUser(UserData user) {
    if (_initialized) return;
    _initialized = true;
    _formation = user.formation;
    for (final pos in kPositions) {
      final all = <String>[
        ...(user.squad[pos] ?? []),
        ...(user.bench[pos] ?? []),
      ];
      _picks[pos] = all.take(kPlantillaTotal[pos]!).toList();
    }
    _posFilter = kPositions.firstWhere(
      (pos) => (_picks[pos]?.length ?? 0) < (kPlantillaTotal[pos] ?? 0),
      orElse: () => kPositions.last,
    );
    if (_allPicked) _showFormation = true;
  }

  List<Player> _filtered(List<Player> all) {
    final taken = {for (final e in _picks.entries) ...e.value};
    var pool = all
        .where(
          (p) =>
              !taken.contains(p.id) && p.position.toUpperCase() == _posFilter,
        )
        .toList();
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      pool = pool
          .where(
            (p) =>
                p.name.toLowerCase().contains(q) ||
                p.team.toLowerCase().contains(q),
          )
          .toList();
    }
    return pool;
  }

  void _pick(String pid) {
    final target = kPlantillaTotal[_posFilter] ?? 0;
    final current = _picks[_posFilter]?.length ?? 0;
    if (current >= target) return;
    setState(() {
      _picks[_posFilter] = [...(_picks[_posFilter] ?? []), pid];
      if (_picks[_posFilter]!.length >= target) {
        final idx = kPositions.indexOf(_posFilter);
        if (idx < kPositions.length - 1) {
          _posFilter = kPositions[idx + 1];
          _search.clear();
        }
        if (_allPicked) _showFormation = true;
      }
    });
  }

  void _remove(String pos, String pid) {
    setState(() {
      _picks[pos] = (_picks[pos] ?? []).where((id) => id != pid).toList();
      _posFilter = pos;
      _showFormation = false;
      _search.clear();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final counts = _parseFormation(_formation);
    final newSquad = <String, List<String>>{};
    final newBench = <String, List<String>>{};
    for (final pos in kPositions) {
      final all = _picks[pos] ?? [];
      final n = counts[pos] ?? 0;
      newSquad[pos] = all.take(n).toList();
      newBench[pos] = all.skip(n).toList();
    }
    try {
      await ref
          .read(userProvider.notifier)
          .save(
            (cur) => cur.copyWith(
              squad: newSquad,
              bench: newBench,
              formation: _formation,
            ),
            'app: draft squad',
          );
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
    final playersAsync = ref.watch(playersProvider);
    final userAsync = ref.watch(userProvider);
    final popAsync = ref.watch(popularityMapProvider);
    final allUsersAsync = ref.watch(allUsersProvider);

    final totalPicked = _picks.values.fold(0, (s, l) => s + l.length);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _showFormation ? 'FORMACIÓN' : 'ARMAR PLANTILLA',
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 13,
            color: kAccentGreen,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '$totalPicked/16',
                style: const TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 12,
                  color: kAccentYellow,
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: kBorder, height: 1),
        ),
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            '$e',
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 12,
              color: kAccentRed,
            ),
          ),
        ),
        data: (user) {
          if (user == null) return const SizedBox();
          _initFromUser(user);

          return playersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(
                '$e',
                style: const TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 12,
                  color: kAccentRed,
                ),
              ),
            ),
            data: (players) {
              final popMap = popAsync.value ?? {};
              final totalUsers = (allUsersAsync.value?.length ?? 1).clamp(
                1,
                999,
              );
              final playerMap = {for (final p in players) p.id: p};

              if (_showFormation) {
                return _FormationPhase(
                  picks: _picks,
                  formation: _formation,
                  playerMap: playerMap,
                  saving: _saving,
                  onFormChange: (f) => setState(() => _formation = f),
                  onBack: () => setState(() {
                    _showFormation = false;
                    _posFilter = kPositions.last;
                  }),
                  onSave: () {
                    final u = ref.read(userProvider).value;
                    if (u != null) _save();
                  },
                );
              }

              final filtered = _filtered(players);
              return Column(
                children: [
                  _PositionProgress(
                    picks: _picks,
                    current: _posFilter,
                    onTap: (pos) => setState(() {
                      _posFilter = pos;
                      _search.clear();
                    }),
                  ),
                  _PickedRow(
                    pids: _picks[_posFilter] ?? [],
                    playerMap: playerMap,
                    target: kPlantillaTotal[_posFilter] ?? 0,
                    pos: _posFilter,
                    onRemove: (pid) => _remove(_posFilter, pid),
                  ),
                  _SearchBar(ctrl: _search, onChanged: (_) => setState(() {})),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'SIN JUGADORES',
                              style: TextStyle(
                                fontFamily: 'ChakraPetch',
                                fontSize: 12,
                                color: kTextMuted,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final p = filtered[i];
                              final pop = calculatePopularityPercent(
                                popMap[p.id] ?? 1,
                                totalUsers,
                              );
                              return _PlayerRow(
                                player: p,
                                popularity: pop,
                                onTap: () => _pick(p.id),
                              );
                            },
                          ),
                  ),
                  if (_allPicked)
                    _AllDoneBar(
                      onNext: () => setState(() => _showFormation = true),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ── Position progress tabs ─────────────────────────────────────────────────

class _PositionProgress extends StatelessWidget {
  final Map<String, List<String>> picks;
  final String current;
  final ValueChanged<String> onTap;

  const _PositionProgress({
    required this.picks,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: kPositions.map((pos) {
          final count = picks[pos]?.length ?? 0;
          final total = kPlantillaTotal[pos] ?? 0;
          final done = count >= total;
          final active = pos == current;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(pos),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: active
                      ? kAccentGreen.withValues(alpha: 0.15)
                      : Colors.transparent,
                  border: Border.all(
                    color: done
                        ? kAccentGreen
                        : (active ? kAccentGreen : kTextMuted),
                    width: active ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      pos,
                      style: TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 6,
                        color: done
                            ? kAccentGreen
                            : (active ? kAccentGreen : kTextMuted),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$count/$total',
                      style: TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 12,
                        color: done
                            ? kAccentGreen
                            : (active ? kTextPrimary : kTextMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Picked players row ─────────────────────────────────────────────────────

class _PickedRow extends StatelessWidget {
  final List<String> pids;
  final Map<String, Player> playerMap;
  final int target;
  final String pos;
  final ValueChanged<String> onRemove;

  const _PickedRow({
    required this.pids,
    required this.playerMap,
    required this.target,
    required this.pos,
    required this.onRemove,
  });

  static String _short(String name) {
    final last = name.split(' ').last;
    return last.substring(0, last.length.clamp(0, 6)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kSurface2,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(target, (i) {
            final pid = i < pids.length ? pids[i] : null;
            final player = pid != null ? playerMap[pid] : null;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: pid != null ? () => onRemove(pid) : null,
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        border: Border.all(
                          color: player != null ? kAccentGreen : kTextDim,
                          width: 1,
                        ),
                      ),
                      child: player != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                PixelPlayerWidget(
                                  skinId: player.skin,
                                  size: 40,
                                  team: player.team,
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Icon(
                                    Icons.close,
                                    size: 10,
                                    color: kAccentRed,
                                  ),
                                ),
                              ],
                            )
                          : Icon(Icons.add, color: kTextDim, size: 16),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: 40,
                      child: Text(
                        player != null ? _short(player.name) : '---',
                        style: TextStyle(
                          fontFamily: 'ChakraPetch',
                          fontSize: 5,
                          color: player != null ? kTextPrimary : kTextDim,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ── Formation phase ────────────────────────────────────────────────────────

class _FormationPhase extends StatelessWidget {
  final Map<String, List<String>> picks;
  final String formation;
  final Map<String, Player> playerMap;
  final bool saving;
  final ValueChanged<String> onFormChange;
  final VoidCallback onBack;
  final VoidCallback onSave;

  const _FormationPhase({
    required this.picks,
    required this.formation,
    required this.playerMap,
    required this.saving,
    required this.onFormChange,
    required this.onBack,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final counts = _parseFormation(formation);

    return Column(
      children: [
        Container(
          color: kSurface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _kFormations
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: PixelButton(
                        label: f,
                        selected: f == formation,
                        onTap: () => onFormChange(f),
                        fontSize: 11,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final pos in kPositions) ...[
                _posHeader(pos, counts[pos] ?? 0),
                _posPlayerList(pos, picks[pos] ?? [], counts[pos] ?? 0),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: kSurface,
            border: Border(top: BorderSide(color: kBorder, width: 1)),
          ),
          padding: const EdgeInsets.all(12),
          child: SafeArea(
            child: Row(
              children: [
                PixelButton(
                  label: 'ATRÁS',
                  onTap: onBack,
                  color: kTextMuted,
                  fontSize: 12,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: saving
                      ? const Center(child: CircularProgressIndicator())
                      : PixelButton(
                          label: 'GUARDAR PLANTILLA',
                          onTap: onSave,
                          color: kAccentGreen,
                          fontSize: 12,
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _posHeader(String pos, int starters) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(
          pos,
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 12,
            color: kAccentYellow,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '($starters TITULARES)',
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 6,
            color: kTextMuted,
          ),
        ),
      ],
    ),
  );

  Widget _posPlayerList(String pos, List<String> pids, int starterCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < pids.length; i++) ...[
          if (i == starterCount)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'SUPLENTES',
                style: TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 6,
                  color: kTextMuted,
                ),
              ),
            ),
          _PlayerLine(
            player: playerMap[pids[i]],
            pid: pids[i],
            isStarter: i < starterCount,
          ),
        ],
      ],
    );
  }
}

class _PlayerLine extends StatelessWidget {
  final Player? player;
  final String pid;
  final bool isStarter;

  const _PlayerLine({
    required this.player,
    required this.pid,
    required this.isStarter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(
          color: isStarter
              ? kAccentBlue.withValues(alpha: 0.6)
              : kTextMuted.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          if (player != null)
            PixelPlayerWidget(
              skinId: player!.skin,
              size: 28,
              team: player!.team,
            )
          else
            const Icon(Icons.help_outline, color: kTextMuted, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              player?.name ?? pid,
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 6,
                color: isStarter ? kTextPrimary : kTextMuted,
                height: 1.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (player != null) ...[
            Text(
              player!.team,
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 5,
                color: kTextMuted,
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (isStarter)
            const Icon(Icons.sports_soccer, color: kAccentGreen, size: 10)
          else
            const Icon(Icons.chair_outlined, color: kTextMuted, size: 10),
        ],
      ),
    );
  }
}

// ── All-done bottom bar ────────────────────────────────────────────────────

class _AllDoneBar extends StatelessWidget {
  final VoidCallback onNext;
  const _AllDoneBar({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kAccentBlue, width: 2)),
      ),
      padding: const EdgeInsets.all(12),
      child: SafeArea(
        child: PixelButton(
          label: 'ELEGIR FORMACIÓN →',
          onTap: onNext,
          color: kAccentGreen,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ── Search bar ─────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController ctrl;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.ctrl, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: TextField(
        controller: ctrl,
        onChanged: onChanged,
        style: const TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: 12,
          color: kTextPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'BUSCAR NOMBRE / EQUIPO...',
          prefixIcon: const Icon(Icons.search, color: kTextMuted, size: 18),
          suffixIcon: ctrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: kTextMuted, size: 18),
                  onPressed: () {
                    ctrl.clear();
                    onChanged('');
                  },
                )
              : null,
        ),
      ),
    );
  }
}

// ── Player row ─────────────────────────────────────────────────────────────

class _PlayerRow extends StatelessWidget {
  final Player player;
  final double popularity;
  final VoidCallback onTap;

  const _PlayerRow({
    required this.player,
    required this.popularity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final popPct = (popularity * 100).round();
    final popColor = popPct >= 80
        ? kAccentGreen
        : (popPct >= 50 ? kAccentYellow : kAccentRed);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kAccentBlue, width: 1),
        ),
        child: Row(
          children: [
            PixelPlayerWidget(skinId: player.skin, size: 36, team: player.team),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    style: const TextStyle(
                      fontFamily: 'ChakraPetch',
                      fontSize: 11,
                      color: kTextPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${player.team}  •  ${player.position}',
                    style: const TextStyle(
                      fontFamily: 'ChakraPetch',
                      fontSize: 5,
                      color: kTextMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'POP',
                  style: TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 5,
                    color: kTextMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$popPct%',
                  style: TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 12,
                    color: popColor,
                    fontWeight: FontWeight.bold,
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
