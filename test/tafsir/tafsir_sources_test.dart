import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:tibyan/core/db/content_database.dart';
import 'package:tibyan/core/flags/feature_flags.dart';
import 'package:tibyan/core/settings/settings_controller.dart';
import 'package:tibyan/core/theme/app_theme.dart';
import 'package:tibyan/core/theme/theme_registry.dart';
import 'package:tibyan/core/theme/theme_tokens.dart';
import 'package:tibyan/features/books/books_providers.dart';
import 'package:tibyan/features/content_extras/credits.dart';
import 'package:tibyan/features/content_extras/english_tafsir.dart';
import 'package:tibyan/features/content_extras/tafsir_library.dart';
import 'package:tibyan/features/mushaf/mushaf_providers.dart';
import 'package:tibyan/features/mushaf/presentation/source_names.dart';
import 'package:tibyan/features/tafsir/tafsir_screen.dart';
import 'package:tibyan/l10n/app_localizations.dart';

/// Placeholder text only: nothing here is from a book.
const _fakePackText = 'نص تجريبي <span class="x">﴿آية﴾</span> للحزمة';

const _fakeSpec = TafsirTextPackSpec(
  id: 'test-tafsir-pack',
  url: 'https://example.test/test-tafsir-pack.pack.db',
  sha256: 'test',
  bytes: 1,
  title: 'تفسير تجريبي',
  author: 'مؤلف تجريبي',
  diedAh: 500,
);

TafsirTextPack _fakePack() {
  final db = sqlite3.openInMemory();
  db.execute(
    'CREATE TABLE pack_index (key TEXT PRIMARY KEY, value TEXT NOT NULL);'
    'CREATE TABLE verse (surah INTEGER NOT NULL, ayah INTEGER NOT NULL, '
    'text TEXT NOT NULL, footnotes TEXT, PRIMARY KEY (surah, ayah));',
  );
  for (final kv in {
    'format': '1',
    'kind': 'tafsir_text',
    'source': ContentSources.quranpedia,
    'title': 'تفسير تجريبي',
    'author': 'مؤلف تجريبي',
    'markup': 'html',
    'version': '2026-08-10',
    'direction': 'rtl',
  }.entries) {
    db.execute('INSERT INTO pack_index VALUES (?, ?)', [kv.key, kv.value]);
  }
  db.execute('INSERT INTO verse VALUES (2, 1, ?, NULL)', [_fakePackText]);
  return TafsirTextPack(db);
}

