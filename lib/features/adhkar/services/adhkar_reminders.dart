import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../l10n/app_localizations.dart';
import '../../prayer/data/adhan_catalog.dart';
import '../../prayer/data/adhan_downloads.dart';
import '../../prayer/domain/prayer_settings.dart';
import '../../prayer/services/prayer_native.dart';
import '../data/adhkar_data.dart';
import '../domain/adhkar_settings.dart';

/// Notification ids: the morning and evening reminders, then the salawat
/// (Apple notifications; Android uses the adhan alarms, from
/// [salawatNativeIdBase]). Clear of the prayer alerts (9100–9239), the
/// adhan test (9399) and the occasions (9400–9407).
const adhkarMorningId = 9410;
const adhkarEveningId = 9411;
const salawatAppleIdBase = 9420;
const salawatAppleMax = 8;
const salawatNativeIdBase = 9500;
const salawatNativeMax = 24;

const adhkarChannelId = 'app.tibyan.adhkar';

String adhkarPayload(AdhkarTime t) => 'tibyan://adhkar?tab=${t.name}';
const salawatPayload = 'tibyan://adhkar';

/// The next [minuteOfDay] after [now], in the device's time zone.
tz.TZDateTime nextAt(int minuteOfDay, tz.TZDateTime now) {
  var at = tz.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day,
    minuteOfDay ~/ 60,
    minuteOfDay % 60,
  );
  if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
  return at;
}

/// Android: the salawat reminders as adhan alarms, so they follow the
/// same rules: never over a call, and «عندما يكون الهاتف قيد الاستخدام».
List<NativeAdhan> salawatNatives(
  AdhkarSettings s,
  PrayerSettings prayer,
  AppLocalizations l,
  String? audio, {
  DateTime? now,
}) {
  if (audio == null) return const [];
  final times = planSalawat(s, now ?? DateTime.now(), limit: salawatNativeMax);
  return [
    for (var i = 0; i < times.length; i++)
      NativeAdhan(
        id: salawatNativeIdBase + i,
        at: times[i],
        title: l.salawatNoticeTitle,
        body: l.salawatAudioName,
        files: [audio],
        payload: salawatPayload,
        volume: prayer.adhanVolume,
        stopLabel: l.adhanStop,
        playLabel: l.adhanPlay,
        inUse: prayer.inUse.name,
        quiet: true,
      ),
  ];
}

/// Schedules the morning and evening reminders (all platforms with
/// notifications) and, on Apple, the salawat with its own sound.
class AdhkarReminders {
  AdhkarReminders({required this.plugin, required this.adhan});

  final Future<FlutterLocalNotificationsPlugin?> Function() plugin;
  final AdhanDownloads adhan;

  bool get _apple => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  NotificationDetails _details(String channelName, {String? sound}) {
    final darwin = DarwinNotificationDetails(sound: sound, presentSound: true);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        adhkarChannelId,
        channelName,
        icon: 'ic_stat_tibyan',
        color: const Color(0xFF0F6660),
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: darwin,
      macOS: darwin,
    );
  }

  Future<void> sync(AdhkarSettings s, AppLocalizations l) async {
    final fln = await plugin();
    if (fln == null) return;
    for (final id in [
      adhkarMorningId,
      adhkarEveningId,
      for (var i = 0; i < salawatAppleMax; i++) salawatAppleIdBase + i,
    ]) {
      await fln.cancel(id: id);
    }
    final now = tz.TZDateTime.now(tz.local);
    Future<void> daily(int id, int minute, String title, AdhkarTime t) async {
      try {
        await fln.zonedSchedule(
          id: id,
          scheduledDate: nextAt(minute, now),
          notificationDetails: _details(l.adhkarChannel),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          title: title,
          payload: adhkarPayload(t),
        );
      } catch (_) {
        // Refused by the system: the other reminders still go.
      }
    }

    if (s.morningOn) {
      await daily(
        adhkarMorningId,
        s.morningAt,
        l.adhkarMorningNotice,
        AdhkarTime.morning,
      );
    }
    if (s.eveningOn) {
      await daily(
        adhkarEveningId,
        s.eveningAt,
        l.adhkarEveningNotice,
        AdhkarTime.evening,
      );
    }
    if (!_apple || !s.salawatOn || !adhan.isInstalled(salawatSlug)) return;
    final sound = await _appleSound();
    if (sound == null) return;
    final times = planSalawat(s, DateTime.now(), limit: salawatAppleMax);
    for (var i = 0; i < times.length; i++) {
      try {
        await fln.zonedSchedule(
          id: salawatAppleIdBase + i,
          scheduledDate: tz.TZDateTime.from(times[i], tz.local),
          notificationDetails: _details(l.adhkarChannel, sound: sound),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: l.salawatNoticeTitle,
          body: l.salawatAudioName,
          payload: salawatPayload,
        );
      } catch (_) {}
    }
  }

  /// Copies the salawat's PCM cut where an Apple notification can play it.
  Future<String?> _appleSound() async {
    try {
      const name = 'tibyan_salawat.caf';
      final lib = await getLibraryDirectory();
      final dir = Directory(p.join(lib.path, 'Sounds'));
      await dir.create(recursive: true);
      final target = File(p.join(dir.path, name));
      if (!await target.exists()) {
        await (await adhan.fileOf(
          salawatSlug,
          'salawat_minshawi.caf',
        )).copy(target.path);
      }
      return name;
    } catch (_) {
      return null;
    }
  }
}
