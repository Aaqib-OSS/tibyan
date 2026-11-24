import 'package:timezone/timezone.dart' as tz;

import 'prayer_calc.dart';
import 'prayer_settings.dart';

/// The stretch of time [now] falls in: the last of the five prayers whose
/// time has come and the next one. After Isha the next is tomorrow's Fajr;
/// before Fajr the previous is yesterday's Isha.
typedef PrayerWindow = ({
  PrayerKind previous,
  tz.TZDateTime previousAt,
  PrayerKind next,
  tz.TZDateTime nextAt,
});

PrayerWindow prayerWindow(PrayerPlace place, DateTime now, PrayerSettings s) {
  final today = placeToday(place, now);
  final times = <(PrayerKind, tz.TZDateTime)>[
    for (var d = -1; d <= 1; d++)
      for (final p in obligatoryPrayers)
        (p, computeDay(place, today.add(Duration(days: d)), s)[p]),
  ];
  final i = times.indexWhere((e) => e.$2.isAfter(now));
  // Yesterday's Isha always precedes now, so i >= 1.
  final prev = times[i - 1];
  final next = times[i];
  return (
    previous: prev.$1,
    previousAt: prev.$2,
    next: next.$1,
    nextAt: next.$2,
  );
}

/// How far [now] is from the previous prayer to the next, 0 to 1.
double windowProgress(PrayerWindow w, DateTime now) {
  final total = w.nextAt.difference(w.previousAt).inSeconds;
  if (total <= 0) return 1;
  return (now.difference(w.previousAt).inSeconds / total).clamp(0.0, 1.0);
}

/// «HH:MM:SS» of [left], never negative; [digits] turns a number into the
/// interface's numerals.
String formatCountdown(Duration left, String Function(int) digits) {
  final secs = left.isNegative ? 0 : left.inSeconds;
  String two(int n) {
    final d = digits(n);
    return n < 10 ? '${digits(0)}$d' : d;
  }

  return '${two(secs ~/ 3600)}:${two(secs % 3600 ~/ 60)}:${two(secs % 60)}';
}
