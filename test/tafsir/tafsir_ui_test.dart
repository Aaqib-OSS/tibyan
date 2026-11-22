import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tibyan/core/db/content_database.dart';
import 'package:tibyan/core/flags/feature_flags.dart';
import 'package:tibyan/core/settings/settings_controller.dart';
import 'package:tibyan/core/theme/app_theme.dart';
import 'package:tibyan/core/theme/theme_registry.dart';
import 'package:tibyan/core/theme/theme_tokens.dart';
import 'package:tibyan/core/ui/share_text.dart';
import 'package:tibyan/features/audio/recitation.dart';
import 'package:tibyan/features/books/books_providers.dart';
import 'package:tibyan/features/books/data/book_pack.dart';
import 'package:tibyan/features/content_extras/english_tafsir.dart';
import 'package:tibyan/features/mushaf/mushaf_providers.dart';
import 'package:tibyan/features/tafsir/tafsir_screen.dart';
import 'package:tibyan/l10n/app_localizations.dart';

import '../books/fake_pack.dart';

class _FakeRecitation extends RecitationController {
  final plays = <(int, int?)>[];

  @override
  RecitationState build() => const RecitationState();

  @override
  Future<void> play(
    int surah, {
    int? from,
    int? to,
    int? rangeFrom,
    int? repeat,
    Duration? silence,
    bool start = true,
    bool nearSpeech = false,
    int? word,
    ReciterRow? reciter,
  }) async => plays.add((surah, from));

  void recite(int surah, int ayah) => state = RecitationState(
    active: true,
    playing: true,
    surah: surah,
    ayah: ayah,
    timed: true,
  );
}

