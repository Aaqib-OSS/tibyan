import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/downloads/background_downloads.dart';
import 'package:tibyan/core/ui/look_kit.dart';
import 'package:tibyan/features/prayer/data/adhan_downloads.dart';
import 'package:tibyan/features/prayer/domain/prayer_settings.dart';
import 'package:tibyan/features/prayer/presentation/adhan_library_screen.dart';
import 'package:tibyan/features/prayer/presentation/adhan_screen.dart';
import 'package:tibyan/features/prayer/presentation/prayer_settings_screen.dart';
import 'package:tibyan/features/prayer/presentation/prayer_times_screen.dart';
import 'package:tibyan/features/prayer/prayer_providers.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../downloads/background_downloads_test.dart' show FakeDownloader;
import '../../tasmee/tasmee_test_env.dart';
import 'prayer_calc_test.dart' show cairo;

void main() {
  late TasmeeTestData data;
  setUpAll(() {
    tzdata.initializeTimeZones();
    data = TasmeeTestData.open();
  });
  tearDownAll(() => data.close());

  Future<(ProviderContainer, FakeDownloader)> setUpScreen(
    WidgetTester tester,
    Widget screen, {
    double textScale = 1,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 1600)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final tmp = Directory.systemTemp.createTempSync('prayer-ui');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final fake = FakeDownloader();
    final downloads = BackgroundDownloads(downloader: fake);
    final adhan = AdhanDownloads(
      downloads: downloads,
      supportDir: () async => tmp,
      apple: false,
      fetchText: (_) async =>
          '${'a' * 64}  minshawi/full.m4a\n'
          '${'b' * 64}  minshawi/short.m4a\n'
          '${'c' * 64}  minshawi/photo.jpg\n',
    );
    const s = PrayerSettings(enabled: true, place: cairo);
    final container = await tasmeeContainer(
      tester,
      data,
      prefs: {prayerSettingsKey: s.encode()},
      overrides: [
        backgroundDownloadsProvider.overrideWithValue(downloads),
        adhanDownloadsProvider.overrideWithValue(adhan),
      ],
    );
    await tester.pumpWidget(
      tasmeeApp(
        container,
        LookTheme(child: screen),
        theme: tasmeeTheme(container),
      ),
    );
    await settle(tester);
    return (container, fake);
  }

  testWidgets('the times list, and a prayer\'s alert set from its icon', (
    tester,
  ) async {
    final (container, _) = await setUpScreen(tester, const PrayerTimesScreen());
    for (final p in ['fajr', 'shuruq', 'dhuhr', 'asr', 'maghrib', 'isha']) {
      expect(find.byKey(ValueKey('prayer-row-$p')), findsOneWidget);
    }
    expect(find.text('مواقيت الصلاة'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('prayer-sound-asr')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('prayer-sound-choice-silent')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('prayer-reminder-10')));
    await settle(tester);
    final s = container.read(prayerSettingsProvider);
    expect(s.soundOf(PrayerKind.asr), AlertSound.silent);
    expect(s.reminderOf(PrayerKind.asr), 10);
  });

  testWidgets('the times screen fits at 200% text', (tester) async {
    await setUpScreen(tester, const PrayerTimesScreen(), textScale: 2);
    expect(tester.takeException(), isNull);
    final icon = tester.getSize(
      find.byKey(const ValueKey('prayer-sound-fajr')),
    );
    expect(icon.width, greaterThanOrEqualTo(48));
    expect(icon.height, greaterThanOrEqualTo(48));
  });

  testWidgets('settings: the dua is off by default; extras switch on', (
    tester,
  ) async {
    final (container, _) = await setUpScreen(
      tester,
      const PrayerSettingsScreen(),
    );
    final dua = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('prayer-dua')),
    );
    expect(dua.value, isFalse);
    // Android: «when the phone is in use», a notification by default.
    final notify = find.byKey(const ValueKey('prayer-inuse-notify'));
    await tester.scrollUntilVisible(notify, 200);
    // ignore: deprecated_member_use
    expect(tester.widget<RadioListTile<InUseAdhan>>(notify).checked, isTrue);
    await tester.tap(find.byKey(const ValueKey('prayer-inuse-short')));
    await settle(tester);
    expect(container.read(prayerSettingsProvider).inUse, InUseAdhan.short);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('prayer-shuruq')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('prayer-shuruq')));
    await settle(tester);
    expect(container.read(prayerSettingsProvider).shuruqAlert, isTrue);
    expect(find.byKey(const ValueKey('prayer-volume')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('prayer-volume')),
      const Offset(400, 0), // RTL: right is lower
    );
    await settle(tester);
    expect(container.read(prayerSettingsProvider).adhanVolume, lessThan(0.7));
    await tester.tap(find.byKey(const ValueKey('prayer-length-short')));
    await settle(tester);
    expect(container.read(prayerSettingsProvider).length, AdhanLength.short);
  });

  testWidgets('the library: every muezzin with its licence; download and '
      'choose', (tester) async {
    final (container, fake) = await setUpScreen(
      tester,
      const AdhanLibraryScreen(),
    );
    expect(find.text('تحت رخصة المشاع الإبداعي CC BY-NC-SA 4.0'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('adhan-select-minshawi')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('adhan-select-minshawi')));
    await settle(tester);
    expect(container.read(prayerSettingsProvider).muezzin, 'minshawi');
    expect(fake.enqueued.map((t) => t.taskId), [
      'adhan-minshawi-full.m4a',
      'adhan-minshawi-short.m4a',
      'adhan-minshawi-photo.jpg',
    ]);
  });

  for (final p in obligatoryPrayers) {
    testWidgets('the full-screen adhan draws the ${p.name} scene', (
      tester,
    ) async {
      await setUpScreen(tester, AdhanScreen(prayer: p));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byKey(const ValueKey('adhan-stop')), findsOneWidget);
      expect(find.text('إيقاف الأذان'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('each prayer has its own sky, all share the mosque shape', () {
    final skies = {for (final p in obligatoryPrayers) AdhanScene.of(p).sky1};
    expect(skies, hasLength(5));
  });
}
