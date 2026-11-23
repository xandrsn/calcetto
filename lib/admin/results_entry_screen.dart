import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily.dart';
import '../providers/game_state_provider.dart';
import '../providers/league_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import 'admin_service.dart';

/// Admin screen to enter per-player goals/assists/**ratings** and per-bet
/// answers for a matchday, then apply + score it (see SCORING.md).
class ResultsEntryScreen extends ConsumerStatefulWidget {
  final String mdKey; // e.g. 'md05'
  const ResultsEntryScreen({super.key, required this.mdKey});

  @override
  ConsumerState<ResultsEntryScreen> createState() => _ResultsEntryScreenState();
}

class _ResultsEntryScreenState extends ConsumerState<ResultsEntryScreen> {
  DailyMatchday? _daily;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  // fixtureId -> [home, away] final scoreline (drives table + Quiniela).
  final _scores = <String, List<int>>{};
  // pid -> [goals, assists]
  final _ga = <String, List<int>>{};
  // pid -> rating (1–10, one decimal). Team scoring is rating-based.
  final _ratings = <String, double>{};
  // betId -> chosen correct option.
  final _betAnswers = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(adminServiceProvider).loadDaily(widget.mdKey);
      if (!mounted) return;
      if (d == null) {
        setState(() {
          _loading = false;
          _error = 'No hay jornada ${widget.mdKey}. Créala primero.';
        });
        return;
      }
      for (final m in d.matches) {
        final g = m.goals;
        if (g != null) _scores[m.id] = [g[0], g[1]];
        for (final p in m.players) {
          _ga[p.id] = [p.goals, p.assists];
          if (p.rating != null) _ratings[p.id] = p.rating!;
        }
      }
      for (final b in d.bets) {
        if (b.answer != null) _betAnswers[b.id] = b.answer!;
      }
      setState(() {
        _daily = d;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _apply() async {
    // Scoring accumulates onto each user's points — running it twice double-counts.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: kAccentRed, width: 2),
          borderRadius: BorderRadius.zero,
        ),
        content: const Text(
          '¿APLICAR Y PUNTUAR?\nSuma puntos a todos — NO lo ejecutes dos veces '
          'para la misma jornada.',
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 12,
            color: kTextPrimary,
            height: 1.3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('NO',
                style: TextStyle(fontFamily: 'ChakraPetch', color: kTextMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SÍ',
                style: TextStyle(fontFamily: 'ChakraPetch', color: kAccentRed)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final summary = await ref.read(adminServiceProvider).applyResultsAndScore(
            mdKey: widget.mdKey,
            matchScores: _scores,
            goalsAssists: _ga,
            ratings: _ratings,
            betAnswers: _betAnswers,
          );
      ref.read(githubServiceProvider).clearCache();
      ref.invalidate(allUsersProvider);
      ref.invalidate(currentMatchdayProvider);
      ref.invalidate(leagueProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              summary,
              style: const TextStyle(fontFamily: 'ChakraPetch', fontSize: 11),
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
              style: const TextStyle(fontFamily: 'ChakraPetch', fontSize: 11),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final p in ref.watch(playersProvider).valueOrNull ?? const [])
        p.id: p.name,
    };
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        title: Text(
          'RESULTS ${widget.mdKey.toUpperCase()}',
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 13,
            color: kAccentYellow,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(color: kAccentYellow, height: 2),
        ),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : Column(
              children: [
                if (_busy)
                  const LinearProgressIndicator(
                    color: kAccentYellow,
                    minHeight: 3,
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(10),
                    children: [
                      for (final m in _daily!.matches) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            '${m.home} vs ${m.away}',
                            style: const TextStyle(
                              fontFamily: 'ChakraPetch',
                              fontSize: 12,
                              color: kAccentGreen,
                            ),
                          ),
                        ),
                        _scoreRow(m.id),
                        for (final p in m.players)
                          _playerRow(p.id, names[p.id] ?? p.id),
                      ],
                      _betsSection(),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: GestureDetector(
                      onTap: _busy ? null : _apply,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        color: _busy ? kTextDim : kAccentGreen,
                        child: const Text(
                          'APLICAR Y PUNTUAR',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'ChakraPetch',
                            fontSize: 13,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Final scoreline for a fixture (drives the league table + Quiniela signs).
  Widget _scoreRow(String fixtureId) {
    final sc = _scores[fixtureId] ?? [0, 0];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: kSurface2),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'RESULTADO',
              style: TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 8,
                color: kAccentYellow,
              ),
            ),
          ),
          _counter('L', sc[0], (v) => setState(() => _scores[fixtureId] = [v, sc[1]])),
          const SizedBox(width: 6),
          _counter('V', sc[1], (v) => setState(() => _scores[fixtureId] = [sc[0], v])),
        ],
      ),
    );
  }

