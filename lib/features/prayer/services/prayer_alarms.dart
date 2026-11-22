import 'dart:async';
import 'dart:io';
import 'dart:ui' show Color, Locale;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../l10n/app_localizations.dart';
import '../../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../data/adhan_catalog.dart';
import '../data/adhan_downloads.dart';
import '../domain/prayer_calc.dart';
import '../domain/prayer_plan.dart';
import '../domain/prayer_settings.dart';
import 'prayer_native.dart';

/// The name of a time in the interface language.
String prayerName(AppLocalizations l, PrayerKind p) => switch (p) {
  PrayerKind.fajr => l.prayerFajr,
  PrayerKind.shuruq => l.prayerShuruq,
  PrayerKind.duha => l.prayerDuha,
  PrayerKind.dhuhr => l.prayerDhuhr,
  PrayerKind.asr => l.prayerAsr,
  PrayerKind.maghrib => l.prayerMaghrib,
  PrayerKind.isha => l.prayerIsha,
};

/// A time of day at the place, in the interface language («٤:٥٩ م»).
String formatPrayerTime(AppLocalizations l, DateTime at, PrayerPlace place) {
  final local = tz.TZDateTime.from(at.toUtc(), locationOf(place));
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final m = local.minute.toString().padLeft(2, '0');
  final digits = NumberFormatter(Locale(l.localeName));
  return '${digits.decimal('$h:$m')} ${local.hour < 12 ? l.timeAm : l.timePm}';
}

/// The link a prayer alert opens.
String alertPayload(PlannedAlert a) => a.kind == AlertKind.atTime
    ? 'tibyan://prayer/adhan?p=${a.prayer.name}'
          '&at=${a.prayerAt.millisecondsSinceEpoch}'
    : 'tibyan://prayer';

/// An alert's title and body.
({String title, String body}) alertTexts(
  AppLocalizations l,
  PlannedAlert a,
  PrayerPlace place,
) {
  final city = place.label(l.localeName == 'ar');
  final time = formatPrayerTime(l, a.prayerAt, place);
  final name = prayerName(l, a.prayer);
  final n = NumberFormatter(Locale(l.localeName))(a.minutes);
  return switch (a.kind) {
    AlertKind.atTime when a.ramadan => (
      title: l.prayerIftarNow,
      body: '$city · $time',
    ),
    AlertKind.atTime
        when a.prayer == PrayerKind.shuruq || a.prayer == PrayerKind.duha =>
      (title: l.prayerTimeOf(name), body: '$city · $time'),
    AlertKind.atTime => (title: l.prayerAdhanNow(name), body: '$city · $time'),
    AlertKind.before => (
      title: l.prayerBefore(a.minutes, n, name),
      body: '$city · $time',
    ),
    AlertKind.suhoor => (
      title: l.prayerBeforeImsak(a.minutes, n),
      body: '${l.prayerFajr} $time · $city',
    ),
    AlertKind.iftar => (
      title: l.prayerBeforeIftar(a.minutes, n),
      body: '${l.prayerMaghrib} $time · $city',
    ),
  };
}

/// Which downloaded recording an adhan plays: the chosen muezzin when it
/// is on the device, else the default one when it is, else none (the
/// alert then sounds the gentle tone). Never a server link.
String? adhanSlugFor(String chosen, bool Function(String slug) installed) {
  if (installed(chosen)) return chosen;
  if (installed(PrayerSettings.defaultMuezzin)) {
    return PrayerSettings.defaultMuezzin;
  }
  return null;
}

/// Schedules the prayer alerts on the device. Nothing runs in the
/// background to keep them: they are planned [prayerDaysAhead] days ahead
/// and planned again whenever the app opens or a setting changes.
///
/// - iOS and macOS: plain scheduled notifications. An adhan alert's sound
///   is the muezzin's short cut (`short.caf`, under 30 s) copied into
///   Library/Sounds; the full adhan plays only in the app (a tap on the
///   alert, or the app in front).
/// - Android: an adhan alert is an exact alarm that starts the adhan
///   service (MediaSession, «إيقاف», the power key stops it). Without the
///   exact-alarm permission it falls back to a notification with the tone.
/// - Windows: scheduled toasts as a fallback for the tray's adhan.
/// - Linux: the tray plays it; no system schedule.
class PrayerAlarms {
  PrayerAlarms({
    required this.plugin,
    required this.native,
    required this.adhan,
  });

