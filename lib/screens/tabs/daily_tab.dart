import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/daily.dart';
import '../../models/user_data.dart';
import '../../providers/game_state_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_clock.dart';
import '../../utils/time_utils.dart';
import '../../widgets/async_states.dart';
import '../../widgets/bet_card.dart';
import '../../widgets/countdown_timer_widget.dart';
import '../../widgets/pixel_button.dart';
import '../../widgets/pixel_player_widget.dart';
import '../past_matches_screen.dart';
import 'quiniela_tab.dart';

class DailyTab extends StatelessWidget {
  const DailyTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: kBackground,
        appBar: AppBar(
          backgroundColor: kSurface,
          elevation: 0,
          title: const Text('PARTIDOS'),
          actions: [
            IconButton(
              tooltip: 'Resultados pasados',
              icon: const Icon(Icons.history, size: 20),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PastMatchesScreen(),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(height: 36, text: 'HOY'),
              Tab(height: 36, text: 'MI QUINIELA'),
              Tab(height: 36, text: 'REAL'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_HoyTab(), _MiQuinielaTab(), _RealTab()],
        ),
      ),
    );
  }
}

// ── HOY tab ────────────────────────────────────────────────────────────────

class _HoyTab extends ConsumerWidget {
  const _HoyTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(clockProvider); // rebuild when the simulated time changes
    final dailyAsync = ref.watch(currentMatchdayProvider);
    final userAsync = ref.watch(userProvider);

    return userAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.invalidate(userProvider)),
      data: (user) {
        if (user == null) return const SizedBox();
        return dailyAsync.when(
          loading: () => const LoadingView(),
          error: (e, _) => const _NoMatchesToday(),
          data: (daily) {
            if (daily == null) return const _NoMatchesToday();
            return _HoyContent(daily: daily, user: user);
          },
        );
      },
    );
  }
}

class _NoMatchesToday extends StatelessWidget {
  const _NoMatchesToday();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.sports_soccer, color: kTextMuted, size: 48),
        SizedBox(height: 16),
        Text(
          'SIN PARTIDOS HOY',
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 14,
            color: kTextMuted,
          ),
        ),
      ],
    ),
  );
}

class _HoyContent extends ConsumerStatefulWidget {
  final DailyMatchday daily;
  final UserData user;

  const _HoyContent({required this.daily, required this.user});

  @override
  ConsumerState<_HoyContent> createState() => _HoyContentState();
}

class _HoyContentState extends ConsumerState<_HoyContent> {
  final Map<String, String> _betSelections = {};
  bool _betsSubmitted = false;
  bool _saving = false;

  void _syncBetsFromUser() {
    final todayBetIds = widget.daily.bets.map((b) => b.id).toSet();
    _betSelections.clear();
    for (final e in widget.user.active.bets.entries) {
      if (todayBetIds.contains(e.key)) _betSelections[e.key] = e.value;
    }
    _betsSubmitted = _betSelections.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _syncBetsFromUser();
  }

