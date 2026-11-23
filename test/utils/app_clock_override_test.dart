import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calcetto/models/daily.dart';
import 'package:calcetto/utils/app_clock.dart';
import 'package:calcetto/utils/time_utils.dart';

// A matchday whose cards window opens 13:00 and locks 17:00 on an in-season day.
DailyMatchday _md() {
  DateTime d(int h, int m) => DateTime(2026, 8, 22, h, m);
  return DailyMatchday(
    matchday: 3,
    date: '2026-08-22',
    firstKickoff: d(17, 0).toIso8601String(),
    cardsOpen: d(13, 0).toIso8601String(),
    lockAt: d(17, 0).toIso8601String(),
    matches: const [],
    bets: const [],
  );
}

/// Proves the admin "change the time" control still works end-to-end:
/// applyClockOverride → appNow() → the phase logic, and that clearing it
/// returns to real time. The override is applied from a live tapped button —
/// the exact pattern the admin TIME buttons use.
void main() {
  testWidgets('admin clock override drives the phase and clears', (
    tester,
  ) async {
    DateTime? pending;
    await tester.pumpWidget(
      ProviderScope(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Consumer(
            builder: (_, ref, _) => GestureDetector(
              onTap: () => applyClockOverride(ref, pending),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    Future<void> jumpTo(DateTime? when) async {
      pending = when;
      await tester.tap(find.text('go'));
      await tester.pump();
    }

    // Phases derive from the current matchday's windows (cards 13:00, lock 17:00).
    setCurrentMatchday(_md());

    // Ensure the global clock + matchday are reset even if an assertion fails.
    addTearDown(() async {
      pending = null;
      setCurrentMatchday(null);
      if (find.text('go').evaluate().isNotEmpty) {
        await tester.tap(find.text('go'));
      }
    });

    // PREP (10:00) — editable.
    await jumpTo(DateTime(2026, 8, 22, 10, 0));
    expect(clockOverride, isNotNull);
    expect(dayPhase(appNow()), DayPhase.manage);
    expect(isTeamLocked(appNow()), isFalse);

    // CARDS (14:00) — cards open.
    await jumpTo(DateTime(2026, 8, 22, 14, 0));
    expect(dayPhase(appNow()), DayPhase.cards);
    expect(isCardsWindowOpen(appNow()), isTrue);

    // BUFFER (12:57) — locked, pre-cards buffer.
    await jumpTo(DateTime(2026, 8, 22, 12, 57));
    expect(dayPhase(appNow()), DayPhase.manage);
    expect(isPhaseBuffer(appNow()), isTrue);
    expect(isTeamLocked(appNow()), isTrue);

    // MATCHES (18:00).
    await jumpTo(DateTime(2026, 8, 22, 18, 0));
    expect(dayPhase(appNow()), DayPhase.games);

    // NEXT DAY drives "today".
    await jumpTo(DateTime(2026, 8, 23, 9, 0));
    expect(todayString(), '2026-08-23');

    // REAL TIME clears the override.
    await jumpTo(null);
    expect(clockOverride, isNull);
  });
}
