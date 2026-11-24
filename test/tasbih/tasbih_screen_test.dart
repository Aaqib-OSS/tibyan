import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tibyan/core/db/user_database.dart';
import 'package:tibyan/core/settings/settings_controller.dart';
import 'package:tibyan/core/theme/app_theme.dart';
import 'package:tibyan/core/theme/theme_registry.dart';
import 'package:tibyan/core/theme/theme_tokens.dart';
import 'package:tibyan/core/ui/look_kit.dart';
import 'package:tibyan/features/mushaf/mushaf_providers.dart';
import 'package:tibyan/features/tasbih/domain/dhikr.dart';
import 'package:tibyan/features/tasbih/domain/tasbih_counter.dart';
import 'package:tibyan/features/tasbih/platform/tasbih_platform.dart';
import 'package:tibyan/features/tasbih/presentation/dhikr_sheet.dart';
import 'package:tibyan/features/tasbih/presentation/styles/counter_styles.dart';
import 'package:tibyan/features/tasbih/presentation/styles/misbaha_view.dart';
import 'package:tibyan/features/tasbih/presentation/tasbih_log_screen.dart';
import 'package:tibyan/features/tasbih/presentation/tasbih_screen.dart';
import 'package:tibyan/features/tasbih/tasbih_providers.dart';
import 'package:tibyan/features/tasbih/tasbih_settings.dart';
import 'package:tibyan/l10n/app_localizations.dart';

import '../support/meta_finders.dart';

late ThemeData _theme;
final _containers = <ProviderContainer>[];

