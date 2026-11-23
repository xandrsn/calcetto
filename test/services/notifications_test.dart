import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/models/daily.dart';
import 'package:calcetto/services/notifications.dart';

DailyMatchday _md({required String cardsOpen, required String lockAt}) =>
    DailyMatchday(
      matchday: 5,
      date: '2026-10-03',
      firstKickoff: '2026-10-03T13:00:00+02:00',
      cardsOpen: cardsOpen,
      lockAt: lockAt,
      matches: const [],
      bets: const [],
    );

void main() {
  group('matchdayReminderPlan', () {
    final md = _md(
      cardsOpen: '2026-10-03T11:00:00Z',
      lockAt: '2026-10-03T11:55:00Z',
    );

    test('schedules both phase changes when both are still ahead', () {
      final plan = matchdayReminderPlan(md, DateTime.utc(2026, 10, 1));
      expect(plan.map((r) => r.id), [1, 2]);
      expect(plan[0].at, DateTime.utc(2026, 10, 3, 11));
      expect(plan[1].at, DateTime.utc(2026, 10, 3, 11, 55));
    });

    test('drops reminders that already passed', () {
      final plan = matchdayReminderPlan(md, DateTime.utc(2026, 10, 3, 11, 30));
      expect(plan.map((r) => r.id), [2]);
    });

    test('nothing left once the matchday is locked', () {
      expect(matchdayReminderPlan(md, DateTime.utc(2026, 10, 4)), isEmpty);
    });

    test('skips a reminder whose time is unparseable', () {
      final bad = _md(cardsOpen: 'not-a-date', lockAt: '2026-10-03T11:55:00Z');
      final plan = matchdayReminderPlan(bad, DateTime.utc(2026, 10, 1));
      expect(plan.map((r) => r.id), [2]);
    });
  });
}
