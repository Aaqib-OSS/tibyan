import 'dart:ui' show Locale;

import 'package:hijri/hijri_calendar.dart';

import '../../../l10n/app_localizations.dart';
import '../../khatma/services/reminder_scheduler.dart';
import '../../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../domain/hijri_occasions.dart';
import '../domain/prayer_settings.dart';

/// Notification ids of the occasion reminders, one per occasion; clear of
/// the prayer alerts (9100–9239) and the adhan test (9399).
const occasionIdBase = 9400;

/// The occasion reminders' own Android notification channel.
const occasionChannelId = 'app.tibyan.occasions';

/// The link an occasion reminder opens: the Hijri calendar.
const occasionPayload = 'tibyan://prayer/hijri';

/// The hour (device time) of the reminder on the day before.
const occasionReminderHour = 20;

String occasionName(AppLocalizations l, HijriOccasion o) => switch (o) {
  HijriOccasion.newYear => l.occasionNewYear,
  HijriOccasion.ashura => l.occasionAshura,
  HijriOccasion.ramadanStart => l.occasionRamadanStart,
  HijriOccasion.lastTen => l.occasionLastTen,
  HijriOccasion.eidFitr => l.occasionEidFitr,
  HijriOccasion.arafah => l.occasionArafah,
  HijriOccasion.eidAdha => l.occasionEidAdha,
  HijriOccasion.tashreeq => l.occasionTashreeq,
};

/// «١٠ محرم», «١١–١٣ ذو الحجة»; the last ten: the month only.
String occasionDateLabel(AppLocalizations l, HijriOccasion o) {
  final digits = NumberFormatter(Locale(l.localeName));
  final month = hijriMonthName(l, o.month);
  if (o == HijriOccasion.lastTen) return month;
  if (o.days == 1) return '${digits(o.day)} $month';
  return '${digits(o.day)}–${digits(o.day + o.days - 1)} $month';
}

/// A Hijri month's name in the interface language (as in [dateLine]).
String hijriMonthName(AppLocalizations l, int month) {
  HijriCalendar.setLocal(l.localeName == 'ar' ? 'ar' : 'en');
  return (HijriCalendar()..hMonth = month).getLongMonthName();
}

/// Schedules (or clears) the day-before reminder of each occasion's next
/// start. Planned again whenever the app opens or the settings change.
Future<void> syncOccasionReminders(
  ReminderScheduler reminders,
  PrayerSettings s,
  AppLocalizations l, {
  DateTime? now,
}) async {
  for (final o in HijriOccasion.values) {
    await reminders.cancelOnce(occasionIdBase + o.index);
  }
  if (!s.occasionReminders) return;
  final when = now ?? DateTime.now();
  for (final u in upcomingOccasions(when, s.hijriOffset)) {
    final at = DateTime(
      u.start.year,
      u.start.month,
      u.start.day - 1,
      occasionReminderHour,
    );
    if (!at.isAfter(when)) continue;
    await reminders.scheduleOnce(
      id: occasionIdBase + u.occasion.index,
      at: at,
      title: l.occasionTomorrow(occasionName(l, u.occasion)),
      body: occasionDateLabel(l, u.occasion),
      payload: occasionPayload,
      channel: l.occasionChannel,
      channelId: occasionChannelId,
    );
  }
}
