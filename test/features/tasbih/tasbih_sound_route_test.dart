import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/tasbih/platform/tasbih_platform.dart';

class _FakeSounds implements TasbihSoundPlayer {
  final played = <String>[];
  final preloaded = <String>[];
  @override
  Future<void> play(String asset) async => played.add(asset);
  @override
  Future<void> preload(List<String> assets) async => preloaded.addAll(assets);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.tibyan/tasbih');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          calls.add(c);
          return null;
        });
  });

  test('routes: native on mobile and macOS, Dart on Windows/Linux', () {
    expect(
      tasbihSoundRoute(TargetPlatform.android, web: false),
      TasbihSoundRoute.native,
    );
    expect(
      tasbihSoundRoute(TargetPlatform.iOS, web: false),
      TasbihSoundRoute.native,
    );
    expect(
      tasbihSoundRoute(TargetPlatform.macOS, web: false),
      TasbihSoundRoute.native,
    );
    expect(
      tasbihSoundRoute(TargetPlatform.windows, web: false),
      TasbihSoundRoute.dart,
    );
    expect(
      tasbihSoundRoute(TargetPlatform.linux, web: false),
      TasbihSoundRoute.dart,
    );
    expect(
      tasbihSoundRoute(TargetPlatform.macOS, web: true),
      TasbihSoundRoute.none,
    );
  });

  for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
    test('$p plays in Dart, not through the channel', () async {
      final sounds = _FakeSounds();
      final t = ChannelTasbihPlatform(
        platform: p,
        web: false,
        desktopSounds: sounds,
      );
      await t.preload(['assets/tasbih/beads/wood_1.wav']);
      await t.play('assets/tasbih/beads/wood_end_1.wav');
      await t.click();
      expect(sounds.preloaded, ['assets/tasbih/beads/wood_1.wav']);
      expect(sounds.played, [
        'assets/tasbih/beads/wood_end_1.wav',
        'assets/tasbih/click.wav',
      ]);
      expect(calls, isEmpty);
    });
  }

  test('macOS uses the native channel for sounds only', () async {
    final sounds = _FakeSounds();
    final t = ChannelTasbihPlatform(
      platform: TargetPlatform.macOS,
      web: false,
      desktopSounds: sounds,
    );
    await t.click();
    await t.play('assets/tasbih/beads/pearl_2.wav');
    await t.setVolumeKeys(true);
    expect(calls.map((c) => c.method), ['click', 'play']);
    expect(sounds.played, isEmpty);
  });

  test('Android keeps its native calls', () async {
    final t = ChannelTasbihPlatform(
      platform: TargetPlatform.android,
      web: false,
    );
    await t.click();
    await t.preload(['a']);
    expect(calls.map((c) => c.method), ['click', 'preload']);
  });
}
