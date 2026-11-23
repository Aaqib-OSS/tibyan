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
import 'package:tibyan/features/prayer/services/prayer_alarms.dart';
import 'package:tibyan/features/prayer/services/prayer_runtime.dart';
import 'package:tibyan/l10n/app_localizations.dart';
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
    List overrides = const [],
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
        ...overrides,
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
    await tester.tap(find.byKey(const ValueKey('prayer-mode-custom')));
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('prayer-length-short')),
      -200,
    );
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

  testWidgets('each prayer\'s adhan: summary rows and its own setup', (
    tester,
  ) async {
    final (container, fake) = await setUpScreen(
      tester,
      const PrayerSettingsScreen(),
    );
    final row = find.byKey(const ValueKey('prayer-adhan-row-maghrib'));
    await tester.scrollUntilVisible(row, 200);
    expect(
      find.descendant(of: row, matching: find.text('حسب العام')),
      findsOneWidget,
    );
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    await tester.tap(row);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('prayer-mode-custom')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('prayer-own-muezzin')));
    await settle(tester);
    await tester.tap(find.text('محمد صديق المنشاوي').last);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('prayer-own-length-short')));
    await settle(tester);
    final own = container
        .read(prayerSettingsProvider)
        .customOf(PrayerKind.maghrib);
    expect(own?.muezzin, 'minshawi');
    expect(own?.length, AdhanLength.short);
    // Not downloaded: offered here, through the download manager.
    await tester.tap(find.byKey(const ValueKey('prayer-own-download')));
    await settle(tester);
    expect(fake.enqueued.map((t) => t.url).join(), contains('minshawi'));
    expect(find.byKey(const ValueKey('prayer-own-try')), findsOneWidget);
    // Back to the general settings.
    await tester.tap(find.byKey(const ValueKey('prayer-mode-general')));
    await settle(tester);
    expect(
      container.read(prayerSettingsProvider).customOf(PrayerKind.maghrib),
      isNull,
    );
  });

  testWidgets('«جرّب» in the per-prayer sheet shows the toast', (tester) async {
    final alarms = _FakeAlarms();
    await setUpScreen(
      tester,
      const PrayerSettingsScreen(),
      overrides: [prayerAlarmsProvider.overrideWithValue(alarms)],
    );
    final row = find.byKey(const ValueKey('prayer-adhan-row-maghrib'));
    await tester.scrollUntilVisible(row, 200);
    await tester.tap(row);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('prayer-mode-custom')));
    await settle(tester);
    final tryIt = find.byKey(const ValueKey('prayer-own-try'));
    await tester.ensureVisible(tryIt);
    await tester.tap(tryIt);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(alarms.tested, PrayerKind.maghrib);
    expect(find.byKey(const ValueKey('prayer-own-try')), findsNothing);
    expect(find.textContaining('يبدأ الأذان بعد'), findsOneWidget);
  });

  testWidgets('the per-prayer sheet fits at 200% text', (tester) async {
    await setUpScreen(tester, const PrayerSettingsScreen(), textScale: 2);
    final row = find.byKey(const ValueKey('prayer-adhan-row-fajr'));
    await tester.scrollUntilVisible(row, 200);
    await tester.ensureVisible(row);
    await settle(tester);
    await tester.tap(row);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('prayer-mode-custom')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('prayer-mode-custom'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('the times rows show each prayer\'s adhan summary', (
    tester,
  ) async {
    final (container, _) = await setUpScreen(tester, const PrayerTimesScreen());
    Finder summary(String p) => find.byKey(ValueKey('prayer-summary-$p'));
    expect(tester.widget<Text>(summary('fajr')).data, 'حسب العام');
    expect(summary('shuruq'), findsNothing);
    await container
        .read(prayerSettingsProvider.notifier)
        .setCustom(
          PrayerKind.maghrib,
          const PrayerAdhan(muezzin: 'minshawi', length: AdhanLength.short),
        );
    await container
        .read(prayerSettingsProvider.notifier)
        .setSound(PrayerKind.isha, AlertSound.tone);
    await settle(tester);
    expect(
      tester.widget<Text>(summary('maghrib')).data,
      'محمد صديق المنشاوي · حتى «حي على الصلاة»',
    );
    expect(tester.widget<Text>(summary('isha')).data, 'نغمة هادئة');
    expect(
      find.bySemanticsLabel(RegExp('المغرب .*محمد صديق المنشاوي')),
      findsOneWidget,
    );
  });

  testWidgets('the summary fits at 200% text', (tester) async {
    final (container, _) = await setUpScreen(
      tester,
      const PrayerTimesScreen(),
      textScale: 2,
    );
    await container
        .read(prayerSettingsProvider.notifier)
        .setCustom(
          PrayerKind.fajr,
          const PrayerAdhan(
            muezzin: 'abdulbasit',
            length: AdhanLength.short,
            volume: 0.5,
          ),
        );
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('prayer-summary-fajr')), findsOneWidget);
  });
}

class _FakeAlarms implements PrayerAlarms {
  PrayerKind? tested;

  @override
  Future<void> testAdhan(
    PrayerSettings s,
    AppLocalizations l, {
    required Future<void> Function() playInApp,
    PrayerKind? prayer,
    void Function(String location)? showScene,
  }) async => tested = prayer;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