  /// The shared notifications plugin, or null where there is none.
  final Future<FlutterLocalNotificationsPlugin?> Function() plugin;
  final PrayerNative native;
  final AdhanDownloads adhan;

  static const _silent = 'app.tibyan.prayer.silent';
  static const _tone = 'app.tibyan.prayer.tone';
  static const _reminder = 'app.tibyan.prayer.reminder';

  bool get _apple => Platform.isIOS || Platform.isMacOS;

  /// The files the adhan plays (the cut or the whole adhan, then the dua
  /// when chosen), or none when the recording is not on the device.
  Future<List<String>> adhanFiles(PrayerSettings s, {bool? full}) async {
    final slug = adhanSlugFor(s.muezzin, adhan.isInstalled);
    if (slug == null) return const [];
    final whole = full ?? s.length == AdhanLength.full;
    final main = await adhan.fileOf(slug, whole ? 'full.m4a' : 'short.m4a');
    if (!await main.exists()) return const [];
    final dua = await adhan.fileOf(duaSlug, 'dua_shaarawy.m4a');
    return [
      main.path,
      if (s.duaAfter && adhan.isInstalled(duaSlug) && await dua.exists())
        dua.path,
    ];
  }

  /// Apple: copies the muezzin's PCM cut where the notification can play
  /// it; its name changes with the muezzin (the system caches sounds by
  /// name). Null when it is not downloaded.
  Future<String?> _appleSound(String slug) async {
    if (!adhan.isInstalled(slug)) return null;
    try {
      final name = 'tibyan_adhan_$slug.caf';
      final lib = await getLibraryDirectory();
      final dir = Directory(p.join(lib.path, 'Sounds'));
      await dir.create(recursive: true);
      final target = File(p.join(dir.path, name));
      if (!await target.exists()) {
        await (await adhan.fileOf(slug, 'short.caf')).copy(target.path);
      }
      // Older muezzins' sounds are removed.
      await for (final f in dir.list()) {
        final b = p.basename(f.path);
        if (b.startsWith('tibyan_adhan_') && b != name) await f.delete();
      }
      return name;
    } catch (_) {
      return null;
    }
  }

  NotificationDetails _details(
    AlertSound sound, {
    required bool reminder,
    String? appleSound,
    required String channelName,
  }) {
    final channel = reminder
        ? _reminder
        : sound == AlertSound.silent
        ? _silent
        : _tone;
    final android = AndroidNotificationDetails(
      channel,
      channelName,
      icon: 'ic_stat_tibyan',
      color: const Color(0xFF0F6660),
      importance: sound == AlertSound.silent ? Importance.low : Importance.high,
      priority: sound == AlertSound.silent ? Priority.low : Priority.high,
      playSound: sound != AlertSound.silent,
      category: AndroidNotificationCategory.reminder,
    );
    final adhanSound = sound == AlertSound.adhan ? appleSound : null;
    final darwin = DarwinNotificationDetails(
      presentSound: sound != AlertSound.silent && adhanSound == null,
      // In the background the alert sounds; in front, the app plays the
      // full adhan itself instead of the cut.
      sound: adhanSound,
    );
    return NotificationDetails(
      android: android,
      iOS: darwin,
      macOS: darwin,
      windows: WindowsNotificationDetails(
        audio: sound == AlertSound.silent
            ? WindowsNotificationAudio.silent()
            : null,
      ),
    );
  }

