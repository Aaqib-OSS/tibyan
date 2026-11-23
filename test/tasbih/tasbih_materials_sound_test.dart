import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tibyan/core/db/user_database.dart';
import 'package:tibyan/core/settings/settings_controller.dart';
import 'package:tibyan/features/mushaf/mushaf_providers.dart';
import 'package:tibyan/features/tasbih/domain/bead_sounds.dart';
import 'package:tibyan/features/tasbih/domain/dhikr.dart';
import 'package:tibyan/features/tasbih/platform/tasbih_platform.dart';
import 'package:tibyan/features/tasbih/presentation/styles/bead_look.dart';
import 'package:tibyan/features/tasbih/presentation/tasbih_settings_tiles.dart';
import 'package:tibyan/features/tasbih/tasbih_providers.dart';
import 'package:tibyan/features/tasbih/tasbih_settings.dart';
import 'package:tibyan/l10n/app_localizations_ar.dart';
import 'package:tibyan/l10n/app_localizations_en.dart';

final _adhkar = parseAppAdhkar(
  File('assets/tasbih/adhkar.json').readAsStringSync(),
);

Future<(ProviderContainer, NoTasbihPlatform)> _container(
  Map<String, Object> prefs,
) async {
  SharedPreferences.setMockInitialValues(prefs);
  final shared = await SharedPreferences.getInstance();
  final platform = NoTasbihPlatform();
  final db = UserDatabase(NativeDatabase.memory());
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(shared),
      userDatabaseProvider.overrideWithValue(db),
      tasbihPlatformProvider.overrideWithValue(platform),
      appAdhkarProvider.overrideWith((ref) => _adhkar),
    ],
  );
  addTearDown(() async {
    c.dispose();
    await db.close();
  });
  c.listen(appAdhkarProvider, (_, _) {});
  await c.read(appAdhkarProvider.future);
  return (c, platform);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('materials', () {
    test('there are six, the first three as they were stored before', () {
      expect(BeadMaterial.values.map((m) => m.name), [
        'amber',
        'wood',
        'pearl',
        'rosewood',
        'turquoise',
        'yusr',
      ]);
    });

    test('each round-trips through the settings', () async {
      for (final m in BeadMaterial.values) {
        final (c, _) = await _container({});
        await c.read(tasbihSettingsProvider.notifier).setMaterial(m);
        final shared = c.read(sharedPreferencesProvider);
        expect(shared.getString('settings.tasbih.material'), m.name);
        final (again, _) = await _container({
          'settings.tasbih.material': m.name,
        });
        expect(again.read(tasbihSettingsProvider).material, m);
      }
    });

    test(
      'a stored value the app does not know falls back to the default',
      () async {
        final (c, _) = await _container({
          'settings.tasbih.material': 'jade',
          'settings.tasbih.render': 'hologram',
          'settings.tasbih.style': 'abacus',
        });
        final s = c.read(tasbihSettingsProvider);
        expect(s.material, const TasbihSettings().material);
        expect(s.material, BeadMaterial.amber);
        expect(s.render, isNull);
        expect(s.style, TasbihStyle.misbaha);
      },
    );

    test('each has its own look, name and surface', () {
      final ar = AppLocalizationsAr(), en = AppLocalizationsEn();
      expect(
        {for (final m in BeadMaterial.values) BeadLook.of(m).kind}.length,
        6,
      );
      expect(
        {for (final m in BeadMaterial.values) beadMaterialName(ar, m)}.length,
        6,
      );
      expect(beadMaterialName(ar, BeadMaterial.rosewood), 'خشب الورد');
      expect(beadMaterialName(ar, BeadMaterial.turquoise), 'فيروز');
      expect(beadMaterialName(ar, BeadMaterial.yusr), 'يُسر');
      expect(beadMaterialName(en, BeadMaterial.turquoise), 'Turquoise');
      // The three that were there keep their colours.
      expect(BeadLook.of(BeadMaterial.amber).base.toARGB32(), 0xFFC77A1C);
      expect(BeadLook.of(BeadMaterial.wood).base.toARGB32(), 0xFF6E4326);
      expect(BeadLook.of(BeadMaterial.pearl).base.toARGB32(), 0xFFE6E0D3);
    });
  });

  group('the default rendering', () {
    test('true 3D where shaders work, unless the reader chose', () {
      expect(
        effectiveMisbahaRender(chosen: null, shaders: true),
        MisbahaRender.real,
      );
      for (final chosen in MisbahaRender.values) {
        expect(effectiveMisbahaRender(chosen: chosen, shaders: true), chosen);
      }
    });

    test('the suggested look where they do not, whatever was chosen', () {
      for (final chosen in [null, ...MisbahaRender.values]) {
        expect(
          effectiveMisbahaRender(chosen: chosen, shaders: false),
          MisbahaRender.suggested,
        );
      }
    });

    test('a choice is stored and read back; none stays none', () async {
      final (c, _) = await _container({});
      expect(c.read(tasbihSettingsProvider).render, isNull);
      await c
          .read(tasbihSettingsProvider.notifier)
          .setRender(MisbahaRender.suggested);
      expect(c.read(tasbihSettingsProvider).render, MisbahaRender.suggested);
      final (again, _) = await _container({'settings.tasbih.render': 'real'});
      expect(again.read(tasbihSettingsProvider).render, MisbahaRender.real);
    });
  });

  group('bead sounds', () {
    test('every file the picker can name is bundled', () {
      final wanted = {
        for (final m in BeadMaterial.values) ...BeadSoundPicker.assetsOf(m),
      };
      expect(wanted.length, 30);
      for (final asset in wanted) {
        expect(File(asset).existsSync(), isTrue, reason: asset);
      }
      expect(Directory('assets/tasbih/beads').listSync().length, wanted.length);
    });

    test('rosewood uses the wood files', () {
      expect(BeadMaterial.rosewood.soundKey, 'wood');
      expect(
        BeadSoundPicker.assetsOf(BeadMaterial.rosewood),
        BeadSoundPicker.assetsOf(BeadMaterial.wood),
      );
      expect(
        BeadSoundPicker.countAsset(BeadMaterial.turquoise, 2),
        'assets/tasbih/beads/turquoise_2.wav',
      );
      expect(
        BeadSoundPicker.endAsset(BeadMaterial.rosewood, 1),
        'assets/tasbih/beads/wood_end_1.wav',
      );
    });

    test(
      'a count plays its material, never the same variant twice running',
      () {
        for (final m in BeadMaterial.values) {
          final picker = BeadSoundPicker(math.Random(3));
          final counts = BeadSoundPicker.assetsOf(m).sublist(0, 4);
          String? last;
          final heard = <String>{};
          for (var i = 0; i < 400; i++) {
            final s = picker.count(m);
            expect(counts, contains(s));
            expect(s, isNot(last));
            heard.add(last = s);
          }
          expect(heard.length, 4);
        }
      },
    );

    test('the joint plays one of the two end variants', () {
      final picker = BeadSoundPicker(math.Random(5));
      final heard = {
        for (var i = 0; i < 60; i++) picker.end(BeadMaterial.yusr),
      };
      expect(heard, {
        'assets/tasbih/beads/yusr_end_1.wav',
        'assets/tasbih/beads/yusr_end_2.wav',
      });
    });

    test(
      'the misbaha plays its beads; the lap ends with an end variant',
      () async {
        final (c, platform) = await _container({
          'settings.tasbih.sound': true,
          'settings.tasbih.material': 'rosewood',
          'settings.tasbih.target': 100,
        });
        final counter = c.read(tasbihCounterProvider.notifier)..preloadSounds();
        expect(platform.preloaded, BeadSoundPicker.assetsOf(BeadMaterial.wood));
        await counter.tap();
        await counter.tap();
        expect(platform.clicks, 0);
        expect(platform.played.length, 2);
        expect(platform.played[0], isNot(platform.played[1]));
        for (final s in platform.played) {
          expect(s, matches(r'^assets/tasbih/beads/wood_[1-4]\.wav$'));
        }
        counter.lapFeedback();
        expect(platform.played.last, matches(r'beads/wood_end_[12]\.wav$'));
      },
    );

    test('the other styles still click', () async {
      for (final style in [
        TasbihStyle.button,
        TasbihStyle.lcd,
        TasbihStyle.screen,
      ]) {
        final (c, platform) = await _container({
          'settings.tasbih.sound': true,
          'settings.tasbih.style': style.name,
        });
        final counter = c.read(tasbihCounterProvider.notifier)..preloadSounds();
        await counter.tap();
        counter.lapFeedback();
        expect(platform.clicks, 1, reason: style.name);
        expect(platform.played, isEmpty);
        expect(platform.preloaded, isEmpty);
      }
    });

    test('sound off (the default): silence', () async {
      final (c, platform) = await _container({});
      final counter = c.read(tasbihCounterProvider.notifier)..preloadSounds();
      await counter.tap();
      counter.lapFeedback();
      expect(platform.clicks, 0);
      expect(platform.played, isEmpty);
      expect(platform.preloaded, isEmpty);
    });
  });
}
