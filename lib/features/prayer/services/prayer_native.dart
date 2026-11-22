import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

/// An adhan the system plays at its time (Android: an exact alarm starts
/// the adhan service, which plays it with the screen off).
@immutable
class NativeAdhan {
  const NativeAdhan({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.files,
    required this.payload,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;

  /// Played one after the other (the adhan, then the dua when chosen).
  final List<String> files;
  final String payload;

  Map<String, Object?> toMap() => {
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'title': title,
    'body': body,
    'files': files,
    'payload': payload,
  };
}

/// The app's own native side for prayer times (`app.tibyan/prayer`):
/// one coarse position, the adhan player, the Android adhan alarms, and
/// the Mac login item. Every call is safe where it is not implemented.
class PrayerNative {
  PrayerNative() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'playing') playing.value = call.arguments == true;
    });
  }

  static const _ch = MethodChannel('app.tibyan/prayer');

  /// Whether the adhan is playing (any player).
  final playing = ValueNotifier<bool>(false);

  AudioPlayer? _desktop;

  bool get _mobileOrMac =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// One coarse position (the system asks for permission the first time);
  /// null when refused, off, or unavailable. No tracking: one fix only.
  Future<({double lat, double lon})?> locate() async {
    if (!_mobileOrMac) return null;
    final r = await _call<Map<Object?, Object?>>('locate');
    final lat = r?['lat'];
    final lon = r?['lon'];
    if (lat is num && lon is num) {
      return (lat: lat.toDouble(), lon: lon.toDouble());
    }
    return null;
  }

  /// Plays [files] (paths or https links) one after the other. Android:
  /// in the adhan service, with its notification and «إيقاف».
  Future<void> play(
    List<String> files, {
    required String title,
    String body = '',
    String payload = '',
  }) async {
    if (files.isEmpty) return;
    if (_mobileOrMac) {
      playing.value = true;
      await _call<void>('play', {
        'files': files,
        'title': title,
        'body': body,
        'payload': payload,
      });
      return;
    }
    // Windows and Linux: just_audio through libmpv, which allows a player
    // besides the recitation's.
    final player = _desktop ??= AudioPlayer();
    await player.stop();
    final sources = [
      for (final f in files)
        f.startsWith('http')
            ? AudioSource.uri(Uri.parse(f))
            : AudioSource.file(p.normalize(f)),
    ];
    playing.value = true;
    unawaited(() async {
      try {
        await player.setAudioSources(sources);
        await player.play();
        await player.processingStateStream.firstWhere(
          (s) => s == ProcessingState.completed,
        );
      } catch (_) {
        // A broken file: nothing plays.
      } finally {
        playing.value = false;
      }
    }());
  }

  Future<void> stop() async {
    playing.value = false;
    if (_mobileOrMac) {
      await _call<void>('stop');
    } else {
      await _desktop?.stop();
    }
  }

  /// Android: replaces every scheduled adhan alarm with [alerts].
  Future<void> scheduleAdhans(List<NativeAdhan> alerts) async {
    if (!Platform.isAndroid) return;
    await _call<void>('schedule', {
      'alerts': [for (final a in alerts) a.toMap()],
    });
  }

  /// Android 12+: whether exact alarms are allowed (the adhan service
  /// may start from an exact alarm only).
  Future<bool> canScheduleExact() async {
    if (!Platform.isAndroid) return false;
    return await _call<bool>('canExact') ?? false;
  }

  /// Android 12+: opens the system page that allows exact alarms.
  Future<void> requestExact() async {
    if (Platform.isAndroid) await _call<void>('requestExact');
  }

  /// macOS 13+: the login item (SMAppService).
  Future<bool> setMacLoginItem(bool on) async {
    if (!Platform.isMacOS) return false;
    return await _call<bool>('loginItem', {'on': on}) ?? false;
  }
}
