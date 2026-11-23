import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/daily.dart';

/// A reminder to show at [at] (wall-clock instant) with the given copy.
typedef PhaseReminder = ({int id, DateTime at, String title, String body});

/// The reminders still in the future for [md], given the current time [now].
/// Phases are data-driven per matchday (cards open / lock), so reminders are
/// one-off per matchday, not a fixed daily clock. Pure, so it is unit-testable.
List<PhaseReminder> matchdayReminderPlan(DailyMatchday md, DateTime now) {
  final plan = <PhaseReminder>[
    if (md.cardsOpenTime != null)
      (
        id: 1,
        at: md.cardsOpenTime!,
        title: 'Abre tu sobre',
        body: 'Ventana de cartas abierta: juega tus cartas.',
      ),
    if (md.lockAtTime != null)
      (
        id: 2,
        at: md.lockAtTime!,
        title: '¡Empiezan los partidos!',
        body: 'Alineaciones bloqueadas. Sigue tus puntos en directo.',
      ),
  ];
  return plan.where((r) => r.at.isAfter(now)).toList();
}

/// Android-only local reminders for the current matchday's phase changes
/// (cards window opens, games lock). Best-effort; no-op on other platforms.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationDetails _details = AndroidNotificationDetails(
    'calcetto_phases',
    'Recordatorios',
    channelDescription: 'Avisos al abrir cada fase de la jornada',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  static Future<void> init() async {
    if (!_supported) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Madrid'));

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {
      // Notifications are best-effort; never block app startup on them.
    }
  }

  /// Replaces any scheduled reminders with the future phase changes of [md].
  static Future<void> scheduleMatchday(DailyMatchday? md) async {
    if (!_supported || md == null) return;
    try {
      await _plugin.cancelAll();
      for (final r in matchdayReminderPlan(md, DateTime.now())) {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: const NotificationDetails(android: _details),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      // Best-effort, see [init].
    }
  }
}
