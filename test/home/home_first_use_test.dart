import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tibyan/core/db/content_database.dart';
import 'package:tibyan/core/db/user_database.dart';
import 'package:tibyan/core/settings/settings_controller.dart';
import 'package:tibyan/core/theme/app_theme.dart';
import 'package:tibyan/core/theme/interface_style.dart';
import 'package:tibyan/core/theme/theme_registry.dart';
import 'package:tibyan/core/theme/theme_tokens.dart';
import 'package:tibyan/core/ui/surah_name.dart';
import 'package:tibyan/features/hifz/hifz_providers.dart';
import 'package:tibyan/features/home/home_screen.dart';
import 'package:tibyan/features/home/whats_new.dart';
import 'package:tibyan/features/khatma/khatma_providers.dart';
import 'package:tibyan/features/mushaf/mushaf_providers.dart';
import 'package:tibyan/l10n/app_localizations.dart';

/// Before any reading the arch offers Al-Fatiha and «ابدأ القراءة», which
/// opens page 1; once a position exists it is the usual «تابع القراءة».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ContentDatabase db;
  late Directory root;
  late ThemeRegistry registry;
  setUpAll(() async {
    db = ContentDatabase(
      NativeDatabase(
        File('assets/db/content.db'),
        setup: (raw) => raw.execute('PRAGMA query_only = ON'),
      ),
    );
    root = Directory.systemTemp.createTempSync('home_first_use');
    registry = await ThemeRegistry.load(rootBundle);
  });
  tearDownAll(() => db.close());

  Future<List<Uri>> pump(
    WidgetTester tester, {
    ReadingPositionRow? position,
    double scale = 1,
    Size size = const Size(390, 844),
    InterfaceStyle style = InterfaceStyle.handasi,
  }) async {
    SharedPreferences.setMockInitialValues({
      'settings.onboardingDone': true,
      whatsNewSeenKey: whatsNewId,
      'crash.consentAsked': true,
      'settings.interfaceStyle': style.name,
    });
    final sp = await SharedPreferences.getInstance();
    final user = UserDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(user.close));
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <Uri>[];
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/mushaf',
          builder: (_, state) {
            opened.add(state.uri);
            return const Text('mushaf');
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentDatabaseProvider.overrideWithValue(db),
          userDatabaseProvider.overrideWithValue(user),
          themeRegistryProvider.overrideWithValue(registry),
          sharedPreferencesProvider.overrideWithValue(sp),
          packRootProvider.overrideWithValue(root),
          readingPositionProvider.overrideWith((ref) => Stream.value(position)),
          khatmaStatusProvider.overrideWith((ref) async => null),
          srsItemsProvider.overrideWith((ref) => Stream.value(const [])),
          journeyProvider.overrideWithValue((memorized: 0, mastered: 0)),
          juzLadderProvider.overrideWithValue((
            memorized: List.filled(30, 0.0),
            mastered: List.filled(30, 0.0),
          )),
          bookmarkSetsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildTheme(
            style: registry.byId(registry.defaultStyleId),
            mode: ThemeModeId.light,
            uiFont: UiFont.changa,
            interfaceStyle: style,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
    return opened;
  }

  final arch = find.byKey(const ValueKey('home-continue-button'));

  testWidgets('no position: Al-Fatiha and «ابدأ القراءة» open page 1', (
    tester,
  ) async {
    final opened = await pump(tester);
    expect(tester.takeException(), isNull);
    final name = tester.widget<SurahNameText>(find.byType(SurahNameText).first);
    expect(name.surah, 1);
    expect(find.text('ابدأ القراءة'), findsOneWidget);
    expect(find.text('تابع القراءة'), findsNothing);
    await tester.tap(arch);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(opened, isNotEmpty);
    expect(opened.last.queryParameters['page'], '1');
  });

  testWidgets('a position: «تابع القراءة» and that surah', (tester) async {
    await pump(
      tester,
      position: ReadingPositionRow(
        id: 1,
        edition: 'madani1441',
        view: 'page',
        surah: 2,
        ayah: 5,
        page: 3,
        updatedAt: DateTime(2026),
      ),
    );
    expect(tester.takeException(), isNull);
    final name = tester.widget<SurahNameText>(find.byType(SurahNameText).first);
    expect(name.surah, 2);
    expect(find.text('تابع القراءة'), findsOneWidget);
    expect(find.text('ابدأ القراءة'), findsNothing);
  });

  for (final style in InterfaceStyle.values) {
    testWidgets('first use fits at text scale 2: ${style.name}', (
      tester,
    ) async {
      await pump(tester, scale: 2, size: const Size(360, 740), style: style);
      expect(tester.takeException(), isNull);
      expect(find.text('ابدأ القراءة'), findsOneWidget);
    });
  }
}
