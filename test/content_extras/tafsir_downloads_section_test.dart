import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tibyan/core/settings/settings_controller.dart';
import 'package:tibyan/core/theme/theme_registry.dart';
import 'package:tibyan/features/books/books_providers.dart';
import 'package:tibyan/features/books/data/book_pack.dart';
import 'package:tibyan/features/content_extras/english_tafsir.dart';
import 'package:tibyan/features/content_extras/tafsir_downloads_section.dart';
import 'package:tibyan/features/content_extras/tafsir_library.dart';
import 'package:tibyan/features/mushaf/data/page_pack.dart';
import 'package:tibyan/features/mushaf/mushaf_providers.dart';
import 'package:tibyan/features/mushaf/presentation/background_downloads_list.dart';
import 'package:tibyan/l10n/app_localizations.dart';

import '../tasmee/tasmee_test_env.dart' show tasmeeTheme;

class _Idle extends TafsirLibraryDownloads {
  @override
  Map<String, PackProgress> build() => const {};
}

class _IdleBooks extends BookDownloads {
  @override
  Map<String, PackProgress> build() => const {};
}

class _IdleEnglish extends EnglishTafsirDownloads {
  @override
  Map<String, PackProgress> build() => const {};
}

const _wajiz = TafsirTextPackSpec(
  id: 'lib-wajiz',
  url: 'https://x/w',
  sha256: 'a',
  bytes: 18000000,
  title: 'الجامع الوجيز',
);
const _thawri = TafsirTextPackSpec(
  id: 'lib-thawri',
  url: 'https://x/t',
  sha256: 'b',
  bytes: 1000000,
  title: 'تفسير سفيان الثوري',
  author: 'سفيان الثوري',
  diedAh: 161,
);
const _mujahid = TafsirTextPackSpec(
  id: 'lib-mujahid',
  url: 'https://x/m',
  sha256: 'c',
  bytes: 2000000,
  title: 'تفسير مجاهد',
  author: 'مجاهد',
  diedAh: 104,
);
const _bookTafsir = BookPackSpec(
  id: 'book-tafsir',
  url: 'https://x/bt',
  sha256: 'd',
  bytes: 3000000,
  kind: BookKind.tafsir,
  title: 'كتاب تفسير',
);
const _asbab = BookPackSpec(
  id: 'book-asbab',
  url: 'https://x/ba',
  sha256: 'e',
  bytes: 1000000,
  kind: BookKind.asbabNuzul,
  title: 'كتاب أسباب',
);
const _english = TafsirTextPackSpec(
  id: 'en-pack',
  url: 'https://x/e',
  sha256: 'f',
  bytes: 1000000,
  title: 'English tafsir',
);