/// The app's adhkar, read from the file once: the asset bundle's cache
/// does not carry over between widget tests' zones.
final _adhkar = parseAppAdhkar(
  File('assets/tasbih/adhkar.json').readAsStringSync(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(() async {
    final themes = await ThemeRegistry.load(rootBundle);
    _theme = buildTheme(
      style: themes.byId(themes.defaultStyleId),
      mode: ThemeModeId.light,
      uiFont: UiFont.changa,
    );
  });

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final m in ['toggle', 'isEnabled']) {
      messenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.$m',
        (_) async => const StandardMessageCodec().encodeMessage(<Object?>[
          m == 'isEnabled' ? false : null,
        ]),
      );
    }
  });

  Future<(ProviderContainer, NoTasbihPlatform, UserDatabase)> pump(
    WidgetTester tester,
    TasbihStyle style, {
    Widget screen = const TasbihScreen(),
    Map<String, Object> prefs = const {},
    double textScale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({
      'settings.tasbih.style': style.name,
      'settings.tasbih.target': 3,
      // A dhikr said whole; the staged one has its own test.
      'settings.tasbih.dhikr': 'app:seen34',
      ...prefs,
    });
    final shared = await SharedPreferences.getInstance();
    final db = UserDatabase(NativeDatabase.memory());
    final platform = NoTasbihPlatform();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        userDatabaseProvider.overrideWithValue(db),
        tasbihPlatformProvider.overrideWithValue(platform),
        appAdhkarProvider.overrideWith((ref) => _adhkar),
      ],
    );
    _containers.add(container);
    // The app's adhkar, read before the screen (a real asset load).
    container.listen(appAdhkarProvider, (_, _) {});
    container.listen(myAdhkarProvider, (_, _) {});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: _theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: LookTheme(child: screen),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return (container, platform, db);
  }

  Future<void> done(WidgetTester tester, UserDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    _containers.removeLast().dispose();
    // Drift's stream queries end on a zero-length timer.
    await tester.pump(const Duration(seconds: 1));
  }

  // Several frames: an animation's first frame only starts its clock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  final counters = {
    TasbihStyle.misbaha: find.byType(MisbahaView),
    TasbihStyle.button: find.byType(PressButtonView),
    TasbihStyle.lcd: find.byType(LcdCounterView),
  };

  for (final style in TasbihStyle.values) {
    testWidgets('${style.name}: a tap counts and the round closes', (
      tester,
    ) async {
      final (c, platform, db) = await pump(tester, style);
      expect(find.text(c.read(currentDhikrProvider)!.text), findsWidgets);
      final target = switch (style) {
        TasbihStyle.screen => find.byType(TasbihScreen),
        TasbihStyle.lcd => find.byKey(lcdKey),
        _ => counters[style]!,
      };
      expect(target, findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.tap(target, warnIfMissed: false);
        await settle(tester);
      }
      final counter = c.read(tasbihCounterProvider);
      expect((counter.rounds, counter.count), (1, 1));
      expect(counter.count, 1);
      final today = await tester.runAsync(
        () => c
            .read(tasbihRepositoryProvider)
            .dayCount(c.read(currentDhikrProvider)!.key),
      );
      expect(today, 4);
      expect(platform.widget?['count'], '4');
      expect(tester.takeException(), isNull);
      await done(tester, db);
    });
  }

  // The tap that reaches the target closes the round at once: the next
  // round starts at 0, not at 1 (staged 33/33/33/1, and a plain target).
  for (final style in TasbihStyle.values.where(
    (s) => s != TasbihStyle.screen,
  )) {
    for (final (dhikr, taps) in [
      ('app:muslimdata69', 100),
      ('app:seen34', 3),
    ]) {
      testWidgets('${style.name}: tap $taps of $dhikr closes the round', (
        tester,
      ) async {
        final (c, _, db) = await pump(
          tester,
          style,
          prefs: {'settings.tasbih.dhikr': dhikr},
        );
        final target = style == TasbihStyle.lcd
            ? find.byKey(lcdKey)
            : counters[style]!;
        for (var i = 0; i < taps; i++) {
          await tester.tap(target, warnIfMissed: false);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 60));
          final k = c.read(tasbihCounterProvider);
          expect(
            (k.rounds, k.count),
            i + 1 == taps ? (1, 0) : (0, i + 1),
            reason: 'after tap ${i + 1}',
          );
        }
        await settle(tester);
        if (dhikr == 'app:muslimdata69') {
          expect(findMeta('1/4 · 0/33'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await done(tester, db);
      });
    }
  }

  // 100 is 99 beads (three whole laps) and the imam: the last count moves
  // no bead, so the next round starts with the beads at the lap's start.
  for (final render in ['real', 'suggested']) {
    testWidgets('$render misbaha: a round of 100 ends on the imam', (
      tester,
    ) async {
      final (c, _, db) = await pump(
        tester,
        TasbihStyle.misbaha,
        prefs: {
          'settings.tasbih.dhikr': 'app:muslimdata69',
          'settings.tasbih.render': render,
        },
      );
      MisbahaMotion motion() {
        final p = tester
            .widgetList<CustomPaint>(
              find.descendant(
                of: find.byType(MisbahaView),
                matching: find.byType(CustomPaint),
              ),
            )
            .map((w) => w.painter)
            .firstWhere(
              (p) => p is RealMisbahaPainter || p is SuggestedMisbahaPainter,
            );
        return p is RealMisbahaPainter
            ? p.motion
            : (p! as SuggestedMisbahaPainter).motion;
      }

      for (var i = 0; i < 100; i++) {
        await tester.tap(find.byType(MisbahaView), warnIfMissed: false);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 60));
        if (i == 98) {
          await settle(tester);
          // 99 beads over: the string is back at the lap's start.
          expect(motion().asked, 99);
        }
      }
      // The 100th count asked for no bead (the string may already have
      // been put at the new round's start).
      expect(motion().asked, anyOf(99, 0));
      for (var i = 0; i < 6; i++) {
        await settle(tester);
      }
      final k = c.read(tasbihCounterProvider);
      expect((k.rounds, k.count, k.stage?.index), (1, 0, 0));
      expect(findMeta('1/4 · 0/33'), findsOneWidget);
      // The new round: the string at rest at the start, nothing owed.
      final m = motion();
      expect((m.asked, m.owed, m.phase), (0, 0, 0.0));
      if (render == 'real') expect(m.step % misbahaItems, 0);
      // The next tap moves the first bead.
      await tester.tap(find.byType(MisbahaView), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 60));
      expect(motion().asked, 1);
      expect(c.read(tasbihCounterProvider).count, 1);
      await done(tester, db);
    });
  }

  testWidgets('a staged round kept at 99 reopens at 99 (not closed by the '
      "settings' target)", (tester) async {
    final (c, _, db) = await pump(
      tester,
      TasbihStyle.button,
      prefs: {
        'settings.tasbih.dhikr': 'app:muslimdata69',
        'tasbih.countOf': 'app:muslimdata69',
        'tasbih.count': 99,
        'tasbih.rounds': 2,
      },
    );
    final k = c.read(tasbihCounterProvider);
    expect((k.rounds, k.count, k.target), (2, 99, 100));
    await done(tester, db);
  });

  testWidgets('true 3D misbaha draws and counts by a pull', (tester) async {
    final (c, _, db) = await pump(
      tester,
      TasbihStyle.misbaha,
      prefs: {'settings.tasbih.render': 'real'},
    );
    expect(find.byType(MisbahaView), findsOneWidget);
    await tester.drag(find.byType(MisbahaView), const Offset(0, 300));
    await settle(tester);
    expect(c.read(tasbihCounterProvider).count, 1);
    // A short pull springs back and does not count.
    await tester.timedDrag(
      find.byType(MisbahaView),
      const Offset(0, 40),
      const Duration(milliseconds: 600),
    );
    await settle(tester);
    expect(c.read(tasbihCounterProvider).count, 1);
    expect(tester.takeException(), isNull);
    await done(tester, db);
  });

  testWidgets('the misbaha fits at 200% text, in each look', (tester) async {
    for (final works in [true, false]) {
      BeadShader.debugSetAvailable(works);
      final (c, _, db) = await pump(
        tester,
        TasbihStyle.misbaha,
        textScale: 2,
        prefs: {'settings.tasbih.material': 'turquoise'},
      );
      expect(tester.takeException(), isNull);
      final painter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(MisbahaView),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter;
      expect(
        painter,
        works ? isA<RealMisbahaPainter>() : isA<SuggestedMisbahaPainter>(),
      );
      // The counter keeps a large area, and is one button with its value.
      expect(tester.getSize(find.byType(MisbahaView)).height, greaterThan(270));
      expect(
        find.bySemanticsLabel(
          AppLocalizations.of(tester.element(find.byType(MisbahaView)))
              .tasbihCountAction,
        ),
        findsOneWidget,
      );
      expect(
        find.text(works ? 'Tap or drag to count' : 'Pull a bead down, or tap'),
        findsOneWidget,
      );
      await tester.tap(find.byType(MisbahaView));
      await settle(tester);
      expect(c.read(tasbihCounterProvider).count, 1);
      expect(tester.takeException(), isNull);
      await done(tester, db);
    }
    BeadShader.debugSetAvailable(null);
  });

  testWidgets('volume buttons, space and enter count', (tester) async {
    final (c, platform, db) = await pump(
      tester,
      TasbihStyle.button,
      prefs: {'settings.tasbih.volumeKeys': true, 'settings.tasbih.target': 0},
    );
    await settle(tester);
    expect(platform.volumeKeys, isTrue);
    platform.pressVolume();
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(c.read(tasbihCounterProvider).count, 3);
    await done(tester, db);
    expect(platform.volumeKeys, isFalse);
  });

  testWidgets('counts made by the widget are added when the screen opens', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final (c, platform, db) = await pump(tester, TasbihStyle.button);
    platform.pending = 7;
    await tester.runAsync(
      () => c.read(tasbihCounterProvider.notifier).absorbPending(),
    );
    await settle(tester);
    // Target 3: two rounds and one over.
    expect(c.read(tasbihCounterProvider).rounds, 2);
    expect(c.read(tasbihCounterProvider).count, 1);
    await done(tester, db);
  });

  testWidgets('counts from the watch join while the screen is open', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final (c, platform, db) = await pump(tester, TasbihStyle.button);
    await tester.runAsync(() async {
      platform.watchCount(2);
      // The screen takes them on its own, no reopening needed.
      for (var i = 0; i < 50 && platform.pending > 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    expect(platform.pending, 0);
    expect(c.read(tasbihCounterProvider).count, 2);
    await done(tester, db);
  });

  testWidgets('watch counts join at once on any screen, into this device', (
    tester,
  ) async {
    final (c, platform, db) = await pump(
      tester,
      TasbihStyle.button,
      screen: const SizedBox(),
    );
    platform.pending = 3; // counted on the watch while the app was closed
    // Started with the app (TibyanApp listens to it).
    await tester.runAsync(() async => c.listen(watchCountsProvider, (_, _) {}));
    Future<void> wait() => tester.runAsync(() async {
      for (var i = 0; i < 50 && platform.pending > 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await wait();
    expect(platform.pending, 0);
    final first = await tester.runAsync(() => db.select(db.tasbihDays).get());
    expect(first!.single.count, 3);
    platform.watchCount(2);
    await wait();
    final rows = await tester.runAsync(() => db.select(db.tasbihDays).get());
    expect(rows!.single.count, 5);
    expect(rows.single.device, '');
    await done(tester, db);
  });

  testWidgets('the screen reader hears the count', (tester) async {
    final handle = tester.ensureSemantics();
    final (_, _, db) = await pump(tester, TasbihStyle.button);
    expect(find.bySemanticsLabel(RegExp('Count')), findsWidgets);
    final node = tester.getSemantics(find.byType(PressButtonView));
    expect(node.value, '0 of 3');
    handle.dispose();
    await done(tester, db);
  });

  testWidgets('the daily log lists the day totals', (tester) async {
    final (c, _, db) = await pump(
      tester,
      TasbihStyle.button,
      screen: const TasbihLogScreen(),
    );
    await tester.runAsync(
      () => c.read(tasbihRepositoryProvider).record('app:seen34', count: 12),
    );
    await settle(tester);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    await done(tester, db);
  });

  test('after-prayer tasbih: the 99 is cut verbatim from the source', () {
    final post = postPrayerTasbih(_adhkar.adhkar)!;
    final full = post.hundred;
    expect(full.stageCounts, [33, 33, 33, 1]);
    expect(post.ninetyNine.stageCounts, [33, 33, 33]);
    expect(post.ninetyNine.target, 99);
    expect(full.text.startsWith(post.ninetyNine.text), isTrue);
    expect(post.ninetyNine.text.length, full.stages[2].end);
    expect(post.ninetyNine.reference, full.reference);
  });

  testWidgets('after-prayer tasbih heads the list; the 99 counts to 99', (
    tester,
  ) async {
    final (c, _, db) = await pump(
      tester,
      TasbihStyle.button,
      screen: const Scaffold(body: DhikrSheet()),
    );
    final post = postPrayerTasbih(_adhkar.adhkar)!;
    expect(find.text('After-prayer tasbih'), findsOneWidget);
    expect(find.text(post.ninetyNine.text), findsOneWidget);
    expect(find.text(post.hundred.text), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('After-prayer tasbih')).dy,
      lessThan(tester.getTopLeft(find.text('From the source')).dy),
    );
    await tester.tap(find.text(post.ninetyNine.text));
    await settle(tester);
    expect(c.read(currentDhikrProvider)!.key, post.ninetyNine.key);
    final ctrl = c.read(tasbihCounterProvider.notifier);
    expect(c.read(tasbihCounterProvider).target, 99);
    final events = <CountEvent>[];
    for (var i = 0; i < 99; i++) {
      events.add((await tester.runAsync(ctrl.tap))!);
    }
    expect(events.where((e) => e == CountEvent.stageChanged), hasLength(2));
    expect(events.last, CountEvent.roundClosed);
    final k = c.read(tasbihCounterProvider);
    expect((k.rounds, k.count, k.stage?.index), (1, 0, 0));
    await done(tester, db);
  });

  testWidgets('a dhikr in stages: 33, 33, 33, then 1 closes the round', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final (c, platform, _) = await pump(
      tester,
      TasbihStyle.button,
      prefs: {'settings.tasbih.dhikr': 'app:muslimdata69'},
    );
    final dhikr = c.read(currentDhikrProvider)!;
    expect(dhikr.stages.map((s) => s.count), [33, 33, 33, 1]);
    // Each stage is a span of the verbatim text.
    for (final s in dhikr.stages) {
      expect(dhikr.text.substring(s.start, s.end).trim(), isNotEmpty);
    }
    expect(c.read(tasbihCounterProvider).target, 100);
    expect(findMeta('1/4 · 0/33'), findsOneWidget);
    final ctrl = c.read(tasbihCounterProvider.notifier);
    final events = <CountEvent>[];
    for (var i = 0; i < 33; i++) {
      events.add((await tester.runAsync(ctrl.tap))!);
    }
    expect(events.last, CountEvent.stageChanged);
    expect(events.where((e) => e == CountEvent.stageChanged), hasLength(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(findMeta('2/4 · 0/33'), findsOneWidget);
    expect(platform.widget?['stages'], '33,33,33,1');
    expect(platform.widget?['round'], '33');
    // The watch gets each stage's own words, cut from the dhikr's text.
    expect(platform.widget?['stageTexts']?.split('\n'), hasLength(4));
    expect(platform.widget?['target'], '0');
    for (var i = 0; i < 66; i++) {
      events.add((await tester.runAsync(ctrl.tap))!);
    }
    expect(c.read(tasbihCounterProvider).stage?.index, 3);
    events.add((await tester.runAsync(ctrl.tap))!);
    expect(events.last, CountEvent.roundClosed);
    expect(events.where((e) => e == CountEvent.stageChanged), hasLength(3));
    expect(c.read(tasbihCounterProvider).rounds, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(findMeta('1/4 · 0/33'), findsOneWidget);
    handle.dispose();
    await done(tester, c.read(userDatabaseProvider));
  });

  testWidgets('lcd: tapping or long-pressing R resets the counter', (
    tester,
  ) async {
    final (c, _, db) = await pump(tester, TasbihStyle.lcd);
    final countKey = find.byKey(lcdKey);
    final resetKey = find.byKey(lcdResetKey);
    expect(countKey, findsOneWidget);
    expect(resetKey, findsOneWidget);

    // Tap to count 3 times.
    for (var i = 0; i < 3; i++) {
      await tester.tap(countKey);
      await settle(tester);
    }
    expect(
      c.read(tasbihCounterProvider).count,
      0,
    ); // target is 3, so count closed to 0, rounds = 1
    expect(c.read(tasbihCounterProvider).rounds, 1);

    // Tap once more so count is 1.
    await tester.tap(countKey);
    await settle(tester);
    expect(c.read(tasbihCounterProvider).count, 1);

    // Tap R button -> resets count & rounds.
    await tester.tap(resetKey);
    await settle(tester);
    expect(c.read(tasbihCounterProvider).count, 0);
    expect(c.read(tasbihCounterProvider).rounds, 0);

    // Tap count twice -> count is 2.
    await tester.tap(countKey);
    await settle(tester);
    await tester.tap(countKey);
    await settle(tester);
    expect(c.read(tasbihCounterProvider).count, 2);

    // Long press R button -> resets count & rounds.
    await tester.longPress(resetKey);
    await settle(tester);
    expect(c.read(tasbihCounterProvider).count, 0);
    expect(c.read(tasbihCounterProvider).rounds, 0);

    await done(tester, db);
  });

  testWidgets('TargetBar reset button resets count in all styles', (
    tester,
  ) async {
    for (final style in [
      TasbihStyle.misbaha,
      TasbihStyle.button,
      TasbihStyle.lcd,
    ]) {
      final (c, _, db) = await pump(tester, style);
      final target = switch (style) {
        TasbihStyle.lcd => find.byKey(lcdKey),
        _ => counters[style]!,
      };
      await tester.tap(target, warnIfMissed: false);
      await settle(tester);
      expect(c.read(tasbihCounterProvider).count, 1);

      final resetBtn = find.byKey(const ValueKey('tasbih-reset-button'));
      expect(resetBtn, findsOneWidget);
      await tester.tap(resetBtn);
      await settle(tester);
      expect(c.read(tasbihCounterProvider).count, 0);
      expect(c.read(tasbihCounterProvider).rounds, 0);

      await done(tester, db);
    }
  });

  testWidgets('screen: long pressing screen resets the counter', (
    tester,
  ) async {
    final (c, _, db) = await pump(tester, TasbihStyle.screen);
    final screen = find.byType(TasbihScreen);
    await tester.tap(screen);
    await settle(tester);
    expect(c.read(tasbihCounterProvider).count, 1);

    await tester.longPress(screen);
    await settle(tester);
    expect(c.read(tasbihCounterProvider).count, 0);
    expect(c.read(tasbihCounterProvider).rounds, 0);

    await done(tester, db);
  });

  testWidgets('keyboard R key resets the counter', (tester) async {
    final (c, _, db) = await pump(tester, TasbihStyle.button);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(c.read(tasbihCounterProvider).count, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await settle(tester);
    expect(c.read(tasbihCounterProvider).count, 0);
    expect(c.read(tasbihCounterProvider).rounds, 0);

    await done(tester, db);
  });
}
