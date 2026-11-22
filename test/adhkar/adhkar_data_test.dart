import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/ui/look_kit.dart';
import 'package:tibyan/features/adhkar/adhkar_providers.dart';
import 'package:tibyan/features/adhkar/data/adhkar_data.dart';
import 'package:tibyan/features/adhkar/domain/adhkar_settings.dart';
import 'package:tibyan/features/adhkar/presentation/adhkar_screen.dart';
import 'package:tibyan/features/adhkar/presentation/adhkar_settings_screen.dart';
import 'package:tibyan/features/adhkar/services/adhkar_reminders.dart';
import 'package:tibyan/features/prayer/data/adhan_catalog.dart';
import 'package:tibyan/features/prayer/domain/prayer_settings.dart';
import 'package:tibyan/l10n/app_localizations.dart';

import '../tasmee/tasmee_test_env.dart';

void main() {
  group('bundled data', () {
    test('every file matches the mirror\'s SHA256SUMS', () {
      final sums = parseSums(
        File('assets/adhkar/SHA256SUMS').readAsStringSync(),
      );
      expect(sums.keys, containsAll(['ar.json', 'en.json', 'LICENSE']));
      for (final e in sums.entries) {
        final bytes = File('assets/adhkar/${e.key}').readAsBytesSync();
        expect(sha256.convert(bytes).toString(), e.value, reason: e.key);
      }
      expect(
        File('assets/adhkar/COMMIT').readAsStringSync().trim(),
        '39d422fb3e3a',
      );
    });

    test('parsed as published: 34 items, morning and evening by type', () {
      final ar = parseAdhkar(File('assets/adhkar/ar.json').readAsStringSync());
      final en = parseAdhkar(File('assets/adhkar/en.json').readAsStringSync());
      expect(ar, hasLength(34));
      expect(en, hasLength(34));
      expect(ar.where((a) => a.isFor(AdhkarTime.morning)), hasLength(26));
      expect(ar.where((a) => a.isFor(AdhkarTime.evening)), hasLength(24));
      // Shown: entry 29 left out (its source grades the hadith weak).
      final shown = ar.where((a) => !excludedAdhkarOrders.contains(a.order));
      expect(shown.where((a) => a.isFor(AdhkarTime.morning)), hasLength(25));
      expect(shown.where((a) => a.isFor(AdhkarTime.evening)), hasLength(23));
      // The same Arabic text in both files; English adds its translation.
      for (var i = 0; i < ar.length; i++) {
        expect(en[i].content, ar[i].content);
        expect(en[i].translation, isNotEmpty);
      }
      expect(ar.first.order, 1);
    });
  });

  group('settings and salawat plan', () {
    test('everything is off by default and kept', () {
      const d = AdhkarSettings();
      expect([d.morningOn, d.eveningOn, d.salawatOn], [false, false, false]);
      final s = AdhkarSettings.decode(
        const AdhkarSettings(
          salawatOn: true,
          salawatEvery: 30,
          salawatUnit: RepeatUnit.minutes,
          windowOn: true,
        ).encode(),
      );
      expect(s.salawatOn, isTrue);
      expect(s.interval, const Duration(minutes: 30));
      expect(s.windowOn, isTrue);
    });

    test('off: nothing planned; every 2 hours: on the even hours', () {
      final now = DateTime(2026, 11, 22, 9, 30);
      expect(planSalawat(const AdhkarSettings(), now), isEmpty);
      final t = planSalawat(
        const AdhkarSettings(salawatOn: true),
        now,
        limit: 3,
      );
      expect(t, [
        DateTime(2026, 11, 22, 10),
        DateTime(2026, 11, 22, 12),
        DateTime(2026, 11, 22, 14),
      ]);
    });

    test('a window keeps them inside it, also across midnight', () {
      final now = DateTime(2026, 11, 22, 20, 10);
      const s = AdhkarSettings(
        salawatOn: true,
        salawatEvery: 1,
        windowOn: true,
        windowFrom: 21 * 60,
        windowTo: 23 * 60,
      );
      final t = planSalawat(s, now, limit: 4);
      expect(t, [
        DateTime(2026, 11, 22, 21),
        DateTime(2026, 11, 22, 22),
        DateTime(2026, 11, 23, 21),
        DateTime(2026, 11, 23, 22),
      ]);
      const night = AdhkarSettings(
        salawatOn: true,
        salawatEvery: 1,
        windowOn: true,
        windowFrom: 23 * 60,
        windowTo: 1 * 60,
      );
      expect(planSalawat(night, now, limit: 2), [
        DateTime(2026, 11, 22, 23),
        DateTime(2026, 11, 23, 0),
      ]);
      expect(inWindow(30, 23 * 60, 60), isTrue);
      expect(inWindow(120, 23 * 60, 60), isFalse);
    });

    test('never more often than every 15 minutes', () {
      const s = AdhkarSettings(
        salawatOn: true,
        salawatEvery: 5,
        salawatUnit: RepeatUnit.minutes,
      );
      expect(s.interval, const Duration(minutes: 15));
    });

    test('Android: quiet adhan alarms that follow the in-use setting', () {
      final l = lookupAppLocalizations(const Locale('ar'));
      const s = AdhkarSettings(salawatOn: true);
      expect(
        salawatNatives(s, const PrayerSettings(), l, null),
        isEmpty,
        reason: 'not downloaded',
      );
      final n = salawatNatives(
        s,
        const PrayerSettings(inUse: InUseAdhan.short),
        l,
        '/x/salawat_minshawi.m4a',
        now: DateTime(2026, 11, 22, 9),
      );
      expect(n, isNotEmpty);
      expect(n.first.toMap()['quiet'], isTrue);
      expect(n.first.toMap()['inUse'], 'short');
      expect(n.first.payload, salawatPayload);
      expect(n.first.id, salawatNativeIdBase);
    });

    test('the salawat recording shares the extras folder', () {
      expect(adhanFolderOf(salawatSlug), 'extras');
      expect(salawatFilesFor(apple: true), [
        'salawat_minshawi.m4a',
        'salawat_minshawi.caf',
      ]);
      expect(salawatFilesFor(apple: false), ['salawat_minshawi.m4a']);
    });
  });

  group('screens', () {
    late TasmeeTestData data;
    setUpAll(() => data = TasmeeTestData.open());
    tearDownAll(() => data.close());

    Future<dynamic> pump(
      WidgetTester tester,
      Widget screen, {
      double textScale = 1,
    }) async {
      tester.view
        ..physicalSize = const Size(390, 1600)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = await tasmeeContainer(tester, data);
      await tester.pumpWidget(
        tasmeeApp(
          container,
          LookTheme(child: screen),
          theme: tasmeeTheme(container),
        ),
      );
      await settle(tester);
      return container;
    }

    testWidgets('count up to the item\'s count, progress, reset', (
      tester,
    ) async {
      final c = await pump(tester, const AdhkarScreen());
      expect(find.byKey(const ValueKey('adhkar-item-1')), findsOneWidget);
      expect(find.textContaining('من ٢٥'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('adhkar-item-31')),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byKey(const ValueKey('adhkar-item-29')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('adhkar-item-1')),
        -400,
        scrollable: find.byType(Scrollable).last,
      );
      // Item 4 is said three times.
      final tap = find.byKey(const ValueKey('adhkar-tap-4'));
      await tester.ensureVisible(tap);
      for (var i = 0; i < 5; i++) {
        await tester.tap(tap);
        await settle(tester, rounds: 2);
      }
      expect(c.read(adhkarProgressProvider)[AdhkarTime.morning]![4], 3);
      await tester.tap(find.byKey(const ValueKey('adhkar-reset')));
      await settle(tester);
      expect(c.read(adhkarProgressProvider)[AdhkarTime.morning], isEmpty);
      await tester.tap(find.byKey(const ValueKey('adhkar-tab-evening')));
      await settle(tester);
      expect(find.byKey(const ValueKey('adhkar-progress')), findsOneWidget);
    });

    testWidgets('the adhkar fit at 200% text', (tester) async {
      await pump(tester, const AdhkarScreen(), textScale: 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('settings: reminders off; salawat off with its recording', (
      tester,
    ) async {
      final c = await pump(
        tester,
        const AdhkarSettingsScreen(salawat: true),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      for (final k in ['adhkar-morning', 'adhkar-evening', 'adhkar-salawat']) {
        expect(
          tester.widget<SwitchListTile>(find.byKey(ValueKey(k))).value,
          isFalse,
        );
      }
      await tester.tap(find.byKey(const ValueKey('adhkar-morning')));
      await settle(tester);
      expect(c.read(adhkarSettingsProvider).morningOn, isTrue);
      expect(find.byKey(const ValueKey('adhkar-morning-time')), findsOneWidget);
      expect(find.byKey(const ValueKey('salawat-download')), findsOneWidget);
    });
  });
}
