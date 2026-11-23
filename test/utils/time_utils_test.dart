import 'package:flutter_test/flutter_test.dart';
import 'package:calcetto/models/daily.dart';
import 'package:calcetto/utils/app_clock.dart';
import 'package:calcetto/utils/time_utils.dart';

// A matchday whose cards window opens 12:00 and locks 18:00 on 2026-08-22 (an
// in-season Saturday). Phase boundaries derive from these datetimes.
DailyMatchday md() {
  DateTime d(int h, int m) => DateTime(2026, 8, 22, h, m);
  return DailyMatchday(
    matchday: 5,
    date: '2026-08-22',
    firstKickoff: d(18, 0).toIso8601String(),
    cardsOpen: d(12, 0).toIso8601String(),
    lockAt: d(18, 0).toIso8601String(),
    matches: const [],
    bets: const [],
  );
}

DateTime at(int h, int m) => DateTime(2026, 8, 22, h, m);

void main() {
  final m = md();

  setUp(() => setCurrentMatchday(m));
  tearDown(() => setCurrentMatchday(null));

  group('dayPhase boundaries (from matchday windows)', () {
    test('manage before cardsOpen', () {
      expect(dayPhase(at(9, 0), m), DayPhase.manage);
      expect(dayPhase(at(11, 59), m), DayPhase.manage);
    });
    test('cards between cardsOpen and lockAt', () {
      expect(dayPhase(at(12, 0), m), DayPhase.cards);
      expect(dayPhase(at(17, 59), m), DayPhase.cards);
    });
    test('games from lockAt', () {
      expect(dayPhase(at(18, 0), m), DayPhase.games);
      expect(dayPhase(at(23, 0), m), DayPhase.games);
    });
    test('no matchday → manage (editing open)', () {
      setCurrentMatchday(null);
      expect(dayPhase(at(20, 0)), DayPhase.manage);
    });
  });

  group('isPhaseBuffer (last 5 min before each boundary)', () {
    test('pre-cards buffer 11:55–12:00', () {
      expect(isPhaseBuffer(at(11, 55), m), isTrue);
      expect(isPhaseBuffer(at(11, 59), m), isTrue);
      expect(isPhaseBuffer(at(12, 0), m), isFalse);
      expect(isPhaseBuffer(at(11, 54), m), isFalse);
    });
    test('pre-lock buffer 17:55–18:00', () {
      expect(isPhaseBuffer(at(17, 55), m), isTrue);
      expect(isPhaseBuffer(at(17, 59), m), isTrue);
      expect(isPhaseBuffer(at(18, 0), m), isFalse);
    });
  });

  group('gating respects phase + buffer (reads the global matchday)', () {
    test('team editable only in manage, not its buffer', () {
      expect(isTeamLocked(at(10, 0)), isFalse); // manage
      expect(isTeamLocked(at(11, 57)), isTrue); // manage buffer
      expect(isTeamLocked(at(14, 0)), isTrue); // cards
      expect(isTeamLocked(at(20, 0)), isTrue); // games
    });
    test('betting open only in manage, not its buffer', () {
      expect(isBettingWindowOpen(at(10, 0)), isTrue);
      expect(isBettingWindowOpen(at(11, 57)), isFalse);
      expect(isBettingWindowOpen(at(14, 0)), isFalse);
    });
    test('cards playable only in cards phase, not its buffer', () {
      expect(isCardsWindowOpen(at(14, 0)), isTrue);
      expect(isCardsWindowOpen(at(17, 57)), isFalse); // cards buffer
      expect(isCardsWindowOpen(at(10, 0)), isFalse); // manage
      expect(isCardsExpired(at(19, 0)), isTrue); // games
    });
  });

  group('pre-season', () {
    DateTime pre(int h, int mm) => DateTime(2026, 8, 1, h, mm);
    test('editing always open before the season', () {
      expect(isPreSeason(pre(20, 0)), isTrue);
      expect(isTeamLocked(pre(20, 0)), isFalse);
      expect(isBettingWindowOpen(pre(3, 0)), isTrue);
    });
    test('season start date is no longer pre-season', () {
      expect(isPreSeason(DateTime(2026, 8, 14, 9, 0)), isFalse);
    });
  });
}
