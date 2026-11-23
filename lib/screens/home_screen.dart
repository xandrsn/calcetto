import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/game_state_provider.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import '../services/notifications.dart';
import '../utils/app_clock.dart';
import 'tabs/home_tab.dart';
import 'tabs/squad_tab.dart';
import 'tabs/cards_tab.dart';
import 'tabs/daily_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  int _tab = 0;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Central cross-device poller (runs for every tab): keeps ownership %s
    // (allUsers) and the admin's simulated clock in sync across devices.
    _poller = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      ref.read(allUsersProvider.notifier).poll();
      ref.invalidate(clockSyncProvider);
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(githubServiceProvider).clearCache();
      ref.invalidate(playersProvider);
      ref.invalidate(currentMatchdayNumberProvider);
      ref.invalidate(currentMatchdayProvider);
      ref.invalidate(activityLogProvider);
      ref.invalidate(chatProvider);
      ref.invalidate(clockSyncProvider);
      ref.read(allUsersProvider.notifier).poll();
      ref.read(userProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Apply the admin's simulated clock (from the backend) on this device when it
    // changes — via listen (not watch) so we mutate clockProvider outside build.
    ref.listen(clockSyncProvider, (prev, next) {
      applyClockOverrideFromRemote(ref, next.valueOrNull);
    });
    ref.watch(clockSyncProvider); // keep it alive + re-run on invalidate
    // Publish the current matchday to the global phase logic (time_utils reads it
    // via app_clock.currentMatchday) — via listen so we set it outside build.
    ref.listen(currentMatchdayProvider, (prev, next) {
      setCurrentMatchday(next.valueOrNull);
      NotificationService.scheduleMatchday(next.valueOrNull);
    });
    setCurrentMatchday(ref.watch(currentMatchdayProvider).valueOrNull);
    final tabs = [
      const HomeTab(),
      const SquadTab(),
      const CardsTab(),
      const DailyTab(),
    ];

    return Scaffold(
      body: IndexedStack(index: _tab, children: tabs),
      bottomNavigationBar: _PixelNavBar(
        current: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}

class _PixelNavBar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;

  const _PixelNavBar({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('HOME', Icons.home),
      ('MI 11', Icons.grass),
      ('CARTAS', Icons.style),
      ('PARTIDOS', Icons.sports_soccer),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kBorder, width: 1)),
      ),
      child: SafeArea(
        child: Row(
          children: List.generate(items.length, (i) {
            final selected = i == current;
            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: selected ? kAccentGreen : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        items[i].$2,
                        color: selected ? kAccentGreen : kTextMuted,
                        size: 22,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items[i].$1,
                        style: TextStyle(
                          fontFamily: kFontUI,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: selected ? kAccentGreen : kTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
