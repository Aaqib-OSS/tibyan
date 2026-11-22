import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_toast.dart';
import '../../../l10n/app_localizations.dart';
import '../../khatma/khatma_providers.dart' show reminderSchedulerProvider;
import '../data/adhan_catalog.dart';
import '../data/adhan_downloads.dart';
import '../domain/prayer_settings.dart';
import '../prayer_providers.dart';
import '../services/prayer_desktop.dart';
import '../services/prayer_runtime.dart';
import 'city_picker.dart';

/// «حدّد موقعي»: one coarse fix, named after the nearest city (whose time
/// zone it takes). Null when refused or unavailable.
Future<PrayerPlace?> locateMe(WidgetRef ref) async {
  final fix = await ref.read(prayerNativeProvider).locate();
  if (fix == null) return null;
  final cities = await ref.read(cityListProvider.future);
  final near = cities.nearest(fix.lat, fix.lon);
  if (near == null) return null;
  return PrayerPlace(
    name: near.name,
    arabicName: near.arabicName,
    country: near.country,
    lat: double.parse(fix.lat.toStringAsFixed(3)),
    lon: double.parse(fix.lon.toStringAsFixed(3)),
    timeZone: near.timeZone,
  );
}

/// Asks where the reader is: «حدّد موقعي» or the city list.
Future<PrayerPlace?> choosePlace(BuildContext context, WidgetRef ref) =>
    Navigator.of(context).push<PrayerPlace>(
      MaterialPageRoute(builder: (_) => const CityPickerScreen()),
    );

/// Switches prayer times on: the place first (asked when missing), the
/// notification permission, the default adhan's download, the exact-alarm
/// permission on Android, and on the desktops the tray question.
Future<void> enablePrayerTimes(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ctrl = ref.read(prayerSettingsProvider.notifier);
  var s = ref.read(prayerSettingsProvider);
  if (s.place == null) {
    final place = await choosePlace(context, ref);
    if (place == null || !context.mounted) return;
    await ctrl.update((x) => x.copyWith(place: place));
    s = ref.read(prayerSettingsProvider);
  }
  final reminders = ref.read(reminderSchedulerProvider);
  final granted = await reminders.requestPermission();
  if (!granted && !PrayerDesktop.supported) {
    messenger?.showSnackBar(appToast(content: Text(l.prayerNotifDenied)));
  }
  await ctrl.update((x) => x.copyWith(enabled: true));
  // The default muezzin downloads now; until it is in, the gentle tone.
  final adhan = ref.read(adhanDownloadsProvider);
  if (!adhan.isInstalled(s.muezzin)) {
    unawaited(
      adhan.download(
        s.muezzin,
        label: muezzinOf(s.muezzin).name(l.localeName == 'ar'),
      ),
    );
  }
  if (!context.mounted) return;
  if (Platform.isAndroid) {
    final native = ref.read(prayerNativeProvider);
    if (!await native.canScheduleExact() && context.mounted) {
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.prayerExactTitle),
          content: Text(l.prayerExactBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.prayerDesktopNo),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.prayerExactOpen),
            ),
          ],
        ),
      );
      if (open == true) await native.requestExact();
    }
  }
  if (PrayerDesktop.supported && !s.desktopAsked && context.mounted) {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.prayerDesktopAskTitle),
        content: Text(l.prayerDesktopAskBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.prayerDesktopNo),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.prayerDesktopYes),
          ),
        ],
      ),
    );
    final on = yes == true;
    await ctrl.update(
      (x) => x.copyWith(desktopAsked: true, tray: on, launchAtLogin: on),
    );
    if (on) await ref.read(prayerDesktopProvider).setLaunchAtLogin(true);
  }
}