void main() {
  late Directory root;
  late ProviderContainer container;
  late ThemeRegistry registry;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registry = await ThemeRegistry.load(rootBundle);
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('tafsir-section');
    // «تفسير سفيان الثوري» is on the device.
    final dir = tafsirTextInstaller(root, _thawri).dir..createSync();
    File('${dir.path}/.installed').writeAsStringSync('');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        themeRegistryProvider.overrideWithValue(registry),
        packsDirProvider.overrideWithValue(root),
        tafsirLibrarySpecsProvider.overrideWithValue([
          _thawri,
          _mujahid,
          _wajiz,
        ]),
        bookPackSpecsProvider.overrideWithValue([_asbab, _bookTafsir]),
        englishTafsirSpecsProvider.overrideWithValue([_english]),
        tafsirLibraryDownloadsProvider.overrideWith(_Idle.new),
        bookDownloadsProvider.overrideWith(_IdleBooks.new),
        englishTafsirDownloadsProvider.overrideWith(_IdleEnglish.new),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    root.deleteSync(recursive: true);
  });

  test('sub-groups and order', () {
    final items = container.read(tafsirDownloadItemsProvider);
    expect(items.map((i) => (i.id, i.group)), [
      ('lib-wajiz', TafsirDownloadGroup.tafsir),
      ('lib-mujahid', TafsirDownloadGroup.tafsir), // d. 104 before 161
      ('lib-thawri', TafsirDownloadGroup.tafsir),
      ('book-tafsir', TafsirDownloadGroup.tafsir),
      ('book-asbab', TafsirDownloadGroup.sciences),
      ('en-pack', TafsirDownloadGroup.translations),
    ]);
    expect(items[2].installed, isTrue);
    expect(items[1].installed, isFalse);
  });

  test('search and filter', () {
    final items = container.read(tafsirDownloadItemsProvider);
    List<String> ids(String q, TafsirLibraryFilter f) => [
      for (final i in items)
        if (tafsirItemMatches(i, q, f)) i.id,
    ];
    expect(ids('سفيان', TafsirLibraryFilter.all), ['lib-thawri']);
    expect(ids('مجاهد', TafsirLibraryFilter.all), ['lib-mujahid']);
    expect(ids('', TafsirLibraryFilter.onDevice), ['lib-thawri']);
    expect(ids('', TafsirLibraryFilter.available), hasLength(5));
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(500, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: tasmeeTheme(container),
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  KeyedSubtree(
                    key: ValueKey('center'),
                    child: TafsirDownloadsSection(),
                  ),
                  // The library scrolls inside its own bounded sheet.
                  SizedBox(
                    height: 2000,
                    child: KeyedSubtree(
                      key: ValueKey('library'),
                      child: TafsirDownloadsSection(library: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final onDevice = find.byWidgetPredicate(
    (w) => w is DownloadRow && w.status.contains('على الجهاز'),
  );

  Finder inside(String where, Finder f) =>
      find.descendant(of: find.byKey(ValueKey(where)), matching: f);

  testWidgets('the center and the library share the same state', (
    tester,
  ) async {
    await pump(tester);
    for (final w in ['center', 'library']) {
      expect(inside(w, find.text('التفاسير')), findsOneWidget);
      expect(inside(w, find.text('علوم القرآن')), findsOneWidget);
      expect(inside(w, find.text('الترجمات')), findsOneWidget);
      expect(inside(w, find.text('تفسير سفيان الثوري')), findsOneWidget);
      expect(inside(w, onDevice), findsOneWidget);
    }
    // The library alone has the search and the show/hide switch.
    expect(inside('library', find.byType(TextField)), findsOneWidget);
    expect(inside('center', find.byType(TextField)), findsNothing);
    expect(inside('library', find.byType(Switch)), findsOneWidget);

    // Deleting from the center (after the confirmation) updates both.
    await tester.tap(inside('center', find.byIcon(Icons.delete_outline)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(inside('library', onDevice), findsOneWidget);
    await tester.tap(inside('center', find.byIcon(Icons.delete_outline)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();
    expect(onDevice, findsNothing);
  });

  testWidgets('the library search field stays pinned while it scrolls', (
    tester,
  ) async {
    await pump(tester);
    // A short sheet so the list has to scroll.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: tasmeeTheme(container),
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(
              height: 300,
              child: TafsirDownloadsSection(library: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('tafsir-library-search'));
    final y = tester.getTopLeft(field).dy;
    final headerY = tester.getTopLeft(find.text('التفاسير')).dy;
    await tester.drag(
      find.byKey(const ValueKey('tafsir-library-scroll')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
    expect(tester.getTopLeft(field).dy, y);
    // The list itself moved under the field.
    final header = find.text('التفاسير');
    expect(
      header.evaluate().isEmpty || tester.getTopLeft(header).dy < headerY,
      isTrue,
    );
  });

  testWidgets('the library search and filter', (tester) async {
    await pump(tester);
    await tester.enterText(inside('library', find.byType(TextField)), 'مجاهد');
    await tester.pumpAndSettle();
    expect(inside('library', find.text('تفسير مجاهد')), findsOneWidget);
    expect(inside('library', find.text('تفسير سفيان الثوري')), findsNothing);
    await tester.enterText(inside('library', find.byType(TextField)), '');
    await tester.tap(
      find.byKey(const ValueKey('tafsir-library-filter-onDevice')),
    );
    await tester.pumpAndSettle();
    expect(inside('library', find.text('تفسير سفيان الثوري')), findsOneWidget);
    expect(inside('library', find.text('تفسير مجاهد')), findsNothing);
  });

  testWidgets('download all asks first, with the total size', (tester) async {
    await pump(tester);
    await tester.tap(
      inside('center', find.byKey(const ValueKey('downloads-all-tafsir'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('confirm-download-all')), findsOneWidget);
    expect(find.textContaining('الحجم الإجمالي'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });
}
