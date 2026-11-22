import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/ui/look_kit.dart';
import 'package:tibyan/features/khatma/services/reminder_scheduler.dart';
import 'package:tibyan/features/prayer/domain/hijri_occasions.dart';
import 'package:tibyan/features/prayer/domain/prayer_calc.dart';
import 'package:tibyan/features/prayer/domain/prayer_settings.dart';
import 'package:tibyan/features/prayer/presentation/hijri_calendar_screen.dart';
import 'package:tibyan/features/prayer/prayer_providers.dart';
import 'package:tibyan/features/prayer/services/occasion_reminders.dart';
import 'package:tibyan/l10n/app_localizations.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../tasmee/tasmee_test_env.dart';
import 'prayer_calc_test.dart' show cairo;

void main() {
  final today = DateTime(2026, 11, 22);

  group('dates', () {
    test('Umm al-Qura starts: 1 Ramadan 1447 is 18 Feb 2026', () {
      expect(gregorianOf(1447, 9, 1, 0), DateTime(2026, 2, 18));
      expect(gregorianOf(1447, 12, 10, 0), DateTime(2026, 5, 27));
    });

    test('the ±day adjustment moves the Gregorian day back', () {
      expect(gregorianOf(1447, 9, 1, 1), DateTime(2026, 2, 17));
      expect(gregorianOf(1447, 9, 1, -1), DateTime(2026, 2, 19));
      for (final o in [-2, -1, 0, 1, 2]) {
        final g = gregorianOf(1448, 1, 10, o);
        final h = hijriOf(g, o);
        expect([h.hYear, h.hMonth, h.hDay], [1448, 1, 10]);
      }
    });

    test('months shift across years', () {
      expect(shiftMonth((year: 1447, month: 12), 1), (year: 1448, month: 1));
      expect(shiftMonth((year: 1448, month: 1), -1), (year: 1447, month: 12));
      final l = hijriMonthLength((year: 1448, month: 3));
      expect(l, inInclusiveRange(29, 30));
    });

    test('occasion days', () {
      expect(occasionOn(1, 10), HijriOccasion.ashura);
      expect(occasionOn(9, 25), HijriOccasion.lastTen);
      expect(occasionOn(12, 13), HijriOccasion.tashreeq);
      expect(occasionOn(12, 14), isNull);
      expect(occasionOn(9, 2), isNull);
    });

    test('upcoming: soonest first, each once, none past', () {
      final u = upcomingOccasions(today, 0);
      expect(u, hasLength(8));
      expect(u.map((e) => e.occasion).toSet(), hasLength(8));
      expect(u.first.occasion, HijriOccasion.ramadanStart);
      expect(u.first.year, 1448);
      for (var i = 1; i < u.length; i++) {
        expect(u[i].start.isBefore(u[i - 1].start), isFalse);
      }
      expect(daysUntil(today, u.first.start), greaterThan(0));
    });

    test('days until', () {
      expect(daysUntil(today, today), 0);
      expect(daysUntil(today, DateTime(2026, 11, 23)), 1);
      expect(daysUntil(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
    });
  });

  group('reminders', () {
    final l = lookupAppLocalizations(const Locale('ar'));

    test('off by default and kept in settings', () {
      expect(const PrayerSettings().occasionReminders, isFalse);
      final s = PrayerSettings.decode(
        const PrayerSettings(occasionReminders: true).encode(),
      );
      expect(s.occasionReminders, isTrue);
    });

    test('off: nothing scheduled; on: the evening before each', () async {
      final r = NoReminders();
      await syncOccasionReminders(r, const PrayerSettings(), l, now: today);
      expect(r.once, isEmpty);
      await syncOccasionReminders(
        r,
        const PrayerSettings(occasionReminders: true),
        l,
        now: today,
      );
      expect(r.once, hasLength(8));
      final upcoming = upcomingOccasions(today, 0);
      for (final u in upcoming) {
        final at = r.once[occasionIdBase + u.occasion.index]!;
        expect(at.hour, occasionReminderHour);
        expect(daysUntil(at, u.start), 1);
      }
      await syncOccasionReminders(r, const PrayerSettings(), l, now: today);
      expect(r.once, isEmpty);
    });

    test('labels are names and dates only', () {
      expect(occasionName(l, HijriOccasion.lastTen), 'العشر الأواخر من رمضان');
      expect(occasionDateLabel(l, HijriOccasion.ashura), '١٠ محرم');
      expect(occasionDateLabel(l, HijriOccasion.tashreeq), '١١–١٣ ذو الحجة');
    });
  });

  group('screen', () {
    late TasmeeTestData data;
    setUpAll(() {
      tzdata.initializeTimeZones();
      data = TasmeeTestData.open();
    });
    tearDownAll(() => data.close());

    Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
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
            child: HijriCalendarScreen(now: DateTime.utc(2026, 11, 22, 10)),
          ),
          theme: tasmeeTheme(container),
        ),
      );
      await settle(tester);
    }

    testWidgets('today, the next occasion, swiping months, the reminder', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('hijri-today-cell')), findsOneWidget);
      expect(find.byKey(const ValueKey('hijri-next')), findsOneWidget);
      expect(find.text('أول رمضان'), findsWidgets);
      final title = find.byKey(const ValueKey('hijri-month-title'));
      final before = tester.widget<Text>(title).data;
      await tester.tap(find.byKey(const ValueKey('hijri-next-month')));
      await settle(tester);
      expect(tester.widget<Text>(title).data, isNot(before));
      expect(find.byKey(const ValueKey('hijri-today')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hijri-today')));
      await settle(tester);
      expect(tester.widget<Text>(title).data, before);

      final sw = find.byKey(const ValueKey('occasion-reminders'));
      await tester.ensureVisible(sw);
      await settle(tester);
      expect(tester.widget<SwitchListTile>(sw).value, isFalse);
    });

    testWidgets('fits at 200% text with 48dp controls', (tester) async {
      await pump(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      final prev = tester.getSize(find.byKey(const ValueKey('hijri-prev')));
      expect(prev.width, greaterThanOrEqualTo(48));
      expect(prev.height, greaterThanOrEqualTo(48));
    });
  });
}
