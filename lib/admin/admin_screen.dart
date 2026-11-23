import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../providers/data_repository.dart';
import '../providers/game_state_provider.dart';
import '../providers/league_provider.dart';
import '../providers/user_provider.dart';
import '../screens/league_table_screen.dart';
import '../screens/splash_screen.dart';
import '../theme/app_theme.dart';
import '../utils/app_clock.dart';
import '../utils/time_utils.dart';
import '../widgets/pixel_button.dart';
import 'admin_service.dart';
import 'player_images_admin_screen.dart';
import 'results_entry_screen.dart';

/// Lightweight internal testing tool. Functional over pretty: buttons, a user
/// table, and a live action log. All operations go through [AdminService].
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final _log = <String>[];
  bool _busy = false;
  List<String>? _users;

  final _newNameCtrl = TextEditingController();
  String? _renameTarget;

  late final _ownerCtrl = TextEditingController(text: kGithubOwner);
  late final _repoCtrl = TextEditingController(text: kGithubRepo);
  final _workflowCtrl = TextEditingController(text: 'daily_resolution.yml');

  // Test-match builder state.
  final _testMdCtrl = TextEditingController(text: '1');
  String? _homeTeam;
  String? _awayTeam;

  String _mdKey(String n) =>
      'md${(int.tryParse(n.trim()) ?? 1).toString().padLeft(2, '0')}';

  AdminService get _svc => ref.read(adminServiceProvider);

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _newNameCtrl.dispose();
    _ownerCtrl.dispose();
    _repoCtrl.dispose();
    _workflowCtrl.dispose();
    _testMdCtrl.dispose();
    super.dispose();
  }

  void _append(String line) {
    if (!mounted) return;
    setState(() => _log.insert(0, line));
  }

  Future<void> _loadUsers() async {
    try {
      final u = await _svc.listUsernames();
      if (mounted) setState(() => _users = u);
    } catch (e) {
      _append('✗ load users: $e');
    }
  }

  /// Runs an operation with busy-guarding and logs the outcome. Refreshes app
  /// providers afterward so the running app reflects the change.
  Future<void> _run(String label, Future<void> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    _append('… $label');
    try {
      await op();
      ref.read(githubServiceProvider).clearCache();
      ref.invalidate(allUsersProvider);
      ref.invalidate(userProvider);
      ref.read(leagueProvider.notifier).refresh();
      _append('✓ $label');
    } catch (e) {
      _append('✗ $label — $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: kAccentRed, width: 2),
          borderRadius: BorderRadius.zero,
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 12,
            color: kTextPrimary,
            height: 1.3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'NO',
              style: TextStyle(fontFamily: 'ChakraPetch', color: kTextMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'SÍ',
              style: TextStyle(fontFamily: 'ChakraPetch', color: kAccentRed),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'ADMIN',
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 12,
            color: kAccentYellow,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(color: kAccentYellow, height: 2),
        ),
      ),
      body: Column(
        children: [
          if (_busy)
            const LinearProgressIndicator(color: kAccentYellow, minHeight: 3),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                _statusSection(),
                _timeSection(),
                _predictionsSection(),
                _testMatchSection(),
                _leagueSection(),
                _usersSection(),
                _renameSection(),
                _resolutionSection(),
                _systemSection(),
              ],
            ),
          ),
          _logPanel(),
        ],
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _section(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: kSurface,
      border: Border.all(color: kAccentBlue, width: 1),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 12,
            color: kAccentGreen,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );

  // ── Status dashboard ────────────────────────────────────────────────────
  Widget _statusSection() {
    final now = appNow();
    final phase = dayPhase(now);
    final buffer = isPhaseBuffer(now);
    final phaseLabel = buffer
        ? 'ACTUALIZANDO'
        : phase == DayPhase.manage
        ? 'PREP'
        : phase == DayPhase.cards
        ? 'CARTAS'
        : 'PARTIDOS';
    final override = ref.watch(clockProvider);
    final usersCount = ref.watch(allUsersProvider).valueOrNull?.length;
    final predOpen = ref.watch(predictionsOpenProvider).valueOrNull;
    final daily = ref.watch(currentMatchdayProvider).valueOrNull;
    final league = ref.watch(leagueProvider).valueOrNull;
    final table = league?.computeTable();
    final leader = (table != null && table.isNotEmpty && table.first.p > 0)
        ? table.first.team
        : null;

    return _section('STATUS', [
      _statusRow('USUARIOS', '${usersCount ?? '…'}', kTextPrimary),
      _statusRow(
        'FASE',
        '$phaseLabel${override == null ? ' (real)' : ' (sim)'}',
        buffer ? kAccentBlue : kAccentGreen,
      ),
      _statusRow(
        'RELOJ',
        override == null ? 'REAL (Madrid)' : _fmt(override),
        override == null ? kTextMuted : kAccentYellow,
      ),
      _statusRow(
        'PREDICCIONES',
        predOpen == null ? '…' : (predOpen ? 'ABIERTAS' : 'CERRADAS'),
        predOpen == true ? kAccentGreen : kAccentRed,
      ),
      _statusRow(
        'JORNADA',
        daily == null ? 'NINGUNA' : 'J${daily.matchday} (${daily.date})',
        daily == null ? kTextMuted : kTextPrimary,
      ),
      _statusRow(
        'LÍDER',
        leader ?? 'EN CURSO',
        leader != null ? kAccentYellow : kTextMuted,
      ),
    ]);
  }

  Widget _statusRow(String label, String value, Color valueColor) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 6,
              color: kTextMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 11,
              color: valueColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  // ── Time simulation ─────────────────────────────────────────────────────
  Widget _timeSection() {
    final daily = ref.watch(currentMatchdayProvider).value;
    final override = ref.watch(clockProvider);
    final cards = daily?.cardsOpenTime;
    final lock = daily?.lockAtTime;

    return _section('TIME — ${override == null ? 'REAL' : _fmt(override)}', [
      Text(
        daily == null
            ? 'SIN JORNADA ACTIVA — USA REAL TIME.'
            : 'SALTA A UNA FASE DE LA JORNADA J${daily.matchday} '
                  '(AFECTA LOCKS, CARTAS, %).',
        style: const TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: 5,
          color: kTextMuted,
          height: 1.3,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (cards != null)
            _timeBtn('PREP', cards.subtract(const Duration(hours: 1))),
          if (cards != null)
            _timeBtn('CARTAS', cards.add(const Duration(minutes: 30))),
          if (lock != null)
            _timeBtn('PARTIDOS', lock.add(const Duration(minutes: 30))),
          if (cards != null)
            _timeBtn('BUFFER', cards.subtract(const Duration(minutes: 2))),
          PixelButton(
            label: 'REAL TIME',
            color: kAccentGreen,
            fontSize: 11,
            onTap: () async {
              applyClockOverride(ref, null);
              await _persistClock(null);
              _append('⏰ real time (todos)');
            },
          ),
        ],
      ),
    ]);
  }

  Widget _timeBtn(String label, DateTime when) => PixelButton(
    label: label,
    color: kAccentYellow,
    fontSize: 11,
    onTap: () async {
      applyClockOverride(ref, when);
      await _persistClock(when);
      _append('⏰ $label → ${_fmt(when)} (todos)');
    },
  );

  /// Persists the simulated clock to the backend so every device converges
  /// (read by clockSyncProvider). null = real time.
  Future<void> _persistClock(DateTime? when) async {
    try {
      await ref
          .read(dataRepositoryProvider)
          .setAppConfig('clock_override', when?.toIso8601String());
      ref.invalidate(clockSyncProvider);
    } catch (_) {
      // Best-effort; the local override already applied for the admin.
    }
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmt(DateTime d) =>
      '${_dateStr(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _predictionsSection() {
    final open = ref.watch(predictionsOpenProvider).valueOrNull ?? true;
    return _section('PREDICTIONS — ${open ? "OPEN" : "CLOSED"}', [
      const Text(
        'WHEN CLOSED, USERS CANNOT EDIT THEIR QUINIELA / GOLEADOR PICKS.',
        style: TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: 5,
          color: kTextMuted,
          height: 1.3,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PixelButton(
            label: 'OPEN',
            fontSize: 11,
            onTap: _busy
                ? null
                : () => _run('open predictions', () async {
                    await _svc.setPredictionsOpen(true);
                    ref.invalidate(predictionsOpenProvider);
                  }),
          ),
          PixelButton(
            label: 'CLOSE',
            color: kAccentRed,
            fontSize: 11,
            onTap: _busy
                ? null
                : () => _run('close predictions', () async {
                    await _svc.setPredictionsOpen(false);
                    ref.invalidate(predictionsOpenProvider);
                  }),
          ),
        ],
      ),
    ]);
  }

  // ── Test match end-to-end harness ───────────────────────────────────────
  Widget _testMatchSection() {
    final players = ref.watch(playersProvider).valueOrNull ?? const [];
    final teams = players.map((p) => p.team).toSet().toList()..sort();

    return _section('TEST MATCH', [
      const Text(
        'CREATE A 1-MATCH DAY, LET USERS SET XI/CAPTAIN/CARDS/BETS, FINISH IT, '
        'THEN RUN RESOLUTION (CI) TO SCORE IT.',
        style: TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: 5,
          color: kTextMuted,
          height: 1.3,
        ),
      ),
      const SizedBox(height: 10),
      _field('JORNADA Nº', _testMdCtrl),
      _teamDrop('HOME', _homeTeam, teams, (v) => setState(() => _homeTeam = v)),
      _teamDrop('AWAY', _awayTeam, teams, (v) => setState(() => _awayTeam = v)),
      const SizedBox(height: 8),
      PixelButton(
        label: 'CREATE MATCHDAY',
        fontSize: 11,
        onTap: _busy
            ? null
            : () {
                final h = _homeTeam;
                final a = _awayTeam;
                if (h == null || a == null || h == a) {
                  _append('✗ pick two different teams');
                  return;
                }
                _run(
                  'create test matchday ${_testMdCtrl.text}',
                  () => _svc.createTestMatchday(
                    mdNumber: int.tryParse(_testMdCtrl.text.trim()) ?? 1,
                    homeTeam: h,
                    awayTeam: a,
                    allPlayers: players,
                  ),
                );
              },
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PixelButton(
            label: 'ENTER RESULTS',
            color: kAccentGreen,
            fontSize: 11,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ResultsEntryScreen(mdKey: _mdKey(_testMdCtrl.text)),
              ),
            ),
          ),
          PixelButton(
            label: 'RUN RESOLUTION (CI)',
            color: kAccentBlue,
            fontSize: 11,
            onTap: _busy
                ? null
                : () => _run(
                    'dispatch resolution ${_testMdCtrl.text}',
                    () async {
                      final status = await _svc.dispatchResolution(
                        owner: _ownerCtrl.text.trim(),
                        repo: _repoCtrl.text.trim(),
                        workflowFile: _workflowCtrl.text.trim(),
                        inputs: {
                          'matchday': _testMdCtrl.text.trim(),
                          'step': 'resolve_only',
                        },
                      );
                      if (status != 204) throw Exception('HTTP $status');
                    },
                  ),
          ),
        ],
      ),
    ]);
  }

  Widget _teamDrop(
    String label,
    String? value,
    List<String> teams,
    ValueChanged<String?> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 5,
              color: kTextMuted,
            ),
          ),
        ),
        Expanded(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            dropdownColor: kSurface,
            hint: const Text(
              'SELECT',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 6,
                color: kTextMuted,
              ),
            ),
            items: teams
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(
                      t,
                      style: const TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 11,
                        color: kTextPrimary,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    ),
  );

  Widget _leagueSection() => _section('LIGA', [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        PixelButton(
          label: 'SIMULATE',
          fontSize: 11,
          onTap: _busy
              ? null
              : () async {
                  if (await _confirm(
                    '¿SIMULAR LIGA?\nSobrescribe los resultados reales con '
                    'resultados aleatorios y repuntúa Pichichi/asistencias.',
                  )) {
                    _run('simulate + score picks', () async {
                      await _svc.simulateLeague();
                      await _svc.scoreSeasonPicksAllUsers();
                    });
                  }
                },
        ),
        PixelButton(
          label: 'RESET',
          color: kAccentRed,
          fontSize: 11,
          onTap: _busy
              ? null
              : () async {
                  if (await _confirm('¿RESET LIGA?')) {
                    _run('reset league', _svc.resetLeague);
                  }
                },
        ),
        PixelButton(
          label: 'VER CLASIFICACIÓN',
          color: kAccentBlue,
          fontSize: 11,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LeagueTableScreen()),
          ),
        ),
      ],
    ),
  ]);

  Widget _usersSection() {
    final users = _users;
    return _section('USERS (${users?.length ?? '…'})', [
      Row(
        children: [
          PixelButton(
            label: 'RELOAD',
            color: kAccentBlue,
            fontSize: 11,
            onTap: _busy ? null : _loadUsers,
          ),
          const SizedBox(width: 8),
          PixelButton(
            label: 'RESET ALL',
            color: kAccentRed,
            fontSize: 11,
            onTap: _busy
                ? null
                : () async {
                    if (await _confirm('¿RESET ALL USERS?')) {
                      _run('reset all users', _svc.resetAllUsers);
                    }
                  },
          ),
          const SizedBox(width: 8),
          // The only logout in the app: admin signs THIS device out and returns
          // to the name screen. (Regular users can't log out.)
          PixelButton(
            label: 'LOGOUT ME',
            color: kAccentYellow,
            fontSize: 11,
            onTap: _busy
                ? null
                : () async {
                    if (await _confirm('¿CERRAR TU SESION?')) {
                      await ref.read(userProvider.notifier).logout();
                      if (mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const SplashScreen(),
                          ),
                          (r) => false,
                        );
                      }
                    }
                  },
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (users == null)
        const Text(
          'LOADING…',
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 6,
            color: kTextMuted,
          ),
        )
      else if (users.isEmpty)
        const Text(
          'NO USERS',
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 6,
            color: kTextMuted,
          ),
        )
      else
        ...users.map(_userRow),
    ]);
  }

  Widget _userRow(String name) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(color: kSurface2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 11,
              color: kTextPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _miniBtn(
          'RESET',
          kAccentRed,
          () async {
            if (await _confirm('¿RESETEAR A $name?\nBorra su 11, cartas y puntos.')) {
              _run('reset $name', () => _svc.resetUser(name));
            }
          },
        ),
        _miniBtn(
          'CARDS',
          kAccentGreen,
          () => _run('give cards $name', () => _svc.giveRandomCards(name)),
        ),
        _miniBtn(
          'CLEAR',
          kTextMuted,
          () => _run('clear cards $name', () => _svc.clearCards(name)),
        ),
        _miniBtn(
          'LOGOUT',
          kAccentYellow,
          () => _run('logout $name', () => _svc.forceLogoutUser(name)),
        ),
      ],
    ),
  );

  Widget _miniBtn(String label, Color color, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: GestureDetector(
      onTap: _busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        color: color.withValues(alpha: 0.25),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 5,
            color: color == kTextMuted ? kTextMuted : color,
          ),
        ),
      ),
    ),
  );

  Widget _renameSection() => _section('RENAME USER', [
    DropdownButton<String>(
      value: _renameTarget,
      isExpanded: true,
      dropdownColor: kSurface,
      hint: const Text(
        'SELECT USER',
        style: TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: 6,
          color: kTextMuted,
        ),
      ),
      items: (_users ?? [])
          .map(
            (u) => DropdownMenuItem(
              value: u,
              child: Text(
                u,
                style: const TextStyle(
                  fontFamily: 'ChakraPetch',
                  fontSize: 11,
                  color: kTextPrimary,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => _renameTarget = v),
    ),
    const SizedBox(height: 8),
    TextField(
      controller: _newNameCtrl,
      style: const TextStyle(
        fontFamily: 'ChakraPetch',
        fontSize: 12,
        color: kTextPrimary,
      ),
      decoration: const InputDecoration(hintText: 'NEW NAME'),
    ),
    const SizedBox(height: 8),
    PixelButton(
      label: 'RENAME',
      fontSize: 11,
      onTap: _busy
          ? null
          : () {
              final target = _renameTarget;
              final newName = _newNameCtrl.text.trim();
              if (target == null || newName.isEmpty) {
                _append('✗ rename — select a user and enter a new name');
                return;
              }
              _run('rename $target -> $newName', () async {
                await _svc.renameUser(target, newName);
                _newNameCtrl.clear();
                _renameTarget = null;
                await _loadUsers();
              });
            },
    ),
  ]);

  Widget _resolutionSection() => _section('RESOLUTION (CI)', [
    const Text(
      'TRIGGERS THE GITHUB ACTIONS PIPELINE (SCORING / REWARDS). '
      'NEEDS A TOKEN WITH WORKFLOW SCOPE.',
      style: TextStyle(
        fontFamily: 'ChakraPetch',
        fontSize: 5,
        color: kTextMuted,
        height: 1.3,
      ),
    ),
    const SizedBox(height: 8),
    _field('OWNER', _ownerCtrl),
    _field('REPO', _repoCtrl),
    _field('WORKFLOW', _workflowCtrl),
    const SizedBox(height: 8),
    PixelButton(
      label: 'DISPATCH',
      color: kAccentBlue,
      fontSize: 11,
      onTap: _busy
          ? null
          : () => _run('dispatch workflow', () async {
              final status = await _svc.dispatchResolution(
                owner: _ownerCtrl.text.trim(),
                repo: _repoCtrl.text.trim(),
                workflowFile: _workflowCtrl.text.trim(),
              );
              if (status != 204) {
                throw Exception('HTTP $status (expected 204)');
              }
            }),
    ),
  ]);

  Widget _field(String label, TextEditingController ctrl) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 5,
              color: kTextMuted,
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: ctrl,
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 11,
              color: kTextPrimary,
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _systemSection() => _section('SYSTEM', [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        PixelButton(
          label: 'PLAYER IMAGES',
          color: kAccentYellow,
          fontSize: 11,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PlayerImagesAdminScreen()),
          ),
        ),
        PixelButton(
          label: 'CLEAR CACHE',
          color: kAccentBlue,
          fontSize: 11,
          onTap: () {
            ref.read(githubServiceProvider).clearCache();
            ref.invalidate(allUsersProvider);
            ref.invalidate(playersProvider);
            ref.invalidate(userProvider);
            _append('✓ cleared cache + invalidated providers');
          },
        ),
      ],
    ),
  ]);

  Widget _logPanel() => Container(
    height: 130,
    width: double.infinity,
    decoration: const BoxDecoration(
      color: Colors.black,
      border: Border(top: BorderSide(color: kAccentYellow, width: 2)),
    ),
    padding: const EdgeInsets.all(8),
    child: _log.isEmpty
        ? const Text(
            'LOG',
            style: TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 6,
              color: kTextDim,
            ),
          )
        : ListView(
            children: _log
                .map(
                  (l) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      l,
                      style: TextStyle(
                        fontFamily: 'ChakraPetch',
                        fontSize: 5,
                        height: 1.5,
                        color: l.startsWith('✗')
                            ? kAccentRed
                            : l.startsWith('✓')
                            ? kAccentGreen
                            : kTextMuted,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
  );
}
