import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/home/next_prayer_card.dart';
import 'package:tibyan/features/prayer/domain/prayer_calc.dart';
import 'package:tibyan/features/prayer/domain/prayer_settings.dart';
import 'package:tibyan/features/prayer/domain/prayer_window.dart';
import 'package:tibyan/features/prayer/prayer_providers.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../features/prayer/prayer_calc_test.dart' show cairo;
import '../tasmee/tasmee_test_env.dart';

void main() {
  late TasmeeTestData data;
  setUpAll(() {
    tzdata.initializeTimeZones();
    data = TasmeeTestData.open();
  });
  tearDownAll(() => data.close());

  const s = PrayerSettings(enabled: true, place: cairo);
  tz.TZDateTime at(int d, int h, int m) =>
      tz.TZDateTime(locationOf(cairo), 2026, 11, d, h, m);

  group('prayerWindow', () {
    test('after Isha the next is tomorrow\'s Fajr', () {
      final w = prayerWindow(cairo, at(24, 23, 30), s);
      expect(w.previous, PrayerKind.isha);
      expect(w.next, PrayerKind.fajr);
      expect(w.previousAt.day, 24);
      expect(w.nextAt.day, 25);
    });

    test('before Fajr the previous is yesterday\'s Isha', () {
      final w = prayerWindow(cairo, at(24, 2, 0), s);
      expect(w.previous, PrayerKind.isha);
      expect(w.previousAt.day, 23);
      expect(w.next, PrayerKind.fajr);
      expect(w.nextAt.day, 24);
    });

    test('midday is between Dhuhr and Asr', () {
      final w = prayerWindow(cairo, at(24, 13, 0), s);
      expect(w.previous, PrayerKind.dhuhr);
      expect(w.next, PrayerKind.asr);
      final p = windowProgress(w, at(24, 13, 0));
      expect(p, inExclusiveRange(0, 1));
    });

    test('exactly at a prayer the next one is shown', () {
      final asr = computeDay(cairo, DateTime(2026, 11, 24), s)[PrayerKind.asr];
      final w = prayerWindow(cairo, asr, s);
      expect(w.previous, PrayerKind.asr);
      expect(w.next, PrayerKind.maghrib);
    });
  });

  group('formatCountdown', () {
    String latin(int n) => '$n';
    String arabic(int n) => '$n'
        .split('')
        .map((c) => String.fromCharCode(0x0660 + int.parse(c)))
        .join();

    test('pads hours, minutes and seconds', () {
      expect(
        formatCountdown(
          const Duration(hours: 1, minutes: 3, seconds: 9),
          latin,
        ),
        '01:03:09',
      );
      expect(
        formatCountdown(const Duration(hours: 13, minutes: 45), latin),
        '13:45:00',
      );
    });

    test('never negative', () {
      expect(formatCountdown(const Duration(seconds: -5), latin), '00:00:00');
    });

    test('Arabic-Indic digits', () {
      expect(
        formatCountdown(
          const Duration(hours: 2, minutes: 5, seconds: 30),
          arabic,
        ),
        '٠٢:٠٥:٣٠',
      );
    });
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    PrayerSettings? settings,
    DateTime? now,
    String lang = 'ar',
    double textScale = 1,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 900)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = await tasmeeContainer(
      tester,
      data,
      prefs: {prayerSettingsKey: ?settings?.encode()},
    );
    await tester.pumpWidget(
      tasmeeApp(
        container,
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [NextPrayerCard(clock: now == null ? null : () => now)],
          ),
        ),
        theme: tasmeeTheme(container),
        lang: lang,
      ),
    );
    await tester.pump();
  }

  testWidgets('no place: the calm card asks for the city', (tester) async {
    await pumpCard(tester);
    expect(find.byKey(const ValueKey('next-prayer-setup')), findsOneWidget);
    expect(find.byKey(const ValueKey('next-prayer-card')), findsNothing);
    expect(find.text('اختر المدينة'), findsOneWidget);
  });

  for (final lang in ['ar', 'en']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('sky card, $lang at ${scale}x text, no overflow', (
        tester,
      ) async {
        await pumpCard(
          tester,
          settings: s,
          now: at(24, 23, 30),
          lang: lang,
          textScale: scale,
        );
        expect(find.byKey(const ValueKey('next-prayer-card')), findsOneWidget);
        expect(find.byKey(const ValueKey('next-prayer-count')), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Unmount so the twinkle ticker stops.
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
