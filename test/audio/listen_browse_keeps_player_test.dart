import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/db/content_database.dart';
import 'package:tibyan/core/settings/app_settings.dart';
import 'package:tibyan/features/audio/audio_downloads_screen.dart';
import 'package:tibyan/features/audio/recitation.dart';
import 'package:tibyan/features/audio/reciter_avatar.dart';
import 'package:tibyan/features/mushaf/mushaf_providers.dart';

import '../tasmee/tasmee_test_env.dart';

/// Plays nothing: records what the screen asks of the player.
class FakeRecitation extends RecitationController {
  FakeRecitation(this.initial);

  final RecitationState initial;
  final calls = <String>[];

  @override
  RecitationState build() => initial;

  @override
  Future<void> changeReciter(int id) async => calls.add('changeReciter $id');

  @override
  Future<void> play(
    int surah, {
    int? from,
    int? to,
    int? rangeFrom,
    int? repeat,
    int? verseRepeat,
    Duration? silence,
    bool start = true,
    bool nearSpeech = false,
    int? word,
    ReciterRow? reciter,
  }) async => calls.add('play $surah ${reciter?.id}');
}

/// «الاستماع»: choosing another reciter only browses its list; the
/// recitation playing goes on until a surah of the new list is played.
void main() {
  late TasmeeTestData data;
  setUpAll(() => data = TasmeeTestData.open());
  tearDownAll(() => data.close());

  for (final edition in MushafEdition.values) {
    testWidgets('browsing a reciter keeps the player (${edition.name})', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => data.root.path,
      );
      tester.view
        ..physicalSize = const Size(430, 932)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      resetListenChoice();
      late FakeRecitation fake;
      final probe = await tasmeeContainer(
        tester,
        data,
        prefs: {'settings.edition': edition.name},
      );
      final all = (await tester.runAsync(
        () => probe.read(allRecitersProvider.future),
      ))!;
      final riwaya = probe.read(editionProvider).riwaya.name;
      final mine = all.where((r) => r.riwaya == riwaya).toList();
      final playingR = mine.first;
      final other = mine.length > 1
          ? mine[1]
          : all.firstWhere((r) => r.id != playingR.id);

      final container = await tasmeeContainer(
        tester,
        data,
        prefs: {'settings.edition': edition.name},
        overrides: [
          recitationProvider.overrideWith(
            () => fake = FakeRecitation(
              RecitationState(
                active: true,
                playing: true,
                surah: 94,
                ayah: 3,
                reciterId: playingR.id,
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        tasmeeApp(
          container,
          const AudioDownloadsScreen(),
          theme: tasmeeTheme(container),
        ),
      );
      await settle(tester);

      Finder avatar(int id) => find.ancestor(
        of: find.byWidgetPredicate((w) => w is ReciterAvatar && w.id == id),
        matching: find.byType(InkWell),
      );
      final list = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last;
      final now = find.byKey(const ValueKey('listen-surah-94'));

      // Browsing the playing reciter: its surah is highlighted.
      await tester.scrollUntilVisible(now, 300, scrollable: list);
      expect(tester.widget<ListTile>(now).selected, isTrue);

      // Browse another reciter: nothing reaches the player.
      await tester.ensureVisible(avatar(other.id).first);
      await tester.tap(avatar(other.id).first);
      await settle(tester);
      expect(fake.calls, isEmpty);
      expect(container.read(recitationProvider).reciterId, playingR.id);
      expect(container.read(recitationProvider).surah, 94);

      // Its al-Sharh is not the one playing.
      await tester.scrollUntilVisible(now, 300, scrollable: list);
      expect(tester.widget<ListTile>(now).selected, isFalse);

      // Playing a surah of the browsed list switches the queue.
      await tester.tap(now);
      await settle(tester);
      expect(fake.calls, ['play 94 ${other.id}']);
    });
  }
}
