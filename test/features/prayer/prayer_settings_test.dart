import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tibyan/core/settings/settings_controller.dart';
import 'package:tibyan/features/prayer/data/cities.dart';
import 'package:tibyan/features/prayer/domain/prayer_settings.dart';
import 'package:tibyan/features/prayer/prayer_providers.dart';

import 'prayer_calc_test.dart' show cairo;

void main() {
  group('PrayerSettings', () {
    test('defaults: off, Refaat, full adhan, extras off, dua off', () {
      const s = PrayerSettings();
      expect(s.enabled, isFalse);
      expect(s.muezzin, 'refaat');
      expect(s.length, AdhanLength.full);
      expect(s.shuruqAlert, isFalse);
      expect(s.duhaAlert, isFalse);
      expect(s.duaAfter, isFalse);
      expect(s.asr, AsrRule.shafii);
      expect(s.hijriOffset, 0);
      expect(s.soundOf(PrayerKind.fajr), AlertSound.adhan);
      expect(s.reminderOf(PrayerKind.fajr), 0);
    });

    test('round-trips through JSON', () {
      final s = const PrayerSettings().copyWith(
        enabled: true,
        place: cairo,
        method: CalcMethod.ummAlQura,
        asr: AsrRule.hanafi,
        offsets: {PrayerKind.maghrib: 2},
        sounds: {PrayerKind.isha: AlertSound.silent},
        reminders: {PrayerKind.dhuhr: 15},
        shuruqAlert: true,
        hijriOffset: -1,
        muezzin: 'minshawi',
        length: AdhanLength.short,
        duaAfter: true,
        tray: true,
      );
      final back = PrayerSettings.decode(s.encode());
      expect(back.enabled, isTrue);
      expect(back.place, cairo);
      expect(back.method, CalcMethod.ummAlQura);
      expect(back.asr, AsrRule.hanafi);
      expect(back.offsetOf(PrayerKind.maghrib), 2);
      expect(back.soundOf(PrayerKind.isha), AlertSound.silent);
      expect(back.reminderOf(PrayerKind.dhuhr), 15);
      expect(back.shuruqAlert, isTrue);
      expect(back.hijriOffset, -1);
      expect(back.muezzin, 'minshawi');
      expect(back.length, AdhanLength.short);
      expect(back.duaAfter, isTrue);
      expect(back.tray, isTrue);
    });

    test('broken or missing values fall back to defaults', () {
      expect(PrayerSettings.decode(null).enabled, isFalse);
      expect(PrayerSettings.decode('not json').muezzin, 'refaat');
      final s = PrayerSettings.decode(
        '{"enabled":true,"method":"nope","hijri":9,"offsets":{"fajr":99}}',
      );
      expect(s.enabled, isTrue);
      expect(s.method, isNull);
      expect(s.hijriOffset, 2);
      expect(s.offsetOf(PrayerKind.fajr), PrayerSettings.maxOffset);
    });

    test('clearing the method returns to the country default', () {
      final s = const PrayerSettings(
        place: cairo,
        method: CalcMethod.karachi,
      ).copyWith(clearMethod: true);
      expect(s.method, isNull);
      expect(s.effectiveMethod, CalcMethod.egyptian);
    });
  });

  group('PrayerSettingsController', () {
    Future<ProviderContainer> make() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      return ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
    }

    test('persists changes and reads them back', () async {
      final c = await make();
      final n = c.read(prayerSettingsProvider.notifier);
      await n.update((s) => s.copyWith(enabled: true, place: cairo));
      await n.setSound(PrayerKind.asr, AlertSound.tone);
      await n.setReminder(PrayerKind.asr, 5);
      await n.setOffset(PrayerKind.asr, 100);
      final prefs = c.read(sharedPreferencesProvider);
      final stored = PrayerSettings.decode(prefs.getString(prayerSettingsKey));
      expect(stored.enabled, isTrue);
      expect(stored.soundOf(PrayerKind.asr), AlertSound.tone);
      expect(stored.reminderOf(PrayerKind.asr), 5);
      expect(stored.offsetOf(PrayerKind.asr), PrayerSettings.maxOffset);
    });

    test('«apply to all» copies one prayer\'s sound and reminder', () async {
      final c = await make();
      final n = c.read(prayerSettingsProvider.notifier);
      await n.setSound(PrayerKind.maghrib, AlertSound.silent);
      await n.setReminder(PrayerKind.maghrib, 10);
      await n.applyToAll(PrayerKind.maghrib);
      final s = c.read(prayerSettingsProvider);
      for (final p in obligatoryPrayers) {
        expect(s.soundOf(p), AlertSound.silent);
        expect(s.reminderOf(p), 10);
      }
    });
  });

  group('CityList', () {
    const tsv =
        '# header\n'
        '#tz\tAfrica/Cairo\tAsia/Riyadh\n'
        '#cc\tEG=Egypt\tSA=Saudi Arabia\n'
        'Cairo\tالقاهرة\tEG\t30.063\t31.250\t0\n'
        'Alexandria\tالإسكندرية\tEG\t31.202\t29.916\t0\n'
        'Riyadh\tالرياض\tSA\t24.688\t46.722\t1\n';

    test('parses names, zones and countries', () {
      final list = CityList.parse(tsv);
      expect(list.cities, hasLength(3));
      expect(list.cities[2].timeZone, 'Asia/Riyadh');
      expect(list.countries['SA'], 'Saudi Arabia');
    });

    test('searches in Arabic (with or without ال and hamza) and English', () {
      final list = CityList.parse(tsv);
      expect(list.search('cai').single.name, 'Cairo');
      expect(list.search('القاه').single.name, 'Cairo');
      expect(list.search('اسكندريه').single.name, 'Alexandria');
      expect(list.search('رياض').single.name, 'Riyadh');
    });

    test('the nearest city to a position', () {
      final list = CityList.parse(tsv);
      expect(list.nearest(30.0, 31.2)!.name, 'Cairo');
      expect(list.nearest(24.7, 46.7)!.name, 'Riyadh');
    });
  });
}