void main() {
  late ContentDatabase db;

  setUpAll(() {
    db = ContentDatabase(
      NativeDatabase(
        File('assets/db/content.db'),
        setup: (raw) => raw.execute('PRAGMA query_only = ON'),
      ),
    );
  });
  tearDownAll(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    List<InstalledTafsirPack> packs = const [],
    String locale = 'ar',
    double textScale = 1,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await tester.runAsync(SharedPreferences.getInstance);
    final registry = (await tester.runAsync(
      () => ThemeRegistry.load(rootBundle),
    ))!;
    final packRoot = Directory.systemTemp.createTempSync('tafsir_sources');
    addTearDown(() => packRoot.deleteSync(recursive: true));
    await tester.binding.setSurfaceSize(const Size(420, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          contentDatabaseProvider.overrideWithValue(db),
          themeRegistryProvider.overrideWithValue(registry),
          sharedPreferencesProvider.overrideWithValue(sp!),
          featureFlagsProvider.overrideWithValue(const FeatureFlags({})),
          installedBookPacksProvider.overrideWithValue(const []),
          englishTafsirSpecsProvider.overrideWithValue(const []),
          tafsirLibrarySpecsProvider.overrideWithValue([_fakeSpec]),
          installedTafsirPacksProvider.overrideWithValue(packs),
          packRootProvider.overrideWithValue(packRoot),
        ],
        child: MaterialApp(
          locale: Locale(locale),
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
          home: const TafsirScreen(surah: 2, ayah: 1),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('al-Mukhtasar and al-Jalalayn are listed with their credits', (
    tester,
  ) async {
    await pump(tester, prefs: {'settings.tafsirCompare': true});
    expect(find.text('المختصر في التفسير'), findsOneWidget);
    expect(find.text('تفسير الجلالين'), findsOneWidget);
    expect(
      find.textContaining(
        'مركز تفسير للدراسات القرآنية، عبر موقع QuranEnc.com',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Tanzil.net', findRichText: true),
      findsOneWidget,
    );
    // Translations stay hidden until chosen, in either interface.
    expect(find.text('الترجمة الإنجليزية: صحيح إنترناشونال'), findsNothing);
    await pump(tester, prefs: {'settings.tafsirCompare': true}, locale: 'en');
    expect(find.text('Al-Mukhtasar fi al-Tafsir'), findsOneWidget);
    expect(find.text('Saheeh International'), findsNothing);
    expect(find.text('Pickthall'), findsNothing);
  });

  testWidgets('the picker leaves out hidden tafsirs', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('tafsir-chip-c:44')), findsOneWidget);
    expect(find.byKey(const ValueKey('tafsir-chip-c:45')), findsOneWidget);
    await pump(
      tester,
      prefs: {
        'settings.hiddenCommentaries': ['44'],
      },
    );
    expect(find.byKey(const ValueKey('tafsir-chip-c:44')), findsNothing);
    expect(find.byKey(const ValueKey('tafsir-chip-c:45')), findsOneWidget);
  });

  testWidgets('a downloaded pack is a choice with its credit, and can hide', (
    tester,
  ) async {
    final pack = _fakePack();
    addTearDown(pack.close);
    final installed = [(spec: _fakeSpec, pack: pack)];
    await pump(
      tester,
      packs: installed,
      prefs: {'settings.tafsirChoice': tafsirPackKey(_fakeSpec)},
    );
    final chip = find.byKey(
      ValueKey('tafsir-chip-${tafsirPackKey(_fakeSpec)}'),
    );
    expect(chip, findsOneWidget);
    // Shown without its markup, credited to Quranpedia with the version.
    expect(find.text('نص تجريبي ﴿آية﴾ للحزمة'), findsOneWidget);
    expect(
      find.textContaining('quranpedia.net', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('2026-08-10', findRichText: true),
      findsOneWidget,
    );

    // Hidden from the settings sheet: the chip goes.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    final sw = find.byKey(ValueKey('tafsir-shown-${tafsirPackKey(_fakeSpec)}'));
    await tester.ensureVisible(sw);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(sw)).pop();
    await tester.pumpAndSettle();
    expect(chip, findsNothing);
  });

  testWidgets('the last shown text cannot be hidden, at 200% text', (
    tester,
  ) async {
    await pump(
      tester,
      textScale: 2,
      prefs: {
        'settings.hiddenCommentaries': ['7', '44'],
      },
    );
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    final last = find.byKey(const ValueKey('tafsir-shown-c:45'));
    await tester.ensureVisible(last);
    final tile = tester.widget<SwitchListTile>(last);
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNull);
    expect(find.text('يبقى نص واحد ظاهرا على الأقل'), findsOneWidget);
    // Others can still be turned on.
    final muyassar = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('tafsir-shown-c:7')),
    );
    expect(muyassar.value, isFalse);
    expect(muyassar.onChanged, isNotNull);
    expect(tester.takeException(), isNull);
  });

  test('the library lists al-Jami\' al-Wajiz and the Quranpedia books', () {
    expect(tafsirLibraryPacks.first.id, 'tafsir-jami-wajiz-v1');
    expect(tafsirLibraryPacks.length, greaterThan(30));
    final ids = <String>{};
    for (final s in tafsirLibraryPacks) {
      expect(ids.add(s.id), isTrue, reason: s.id);
      expect(s.url, startsWith('https://altibyan.app/mirror/packs/tafsir/'));
      expect(s.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(s.bytes, greaterThan(0));
      expect(s.author, isNotNull);
    }
    // Books the app already ships are not offered again.
    for (final t in tafsirLibraryPacks.map((s) => s.title)) {
      expect(t, isNot(contains('الميسر')));
      expect(t, isNot(contains('المختصر في تفسير')));
      expect(t, isNot('تفسير الجلالين'));
    }
    for (final key in [
      'quranenc-arabic-mokhtasar',
      'tanzil-ar-jalalayn',
      ContentSources.quranpedia,
      ContentSources.jamiWajiz,
    ]) {
      for (final lang in ['ar', 'en']) {
        expect(sourceText(key, lang), isNotNull, reason: '$key $lang');
      }
    }
    expect(
      sourceText(ContentSources.jamiWajiz, 'ar')!.credit,
      contains('CC BY-ND 4.0'),
    );
    expect(
      tafsirLibrarySources.map((s) => s.key),
      containsAll([ContentSources.quranpedia, ContentSources.jamiWajiz]),
    );
  });

  test('pack markup is dropped for display only', () {
    expect(tafsirPackDisplayText('أ <b>ب</b>&amp;ج', html: true), 'أ ب&ج');
    expect(tafsirPackDisplayText('أ <b>ب</b>', html: false), 'أ <b>ب</b>');
  });
}
