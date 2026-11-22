import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/settings/settings_controller.dart';
import 'package:tibyan/core/theme/theme_registry.dart';
import 'package:tibyan/features/audio/ayah_repeat_sheet.dart';
import 'package:tibyan/features/audio/recitation.dart';
import 'package:tibyan/l10n/app_localizations.dart';

import 'player_test.dart' as player;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => player.registry = await ThemeRegistry.load(rootBundle));

  group('repeat each verse inside a stretch', () {
    testWidgets('each verse twice, then the stretch again', (tester) async {
      final (c, audio) = await player.recitation();
      final ctrl = c.read(recitationProvider.notifier);
      await ctrl.play(2, from: 2, to: 3, repeat: 2, verseRepeat: 2);
      RecitationState s() => c.read(recitationProvider);
      expect(s().repeatsVerseInRange, isTrue);

      // Verse 2 (10–20 s): once more.
      audio.at(19970);
      await tester.pump();
      expect(s().verseRepeatDone, 1);
      expect(audio.seeks.last, const Duration(milliseconds: 10000));
      expect(audio.playing, isTrue);

      // Its second time done: plays on into verse 3.
      final seeks = audio.seeks.length;
      audio.at(19970);
      await tester.pump();
      expect(audio.seeks.length, seeks);
      audio.at(20500);
      expect(s().ayah, 3);
      expect(s().verseRepeatDone, 0);

      // Verse 3 (20–30 s) twice, then the stretch from verse 2.
      audio.at(29970);
      await tester.pump();
      expect(s().verseRepeatDone, 1);
      expect(audio.seeks.last, const Duration(milliseconds: 20000));
      audio.at(29970);
      await tester.pump();
      expect(s().repeatDone, 1);
      expect(s().ayah, 2);
      expect(audio.seeks.last, const Duration(milliseconds: 10000));

      // The second pass repeats each verse afresh.
      audio.at(19970);
      await tester.pump();
      expect(s().verseRepeatDone, 1);
      expect(audio.seeks.last, const Duration(milliseconds: 10000));
      audio.at(19970);
      await tester.pump();
      audio.at(20500);
      audio.at(29970);
      await tester.pump();
      audio.at(29970);
      await tester.pump();
      // Both passes done: it stops.
      expect(s().repeatDone, 2);
      expect(audio.playing, isFalse);
    });

    testWidgets('∞ per verse keeps the first verse', (tester) async {
      final (c, audio) = await player.recitation();
      final ctrl = c.read(recitationProvider.notifier);
      await ctrl.play(2, from: 1, to: 3, verseRepeat: 0);
      for (var i = 1; i <= 6; i++) {
        audio.at(9970);
        await tester.pump();
        expect(c.read(recitationProvider).verseRepeatDone, i);
        expect(audio.seeks.last, Duration.zero);
      }
      expect(c.read(recitationProvider).ayah, 1);
    });

    testWidgets('a pause between verse repetitions', (tester) async {
      final (c, audio) = await player.recitation();
      final ctrl = c.read(recitationProvider.notifier);
      await ctrl.play(
        2,
        from: 2,
        to: 3,
        verseRepeat: 3,
        silence: const Duration(seconds: 2),
      );
      audio.at(19970);
      await tester.pump();
      expect(audio.playing, isFalse);
      expect(c.read(recitationProvider).playing, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(audio.playing, isTrue);
      expect(audio.seeks.last, const Duration(milliseconds: 10000));
    });
  });

  group('playRepeat', () {
    testWidgets('remembers the choices', (tester) async {
      final (c, _) = await player.recitation();
      await c
          .read(recitationProvider.notifier)
          .playRepeat(
            2,
            from: 4,
            to: 2,
            verseRepeat: 5,
            repeat: 3,
            silence: const Duration(seconds: 4),
          );
      final s = c.read(recitationProvider);
      expect((s.rangeFrom, s.rangeTo), (2, 4));
      expect((s.verseRepeat, s.repeat), (5, 3));
      expect(s.silence, const Duration(seconds: 4));
      final saved = c.read(settingsProvider);
      expect((saved.verseRepeat, saved.repeat, saved.repeatSilence), (5, 3, 4));
    });

    testWidgets('one verse: its count is the whole count', (tester) async {
      final (c, audio) = await player.recitation();
      await c
          .read(recitationProvider.notifier)
          .playRepeat(
            2,
            from: 2,
            to: 2,
            verseRepeat: 3,
            repeat: 10,
            silence: Duration.zero,
          );
      final s = c.read(recitationProvider);
      expect((s.repeat, s.verseRepeat), (3, 1));
      for (var i = 0; i < 3; i++) {
        audio.at(19970);
        await tester.pump();
      }
      expect(audio.playing, isFalse);
    });
  });

  group('sheet', () {
    Future<ProviderContainer> pumpSheet(
      WidgetTester tester, {
      double textScale = 1,
    }) async {
      final (c, _) = await player.recitation();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const Scaffold(
              body: AyahRepeatSheet(surah: 2, from: 2, to: 3, reciterId: 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('starts the chosen repetition', (tester) async {
      final c = await pumpSheet(tester);
      await tester.tap(find.text('×١٠').first);
      await tester.pump();
      await tester.ensureVisible(find.byIcon(Icons.repeat));
      await tester.tap(find.byIcon(Icons.repeat));
      await tester.pumpAndSettle();
      final s = c.read(recitationProvider);
      expect((s.rangeFrom, s.rangeTo, s.verseRepeat), (2, 3, 10));
    });

    testWidgets('targets of 48 dp and no overflow at 200% text', (
      tester,
    ) async {
      await pumpSheet(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });
  });
}
