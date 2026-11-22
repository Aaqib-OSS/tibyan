import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/prayer/domain/prayer_calc.dart';
import 'package:tibyan/features/prayer/domain/prayer_settings.dart';
import 'package:timezone/data/latest.dart' as tzdata;

const cairo = PrayerPlace(
  name: 'Cairo',
  arabicName: 'القاهرة',
  country: 'EG',
  lat: 30.0444,
  lon: 31.2357,
  timeZone: 'Africa/Cairo',
);

const makkah = PrayerPlace(
  name: 'Mecca',
  arabicName: 'مكة',
  country: 'SA',
  lat: 21.4225,
  lon: 39.8262,
  timeZone: 'Asia/Riyadh',
);

const london = PrayerPlace(
  name: 'London',
  arabicName: 'لندن',
  country: 'GB',
  lat: 51.5074,
  lon: -0.1278,
  timeZone: 'Europe/London',
);

const newYork = PrayerPlace(
  name: 'New York',
  arabicName: 'نيويورك',
  country: 'US',
  lat: 40.7128,
  lon: -74.0060,
  timeZone: 'America/New_York',
);

/// The wall-clock minutes of a time (hour * 60 + minute) at its place.
int clock(DateTime t) => t.hour * 60 + t.minute;

void expectNear(DateTime t, int h, int m, {int slack = 3}) {
  expect(
    (clock(t) - (h * 60 + m)).abs(),
    lessThanOrEqualTo(slack),
    reason: 'got ${t.hour}:${t.minute}, want $h:$m',
  );
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('default method by country', () {
    test('Egypt uses the Egyptian authority, Saudi Arabia Umm al-Qura', () {
      expect(defaultMethodFor('EG'), CalcMethod.egyptian);
      expect(defaultMethodFor('SA'), CalcMethod.ummAlQura);
      expect(defaultMethodFor('US'), CalcMethod.northAmerica);
      expect(defaultMethodFor('FR'), CalcMethod.muslimWorldLeague);
      expect(defaultMethodFor(null), CalcMethod.muslimWorldLeague);
    });

    test('a chosen method wins over the country', () {
      const s = PrayerSettings(place: cairo, method: CalcMethod.karachi);
      expect(s.effectiveMethod, CalcMethod.karachi);
      expect(
        const PrayerSettings(place: cairo).effectiveMethod,
        CalcMethod.egyptian,
      );
    });
  });

  group('calculation per method and time zone', () {
    test('Cairo, Egyptian authority, in Cairo time', () {
      final d = computeDay(
        cairo,
        DateTime(2026, 1, 15),
        const PrayerSettings(place: cairo),
      );
      // Published Egyptian timetable for 15 January 2026 (±3 min).
      expectNear(d[PrayerKind.fajr], 5, 20);
      expectNear(d[PrayerKind.shuruq], 6, 50);
      expectNear(d[PrayerKind.dhuhr], 12, 3);
      expectNear(d[PrayerKind.maghrib], 17, 15);
      expect(d[PrayerKind.fajr].location.name, 'Africa/Cairo');
      expect(d[PrayerKind.fajr].timeZoneOffset, const Duration(hours: 2));
    });

    test('Makkah, Umm al-Qura: Isha 90 minutes after Maghrib', () {
      final d = computeDay(
        makkah,
        DateTime(2026, 3, 1),
        const PrayerSettings(place: makkah),
      );
      expect(
        d[PrayerKind.isha].difference(d[PrayerKind.maghrib]).inMinutes,
        90,
      );
      expect(d[PrayerKind.dhuhr].timeZoneOffset, const Duration(hours: 3));
    });

    test('methods differ where their angles differ', () {
      final day = DateTime(2026, 6, 1);
      final egypt = computeDay(cairo, day, const PrayerSettings(place: cairo));
      final mwl = computeDay(
        cairo,
        day,
        const PrayerSettings(
          place: cairo,
          method: CalcMethod.muslimWorldLeague,
        ),
      );
      // Fajr at 19.5° (Egypt) is earlier than at 18° (MWL).
      expect(egypt[PrayerKind.fajr].isBefore(mwl[PrayerKind.fajr]), isTrue);
    });

    test('Hanafi Asr comes later than the majority', () {
      final day = DateTime(2026, 4, 10);
      final shafii = computeDay(cairo, day, const PrayerSettings(place: cairo));
      final hanafi = computeDay(
        cairo,
        day,
        const PrayerSettings(place: cairo, asr: AsrRule.hanafi),
      );
      final gap = hanafi[PrayerKind.asr].difference(shafii[PrayerKind.asr]);
      expect(gap.inMinutes, greaterThan(30));
    });

    test('each prayer moves by its own minutes', () {
      final day = DateTime(2026, 4, 10);
      final base = computeDay(cairo, day, const PrayerSettings(place: cairo));
      final moved = computeDay(
        cairo,
        day,
        const PrayerSettings(
          place: cairo,
          offsets: {PrayerKind.maghrib: 3, PrayerKind.fajr: -2},
        ),
      );
      expect(
        moved[PrayerKind.maghrib].difference(base[PrayerKind.maghrib]),
        const Duration(minutes: 3),
      );
      expect(
        moved[PrayerKind.fajr].difference(base[PrayerKind.fajr]),
        const Duration(minutes: -2),
      );
      expect(moved[PrayerKind.dhuhr], base[PrayerKind.dhuhr]);
    });

    test('the same instant whatever the device zone (computed in UTC)', () {
      final d = computeDay(
        newYork,
        DateTime(2026, 1, 15),
        const PrayerSettings(place: newYork),
      );
      expect(d[PrayerKind.dhuhr].timeZoneOffset, const Duration(hours: -5));
      expectNear(d[PrayerKind.dhuhr], 12, 6);
    });

    test('Duha is twenty minutes after sunrise', () {
      final d = computeDay(
        cairo,
        DateTime(2026, 4, 10),
        const PrayerSettings(place: cairo),
      );
      expect(
        d[PrayerKind.duha].difference(d[PrayerKind.shuruq]),
        duhaAfterSunrise,
      );
    });
  });

  group('summer time', () {
    test('New York: Dhuhr keeps its clock time across the March change', () {
      const s = PrayerSettings(place: newYork);
      final before = computeDay(newYork, DateTime(2026, 3, 7), s);
      final after = computeDay(newYork, DateTime(2026, 3, 9), s);
      expect(before[PrayerKind.dhuhr].timeZoneOffset.inHours, -5);
      expect(after[PrayerKind.dhuhr].timeZoneOffset.inHours, -4);
      // The sun moved a few minutes; the clock jumped an hour with it.
      expect(
        (clock(after[PrayerKind.dhuhr]) - clock(before[PrayerKind.dhuhr]))
            .abs(),
        greaterThan(50),
      );
    });

    test('London: offsets follow BST', () {
      const s = PrayerSettings(place: london);
      expect(
        computeDay(
          london,
          DateTime(2026, 7, 1),
          s,
        )[PrayerKind.dhuhr].timeZoneOffset,
        const Duration(hours: 1),
      );
      expect(
        computeDay(
          london,
          DateTime(2026, 12, 1),
          s,
        )[PrayerKind.dhuhr].timeZoneOffset,
        Duration.zero,
      );
    });

    test('Cairo: Egypt\'s summer time is applied by the zone rules', () {
      const s = PrayerSettings(place: cairo);
      final summer = computeDay(cairo, DateTime(2026, 7, 15), s);
      expect(summer[PrayerKind.dhuhr].timeZoneOffset.inHours, 3);
      expectNear(summer[PrayerKind.dhuhr], 13, 0, slack: 6);
    });
  });

  group('next prayer and hijri', () {
    test('after Isha the next prayer is tomorrow\'s Fajr', () {
      const s = PrayerSettings(place: cairo);
      final day = computeDay(cairo, DateTime(2026, 4, 10), s);
      final next = nextPrayer(
        cairo,
        day[PrayerKind.isha].add(const Duration(minutes: 1)),
        s,
      )!;
      expect(next.prayer, PrayerKind.fajr);
      expect(next.at.day, 11);
    });

    test('Umm al-Qura date with a manual adjustment', () {
      // 1 Ramadan 1447 = 18 February 2026 (Umm al-Qura).
      expect(hijriOf(DateTime(2026, 2, 18), 0).hMonth, 9);
      expect(hijriOf(DateTime(2026, 2, 18), 0).hDay, 1);
      expect(hijriOf(DateTime(2026, 2, 18), -1).hMonth, 8);
      expect(hijriOf(DateTime(2026, 2, 18), 2).hDay, 3);
      expect(isRamadan(DateTime(2026, 3, 1), 0), isTrue);
      expect(isRamadan(DateTime(2026, 4, 1), 0), isFalse);
    });
  });
}
