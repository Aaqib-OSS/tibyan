import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tibyan/core/db/content_database.dart';
import 'package:tibyan/core/downloads/background_downloads.dart';
import 'package:tibyan/core/ui/look_kit.dart';
import 'package:tibyan/features/audio/background_recitations.dart';
import 'package:tibyan/features/audio/recitation.dart';
import 'package:tibyan/features/mushaf/presentation/downloads_center_screen.dart';

import '../tasmee/tasmee_test_env.dart';
import 'background_downloads_test.dart' show FakeDownloader;

const _here = ReciterRow(
  id: 7,
  nameAr: 'المنشاوي',
  nameEn: 'Minshawi',
  style: 'murattal',
  folderUrl: 'https://host/minshawi/',
  sourceId: 1,
  riwaya: 'hafs',
);

const _there = ReciterRow(
  id: 9,
  nameAr: 'الحصري',
  nameEn: 'Husary',
  style: 'murattal',
  folderUrl: 'https://host/husary/',
  sourceId: 1,
  riwaya: 'hafs',
);

void main() {
  late TasmeeTestData data;
  setUpAll(() => data = TasmeeTestData.open());
  tearDownAll(() => data.close());

  Future<void> pumpCenter(
    WidgetTester tester, {
    double textScale = 1,
    DownloadsSection? section,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => data.root.path,
    );
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('hub');
    addTearDown(() => tmp.deleteSync(recursive: true));
    // One surah of reciter 7 on the device.
    File(p.join(tmp.path, 'audio', '7', surahFile(1)))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(2000, 1));
    final downloads = BackgroundDownloads(downloader: FakeDownloader());
    final recitations = BackgroundRecitations(
      downloads: downloads,
      files: AudioFiles(tmp),
      supportDir: () async => tmp,
    );
    final container = await tasmeeContainer(
      tester,
      data,
      overrides: [
        backgroundDownloadsProvider.overrideWithValue(downloads),
        backgroundRecitationsProvider.overrideWithValue(recitations),
        recitersProvider.overrideWith((ref) async => [_here, _there]),
      ],
    );
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: tasmeeApp(
          container,
          LookTheme(child: DownloadsCenterScreen(section: section)),
          theme: tasmeeTheme(container),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('the hub: the storage card first, then the five tiles', (
    tester,
  ) async {
    await pumpCenter(tester);
    final card = find.byKey(const ValueKey('downloads-storage-card'));
    expect(card, findsOneWidget);
    for (final s in DownloadsSection.values) {
      final tile = find.byKey(ValueKey('downloads-tile-${s.name}'));
      expect(tile, findsOneWidget, reason: s.name);
      expect(
        tester.getTopLeft(card).dy,
        lessThan(tester.getTopLeft(tile).dy),
      );
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tile opens its section; «على جهازي» hides the rest', (
    tester,
  ) async {
    await pumpCenter(tester);
    await tester.tap(find.byKey(const ValueKey('downloads-tile-recitations')));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('downloads-section-recitations')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('downloads-reciter-7-idle')), findsOne);
    expect(find.byKey(const ValueKey('downloads-reciter-9-idle')), findsOne);
    expect(find.byKey(const ValueKey('downloads-header-on-device')), findsOne);

    await tester.tap(find.byKey(const ValueKey('downloads-filter-on-device')));
    await settle(tester, rounds: 4);
    expect(find.byKey(const ValueKey('downloads-reciter-7-idle')), findsOne);
    expect(find.byKey(const ValueKey('downloads-reciter-9-idle')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the hub search finds items across sections', (tester) async {
    await pumpCenter(tester);
    await tester.enterText(
      find.byKey(const ValueKey('downloads-search')),
      'الحصري',
    );
    await settle(tester, rounds: 4);
    final hit = find.byKey(const ValueKey('downloads-result-recitations-9'));
    expect(hit, findsOneWidget);
    expect(find.byKey(const ValueKey('downloads-tile-mushaf')), findsNothing);
    await tester.tap(hit);
    await settle(tester);
    expect(find.byKey(const ValueKey('downloads-reciter-9-idle')), findsOne);
    expect(find.byKey(const ValueKey('downloads-reciter-7-idle')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a section opens directly from its deep link', (tester) async {
    await pumpCenter(tester, section: DownloadsSection.adhan);
    expect(find.byKey(const ValueKey('downloads-section-adhan')), findsOne);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('text scale 2.0: the hub and a section do not overflow', (
    tester,
  ) async {
    await pumpCenter(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('downloads-tile-recitations')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('downloads-tile-recitations')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
