// GlitchTip 14/15: no toImage/toImageSync on Android while the surface is
// gone (background) or not back yet (just resumed).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/ui/raster_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugResumedAt = null);

  const android = TargetPlatform.android;

  test('Android: only while resumed', () {
    for (final s in AppLifecycleState.values) {
      expect(
        canRasterizeNow(platform: android, state: s),
        s == AppLifecycleState.resumed,
        reason: s.name,
      );
    }
  });

  test('Android: waits a moment after coming back', () {
    final back = DateTime(2026, 11, 22, 12);
    debugResumedAt = back;
    bool at(Duration d) => canRasterizeNow(
      platform: android,
      state: AppLifecycleState.resumed,
      now: back.add(d),
    );
    expect(at(const Duration(milliseconds: 15)), isFalse);
    expect(at(rasterSettle - const Duration(milliseconds: 1)), isFalse);
    expect(at(rasterSettle), isTrue);
  });

  test('other platforms are never held back', () {
    for (final p in [
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      expect(
        canRasterizeNow(platform: p, state: AppLifecycleState.paused),
        isTrue,
        reason: p.name,
      );
    }
  });
}
