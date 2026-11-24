import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/platform/watch_bridge.dart';

/// The native side of the misbaha: the bead's click, counting with the
/// volume buttons while the app is open, and the home screen widget.
abstract interface class TasbihPlatform {
  /// Plays the bundled click (assets/tasbih/click.wav), with no delay.
  Future<void> click();

  /// Plays a bundled sound (a bead's knock, `assets/tasbih/beads/…`) the
  /// same way: natively, with no delay.
  Future<void> play(String asset);

  /// Loads [assets] ahead of their first [play].
  Future<void> preload(List<String> assets);

  /// While on, the volume buttons count (and do not change the volume).
  Future<void> setVolumeKeys(bool on);

  /// A volume button press, while [setVolumeKeys] is on.
  Stream<void> get volumeKey;

  /// Counts made on the home screen widget or the watch since the last
  /// call; the counter is emptied.
  Future<int> takePending();

  /// Fires when the watch adds counts while the app runs, so they can be
  /// taken at once.
  Stream<void> get pendingAdded;

  /// What the home screen widget shows. For a dhikr said in stages,
  /// [stages] is their counts (`33,33,33,1`) and [round] the count in the
  /// current round, so the widget shows the stage as it counts.
  /// [target] is the count to a round (0 for none) and [stageTexts] the
  /// stages' own words, for the watch.
  Future<void> writeWidget({
    required String dhikr,
    required String count,
    required String label,
    String stages = '',
    int round = 0,
    int target = 0,
    List<String> stageTexts = const [],
  });
}

class NoTasbihPlatform implements TasbihPlatform {
  int clicks = 0;

  /// The sounds asked for by [play], in order, and by [preload].
  final played = <String>[];
  final preloaded = <String>[];
  bool volumeKeys = false;
  int pending = 0;
  Map<String, String>? widget;
  final _keys = StreamController<void>.broadcast();

  final _pending = StreamController<void>.broadcast();

  void pressVolume() => _keys.add(null);

  /// A count from the watch: added to [pending], then announced.
  void watchCount(int n) {
    pending += n;
    _pending.add(null);
  }

  @override
  Stream<void> get pendingAdded => _pending.stream;

  @override
  Future<void> click() async => clicks++;

  @override
  Future<void> play(String asset) async => played.add(asset);

  @override
  Future<void> preload(List<String> assets) async => preloaded
    ..clear()
    ..addAll(assets);

  @override
  Future<void> setVolumeKeys(bool on) async => volumeKeys = on;

  @override
  Stream<void> get volumeKey => _keys.stream;

  @override
  Future<int> takePending() async {
    final n = pending;
    pending = 0;
    return n;
  }

  @override
  Future<void> writeWidget({
    required String dhikr,
    required String count,
    required String label,
    String stages = '',
    int round = 0,
    int target = 0,
    List<String> stageTexts = const [],
  }) async => widget = {
    'dhikr': dhikr,
    'count': count,
    'label': label,
    'stages': stages,
    'round': '$round',
    'target': '$target',
    'stageTexts': stageTexts.join('\n'),
  };
}

/// Where the misbaha's sounds play on this platform.
enum TasbihSoundRoute {
  /// The native channel: Android, iOS and macOS.
  native,

  /// just_audio in Dart (libmpv through just_audio_media_kit): Windows and
  /// Linux, which have no native side for the misbaha.
  dart,

  /// Nowhere (the web).
  none,
}

TasbihSoundRoute tasbihSoundRoute(
  TargetPlatform platform, {
  bool web = kIsWeb,
}) {
  if (web) return TasbihSoundRoute.none;
  return switch (platform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS => TasbihSoundRoute.native,
    TargetPlatform.windows || TargetPlatform.linux => TasbihSoundRoute.dart,
    _ => TasbihSoundRoute.none,
  };
}

/// Plays bundled assets on Windows and Linux.
abstract interface class TasbihSoundPlayer {
  Future<void> play(String asset);
  Future<void> preload(List<String> assets);
}

/// A small pool of just_audio players per sound, readied ahead, taken in
/// turn so quick taps overlap. Each player is separate from the
/// recitation's (libmpv allows several), so the recitation goes on.
class JustAudioTasbihSoundPlayer implements TasbihSoundPlayer {
  static const clickAsset = 'assets/tasbih/click.wav';

  final _pools = <String, Future<List<AudioPlayer>>>{};
  var _next = 0;

  Future<List<AudioPlayer>> _load(String asset) {
    if (!asset.startsWith('assets/tasbih/') || asset.contains('..')) {
      return Future.value(const []);
    }
    return _pools[asset] ??= () async {
      final made = <AudioPlayer>[];
      for (var i = 0; i < (asset == clickAsset ? 3 : 2); i++) {
        final p = AudioPlayer(handleAudioSessionActivation: false);
        try {
          await p.setAsset(asset);
          made.add(p);
        } catch (_) {
          await p.dispose();
        }
      }
      return made;
    }();
  }

