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
/// is on the device, else [general] (the general muezzin, when a prayer
/// chose its own), else the default one, else none (the alert then sounds
/// the gentle tone). Never a server link.
String? adhanSlugFor(
  String chosen,
  bool Function(String slug) installed, {
  String? general,
}) {
  if (installed(chosen)) return chosen;
  if (general != null && installed(general)) return general;
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
    this.readLate,
    this.writeLate,
    this.extraNatives,
  });

  /// Android: other alarms that go through the adhan service and its rules
  /// (the salawat reminder), scheduled with the adhans.
  final Future<List<NativeAdhan>> Function()? extraNatives;

  /// The late alerts that already fired (kept on the device), so a plan
  /// made again within their minute never fires them twice.
  final Set<String> Function()? readLate;
  final Future<void> Function(Set<String>)? writeLate;

  /// The shared notifications plugin, or null where there is none.
  final Future<FlutterLocalNotificationsPlugin?> Function() plugin;
  final PrayerNative native;
  final AdhanDownloads adhan;

  static const _silent = 'app.tibyan.prayer.silent';
  static const _tone = 'app.tibyan.prayer.tone';
  static const _reminder = 'app.tibyan.prayer.reminder';

  bool get _apple => Platform.isIOS || Platform.isMacOS;

  /// The muezzin [prayer]'s adhan plays (its own, then the general one,
  /// then the default), or null when none is downloaded.
  String? slugFor(PrayerSettings s, PrayerKind? prayer) => adhanSlugFor(
    s.forPrayer(prayer).muezzin,
    adhan.isInstalled,
    general: s.muezzin,
  );

  /// The files [prayer]'s adhan plays (the cut or the whole adhan, its own
  /// length or the general one, then the dua when chosen), or none when no
  /// recording is on the device. No [prayer]: the general settings.
  Future<List<String>> adhanFiles(
    PrayerSettings s, {
    bool? full,
    PrayerKind? prayer,
  }) async {
    final slug = slugFor(s, prayer);
    if (slug == null) return const [];
    final whole = full ?? s.forPrayer(prayer).length == AdhanLength.full;
    final main = await adhan.fileOf(slug, whole ? 'full.m4a' : 'short.m4a');
    if (!await main.exists()) return const [];
    final dua = await adhan.fileOf(duaSlug, 'dua_shaarawy.m4a');
    return [
      main.path,
      if (s.duaAfter && adhan.isInstalled(duaSlug) && await dua.exists())
        dua.path,
    ];
  }

  /// Apple: copies each muezzin's PCM cut where the notification can play
  /// it; its name changes with the muezzin (the system caches sounds by
  /// name). Returns slug → sound name for those downloaded; the sounds of
  /// muezzins no longer used are removed.
  Future<Map<String, String>> _appleSounds(Set<String> slugs) async {
    final out = <String, String>{};
    try {
      final lib = await getLibraryDirectory();
      final dir = Directory(p.join(lib.path, 'Sounds'));
      await dir.create(recursive: true);
      for (final slug in slugs) {
        if (!adhan.isInstalled(slug)) continue;
        final name = 'tibyan_adhan_$slug.caf';
        final target = File(p.join(dir.path, name));
        if (!await target.exists()) {
          await (await adhan.fileOf(slug, 'short.caf')).copy(target.path);
        }
        out[slug] = name;
      }
      await for (final f in dir.list()) {
        final b = p.basename(f.path);
        if (b.startsWith('tibyan_adhan_') && !out.containsValue(b)) {
          await f.delete();
        }
      }
    } catch (_) {}
    return out;
  }

  Future<String?> _appleSound(String? slug) async =>
      slug == null ? null : (await _appleSounds({slug}))[slug];

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
    final plan = planAlerts(
      settings: s,
      now: when,
      adhanReady: slugFor(s, null) != null,
      readyFor: (p) => slugFor(s, p) != null,
      limit: apple ? appleMaxPrayerAlerts : null,
      lateFired: readLate?.call() ?? const {},
    );
    if (plan.any((a) => a.late)) {
      await writeLate?.call(
        recordLate(readLate?.call() ?? const {}, plan, when),
      );
    }
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
      await native.scheduleAdhans(await _extras());
      return plan;
    }
    // Each prayer's own files, volume and Apple sound.
    final files = <PrayerKind, List<String>>{};
    final shortFiles = <PrayerKind, List<String>>{};
    final slugs = <PrayerKind, String?>{};
    for (final p in obligatoryPrayers) {
      files[p] = await adhanFiles(s, prayer: p);
      shortFiles[p] = await adhanFiles(s, prayer: p, full: false);
      slugs[p] = slugFor(s, p);
    }
    final appleSounds = apple
        ? await _appleSounds({...slugs.values.nonNulls})
        : const <String, String>{};
    for (final a in plan) {
      final t = alertTexts(l, a, place);
      final mine = files[a.prayer] ?? const <String>[];
      final appleSound = appleSounds[slugs[a.prayer]];
      if (Platform.isAndroid &&
          exact &&
          a.kind == AlertKind.atTime &&
          a.sound == AlertSound.adhan &&
          mine.isNotEmpty) {
        natives.add(
          NativeAdhan(
            id: a.id,
            at: a.at,
            title: t.title,
            body: t.body,
            files: mine,
            payload: alertPayload(a),
            volume: s.forPrayer(a.prayer).adhanVolume,
            stopLabel: l.adhanStop,
            playLabel: l.adhanPlay,
            prayerAt: a.prayerAt,
            shortFiles: shortFiles[a.prayer] ?? const [],
            inUse: s.inUse.name,
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
    await native.scheduleAdhans([...natives, ...await _extras()]);
    return plan;
  }

  Future<List<NativeAdhan>> _extras() async {
    if (!Platform.isAndroid) return const [];
    try {
      return await extraNatives?.call() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// How long after «جرّب الأذان» the test alert fires.
  static const testDelay = Duration(seconds: 10);

  /// «جرّب الأذان»: the chosen adhan (full or short, then the dua when on)
  /// through the same path as a real alert, [testDelay] from now. Android:
  /// the exact alarm and the adhan service. Apple: a notification with the
  /// short cut as its sound (heard in front too). Desktop: the app plays
  /// it. Returns when it is scheduled.
  /// [prayer]: that prayer's own adhan («جرّب» in its sheet).
  Future<void> testAdhan(
    PrayerSettings s,
    AppLocalizations l, {
    required Future<void> Function() playInApp,
    PrayerKind? prayer,
    void Function(String location)? showScene,
  }) async {
    final at = DateTime.now().add(testDelay);
    final files = await adhanFiles(s, prayer: prayer);
    // A test never claims a real prayer time: its own title, the next
    // prayer's scene.
    final place = s.place;
    final scene =
        prayer ??
        (place == null
            ? PrayerKind.maghrib
            : nextPrayer(place, DateTime.now(), s)?.prayer ??
                  PrayerKind.maghrib);
    final title = l.adhanTestBody;
    final slugNow = slugFor(s, prayer);
    final body = slugNow == null
        ? l.soundTone
        : l.adhanByMuezzin(muezzinOf(slugNow).name(l.localeName == 'ar'));
    final payload = 'tibyan://prayer/adhan?p=${scene.name}&test=1';
    // The full-screen scene comes with the test, like the real adhan's.
    if (showScene != null) {
      Timer(testDelay, () => showScene('/prayer/adhan?p=${scene.name}&test=1'));
    }
    if (Platform.isAndroid) {
      await native.testAdhan(
        NativeAdhan(
          id: prayerTestId,
          at: at,
          title: title,
          body: body,
          files: files,
          payload: payload,
          volume: s.forPrayer(prayer).adhanVolume,
          stopLabel: l.adhanStop,
        ),
      );
      return;
    }
    if (_apple) {
      // macOS plays the adhan in the app (as the real one does from the
      // runtime's check); the notice comes silent. iOS: the notification's
      // own sound.
      final mac = Platform.isMacOS;
      final fln = await plugin();
      final sound = mac ? null : await _appleSound(slugNow);
      final darwin = DarwinNotificationDetails(
        sound: sound,
        presentSound: !mac,
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
      if (mac) Timer(testDelay, () => unawaited(playInApp()));
      return;
    }
    Timer(testDelay, () => unawaited(playInApp()));
  }
}
