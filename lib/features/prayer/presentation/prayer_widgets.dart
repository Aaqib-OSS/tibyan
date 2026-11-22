import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../domain/prayer_calc.dart';
import '../domain/prayer_settings.dart';

/// «الخميس ١٩ نوفمبر · ٩ جمادى الآخرة ١٤٤٨».
String dateLine(AppLocalizations l, DateTime day, int hijriOffset) {
  final digits = NumberFormatter(Locale(l.localeName));
  final greg = digits.decimal(
    DateFormat('EEEE d MMMM', l.localeName).format(day),
  );
  HijriCalendar.setLocal(l.localeName == 'ar' ? 'ar' : 'en');
  final h = hijriOf(day, hijriOffset);
  return '$greg · ${digits(h.hDay)} ${h.longMonthName} ${digits(h.hYear)}';
}

/// «بعد ١ ساعة و ١٢ دقيقة».
String untilLine(AppLocalizations l, Duration d) {
  final digits = NumberFormatter(Locale(l.localeName));
  final mins = d.inMinutes + (d.inSeconds % 60 > 0 ? 1 : 0);
  final h = mins ~/ 60;
  final m = mins % 60;
  return l.prayerIn(
    h > 0
        ? l.prayerHoursMinutes(digits(h), digits(m))
        : l.prayerMinutesOnly(digits(m)),
  );
}

/// A signed number of minutes («+٢»).
String signedMinutes(AppLocalizations l, int n) {
  final digits = NumberFormatter(Locale(l.localeName));
  if (n == 0) return digits(0);
  return '${n > 0 ? '+' : '−'}${digits(n.abs())}';
}

String methodName(AppLocalizations l, CalcMethod m) => switch (m) {
  CalcMethod.egyptian => l.methodEgyptian,
  CalcMethod.ummAlQura => l.methodUmmAlQura,
  CalcMethod.muslimWorldLeague => l.methodMwl,
  CalcMethod.karachi => l.methodKarachi,
  CalcMethod.northAmerica => l.methodNorthAmerica,
  CalcMethod.dubai => l.methodDubai,
  CalcMethod.kuwait => l.methodKuwait,
  CalcMethod.qatar => l.methodQatar,
  CalcMethod.singapore => l.methodSingapore,
  CalcMethod.turkey => l.methodTurkey,
  CalcMethod.moonsighting => l.methodMoonsighting,
};

String asrName(AppLocalizations l, AsrRule r) =>
    r == AsrRule.hanafi ? l.asrHanafi : l.asrShafii;

String soundName(AppLocalizations l, AlertSound s) => switch (s) {
  AlertSound.silent => l.soundSilent,
  AlertSound.tone => l.soundTone,
  AlertSound.adhan => l.soundAdhan,
};

IconData soundIcon(AlertSound s) => switch (s) {
  AlertSound.silent => Icons.notifications_none,
  AlertSound.tone => Icons.music_note_outlined,
  AlertSound.adhan => Icons.mosque_outlined,
};
