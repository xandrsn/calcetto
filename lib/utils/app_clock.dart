import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/daily.dart';

/// The app's clock. **All matchday-phase logic** (prep/cards/matches windows,
/// team/captain locks, betting, "today") reads time through [appNow], so it is
/// always evaluated in **Europe/Madrid** wall-clock time — never the device's
/// local timezone. This means users abroad see exactly the same phase as users
/// in Spain.
///
/// Live UI timers and real event timestamps keep using `DateTime.now()`.

tz.Location? _madrid;

/// Initializes timezone data and resolves Europe/Madrid. Call once from `main`
/// before the app reads the clock. Idempotent and safe on every platform.
void initAppClock() {
  if (_madrid != null) return;
  tzdata.initializeTimeZones();
  _madrid = tz.getLocation('Europe/Madrid');
}

/// A test/admin override for "now", interpreted as a Madrid wall-clock time.
/// `null` means use the real Madrid time.
DateTime? _override;

/// "Now" as Madrid wall-clock time, or the admin override when set.
///
/// The returned value's component accessors (`.hour`, `.minute`, `.year`, …)
/// are Madrid wall-clock — that is what the phase logic reads. Falls back to
/// `DateTime.now()` only if [initAppClock] hasn't run yet.
DateTime appNow() {
  if (_override != null) return _override!;
  final madrid = _madrid;
  if (madrid != null) return tz.TZDateTime.now(madrid);
  return DateTime.now();
}

DateTime? get clockOverride => _override;

/// Mirrors [_override] so widgets can `watch` it and rebuild when the simulated
/// time changes. Always update both together via [applyClockOverride].
final clockProvider = StateProvider<DateTime?>((ref) => null);

/// Sets (or clears, with null) the simulated time and notifies watchers.
/// Local only — the admin caller also persists it to the backend so every
/// device converges (see clockSyncProvider).
void applyClockOverride(WidgetRef ref, DateTime? when) {
  _override = when;
  ref.read(clockProvider.notifier).state = when;
}

/// Applies a remotely-sourced override (from `data/app_config.json`) so every
/// device follows the admin's simulated clock. No-op if unchanged. Called from a
/// widget `ref.listen` (WidgetRef), never inside a provider build.
void applyClockOverrideFromRemote(WidgetRef ref, DateTime? when) {
  if (when == _override) return;
  _override = when;
  ref.read(clockProvider.notifier).state = when;
}

/// The matchday currently driving the phase windows (manage/cards/games), or
/// null between matchdays / pre-season. The phase logic in `time_utils.dart`
/// reads this by default so call sites need not thread the matchday through.
/// Set from a widget `ref.listen` on `currentMatchdayProvider` (see HomeScreen),
/// mirroring how the clock override is applied — never inside a provider build.
DailyMatchday? _currentMatchday;

DailyMatchday? currentMatchday() => _currentMatchday;

void setCurrentMatchday(DailyMatchday? md) => _currentMatchday = md;
