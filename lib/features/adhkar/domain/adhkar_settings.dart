import 'dart:convert';

import 'package:flutter/foundation.dart';

/// How often the salawat reminder repeats.
enum RepeatUnit { minutes, hours }

/// «إعدادات الأذكار»: the morning and evening reminders and the salawat
/// reminder. Everything is off until the reader turns it on.
@immutable
class AdhkarSettings {
  const AdhkarSettings({
    this.morningOn = false,
    this.morningAt = 6 * 60,
    this.eveningOn = false,
    this.eveningAt = 17 * 60,
    this.salawatOn = false,
    this.salawatEvery = 2,
    this.salawatUnit = RepeatUnit.hours,
    this.windowOn = false,
    this.windowFrom = 9 * 60,
    this.windowTo = 21 * 60,
  });

  final bool morningOn;

  /// Minutes after midnight (device time).
  final int morningAt;
  final bool eveningOn;
  final int eveningAt;
  final bool salawatOn;
  final int salawatEvery;
  final RepeatUnit salawatUnit;

  /// Only between [windowFrom] and [windowTo] (minutes of the day; a
  /// window may pass midnight).
  final bool windowOn;
  final int windowFrom;
  final int windowTo;

  /// The shortest repeat allowed.
  static const minMinutes = 15;

  Duration get interval {
    final d = salawatUnit == RepeatUnit.hours
        ? Duration(hours: salawatEvery)
        : Duration(minutes: salawatEvery);
    return d < const Duration(minutes: minMinutes)
        ? const Duration(minutes: minMinutes)
        : d;
  }

  AdhkarSettings copyWith({
    bool? morningOn,
    int? morningAt,
    bool? eveningOn,
    int? eveningAt,
    bool? salawatOn,
    int? salawatEvery,
    RepeatUnit? salawatUnit,
    bool? windowOn,
    int? windowFrom,
    int? windowTo,
  }) => AdhkarSettings(
    morningOn: morningOn ?? this.morningOn,
    morningAt: morningAt ?? this.morningAt,
    eveningOn: eveningOn ?? this.eveningOn,
    eveningAt: eveningAt ?? this.eveningAt,
    salawatOn: salawatOn ?? this.salawatOn,
    salawatEvery: (salawatEvery ?? this.salawatEvery).clamp(1, 999),
    salawatUnit: salawatUnit ?? this.salawatUnit,
    windowOn: windowOn ?? this.windowOn,
    windowFrom: windowFrom ?? this.windowFrom,
    windowTo: windowTo ?? this.windowTo,
  );

  String encode() => jsonEncode({
    'morningOn': morningOn,
    'morningAt': morningAt,
    'eveningOn': eveningOn,
    'eveningAt': eveningAt,
    'salawatOn': salawatOn,
    'salawatEvery': salawatEvery,
    'salawatUnit': salawatUnit.name,
    'windowOn': windowOn,
    'windowFrom': windowFrom,
    'windowTo': windowTo,
  });

  static AdhkarSettings decode(String? s) {
    if (s == null || s.isEmpty) return const AdhkarSettings();
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      const d = AdhkarSettings();
      int i(String k, int def) => (j[k] as num?)?.toInt() ?? def;
      return AdhkarSettings(
        morningOn: j['morningOn'] as bool? ?? false,
        morningAt: i('morningAt', d.morningAt).clamp(0, 1439),
        eveningOn: j['eveningOn'] as bool? ?? false,
        eveningAt: i('eveningAt', d.eveningAt).clamp(0, 1439),
        salawatOn: j['salawatOn'] as bool? ?? false,
        salawatEvery: i('salawatEvery', d.salawatEvery).clamp(1, 999),
        salawatUnit:
            RepeatUnit.values
                .where((u) => u.name == j['salawatUnit'])
                .firstOrNull ??
            d.salawatUnit,
        windowOn: j['windowOn'] as bool? ?? false,
        windowFrom: i('windowFrom', d.windowFrom).clamp(0, 1439),
        windowTo: i('windowTo', d.windowTo).clamp(0, 1439),
      );
    } catch (_) {
      return const AdhkarSettings();
    }
  }
}

/// Whether [minute] of the day is inside the window [from]…[to] (which may
/// pass midnight; equal ends: the whole day).
bool inWindow(int minute, int from, int to) {
  if (from == to) return true;
  return from < to
      ? minute >= from && minute < to
      : minute >= from || minute < to;
}

/// The next salawat reminders after [now] (device time), at most [limit],
/// within [horizon]. They repeat every interval from the start of the
/// window (or from midnight), so the times stay the same from day to day.
List<DateTime> planSalawat(
  AdhkarSettings s,
  DateTime now, {
  int limit = 24,
  Duration horizon = const Duration(days: 2),
}) {
  if (!s.salawatOn) return const [];
  final step = s.interval.inMinutes;
  final out = <DateTime>[];
  final end = now.add(horizon);
  var day = DateTime(now.year, now.month, now.day - 1);
  while (out.length < limit && day.isBefore(end)) {
    final start = s.windowOn ? s.windowFrom : 0;
    for (var m = start; m < start + 24 * 60; m += step) {
      final minute = m % (24 * 60);
      if (s.windowOn && !inWindow(minute, s.windowFrom, s.windowTo)) break;
      final at = DateTime(day.year, day.month, day.day, 0, m);
      if (at.isAfter(now) && at.isBefore(end)) out.add(at);
      if (out.length >= limit) break;
    }
    day = DateTime(day.year, day.month, day.day + 1);
  }
  out.sort();
  // A window passing midnight can repeat a time across two days' runs.
  final unique = <DateTime>[];
  for (final t in out) {
    if (unique.isEmpty || unique.last != t) unique.add(t);
  }
  return unique.take(limit).toList();
}
