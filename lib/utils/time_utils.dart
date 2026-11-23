import '../models/daily.dart';
import 'app_clock.dart';

/// Each matchday (jornada) is split into three phases so the rules never clash.
/// Unlike the old World-Cup daily clock (fixed 08:30/13:00/17:00 every day), the
/// boundaries are **data-driven** from the current matchday's real fixture
/// datetimes ([DailyMatchday.cardsOpen] / [DailyMatchday.lockAt]), read from the
/// global [currentMatchday] (see `app_clock.dart`). This makes midweek rounds and
/// postponed matches work without special-casing. All times are Europe/Madrid
/// via [appNow].
///
///   manage   … until cardsOpen   edit team, buy/sell, set captain, bets, Quiniela.
///   cards    cardsOpen … lockAt   open card packs and play cards (own + rivals).
///   games    from lockAt          everything locked; matches play, points resolve.
///
/// The last [kPhaseBufferMinutes] before each boundary is a locked buffer for the
/// server scripts (see [isPhaseBuffer]); the UI shows "ACTUALIZANDO".
///
/// Between matchdays / before the season, there is no current matchday and
/// editing is always open (manage).
enum DayPhase { manage, cards, games }

/// Length of the script buffer just before each phase boundary, in minutes.
const int kPhaseBufferMinutes = 5;

/// The season starts on this Madrid date; before it, editing is always open.
final DateTime _seasonStart = DateTime(2026, 8, 14);

bool isPreSeason([DateTime? at]) {
  final now = at ?? appNow();
  final today = DateTime(now.year, now.month, now.day);
  return today.isBefore(_seasonStart);
}

/// Phase for [md] (defaults to the global [currentMatchday]) at [at]. Before
/// `cardsOpen` → manage; `cardsOpen`..`lockAt` → cards; from `lockAt` → games.
/// No matchday → manage (editing open).
DayPhase dayPhase([DateTime? at, DailyMatchday? md]) {
  md ??= currentMatchday();
  if (md == null) return DayPhase.manage;
  final now = at ?? appNow();
  final lock = md.lockAtTime;
  final cards = md.cardsOpenTime;
  if (lock != null && !now.isBefore(lock)) return DayPhase.games;
  if (cards != null && !now.isBefore(cards)) return DayPhase.cards;
  return DayPhase.manage;
}

/// True during the [kPhaseBufferMinutes] just before the cards/lock boundaries —
/// a short locked window for the server scripts. UI shows "ACTUALIZANDO".
bool isPhaseBuffer([DateTime? at, DailyMatchday? md]) {
  md ??= currentMatchday();
  if (md == null) return false;
  final now = at ?? appNow();
  bool before(DateTime? b) =>
      b != null &&
      !now.isBefore(b.subtract(const Duration(minutes: kPhaseBufferMinutes))) &&
      now.isBefore(b);
  return before(md.cardsOpenTime) || before(md.lockAtTime);
}

/// Team / captain / bet / Quiniela edits are allowed only in the manage phase
/// (outside its buffer) — and freely pre-season or between matchdays.
bool isTeamLocked([DateTime? at]) {
  final now = at ?? appNow();
  if (isPreSeason(now)) return false;
  if (currentMatchday() == null) return false;
  return dayPhase(now) != DayPhase.manage || isPhaseBuffer(now);
}

bool isCaptainLocked([DateTime? at]) => isTeamLocked(at);

bool isBettingWindowOpen([DateTime? at]) {
  final now = at ?? appNow();
  if (isPreSeason(now)) return true;
  if (currentMatchday() == null) return true;
  return dayPhase(now) == DayPhase.manage && !isPhaseBuffer(now);
}

/// Cards can be opened/played only in the cards phase, outside its buffer.
bool isCardsWindowOpen([DateTime? at]) {
  final now = at ?? appNow();
  return dayPhase(now) == DayPhase.cards && !isPhaseBuffer(now);
}

bool isCardsExpired([DateTime? at]) => dayPhase(at) == DayPhase.games;

/// Games phase: cards/points are resolved, so the live % shows real values.
bool isResolutionTime([DateTime? at]) => dayPhase(at) == DayPhase.games;

String todayString() {
  final now = appNow();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String formatTimestamp(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$d/$mo $h:$m';
  } catch (_) {
    return iso;
  }
}
