import 'package:hijri/hijri_calendar.dart';

import 'prayer_calc.dart';

/// The well-known fixed-date occasions of the Hijri year, shown by name and
/// date only.
enum HijriOccasion {
  newYear(1, 1),
  ashura(1, 10),
  ramadanStart(9, 1),
  lastTen(9, 21, days: 10),
  eidFitr(10, 1),
  arafah(12, 9),
  eidAdha(12, 10),
  tashreeq(12, 11, days: 3);

  const HijriOccasion(this.month, this.day, {this.days = 1});

  final int month;
  final int day;

  /// How many days it lasts (the last ten: until the month ends).
  final int days;
}

/// A Hijri month: year and month (1…12).
typedef HijriMonth = ({int year, int month});

HijriMonth hijriMonthOf(DateTime day, int offset) {
  final h = hijriOf(day, offset);
  return (year: h.hYear, month: h.hMonth);
}

HijriMonth shiftMonth(HijriMonth m, int by) {
  final i = m.year * 12 + (m.month - 1) + by;
  return (year: i ~/ 12, month: i % 12 + 1);
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The Gregorian day that is Hijri [year]/[month]/[day] with the reader's
/// ±days.
DateTime gregorianOf(int year, int month, int day, int offset) {
  final g = _dateOnly(HijriCalendar().hijriToGregorian(year, month, day));
  var d = DateTime(g.year, g.month, g.day - offset);
  // Guard against the table and the conversion disagreeing by a day.
  for (var i = 0; i < 3; i++) {
    final h = hijriOf(d, offset);
    final diff =
        (h.hYear * 400 + h.hMonth * 31 + h.hDay) -
        (year * 400 + month * 31 + day);
    if (diff == 0) break;
    d = DateTime(d.year, d.month, d.day - diff.sign);
  }
  return d;
}

/// How many days Hijri [month] has (Umm al-Qura).
int hijriMonthLength(HijriMonth m) =>
    HijriCalendar().getDaysInMonth(m.year, m.month);

/// The occasions that start in [m].
List<HijriOccasion> occasionsIn(HijriMonth m) => [
  for (final o in HijriOccasion.values)
    if (o.month == m.month) o,
];

/// The occasion covering Hijri day [day] of month [month], if any.
HijriOccasion? occasionOn(int month, int day) {
  for (final o in HijriOccasion.values) {
    if (o.month == month && day >= o.day && day < o.day + o.days) return o;
  }
  return null;
}

/// An occasion on the Gregorian calendar.
typedef OccasionDate = ({HijriOccasion occasion, DateTime start, int year});

/// The next starts of the occasions from [today] (today included),
/// soonest first, covering [count] occasions.
List<OccasionDate> upcomingOccasions(
  DateTime today,
  int offset, {
  int count = 8,
}) {
  final day = _dateOnly(today);
  final year = hijriOf(day, offset).hYear;
  final out = <OccasionDate>[];
  for (var y = year; y <= year + 1; y++) {
    for (final o in HijriOccasion.values) {
      final start = gregorianOf(y, o.month, o.day, offset);
      final end = DateTime(start.year, start.month, start.day + o.days - 1);
      if (end.isBefore(day)) continue;
      out.add((occasion: o, start: start, year: y));
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out.take(count).toList();
}

/// Whole days from [today] to [day] (0: today).
int daysUntil(DateTime today, DateTime day) => DateTime.utc(
  day.year,
  day.month,
  day.day,
).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