  /// Plans and schedules every alert again; cancels them all when prayer
  /// times are off. Returns what was planned.
  Future<List<PlannedAlert>> sync(
    PrayerSettings s,
    AppLocalizations l, {
    DateTime? now,
  }) async {
    final when = now ?? DateTime.now();
    final apple = _apple;
    final slug = adhanSlugFor(s.muezzin, adhan.isInstalled);
    final adhanReady = slug != null;
    final plan = planAlerts(
      settings: s,
      now: when,
      adhanReady: adhanReady,
      limit: apple ? appleMaxPrayerAlerts : null,
    );
    final place = s.place;
    final fln = await plugin();
    if (fln != null) {
      final pending = await fln.pendingNotificationRequests();
      for (final r in pending) {
        if (r.id >= prayerIdBase && r.id < prayerIdLimit) {
          await fln.cancel(id: r.id);
        }
      }
    }
    var exact = false;
    if (Platform.isAndroid) exact = await native.canScheduleExact();
    final natives = <NativeAdhan>[];
    if (place == null || plan.isEmpty) {
      await native.scheduleAdhans(const []);
      return plan;
    }
    final files = await adhanFiles(s);
    final appleSound = apple && slug != null ? await _appleSound(slug) : null;
    for (final a in plan) {
      final t = alertTexts(l, a, place);
      if (Platform.isAndroid &&
          exact &&
          a.kind == AlertKind.atTime &&
          a.sound == AlertSound.adhan &&
          files.isNotEmpty) {
        natives.add(
          NativeAdhan(
            id: a.id,
            at: a.at,
            title: t.title,
            body: t.body,
            files: files,
            payload: alertPayload(a),
            volume: s.adhanVolume,
            stopLabel: l.adhanStop,
          ),
        );
        continue;
      }
      if (fln == null) continue;
      var sound = a.sound;
      if (sound == AlertSound.adhan && !apple) sound = AlertSound.tone;
      try {
        await fln.zonedSchedule(
          id: a.id,
          scheduledDate: tz.TZDateTime.from(a.at, tz.UTC),
          notificationDetails: _details(
            sound,
            reminder: a.kind != AlertKind.atTime,
            appleSound: appleSound,
            channelName: a.kind == AlertKind.atTime
                ? l.prayerChannel
                : l.prayerReminderChannel,
          ),
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          title: t.title,
          body: t.body,
          payload: alertPayload(a),
        );
      } catch (_) {
        // One alert the system refused: the others still go.
      }
    }
    await native.scheduleAdhans(natives);
    return plan;
  }

  /// How long after «جرّب الأذان» the test alert fires.
  static const testDelay = Duration(seconds: 10);

  /// «جرّب الأذان»: the chosen adhan (full or short, then the dua when on)
  /// through the same path as a real alert, [testDelay] from now. Android:
  /// the exact alarm and the adhan service. Apple: a notification with the
  /// short cut as its sound (heard in front too). Desktop: the app plays
  /// it. Returns when it is scheduled.
  Future<void> testAdhan(
    PrayerSettings s,
    AppLocalizations l, {
    required Future<void> Function() playInApp,
  }) async {
    final at = DateTime.now().add(testDelay);
    final files = await adhanFiles(s);
    // A test never claims a real prayer time: its own title, the next
    // prayer's scene.
    final place = s.place;
    final scene = place == null
        ? PrayerKind.maghrib
        : nextPrayer(place, DateTime.now(), s)?.prayer ?? PrayerKind.maghrib;
    final title = l.adhanTestBody;
    final slugNow = adhanSlugFor(s.muezzin, adhan.isInstalled);
    final body = slugNow == null
        ? l.soundTone
        : l.adhanByMuezzin(muezzinOf(slugNow).name(l.localeName == 'ar'));
    final payload = 'tibyan://prayer/adhan?p=${scene.name}&test=1';
    if (Platform.isAndroid) {
      await native.testAdhan(
        NativeAdhan(
          id: prayerTestId,
          at: at,
          title: title,
          body: body,
          files: files,
          payload: payload,
          volume: s.adhanVolume,
          stopLabel: l.adhanStop,
        ),
      );
      return;
    }
    if (_apple) {
      final fln = await plugin();
      final slug = adhanSlugFor(s.muezzin, adhan.isInstalled);
      final sound = slug == null ? null : await _appleSound(slug);
      final darwin = DarwinNotificationDetails(
        sound: sound,
        presentSound: true,
      );
      await fln?.zonedSchedule(
        id: prayerTestId,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        notificationDetails: NotificationDetails(iOS: darwin, macOS: darwin),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        payload: payload,
      );
      return;
    }
    Timer(testDelay, () => unawaited(playInApp()));
  }
}
