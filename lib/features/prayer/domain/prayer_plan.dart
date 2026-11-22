import 'package:flutter/foundation.dart';

import 'prayer_calc.dart';
import 'prayer_settings.dart';

/// How far ahead alerts are scheduled. They are planned again whenever the
/// app opens, so a week covers someone who does not open it for days.
const prayerDaysAhead = 7;

/// Notification ids of the prayer alerts: [prayerIdBase] up to (not
/// including) [prayerIdLimit]; clear of the khatma reminders (7100–7799).
const prayerIdBase = 9100;
const _slotsPerDay = 20;
const prayerIdLimit = prayerIdBase + prayerDaysAhead * _slotsPerDay;

/// iOS keeps at most 64 pending notifications per app, and the khatma
/// reminders need some: the prayer alerts take the earliest ones up to
/// this many there.
const appleMaxPrayerAlerts = 48;

/// What an alert announces.
enum AlertKind {
  /// The time of [PlannedAlert.prayer] has come.
  atTime,

  /// [PlannedAlert.minutes] before [PlannedAlert.prayer].
  before,

  /// Ramadan: [PlannedAlert.minutes] before Fajr (the end of suhoor).
  suhoor,

  /// Ramadan: [PlannedAlert.minutes] before Maghrib (iftar).
  iftar,
}

@immutable
class PlannedAlert {
  const PlannedAlert({
    required this.id,
    required this.at,
    required this.prayer,
    required this.kind,
    required this.sound,
    required this.prayerAt,
    this.minutes = 0,
    this.ramadan = false,
  });

  final int id;

  /// When it fires (an instant; UTC).
  final DateTime at;
  final PrayerKind prayer;
  final AlertKind kind;
  final AlertSound sound;

  /// The prayer's own time.
  final DateTime prayerAt;
  final int minutes;

  /// Maghrib in Ramadan: the alert also announces iftar.
  final bool ramadan;

  @override
  String toString() => 'PlannedAlert($id ${prayer.name} ${kind.name} $at)';
}

int _slot(PrayerKind p, AlertKind k) => switch (k) {
  AlertKind.atTime => p.index, // 0–6
  AlertKind.before => 7 + p.index, // 7–13
  AlertKind.suhoor => 14,
  AlertKind.iftar => 15,
};

/// Every alert of the next [prayerDaysAhead] days at the place (from its
/// today), after [now], earliest first. [adhanReady]: the adhan recording
/// is on the device; until then a prayer set to the adhan sounds the
/// gentle tone. [limit] keeps only the earliest ones.
List<PlannedAlert> planAlerts({
  required PrayerSettings settings,
  required DateTime now,
  required bool adhanReady,
  int? limit,
}) {
  final place = settings.place;
  if (!settings.enabled || place == null) return const [];
  final today = placeToday(place, now);
  final out = <PlannedAlert>[];
  for (var d = 0; d < prayerDaysAhead; d++) {
    final date = today.add(Duration(days: d));
    final day = computeDay(place, date, settings);
    final ramadan = isRamadan(date, settings.hijriOffset);
    void add(PrayerKind p, AlertKind k, AlertSound sound, {int minutes = 0}) {
      final prayerAt = day[p].toUtc();
      final at = prayerAt.subtract(Duration(minutes: minutes));
      if (!at.isAfter(now)) return;
      out.add(
        PlannedAlert(
          id: prayerIdBase + d * _slotsPerDay + _slot(p, k),
          at: at,
          prayer: p,
          kind: k,
          sound: sound,
          prayerAt: prayerAt,
          minutes: minutes,
          ramadan: ramadan && p == PrayerKind.maghrib,
        ),
      );
    }

    for (final p in obligatoryPrayers) {
      var sound = settings.soundOf(p);
      if (sound == AlertSound.adhan && !adhanReady) sound = AlertSound.tone;
      add(p, AlertKind.atTime, sound);
      final before = settings.reminderOf(p);
      if (before > 0) {
        add(p, AlertKind.before, AlertSound.tone, minutes: before);
      }
    }
    if (settings.shuruqAlert) {
      add(PrayerKind.shuruq, AlertKind.atTime, AlertSound.tone);
    }
    if (settings.duhaAlert) {
      add(PrayerKind.duha, AlertKind.atTime, AlertSound.tone);
    }
    if (ramadan && settings.suhoorAlert && settings.suhoorMinutes > 0) {
      add(
        PrayerKind.fajr,
        AlertKind.suhoor,
        AlertSound.tone,
        minutes: settings.suhoorMinutes,
      );
    }
    if (ramadan && settings.iftarAlert && settings.iftarMinutes > 0) {
      add(
        PrayerKind.maghrib,
        AlertKind.iftar,
        AlertSound.tone,
        minutes: settings.iftarMinutes,
      );
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  if (limit != null && out.length > limit) return out.sublist(0, limit);
  return out;
}
