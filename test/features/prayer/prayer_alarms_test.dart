import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/prayer/domain/prayer_plan.dart';
import 'package:tibyan/features/prayer/domain/prayer_settings.dart';
import 'package:tibyan/features/prayer/services/prayer_alarms.dart';
import 'package:tibyan/l10n/app_localizations.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'prayer_calc_test.dart' show cairo;

void main() {
  setUpAll(tzdata.initializeTimeZones);
  final ar = lookupAppLocalizations(const Locale('ar'));
  final en = lookupAppLocalizations(const Locale('en'));
  // 16:59 Cairo (UTC+2 in November).
  final maghrib = DateTime.utc(2026, 11, 19, 14, 59);

  PlannedAlert alert(AlertKind kind, {int minutes = 0, bool ramadan = false}) =>
      PlannedAlert(
        id: prayerIdBase,
        at: maghrib.subtract(Duration(minutes: minutes)),
        prayer: PrayerKind.maghrib,
        kind: kind,
        sound: AlertSound.adhan,
        prayerAt: maghrib,
        minutes: minutes,
        ramadan: ramadan,
      );

  test('times read in the place\'s zone, Arabic digits in Arabic', () {
    expect(formatPrayerTime(ar, maghrib, cairo), '٤:٥٩ م');
    expect(formatPrayerTime(en, maghrib, cairo), '4:59 PM');
  });

  test('alert texts', () {
    expect(
      alertTexts(ar, alert(AlertKind.atTime), cairo).title,
      'حان الآن موعد أذان المغرب',
    );
    expect(
      alertTexts(ar, alert(AlertKind.atTime), cairo).body,
      'القاهرة · ٤:٥٩ م',
    );
    expect(
      alertTexts(ar, alert(AlertKind.before, minutes: 10), cairo).title,
      'بقي ١٠ دقائق على أذان المغرب',
    );
    expect(
      alertTexts(ar, alert(AlertKind.iftar, minutes: 15), cairo).title,
      'بقي ١٥ دقيقة على الإفطار',
    );
    expect(
      alertTexts(ar, alert(AlertKind.atTime, ramadan: true), cairo).title,
      'حان موعد الإفطار: أذان المغرب',
    );
    expect(
      alertTexts(en, alert(AlertKind.before, minutes: 5), cairo).title,
      '5 minutes to the Maghrib adhan',
    );
  });

  test('the adhan alert opens the full-screen adhan', () {
    expect(
      alertPayload(alert(AlertKind.atTime)),
      'tibyan://prayer/adhan?p=maghrib&at=${maghrib.millisecondsSinceEpoch}',
    );
    expect(
      alertPayload(alert(AlertKind.before, minutes: 5)),
      'tibyan://prayer',
    );
  });
}