  Widget _playerRow(String pid, String name) {
    final ga = _ga[pid] ?? [0, 0];
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: kSurface2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'ChakraPetch',
                fontSize: 6,
                color: kTextPrimary,
              ),
            ),
          ),
          _ratingField(pid),
          const SizedBox(width: 6),
          _counter('G', ga[0], (v) => setState(() => _ga[pid] = [v, ga[1]])),
          const SizedBox(width: 6),
          _counter('A', ga[1], (v) => setState(() => _ga[pid] = [ga[0], v])),
        ],
      ),
    );
  }

  /// Rating 1–10 (one decimal) for team scoring. Free-text so any rating loads
  /// cleanly; clamped to 0–10 on parse.
  Widget _ratingField(String pid) {
    return Row(
      children: [
        const Text(
          'R',
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 6,
            color: kAccentYellow,
          ),
        ),
        const SizedBox(width: 3),
        SizedBox(
          width: 34,
          height: 22,
          child: TextFormField(
            initialValue: _ratings[pid]?.toStringAsFixed(1),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 12,
              color: kTextPrimary,
            ),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '—',
              contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            ),
            onChanged: (s) {
              final v = double.tryParse(s.replaceAll(',', '.'));
              if (v == null) {
                _ratings.remove(pid);
              } else {
                _ratings[pid] = v.clamp(0, 10).toDouble();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _betsSection() {
    final bets = _daily?.bets ?? const [];
    if (bets.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'APUESTAS — ELIGE LA RESPUESTA CORRECTA',
            style: TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 12,
              color: kAccentGreen,
            ),
          ),
        ),
        for (final b in bets)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: kSurface2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.question,
                  style: const TextStyle(
                    fontFamily: 'ChakraPetch',
                    fontSize: 11,
                    color: kTextPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final opt in b.options)
                      GestureDetector(
                        onTap: () =>
                            setState(() => _betAnswers[b.id] = opt),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _betAnswers[b.id] == opt
                                ? kAccentGreen.withValues(alpha: 0.3)
                                : kSurface,
                            border: Border.all(
                              color: _betAnswers[b.id] == opt
                                  ? kAccentGreen
                                  : kAccentBlue.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            opt,
                            style: TextStyle(
                              fontFamily: 'ChakraPetch',
                              fontSize: 6,
                              color: _betAnswers[b.id] == opt
                                  ? kAccentGreen
                                  : kTextPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _counter(String label, int value, ValueChanged<int> onChanged) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'ChakraPetch',
            fontSize: 6,
            color: kTextMuted,
          ),
        ),
        _miniBtn('-', value > 0 ? () => onChanged(value - 1) : null),
        SizedBox(
          width: 16,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'ChakraPetch',
              fontSize: 12,
              color: kTextPrimary,
            ),
          ),
        ),
        _miniBtn('+', () => onChanged(value + 1)),
      ],
    );
  }

  Widget _miniBtn(String s, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      color: onTap == null ? kSurface : kAccentBlue.withValues(alpha: 0.4),
      child: Text(
        s,
        style: TextStyle(
          fontFamily: 'ChakraPetch',
          fontSize: 13,
          color: onTap == null ? kTextDim : kAccentGreen,
        ),
      ),
    ),
  );
}
