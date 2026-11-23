import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/daily.dart';
import '../../models/user_data.dart';
import '../../providers/game_state_provider.dart';
import '../../providers/league_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_clock.dart';
import '../../utils/scoring.dart';
import '../../utils/time_utils.dart';
import '../../widgets/async_states.dart';
import '../../widgets/league_table.dart';
import '../../widgets/pixel_button.dart';

// ── MI QUINIELA ──────────────────────────────────────────────────────────────

/// The weekly Quiniela: pick 1-X-2 for every fixture of the current matchday,
/// plus optional season Pichichi / top-assist picks.
class MyQuinielaPanel extends ConsumerStatefulWidget {
  final UserData user;
  const MyQuinielaPanel({super.key, required this.user});

  @override
  ConsumerState<MyQuinielaPanel> createState() => _MyQuinielaPanelState();
}

class _MyQuinielaPanelState extends ConsumerState<MyQuinielaPanel> {
  final Map<String, String> _picks = {};
  String? _pichichi;
  String? _asistente;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _seed();
  }

  void _seed() {
    _picks
      ..clear()
      ..addAll(widget.user.quinielaPrediction.picks);
    _pichichi = widget.user.goldenBoot;
    _asistente = widget.user.topAssister;
    _dirty = false;
  }

  @override
  void didUpdateWidget(MyQuinielaPanel old) {
    super.didUpdateWidget(old);
    if (!_dirty &&
        old.user.quinielaPrediction.picks != widget.user.quinielaPrediction.picks) {
      setState(_seed);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final picks = Map<String, String>.from(_picks);
    try {
      await ref.read(userProvider.notifier).save(
        (cur) => cur.copyWith(
          quinielaPrediction: QuinielaPrediction(picks: picks),
          goldenBoot: _pichichi,
          topAssister: _asistente,
        ),
        'app: quiniela',
      );
      if (mounted) setState(() => _dirty = false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NO SE PUDO GUARDAR')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(clockProvider);
    final predOpen = ref.watch(predictionsOpenProvider).valueOrNull ?? true;
    final editable = predOpen && isBettingWindowOpen();
    final mdAsync = ref.watch(currentMatchdayProvider);

    return mdAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.invalidate(currentMatchdayProvider)),
      data: (md) {
        if (md == null || md.matches.isEmpty) {
          return const EmptyView(
            icon: Icons.sports_soccer,
            message: 'SIN JORNADA ACTIVA',
          );
        }
        final actualSigns = <String, String>{
          for (final m in md.matches)
            if (m.sign != null) m.id: m.sign!,
        };
        final pts = quinielaPoints(
          pred: QuinielaPrediction(picks: _picks),
          actualSigns: actualSigns,
        );
        final correct = actualSigns.entries
            .where((e) => _picks[e.key] == e.value)
            .length;

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _header(md, editable),
            const SizedBox(height: 10),
            if (actualSigns.isNotEmpty)
              _pointsBanner(pts, correct, actualSigns.length),
            for (final m in md.matches)
              _FixtureRow(
                match: m,
                pick: _picks[m.id],
                actual: m.sign,
                editable: editable && !m.played,
                onPick: (sign) => setState(() {
                  if (_picks[m.id] == sign) {
                    _picks.remove(m.id);
                  } else {
                    _picks[m.id] = sign;
                  }
                  _dirty = true;
                }),
              ),
            const SizedBox(height: 8),
            _seasonPicks(editable),
            const SizedBox(height: 12),
            if (editable && _dirty)
              _saving
                  ? const Center(child: CircularProgressIndicator())
                  : PixelButton(
                      label: 'GUARDAR QUINIELA',
                      color: kAccentGreen,
                      onTap: _save,
                      fontSize: 13,
                    ),
            if (!predOpen)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'PREDICCIONES CERRADAS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 12,
                    color: kAccentRed,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _header(DailyMatchday md, bool editable) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        'JORNADA ${md.matchday}',
        style: const TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: kTextPrimary,
        ),
      ),
      Text(
        editable ? '1 · X · 2' : 'BLOQUEADA',
        style: TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: 11,
          color: editable ? kAccentGreen : kTextMuted,
        ),
      ),
    ],
  );

  Widget _pointsBanner(double pts, int correct, int decided) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: kAccentGreen, width: 1),
    ),
    child: Text(
      'ACIERTOS $correct/$decided · ${pts.round()} PTS',
      style: const TextStyle(
        fontFamily: 'ChakraPetch',
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: kAccentGreen,
      ),
    ),
  );

  Widget _seasonPicks(bool editable) {
    final playersAsync = ref.watch(playersProvider);
    return playersAsync.maybeWhen(
      orElse: () => const SizedBox(),
      data: (players) {
        final byId = {for (final p in players) p.id: p};
        String label(String? id, String empty) =>
            id != null ? (byId[id]?.name ?? id) : empty;
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kBorder, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'APUESTAS DE TEMPORADA',
                style: TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 11,
                  color: kAccentYellow,
                ),
              ),
              const SizedBox(height: 8),
              _pickRow('PICHICHI', label(_pichichi, 'ELEGIR'), editable, () {
                _showPlayerPicker(players.map((p) => p.id).toList(), byId, (id) {
                  setState(() {
                    _pichichi = id;
                    _dirty = true;
                  });
                });
              }),
              const SizedBox(height: 6),
              _pickRow('MÁS ASISTENCIAS', label(_asistente, 'ELEGIR'), editable, () {
                _showPlayerPicker(players.map((p) => p.id).toList(), byId, (id) {
                  setState(() {
                    _asistente = id;
                    _dirty = true;
                  });
                });
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _pickRow(String label, String value, bool editable, VoidCallback onTap) =>
      Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 10,
                color: kTextDim,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 11,
                color: kTextPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (editable)
            PixelButton(label: 'CAMBIAR', onTap: onTap, color: kAccentYellow, fontSize: 9),
        ],
      );

  void _showPlayerPicker(
    List<String> ids,
    Map<String, dynamic> byId,
    ValueChanged<String> onPick,
  ) {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) {
          final q = controller.text.toLowerCase();
          final filtered = ids
              .where((id) => (byId[id]?.name ?? '').toLowerCase().contains(q))
              .take(60)
              .toList();
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              height: 420,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: TextField(
                      controller: controller,
                      onChanged: (_) => setSheet(() {}),
                      style: const TextStyle(fontFamily: 'ChakraPetch', fontSize: 12),
                      decoration: const InputDecoration(hintText: 'Buscar jugador…'),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final id in filtered)
                          ListTile(
                            dense: true,
                            title: Text(
                              '${byId[id]?.name ?? id}  ·  ${byId[id]?.team ?? ''}',
                              style: const TextStyle(
                                fontFamily: 'ChakraPetch',
                                fontSize: 11,
                              ),
                            ),
                            onTap: () {
                              onPick(id);
                              Navigator.pop(context);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FixtureRow extends StatelessWidget {
  final DailyMatch match;
  final String? pick;
  final String? actual;
  final bool editable;
  final ValueChanged<String> onPick;

  const _FixtureRow({
    required this.match,
    required this.pick,
    required this.actual,
    required this.editable,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBorder, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${match.home}  -  ${match.away}',
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 10,
                color: kTextPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (match.postponed)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'APLAZADO',
                style: TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 8,
                  color: kAccentYellow,
                ),
              ),
            ),
          for (final s in const ['1', 'X', '2']) _signButton(s),
        ],
      ),
    );
  }

  Widget _signButton(String s) {
    final selected = pick == s;
    final isActual = actual == s;
    Color bg;
    Color fg;
    if (actual != null) {
      // Resolved: green if the pick was right, red if wrong, dim otherwise.
      if (selected && isActual) {
        bg = kAccentGreen;
        fg = Colors.white;
      } else if (selected && !isActual) {
        bg = kAccentRed;
        fg = Colors.white;
      } else if (isActual) {
        bg = kSurface;
        fg = kAccentGreen;
      } else {
        bg = kSurface;
        fg = kTextMuted;
      }
    } else {
      bg = selected ? kAccentGreen : kSurface;
      fg = selected ? Colors.white : kTextPrimary;
    }
    return GestureDetector(
      onTap: editable ? () => onPick(s) : null,
      child: Container(
        width: 26,
        height: 26,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActual && actual != null ? kAccentGreen : kBorder,
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          s,
          style: TextStyle(fontFamily: 'ChakraPetch', fontSize: 11, color: fg),
        ),
      ),
    );
  }
}

// ── REAL (league table) ──────────────────────────────────────────────────────

/// The real La Liga table, read-only.
class RealTablePanel extends ConsumerWidget {
  const RealTablePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leagueAsync = ref.watch(leagueProvider);
    return leagueAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.read(leagueProvider.notifier).refresh()),
      data: (ld) => RefreshIndicator(
        onRefresh: () => ref.read(leagueProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text(
              'CLASIFICACIÓN',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: kTextPrimary,
              ),
            ),
            const SizedBox(height: 10),
            LeagueTable(rows: ld.computeTable()),
          ],
        ),
      ),
    );
  }
}
