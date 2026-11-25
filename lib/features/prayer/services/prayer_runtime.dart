import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../khatma/khatma_providers.dart' show reminderSchedulerProvider;
import '../../khatma/services/reminder_scheduler.dart';
import '../data/adhan_catalog.dart';
import '../data/adhan_downloads.dart';
import '../domain/prayer_plan.dart';
import '../domain/prayer_settings.dart';
import '../prayer_providers.dart';
import 'prayer_alarms.dart';
import 'prayer_desktop.dart';
import 'occasion_reminders.dart';
import 'prayer_native.dart';
import '../../adhkar/adhkar_providers.dart';
import '../../adhkar/services/adhkar_reminders.dart';

final prayerNativeProvider = Provider<PrayerNative>((ref) => PrayerNative());

final prayerAlarmsProvider = Provider<PrayerAlarms>((ref) {
  final reminders = ref.watch(reminderSchedulerProvider);
  return PrayerAlarms(
    plugin: () async =>
        reminders is LocalReminderScheduler ? reminders.plugin() : null,
    native: ref.watch(prayerNativeProvider),
    adhan: ref.watch(adhanDownloadsProvider),
    readLate: () =>
        (ref.read(sharedPreferencesProvider).getStringList(_lateKey) ?? [])
            .toSet(),
    writeLate: (v) =>
        ref.read(sharedPreferencesProvider).setStringList(_lateKey, v.toList()),
    extraNatives: () async {
      final adhan = ref.read(adhanDownloadsProvider);
      final s = ref.read(adhkarSettingsProvider);
      final audio = s.salawatOn && adhan.isInstalled(salawatSlug)
          ? (await adhan.fileOf(salawatSlug, 'salawat_minshawi.m4a')).path
          : null;
      return salawatNatives(
        s,
        ref.read(prayerSettingsProvider),
        lookupAppLocalizations(
          ref.read(settingsProvider).locale ?? const Locale('ar'),
        ),
        audio,
      );
    },
  );
});

final adhkarRemindersProvider = Provider<AdhkarReminders>((ref) {
  final reminders = ref.watch(reminderSchedulerProvider);
  return AdhkarReminders(
    plugin: () async =>
        reminders is LocalReminderScheduler ? reminders.plugin() : null,
    adhan: ref.watch(adhanDownloadsProvider),
  );
});

const _lateKey = 'prayer.lateFired.v1';

final prayerDesktopProvider = Provider<PrayerDesktop>(
  (ref) => PrayerDesktop(ref.watch(prayerNativeProvider)),
);

/// Whether the app plays the adhan itself at its time: the desktops (the
/// tray), and iOS / macOS while the app is in front (the notification
/// sounds the short cut otherwise). Android's adhan service plays it.
bool get playsAdhanInApp => !kIsWeb && !Platform.isAndroid;

/// Keeps the prayer alerts planned and plays the adhan in the app where
/// it does: started once at launch.
class PrayerRuntime {
  PrayerRuntime(this._c, {this.onAdhan});

  final ProviderContainer _c;

  /// Called when the app itself starts the adhan (to show its screen).
  final void Function(PrayerKind prayer, DateTime at)? onAdhan;

  Timer? _tick;
  Timer? _debounce;
  List<PlannedAlert> _plan = const [];
  DateTime _last = DateTime.now();
  bool _front = true;
  final _played = <int>{};

  AppLocalizations get _l => lookupAppLocalizations(
    _c.read(settingsProvider).locale ?? const Locale('ar'),
  );

  /// The running one (screens play the adhan through it).
  static PrayerRuntime? instance;

  void start() {
    instance = this;
    AdhanDownloads.displayName = _l.adhanLibraryTitle;
    _c.read(prayerNativeProvider).stopLabel = _l.adhanStop;
    _c.listen(prayerSettingsProvider, (_, _) => schedule());
    _c.listen(adhkarSettingsProvider, (_, _) => schedule());
    final adhan = _c.read(adhanDownloadsProvider);
    adhan.changes.addListener(schedule);
    AppLifecycleListener(
      onResume: () {
        _front = true;
        schedule();
      },
      onHide: () => _front = false,
    );
    unawaited(_applyDesktop());
    _c.listen(
      prayerSettingsProvider.select((s) => (s.tray, s.enabled)),
      (_, _) => unawaited(_applyDesktop()),
    );
    if (playsAdhanInApp) {
      _tick = Timer.periodic(const Duration(seconds: 15), (_) => _onTick());
    }
    schedule();
  }

