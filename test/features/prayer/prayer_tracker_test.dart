import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/backup/backup.dart';
import 'package:tibyan/core/db/user_database.dart';
import 'package:tibyan/core/sync/cloud/sync_records.dart';
import 'package:tibyan/core/ui/look_kit.dart';
import 'package:tibyan/features/prayer/data/prayer_log_repository.dart';
import 'package:tibyan/features/prayer/domain/prayer_settings.dart';
import 'package:tibyan/features/prayer/presentation/prayer_tracker_screen.dart';
import 'package:tibyan/features/prayer/prayer_providers.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../tasmee/tasmee_test_env.dart';
import 'prayer_calc_test.dart' show cairo;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('log', () {
    late UserDatabase db;
    late PrayerLogRepository repo;
    setUp(() {
      db = UserDatabase(NativeDatabase.memory());
      repo = PrayerLogRepository(db);
    });
    tearDown(() => db.close());
    final day = DateTime(2026, 11, 22);

    test('a prayer is marked, changed and cleared', () async {
      await repo.mark(day, PrayerKind.fajr, PrayedHow.late);
      await repo.mark(day, PrayerKind.fajr, PrayedHow.jamaah);
      await repo.mark(day, PrayerKind.dhuhr, PrayedHow.onTime);
      expect(await repo.watchDay(day).first, {
        PrayerKind.fajr: PrayedHow.jamaah,
        PrayerKind.dhuhr: PrayedHow.onTime,
      });
      await repo.mark(day, PrayerKind.fajr, null);
      expect(await repo.watchDay(day).first, {
        PrayerKind.dhuhr: PrayedHow.onTime,
      });
      expect(await repo.watchDay(DateTime(2026, 11, 21)).first, isEmpty);
    });

    test('the week counts the last seven days only', () async {
      await repo.mark(day, PrayerKind.fajr, PrayedHow.onTime);
      await repo.mark(day, PrayerKind.isha, PrayedHow.jamaah);
      await repo.mark(DateTime(2026, 11, 16), PrayerKind.asr, PrayedHow.late);
      await repo.mark(DateTime(2026, 11, 15), PrayerKind.asr, PrayedHow.late);
      final w = await repo.week(day);
      expect(w.prayed, 3);
      expect(w.possible, 35);
      expect(w.counts[PrayedHow.late], 1);
    });

    test('qada: added and settled, never below zero', () async {
      await repo.changeQada(PrayerKind.fajr, 1);
      await repo.changeQada(PrayerKind.fajr, 1);
      await repo.changeQada(PrayerKind.fajr, -1);
      await repo.changeQada(PrayerKind.asr, -1);
      expect(await repo.watchQada().first, {PrayerKind.fajr: 1});
      await repo.changeQada(PrayerKind.fajr, -5);
      expect(await repo.watchQada().first, {PrayerKind.fajr: 0});
    });

    test('backup carries the log and qada, merging once', () async {
      await repo.mark(day, PrayerKind.maghrib, PrayedHow.jamaah);
      await repo.changeQada(PrayerKind.isha, 3);
      final text = await Backup(db).export();
      final tables = (jsonDecode(text) as Map)['tables'] as Map;
      expect(tables.keys, containsAll(['prayer_log', 'qada_count']));
      final other = UserDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await Backup(other).import(text);
      await Backup(other).import(text);
      final r = PrayerLogRepository(other);
      expect(await r.watchDay(day).first, {
        PrayerKind.maghrib: PrayedHow.jamaah,
      });
      expect(await r.watchQada().first, {PrayerKind.isha: 3});
    });

    test('it syncs with the reader\'s own data', () {
      expect(syncedEntities['prayer_log'], ['day', 'prayer']);
      expect(syncedEntities['qada_count'], ['prayer']);
    });
  });

  group('screen', () {
    late TasmeeTestData data;
    setUpAll(() {
      tzdata.initializeTimeZones();
      data = TasmeeTestData.open();
    });
    tearDownAll(() => data.close());

    // Drift's stream queries end on a zero-length timer.
    Future<void> done(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> pump(
      WidgetTester tester, {
      double textScale = 1,
      DateTime? now,
    }) async {
      tester.view
        ..physicalSize = const Size(390, 1800)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const s = PrayerSettings(enabled: true, place: cairo);
      final container = await tasmeeContainer(
        tester,
        data,
        prefs: {prayerSettingsKey: s.encode()},
      );
      await tester.pumpWidget(
        tasmeeApp(
          container,
          LookTheme(
            child: PrayerTrackerScreen(
              now: now ?? DateTime.utc(2026, 11, 22, 18),
            ),
          ),
          theme: tasmeeTheme(container),
        ),
      );
      await settle(tester);
    }

    testWidgets('mark a prayer, count qada, a calm week', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('tracker-week')), findsOneWidget);
      expect(find.text('لم تُسجَّل'), findsNWidgets(5));
      await tester.tap(find.byKey(const ValueKey('tracker-row-asr')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('prayed-jamaah')));
      await settle(tester);
      expect(find.text('في جماعة'), findsOneWidget);
      expect(find.text('لم تُسجَّل'), findsNWidgets(4));
      expect(find.textContaining('سجّلت ١ من ٣٥'), findsOneWidget);

      final add = find.byKey(const ValueKey('qada-add-fajr'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await settle(tester);
      await tester.tap(add);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('qada-settle-fajr')));
      await settle(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('qada-count-fajr'))).data,
        '١',
      );
      await done(tester);
    });

    FilledButton markAll(WidgetTester tester) => tester.widget<FilledButton>(
      find.byKey(const ValueKey('tracker-mark-all')),
    );

    testWidgets('«صلّيت الكل» waits for isha, then keeps marks', (
      tester,
    ) async {
      // Cairo, 22 Nov: isha is about 18:30 local (16:30 UTC).
      await pump(tester, now: DateTime.utc(2026, 11, 22, 12));
      expect(markAll(tester).onPressed, isNull);
      expect(find.text('يتاح بعد دخول وقت العشاء'), findsOneWidget);
      // An earlier day is open to it.
      await tester.tap(find.byKey(const ValueKey('tracker-prev')));
      await settle(tester);
      expect(markAll(tester).onPressed, isNotNull);
      await done(tester);

      await pump(tester, now: DateTime.utc(2026, 11, 22, 18));
      expect(markAll(tester).onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('tracker-row-asr')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('prayed-jamaah')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('tracker-mark-all')));
      await settle(tester);
      expect(find.text('في جماعة'), findsOneWidget);
      expect(find.text('في وقتها'), findsNWidgets(4));
      expect(find.byKey(const ValueKey('tracker-mark-all')), findsNothing);
      await done(tester);
    });

    testWidgets('fits at 200% text with 48dp buttons', (tester) async {
      await pump(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('tracker-mark-all')),
        200,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('tracker-mark-all'))).height,
        greaterThanOrEqualTo(48),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('qada-add-fajr')),
        200,
      );
      final b = tester.getSize(find.byKey(const ValueKey('qada-add-fajr')));
      expect(b.width, greaterThanOrEqualTo(48));
      await done(tester);
    });
  });
}