  @override
  void didUpdateWidget(_HoyContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.active.bets != widget.user.active.bets ||
        oldWidget.daily.date != widget.daily.date) {
      setState(_syncBetsFromUser);
    }
  }

  Future<void> _submitBets() async {
    if (_betSelections.isEmpty) return;
    setState(() => _saving = true);
    final selections = Map<String, String>.from(_betSelections);
    try {
      await ref
          .read(userProvider.notifier)
          .save(
            (cur) => cur.copyWith(
              active: ActiveState(
                captain: cur.active.captain,
                bets: selections,
                cardsReceived: cur.active.cardsReceived,
                cardsPlayed: cur.active.cardsPlayed,
                attacksReceivedToday: cur.active.attacksReceivedToday,
              ),
            ),
            'app: bets submitted',
          );
      setState(() => _betsSubmitted = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NO SE PUDO GUARDAR — VERIFICA CONEXION'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final daily = widget.daily;
    final user = widget.user;
    final inWindow = isBettingWindowOpen();
    final locked = isCaptainLocked();

    final allUsersAsync = ref.watch(allUsersProvider);
    final betOdds = <String, Map<String, double>>{};
    if (allUsersAsync.hasValue) {
      final allUsers = allUsersAsync.value!;
      for (final bet in daily.bets) {
        final counts = <String, int>{};
        for (final opt in bet.options) {
          counts[opt] = 0;
        }
        for (final ud in allUsers.values) {
          final bets =
              (ud as Map<String, dynamic>)['active']?['bets']
                  as Map<String, dynamic>?;
          if (bets != null && bets.containsKey(bet.id)) {
            final chosen = bets[bet.id] as String;
            counts[chosen] = (counts[chosen] ?? 0) + 1;
          }
        }
        final total = counts.values.fold(0, (a, b) => a + b);
        betOdds[bet.id] = counts.map(
          (k, v) => MapEntry(k, total > 0 ? v / total * 100 : 0),
        );
      }
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(githubServiceProvider).clearCache();
        ref.invalidate(currentMatchdayProvider);
        ref.invalidate(allUsersProvider);
        ref.read(userProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _windowHeader(daily, inWindow),
          const SizedBox(height: 16),
          _CaptainSection(user: user, daily: daily, locked: locked),
          const SizedBox(height: 16),
          ...[
            _sectionHeader('APUESTAS DE LA JORNADA'),
            if (daily.bets.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'SIN APUESTAS HOY',
                  style: TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 12,
                    color: kTextMuted,
                  ),
                ),
              )
            else ...[
              for (final bet in daily.bets)
                BetCard(
                  bet: bet,
                  match: {for (final m in daily.matches) m.id: m}[bet.matchId],
                  selectedOption: _betSelections[bet.id],
                  locked: _betsSubmitted || !inWindow,
                  optionOdds: betOdds[bet.id] ?? {},
                  onSelect: (opt) {
                    if (!_betsSubmitted && inWindow) {
                      setState(() {
                        if (_betSelections[bet.id] == opt) {
                          _betSelections.remove(bet.id);
                        } else {
                          _betSelections[bet.id] = opt;
                        }
                      });
                    }
                  },
                ),
              if (inWindow && !_betsSubmitted)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _saving
                      ? const Center(child: CircularProgressIndicator())
                      : PixelButton(
                          label: 'ENVIAR APUESTAS',
                          color: kAccentGreen,
                          onTap: _betSelections.length == daily.bets.length
                              ? _submitBets
                              : null,
                          fontSize: 13,
                        ),
                ),
              if (_betsSubmitted)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'APUESTAS ENVIADAS',
                    style: TextStyle(
                      fontFamily: 'ChakraPetch',
                      fontSize: 12,
                      color: kAccentGreen,
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _windowHeader(DailyMatchday daily, bool inWindow) {
    if (inWindow) {
      final lock = daily.lockAtTime;
      if (lock != null && lock.isAfter(appNow())) {
        return Center(
          child: CountdownTimerWidget(
            target: lock,
            label: 'APUESTAS CIERRAN',
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kAccentGreen, width: 1),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_open, color: kAccentGreen, size: 16),
            SizedBox(width: 8),
            Text(
              'APUESTAS ABIERTAS',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kAccentGreen,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kAccentRed, width: 1),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock, color: kAccentRed, size: 16),
          SizedBox(width: 8),
          Text(
            'APUESTAS CERRADAS',
            style: TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: kAccentRed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontFamily: 'ChakraPetch',
        fontSize: 14,
        color: kAccentGreen,
      ),
    ),
  );
}

// ── Captain section ────────────────────────────────────────────────────────

class _CaptainSection extends ConsumerStatefulWidget {
  final UserData user;
  final DailyMatchday daily;
  final bool locked;

  const _CaptainSection({
    required this.user,
    required this.daily,
    required this.locked,
  });

  @override
  ConsumerState<_CaptainSection> createState() => _CaptainSectionState();
}

class _CaptainSectionState extends ConsumerState<_CaptainSection> {
  bool _saving = false;

  Future<void> _changeCaptain(String pid) async {
    setState(() => _saving = true);
    final date = widget.daily.date;
    try {
      await ref
          .read(userProvider.notifier)
          .save((cur) {
            final newPicks = Map<String, String?>.from(cur.captainPicks);
            newPicks[date] = pid;
            return cur.copyWith(captainPicks: newPicks);
          }, 'app: set captain');
      if (mounted) Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    final captain = widget.user.captainPicks[widget.daily.date];
    final playersAsync = ref.watch(playersProvider);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder, width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.star, color: kAccentYellow, size: 16),
              SizedBox(width: 6),
              Text(
                'CAPITÁN',
                style: TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          playersAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (players) {
              final playerMap = {for (final p in players) p.id: p};
              final cap = captain != null ? playerMap[captain] : null;
              return Row(
                children: [
                  if (cap != null)
                    PixelPlayerWidget(
                      skinId: cap.skin,
                      size: 40,
                      team: cap.team,
                      isCaptain: true,
                    )
                  else
                    const Icon(Icons.help_outline, color: kTextMuted, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      cap?.name ?? 'SIN CAPITÁN',
                      style: const TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 12,
                        color: kTextPrimary,
                      ),
                    ),
                  ),
                  if (!widget.locked)
                    PixelButton(
                      label: 'CAMBIAR',
                      onTap: () => _showCaptainPicker(context, playerMap),
                      color: kAccentYellow,
                      fontSize: 11,
                    )
                  else
                    const Text(
                      'BLOQUEADO',
                      style: TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 11,
                        color: kTextMuted,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _showCaptainPicker(
    BuildContext context,
    Map<String, dynamic> playerMap,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'ELEGIR CAPITÁN',
            style: TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 14,
              color: kAccentYellow,
            ),
          ),
          const SizedBox(height: 12),
          ...widget.user.allSquadPlayers.map((id) {
            final p = playerMap[id];
            if (p == null) return const SizedBox();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PixelButton(
                label: p.name,
                onTap: _saving ? null : () => _changeCaptain(id),
                color: kAccentYellow,
                fontSize: 12,
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── MI QUINIELA tab ────────────────────────────────────────────────────────

class _MiQuinielaTab extends ConsumerWidget {
  const _MiQuinielaTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);
    return userAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.invalidate(userProvider)),
      data: (user) {
        if (user == null) return const SizedBox();
        return MyQuinielaPanel(user: user);
      },
    );
  }
}

// ── REAL tab ───────────────────────────────────────────────────────────────

class _RealTab extends StatelessWidget {
  const _RealTab();

  @override
  Widget build(BuildContext context) => const RealTablePanel();
}
