import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/prayer/domain/prayer_calc.dart';
import 'package:tibyan/features/prayer/domain/prayer_plan.dart';
import 'package:tibyan/features/prayer/domain/prayer_settings.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'prayer_calc_test.dart' show cairo;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  const on = PrayerSettings(enabled: true, place: cairo);
  // A Tuesday in April 2026, 10:00 in Cairo (07:00 UTC; Egypt on summer
  // time, UTC+3).
  final now = DateTime.utc(2026, 4, 14, 7);

  test('nothing is planned while prayer times are off or have no place', () {
    expect(
      planAlerts(settings: const PrayerSettings(), now: now, adhanReady: true),
      isEmpty,
    );
    expect(
      planAlerts(
        settings: const PrayerSettings(enabled: true),
        now: now,
        adhanReady: true,
      ),
      isEmpty,
    );
  });

  test('seven days ahead, five prayers a day, only after now', () {
    final plan = planAlerts(settings: on, now: now, adhanReady: true);
    // Today's Fajr has passed (10:00): 4 today + 6 × 5.
    expect(plan.length, 4 + 6 * 5);
    expect(plan.every((a) => a.at.isAfter(now)), isTrue);
    expect(plan.first.prayer, PrayerKind.dhuhr);
    final last = plan.last.at;
    expect(last.difference(now).inDays, lessThan(prayerDaysAhead));
    for (var i = 1; i < plan.length; i++) {
      expect(plan[i].at.isAfter(plan[i - 1].at), isTrue);
    }
  });

  test('ids are unique and inside the prayer range', () {
    final plan = planAlerts(
      settings: on.copyWith(
        reminders: {for (final p in obligatoryPrayers) p: 10},
        shuruqAlert: true,
        duhaAlert: true,
      ),
      now: now,
      adhanReady: true,
    );
    final ids = plan.map((a) => a.id).toSet();
    expect(ids.length, plan.length);
    expect(ids.every((i) => i >= prayerIdBase && i < prayerIdLimit), isTrue);
  });

  test('until the adhan is downloaded the gentle tone is used', () {
    final waiting = planAlerts(settings: on, now: now, adhanReady: false);
    expect(waiting.every((a) => a.sound == AlertSound.tone), isTrue);
    final ready = planAlerts(settings: on, now: now, adhanReady: true);
    expect(ready.every((a) => a.sound == AlertSound.adhan), isTrue);
  });

  test('per-prayer sounds and reminders', () {
    final plan = planAlerts(
      settings: on.copyWith(
        sounds: {PrayerKind.isha: AlertSound.silent},
        reminders: {PrayerKind.maghrib: 10},
      ),
      now: now,
      adhanReady: true,
    );
    final isha = plan.where(
      (a) => a.prayer == PrayerKind.isha && a.kind == AlertKind.atTime,
    );
    expect(isha.every((a) => a.sound == AlertSound.silent), isTrue);
    final before = plan.where((a) => a.kind == AlertKind.before).toList();
    expect(before, hasLength(7));
    for (final b in before) {
      expect(b.prayer, PrayerKind.maghrib);
      expect(b.prayerAt.difference(b.at), const Duration(minutes: 10));
    }
  });

  test('sunrise and Duha alerts are off by default', () {
    final plan = planAlerts(settings: on, now: now, adhanReady: true);
    expect(plan.any((a) => a.prayer == PrayerKind.shuruq), isFalse);
    expect(plan.any((a) => a.prayer == PrayerKind.duha), isFalse);
    final withThem = planAlerts(
      settings: on.copyWith(shuruqAlert: true, duhaAlert: true),
      now: now,
      adhanReady: true,
    );
    expect(withThem.where((a) => a.prayer == PrayerKind.shuruq).length, 6);
    expect(withThem.where((a) => a.prayer == PrayerKind.duha).length, 6);
  });

  test('Ramadan: suhoor and iftar reminders, Maghrib announces iftar', () {
    // 1 March 2026 is in Ramadan 1447.
    final ramadanNow = DateTime.utc(2026, 3, 1, 7);
    final plan = planAlerts(settings: on, now: ramadanNow, adhanReady: true);
    final suhoor = plan.where((a) => a.kind == AlertKind.suhoor).toList();
    final iftar = plan.where((a) => a.kind == AlertKind.iftar).toList();
    expect(suhoor.length, 6); // today's Fajr has passed
    expect(iftar.length, 7);
    expect(suhoor.first.prayerAt.difference(suhoor.first.at).inMinutes, 10);
    expect(iftar.first.prayerAt.difference(iftar.first.at).inMinutes, 15);
    final maghrib = plan.firstWhere(
      (a) => a.prayer == PrayerKind.maghrib && a.kind == AlertKind.atTime,
    );
    expect(maghrib.ramadan, isTrue);
    // Outside Ramadan: none.
    final april = planAlerts(settings: on, now: now, adhanReady: true);
    expect(april.any((a) => a.kind == AlertKind.suhoor), isFalse);
    expect(april.any((a) => a.ramadan), isFalse);
  });

  test('Apple: only the earliest alerts, within the pending limit', () {
    final plan = planAlerts(
      settings: on.copyWith(
        reminders: {for (final p in obligatoryPrayers) p: 10},
        shuruqAlert: true,
        duhaAlert: true,
      ),
      now: now,
      adhanReady: true,
      limit: appleMaxPrayerAlerts,
    );
    expect(plan.length, appleMaxPrayerAlerts);
    final all = planAlerts(
      settings: on.copyWith(
        reminders: {for (final p in obligatoryPrayers) p: 10},
        shuruqAlert: true,
        duhaAlert: true,
      ),
      now: now,
      adhanReady: true,
    );
    expect(plan.last.at, all[appleMaxPrayerAlerts - 1].at);
  });

  test('a re-plan an hour later drops what passed and keeps the window', () {
    final first = planAlerts(settings: on, now: now, adhanReady: true);
    final dhuhr = first.first.at;
    final later = planAlerts(
      settings: on,
      now: dhuhr.add(const Duration(minutes: 1)),
      adhanReady: true,
    );
    expect(later.first.prayer, PrayerKind.asr);
    expect(later.length, first.length - 1);
  });

  test('summer time inside the window keeps clock times', () {
    // New York changes on 8 March 2026; plan from 5 March.
    const ny = PrayerPlace(
      name: 'New York',
      arabicName: '',
      country: 'US',
      lat: 40.7128,
      lon: -74.006,
      timeZone: 'America/New_York',
    );
    final plan = planAlerts(
      settings: const PrayerSettings(enabled: true, place: ny),
      now: DateTime.utc(2026, 3, 5, 20),
      adhanReady: true,
    );
    final dhuhrs = plan
        .where((a) => a.prayer == PrayerKind.dhuhr)
        .map((a) => a.prayerAt)
        .toList();
    final loc = locationOf(ny);
    final hours = {for (final d in dhuhrs) tz.TZDateTime.from(d, loc).hour};
    // Dhuhr stays around noon (12 or 13 on the clock), never 11.
    expect(hours.every((h) => h == 12 || h == 13), isTrue);
  });
}