  @override
  Future<void> preload(List<String> assets) async {
    await Future.wait(assets.map(_load));
  }

  @override
  Future<void> play(String asset) async {
    final ready = await _load(asset);
    if (ready.isEmpty) return;
    final p = ready[_next++ % ready.length];
    await p.seek(Duration.zero);
    if (!p.playing) unawaited(p.play());
  }
}

class ChannelTasbihPlatform implements TasbihPlatform {
  ChannelTasbihPlatform({
    TargetPlatform? platform,
    bool? web,
    TasbihSoundPlayer? desktopSounds,
  }) : _platform = platform ?? defaultTargetPlatform,
       _web = web ?? kIsWeb,
       _route = tasbihSoundRoute(
         platform ?? defaultTargetPlatform,
         web: web ?? kIsWeb,
       ),
       _injected = desktopSounds {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'volumeKey') _keys.add(null);
      if (call.method == 'pendingAdded') _pending.add(null);
    });
  }

  static const _channel = MethodChannel('app.tibyan/tasbih');

  /// The keys the widgets read (docs/HOME_WIDGET.md).
  static const androidProvider = 'app.tibyan.tibyan.TasbihWidgetProvider';
  static const iosKind = 'TibyanTasbihWidget';
  static const pendingKey = 'tasbih_pending';

  final _keys = StreamController<void>.broadcast();
  final _pending = StreamController<void>.broadcast();
  final TargetPlatform _platform;
  final bool _web;
  final TasbihSoundRoute _route;
  late TasbihSoundPlayer? _desktopSounds = _injected;
  final TasbihSoundPlayer? _injected;

  TasbihSoundPlayer get _dartSounds =>
      _desktopSounds ??= JustAudioTasbihSoundPlayer();

  @override
  Stream<void> get pendingAdded => _pending.stream;

  Future<void> _group() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await HomeWidget.setAppGroupId('group.app.tibyan.tibyan');
    }
  }

  /// Volume keys, the widget and the watch: mobile only.
  bool get _mobile =>
      !_web &&
      (_platform == TargetPlatform.android || _platform == TargetPlatform.iOS);

  Future<void> _call(String method, [Object? args]) async {
    if (!_mobile) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (_) {
      // The sound or the service could not start; counting goes on without crash.
    }
  }

  /// The sounds: natively on mobile and macOS, in Dart on Windows/Linux.
  Future<void> _sound(String method, Object? args) async {
    switch (_route) {
      case TasbihSoundRoute.native:
        try {
          await _channel.invokeMethod<void>(method, args);
        } catch (_) {
          // No sound; counting goes on.
        }
      case TasbihSoundRoute.dart:
        try {
          if (method == 'preload') {
            await _dartSounds.preload((args as List).cast<String>());
          } else {
            await _dartSounds.play(args as String);
          }
        } catch (_) {
          // No sound; counting goes on.
        }
      case TasbihSoundRoute.none:
    }
  }

  @override
  Future<void> click() => _route == TasbihSoundRoute.native
      ? _sound('click', null)
      : _sound('play', JustAudioTasbihSoundPlayer.clickAsset);

  @override
  Future<void> play(String asset) => _sound('play', asset);

  @override
  Future<void> preload(List<String> assets) => _sound('preload', assets);

  @override
  Future<void> setVolumeKeys(bool on) => _call('setVolumeKeys', on);

  @override
  Stream<void> get volumeKey => _keys.stream;

  @override
  Future<int> takePending() async {
    if (!_mobile) return 0;
    var n = 0;
    try {
      await _group();
      final w = await HomeWidget.getWidgetData<int>(pendingKey);
      if (w != null && w > 0) {
        n += w;
        await HomeWidget.saveWidgetData<int>(pendingKey, 0);
      }
    } on Object {
      // No widget storage (no App Group yet).
    }
    return n;
  }

  @override
  Future<void> writeWidget({
    required String dhikr,
    required String count,
    required String label,
    String stages = '',
    int round = 0,
    int target = 0,
    List<String> stageTexts = const [],
  }) async {
    if (!_mobile) return;
    await WatchBridge.push({
      'tasbih_dhikr': dhikr,
      'tasbih_count': count,
      'tasbih_label': label,
      'tasbih_target': '$target',
      'tasbih_stages': stages,
      // One line per stage, cut from the dhikr's own text.
      'tasbih_stage_texts': stageTexts.join('\n'),
    });
    try {
      await _group();
      await HomeWidget.saveWidgetData<String>('tasbih_dhikr', dhikr);
      await HomeWidget.saveWidgetData<String>('tasbih_count', count);
      await HomeWidget.saveWidgetData<String>('tasbih_label', label);
      await HomeWidget.saveWidgetData<String>('tasbih_stages', stages);
      await HomeWidget.saveWidgetData<int>('tasbih_round', round);
      await HomeWidget.updateWidget(
        qualifiedAndroidName: androidProvider,
        iOSName: iosKind,
      );
    } on Object {
      // The widget is not set up on this device.
    }
  }
}