/// The tafsir's chip bar, «قارن», «اقرأ المزيد», verse navigation, the
/// per-card actions and the mushaf's half sheet, on the real bundled
/// database.
void main() {
  late ContentDatabase db;
  late BookPack pack;
  late _FakeRecitation recitation;
  late List<String> shared;
  late SharedPreferences prefs;

  setUpAll(() {
    db = ContentDatabase(
      NativeDatabase(
        File('assets/db/content.db'),
        setup: (raw) => raw.execute('PRAGMA query_only = ON'),
      ),
    );
  });
  tearDownAll(() => db.close());
  setUp(() => pack = BookPack(fakeBooksPackDb()));
  tearDown(() => pack.close());

  Future<void> settle(WidgetTester tester) async {
    // The queries run on the database's own isolate, off the test clock.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    Map<String, Object> initialPrefs = const {},
    List<BookPack>? packs,
    int surah = 2,
    int ayah = 1,
    double textScale = 1,
    bool sheet = false,
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    final registry = (await tester.runAsync(
      () => ThemeRegistry.load(rootBundle),
    ))!;
    final packRoot = Directory.systemTemp.createTempSync('tafsir_ui');
    addTearDown(() => packRoot.deleteSync(recursive: true));
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    recitation = _FakeRecitation();
    shared = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentDatabaseProvider.overrideWithValue(db),
          themeRegistryProvider.overrideWithValue(registry),
          sharedPreferencesProvider.overrideWithValue(prefs),
          featureFlagsProvider.overrideWithValue(const FeatureFlags({})),
          installedBookPacksProvider.overrideWithValue(packs ?? [pack]),
          englishTafsirSpecsProvider.overrideWithValue(const []),
          packRootProvider.overrideWithValue(packRoot),
          recitationProvider.overrideWith(() => recitation),
          shareTextProvider.overrideWithValue((text) async => shared.add(text)),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildTheme(
            style: registry.byId(registry.defaultStyleId),
            mode: ThemeModeId.light,
            uiFont: UiFont.plex,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: sheet
              ? Scaffold(
                  body: Builder(
                    builder: (context) => Center(
                      child: TextButton(
                        onPressed: () =>
                            showTafsirSheet(context, surah: surah, ayah: ayah),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                )
              : TafsirScreen(surah: surah, ayah: ayah),
        ),
      ),
    );
    await settle(tester);
    if (sheet) {
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    }
  }

  Finder chip(String name) => find.widgetWithText(ChoiceChip, name);
  Finder verse(int s, int a) => find.byKey(ValueKey('tafsir-verse-$s:$a'));

  group('(a) chips', () {
    testWidgets('one text at a time, the choice remembered', (tester) async {
      await pump(tester);
      expect(chip('التفسير الميسر'), findsOneWidget);
      expect(chip('تفسير تجريبي ثان'), findsOneWidget);
      // The first shown text by default.
      expect(find.text(fakeOtherTafsirText, findRichText: true), findsNothing);

      await tester.ensureVisible(chip('تفسير تجريبي ثان'));
      await tester.pumpAndSettle();
      await tester.tap(chip('تفسير تجريبي ثان'));
      await tester.pumpAndSettle();
      expect(
        find.text(fakeOtherTafsirText, findRichText: true),
        findsOneWidget,
      );
      expect(find.text(fakeTafsirText, findRichText: true), findsNothing);
      final saved = prefs.getString('settings.tafsirChoice');
      expect(saved, startsWith('b:'));

      // Opened again: the same choice.
      await pump(tester, initialPrefs: {'settings.tafsirChoice': saved!});
      expect(
        find.text(fakeOtherTafsirText, findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a choice no longer shown falls back to the first', (
      tester,
    ) async {
      await pump(tester, initialPrefs: {'settings.tafsirChoice': 'c:gone'});
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(chips.where((c) => c.selected).length, 1);
      expect(chips.first.selected, isTrue);
    });

    testWidgets('«قارن» brings back every text', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('tafsir-compare')));
      await tester.pumpAndSettle();
      expect(find.text(fakeTafsirText, findRichText: true), findsOneWidget);
      expect(
        find.text(fakeOtherTafsirText, findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(ChoiceChip), findsNothing);
      expect(prefs.getBool('settings.tafsirCompare'), isTrue);
    });

    testWidgets('a long text folds after 8 lines, also at 200% text', (
      tester,
    ) async {
      await pump(tester, ayah: 255, textScale: 2, packs: []);
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(
        find.text('اقرأ المزيد'),
        find
            .descendant(of: verse(2, 255), matching: find.byType(Scrollable))
            .first,
        const Offset(0, -300),
      );
      expect(find.text('اقرأ المزيد'), findsOneWidget);
      await tester.ensureVisible(find.text('اقرأ المزيد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('اقرأ المزيد'));
      await tester.pumpAndSettle();
      expect(find.text('عرض أقل', skipOffstage: false), findsOneWidget);
      expect(find.text('اقرأ المزيد', skipOffstage: false), findsNothing);
    });
  });

  group('(b) navigation', () {
    testWidgets('the counter opens «اذهب لآية»', (tester) async {
      await pump(tester, packs: []);
      await tester.tap(find.byKey(const ValueKey('tafsir-verse-counter')));
      await tester.pumpAndSettle();
      expect(find.text('اذهب لآية'), findsOneWidget);
      final target = find.byKey(const ValueKey('verse-pick-40'));
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.descendant(
          of: find.byType(GridView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(target);
      await tester.pumpAndSettle();
      await settle(tester);
      expect(verse(2, 40), findsOneWidget);
    });

    testWidgets('next past the last verse goes on to the next surah', (
      tester,
    ) async {
      await pump(tester, surah: 1, ayah: 7, packs: []);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(verse(2, 1), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(verse(1, 7), findsOneWidget);
    });

    testWidgets('a swipe past the first verse goes back a surah', (
      tester,
    ) async {
      await pump(tester, surah: 2, ayah: 1, packs: []);
      // Right to left: the previous page lies to the left.
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
      await tester.pumpAndSettle();
      await settle(tester);
      expect(verse(1, 7), findsOneWidget);
      // On Android the text selection takes horizontal drags first (as it
      // did before); iOS hands them to the pages.
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('(d) card actions', () {
    testWidgets('share gives the text with its source and credit', (
      tester,
    ) async {
      await pump(tester, packs: []);
      await tester.tap(find.byTooltip('مشاركة النص').first);
      await tester.pump();
      expect(shared, hasLength(1));
      expect(shared.single, contains('\n\nالتفسير الميسر'));
    });

    testWidgets('tapping the verse plays it', (tester) async {
      await pump(tester, ayah: 3, packs: []);
      await tester.tap(find.byKey(const ValueKey('tafsir-verse')).first);
      await tester.pump();
      expect(recitation.plays, [(2, 3)]);
    });

    testWidgets('nothing shown: «اختار التفاسير» opens the settings', (
      tester,
    ) async {
      await pump(tester, packs: []);
      await tester.tap(find.byIcon(Icons.text_fields));
      await tester.pumpAndSettle();
      final sw = find.widgetWithText(SwitchListTile, 'التفسير الميسر');
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(sw)).pop();
      await tester.pumpAndSettle();

      expect(find.text('اختار التفاسير'), findsOneWidget);
      await tester.tap(find.text('اختار التفاسير'));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsWidgets);
    });
  });

  testWidgets('(c) the mushaf half sheet follows the recitation', (
    tester,
  ) async {
    await pump(tester, sheet: true, packs: []);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.text('open'), findsOneWidget); // the page stays in sight
    expect(verse(2, 1), findsOneWidget);

    recitation.recite(2, 5);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(verse(2, 5), findsOneWidget);
  });
}
