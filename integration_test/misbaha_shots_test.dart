// Screenshots of «المسبحة» in its true 3D rendering, on a real device or
// simulator (the shader runs on its GPU): each material in the light
// theme, one at night, one part of the way round and one as the joint
// crosses; then frame times over a run of counts.
//
//   flutter test integration_test/misbaha_shots_test.dart -d <device>
//
// Uses the device's own app data (run it on a simulator made for it).
// Each picture is printed as base64 lines «PNG:<name>:<chunk>» and
// «PNGEND:<name>», joined into files by a shell; the frame times as
// «FRAMES:…».
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tibyan/app.dart';
import 'package:tibyan/core/router/app_router.dart';
import 'package:tibyan/core/settings/app_settings.dart';
import 'package:tibyan/core/settings/settings_controller.dart';
import 'package:tibyan/features/tasbih/presentation/styles/misbaha_view.dart';
import 'package:tibyan/features/tasbih/presentation/tasbih_screen.dart';
import 'package:tibyan/features/tasbih/tasbih_providers.dart';
import 'package:tibyan/features/tasbih/tasbih_settings.dart';
import 'package:tibyan/main.dart' as app;

Future<void> pumpFor(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

Future<void> snap(
  WidgetTester t,
  String name, {
  Duration wait = const Duration(seconds: 3),
}) async {
  await pumpFor(t, wait);
  final view = t.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final px = view.flutterView.physicalSize;
  final image = await layer.toImage(Offset.zero & px, pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final b64 = base64Encode(bytes!.buffer.asUint8List());
  for (var i = 0; i < b64.length; i += 2000) {
    // ignore: avoid_print
    print('PNG:$name:${b64.substring(i, (i + 2000).clamp(0, b64.length))}');
    if (i % 200000 == 0) await Future<void>.delayed(Duration.zero);
  }
  // ignore: avoid_print
  print('PNGEND:$name');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('misbaha screenshots', (t) async {
    unawaited(app.main());
    while (find.byType(TibyanApp).evaluate().isEmpty) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await pumpFor(t, const Duration(seconds: 3));
    final skip = find.byKey(const ValueKey('onboarding-skip-all'));
    if (skip.evaluate().isNotEmpty) {
      await t.tap(skip);
      await pumpFor(t, const Duration(seconds: 2));
    }
    final c = ProviderScope.containerOf(t.element(find.byType(TibyanApp)));
    final s = c.read(settingsProvider.notifier);
    TasbihSettingsController tasbihOf() =>
        c.read(tasbihSettingsProvider.notifier);
    final router = c.read(appRouterProvider);
    final modeBefore = c.read(settingsProvider).mode;
    final before = c.read(tasbihSettingsProvider);
    final prefs = c.read(sharedPreferencesProvider);
    await prefs.remove('settings.tasbih.render');
    c.invalidate(tasbihSettingsProvider);
    await s.setMode(ModeSetting.light);
    await tasbihOf().setStyle(TasbihStyle.misbaha);
    await tasbihOf().setTarget(33);
    await tasbihOf().setSound(false);
    // A reader who never chose a rendering: true 3D where shaders work.
    expect(c.read(tasbihSettingsProvider).render, isNull);
    router.go(tasbihLocation);
    await pumpFor(t, const Duration(seconds: 3));
    c.read(tasbihCounterProvider.notifier).reset();
    await pumpFor(t, const Duration(seconds: 1));
    expect(BeadShader.available.value, isTrue);
    final view = find.byType(MisbahaView);
    expect(view, findsOneWidget);

    Future<void> count(int n) async {
      for (var i = 0; i < n; i++) {
        await t.tap(view);
        await pumpFor(t, const Duration(milliseconds: 240));
      }
    }

    // Each material, six counts in.
    await count(6);
    for (final m in BeadMaterial.values) {
      await tasbihOf().setMaterial(m);
      await snap(t, 'app-${m.name}-light');
    }
    // At night.
    await tasbihOf().setMaterial(BeadMaterial.rosewood);
    await s.setMode(ModeSetting.night);
    await snap(t, 'app-rosewood-night');
    await tasbihOf().setMaterial(BeadMaterial.pearl);
    await snap(t, 'app-pearl-night');
    await s.setMode(ModeSetting.light);
    await tasbihOf().setMaterial(BeadMaterial.rosewood);

    // Part of the way: the joint about half way round. Frame times over
    // these counts.
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> list) => timings.addAll(list);
    SchedulerBinding.instance.addTimingsCallback(collect);
    await count(10);
    await pumpFor(t, const Duration(seconds: 2));
    SchedulerBinding.instance.removeTimingsCallback(collect);
    if (timings.isNotEmpty) {
      double ms(Duration d) => d.inMicroseconds / 1000;
      final build = [for (final f in timings) ms(f.buildDuration)]..sort();
      final raster = [for (final f in timings) ms(f.rasterDuration)]..sort();
      String stats(List<double> v) =>
          'median ${v[v.length ~/ 2].toStringAsFixed(2)} '
          'p90 ${v[v.length * 9 ~/ 10].toStringAsFixed(2)} '
          'max ${v.last.toStringAsFixed(2)}';
      // ignore: avoid_print
      print(
        'FRAMES: ${timings.length} frames; build ms ${stats(build)}; '
        'raster ms ${stats(raster)}',
      );
    }
    await snap(t, 'app-rosewood-halfway');

    // The 33rd bead, then the joint crossing by itself: caught on its way.
    await count(16);
    await t.tap(view);
    await pumpFor(t, const Duration(milliseconds: 520));
    await snap(t, 'app-rosewood-joint-crossing', wait: Duration.zero);
    await pumpFor(t, const Duration(seconds: 3));
    expect(c.read(tasbihCounterProvider).rounds, greaterThanOrEqualTo(1));
    await snap(t, 'app-rosewood-lap-done');

    // The light option stays selectable.
    await tasbihOf().setRender(MisbahaRender.suggested);
    await snap(t, 'app-rosewood-suggested');
    // The reader's settings are left as they were.
    await s.setMode(modeBefore);
    await tasbihOf().setStyle(before.style);
    await tasbihOf().setMaterial(before.material);
    await tasbihOf().setTarget(before.target);
    await tasbihOf().setSound(before.sound);
    final chosen = before.render;
    if (chosen == null) {
      await prefs.remove('settings.tasbih.render');
    } else {
      await tasbihOf().setRender(chosen);
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
