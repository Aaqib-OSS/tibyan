import 'package:adhan/adhan.dart' as adhan;
import 'package:flutter/foundation.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:timezone/timezone.dart' as tz;

import 'prayer_settings.dart';

/// The forenoon prayer's time, after sunrise.
const duhaAfterSunrise = Duration(minutes: 20);

/// One day's times at a place, as instants in the place's time zone.
@immutable
class PrayerDay {
  const PrayerDay({required this.date, required this.times});

  /// The calendar day at the place.
  final DateTime date;
  final Map<PrayerKind, tz.TZDateTime> times;

  tz.TZDateTime operator [](PrayerKind p) => times[p]!;
}

adhan.CalculationMethod _method(CalcMethod m) => switch (m) {
  CalcMethod.egyptian => adhan.CalculationMethod.egyptian,
  CalcMethod.ummAlQura => adhan.CalculationMethod.umm_al_qura,
  CalcMethod.muslimWorldLeague => adhan.CalculationMethod.muslim_world_league,
  CalcMethod.karachi => adhan.CalculationMethod.karachi,
  CalcMethod.northAmerica => adhan.CalculationMethod.north_america,
  CalcMethod.dubai => adhan.CalculationMethod.dubai,
  CalcMethod.kuwait => adhan.CalculationMethod.kuwait,
  CalcMethod.qatar => adhan.CalculationMethod.qatar,
  CalcMethod.singapore => adhan.CalculationMethod.singapore,
  CalcMethod.turkey => adhan.CalculationMethod.turkey,
  CalcMethod.moonsighting => adhan.CalculationMethod.moon_sighting_committee,
};

/// The place's time zone; UTC when the name is unknown (the database must
/// be initialised first: `timezone/data/latest.dart`).
tz.Location locationOf(PrayerPlace place) {
  try {
    return tz.getLocation(place.timeZone);
  } catch (_) {
    return tz.UTC;
  }
}

/// Computes [date]'s times (the calendar day at the place) on the device.
/// The adhan package works in UTC; each instant is then given in the
/// place's IANA zone, so summer time is applied by the zone's own rules.
PrayerDay computeDay(PrayerPlace place, DateTime date, PrayerSettings s) {
  final params = _method(s.effectiveMethod).getParameters()
    ..madhab = s.asr == AsrRule.hanafi
        ? adhan.Madhab.hanafi
        : adhan.Madhab.shafi
    ..adjustments = adhan.PrayerAdjustments(
      fajr: s.offsetOf(PrayerKind.fajr),
      sunrise: s.offsetOf(PrayerKind.shuruq),
      dhuhr: s.offsetOf(PrayerKind.dhuhr),
      asr: s.offsetOf(PrayerKind.asr),
      maghrib: s.offsetOf(PrayerKind.maghrib),
      isha: s.offsetOf(PrayerKind.isha),
    );
  if (place.lat.abs() > 48) {
    params.highLatitudeRule = adhan.HighLatitudeRule.seventh_of_the_night;
  }
  final t = adhan.PrayerTimes.utc(
    adhan.Coordinates(place.lat, place.lon),
    adhan.DateComponents(date.year, date.month, date.day),
    params,
  );
  final loc = locationOf(place);
  tz.TZDateTime at(DateTime utc) => tz.TZDateTime.from(utc.toUtc(), loc);
  final sunrise = at(t.sunrise);
  return PrayerDay(
    date: DateTime(date.year, date.month, date.day),
    times: {
      PrayerKind.fajr: at(t.fajr),
      PrayerKind.shuruq: sunrise,
      PrayerKind.duha: sunrise
          .add(duhaAfterSunrise)
          .add(Duration(minutes: s.offsetOf(PrayerKind.duha))),
      PrayerKind.dhuhr: at(t.dhuhr),
      PrayerKind.asr: at(t.asr),
      PrayerKind.maghrib: at(t.maghrib),
      PrayerKind.isha: at(t.isha),
    },
  );
}

/// Today at the place (its own calendar day, not the device's).
DateTime placeToday(PrayerPlace place, DateTime now) {
  final local = tz.TZDateTime.from(now.toUtc(), locationOf(place));
  return DateTime(local.year, local.month, local.day);
}

/// The next of the five prayers after [now], looking into tomorrow.
({PrayerKind prayer, tz.TZDateTime at})? nextPrayer(
  PrayerPlace place,
  DateTime now,
  PrayerSettings s,
) {
  final today = placeToday(place, now);
  for (var d = 0; d < 2; d++) {
    final day = computeDay(place, today.add(Duration(days: d)), s);
    for (final p in obligatoryPrayers) {
      if (day[p].isAfter(now)) return (prayer: p, at: day[p]);
    }
  }
  return null;
}

/// The Umm al-Qura date of [date], moved by the reader's ±days.
HijriCalendar hijriOf(DateTime date, int offset) =>
    HijriCalendar.fromDate(date.add(Duration(days: offset)));

/// Whether [date] falls in Ramadan (with the reader's adjustment).
bool isRamadan(DateTime date, int offset) => hijriOf(date, offset).hMonth == 9;