  Future<void> _applyDesktop() async {
    if (!PrayerDesktop.supported) return;
    final s = _c.read(prayerSettingsProvider);
    final d = _c.read(prayerDesktopProvider);
    final l = _l;
    d.labels = (
      show: l.prayerTrayShow,
      stop: l.adhanStop,
      quit: l.prayerTrayQuit,
    );
    d.tooltip = l.prayerTimesTitle;
    await d.setTray(s.enabled && s.tray);
  }

  /// Plans the alerts again (soon, once for a burst of changes).
  void schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        _plan = await _c
            .read(prayerAlarmsProvider)
            .sync(_c.read(prayerSettingsProvider), _l);
      } catch (e) {
        debugPrint('prayer alerts: $e');
      }
      try {
        await _c
            .read(adhkarRemindersProvider)
            .sync(_c.read(adhkarSettingsProvider), _l);
      } catch (e) {
        debugPrint('adhkar reminders: $e');
      }
      try {
        await syncOccasionReminders(
          _c.read(reminderSchedulerProvider),
          _c.read(prayerSettingsProvider),
          _l,
        );
      } catch (e) {
        debugPrint('occasion reminders: $e');
      }
    });
  }

  /// Wall-clock check (a timer would drift while the computer sleeps):
  /// plays an adhan whose time came since the last check, if not late.
  Future<void> _onTick() async {
    final now = DateTime.now();
    final since = _last;
    _last = now;
    final desktop = PrayerDesktop.supported;
    // iOS: only in front; the notification has the sound otherwise.
    if (!desktop && !_front) return;
    for (final a in _plan) {
      if (a.kind != AlertKind.atTime || a.sound != AlertSound.adhan) continue;
      if (wasPlayed(a.prayerAt)) continue;
      if (_c.read(prayerNativeProvider).stoppedRecently) continue;
      if (a.at.isAfter(now) || !a.at.isAfter(since)) continue;
      if (now.difference(a.at) > const Duration(minutes: 2)) continue;
      markPlayed(a.prayerAt);
      await playAdhan(a.prayer);
      onAdhan?.call(a.prayer, a.prayerAt);
    }
  }

  /// Plays the chosen adhan now (and the dua after it when chosen).
  /// Whether the adhan of the prayer at [prayerAt] already played (each
  /// prayer's adhan starts by itself once).
  bool wasPlayed(DateTime prayerAt) =>
      _played.contains(prayerAt.millisecondsSinceEpoch);

  void markPlayed(DateTime prayerAt) =>
      _played.add(prayerAt.millisecondsSinceEpoch);

  /// [general]: the general settings, not [prayer]'s own (the general
  /// previews).
  /// Plays the adhan in the app. False when its recording isn't on the
  /// device, so the caller can say so instead of staying silent.
  Future<bool> playAdhan(
    PrayerKind prayer, {
    bool? full,
    bool general = false,
  }) async {
    final all = _c.read(prayerSettingsProvider);
    final s = general ? all.copyWith(custom: const {}) : all;
    final alarms = _c.read(prayerAlarmsProvider);
    final files = await alarms.adhanFiles(s, full: full, prayer: prayer);
    if (files.isEmpty) return false;
    final slug = alarms.slugFor(s, prayer) ?? s.muezzin;
    final l = _l;
    _c.read(prayerNativeProvider).stopLabel = l.adhanStop;
    await _c
        .read(prayerNativeProvider)
        .play(
          files,
          title: l.prayerAdhanNow(prayerName(l, prayer)),
          body: l.adhanByMuezzin(muezzinOf(slug).name(l.localeName == 'ar')),
          volume: s.forPrayer(prayer).adhanVolume,
        );
    return true;
  }

  void dispose() {
    _tick?.cancel();
    _debounce?.cancel();
  }
}
