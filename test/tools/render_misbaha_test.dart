import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/tasbih/presentation/styles/misbaha_view.dart';
import 'package:tibyan/features/tasbih/tasbih_settings.dart';

/// Not a test: draws the true 3D misbaha alone, each material on a light
/// and a dark surface, at rest and part of the way round, into
/// `$MISBAHA_OUT/<name>.png`, for comparing with the approved mockup.
/// Runs only with RENDER_MISBAHA=1.
void main() {
  final run = Platform.environment['RENDER_MISBAHA'] == '1';
  final outPath = Platform.environment['MISBAHA_OUT'] ?? 'build/misbaha';

  testWidgets(
    'render the misbaha',
    (tester) async {
      tester.view.physicalSize = const Size(356, 430) * 3;
      tester.view.devicePixelRatio = 3;
      final out = Directory(outPath)..createSync(recursive: true);
      BeadShader.debugSetAvailable(null);
      await tester.runAsync(() async {
        BeadShader.ensureLoaded();
        for (var i = 0; i < 100 && BeadShader.available.value == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(BeadShader.available.value, isTrue);
      final boundary = GlobalKey();
      Future<void> shot(
        String name,
        BeadMaterial material, {
        bool dark = false,
        int count = 0,
        int taps = 0,
        Duration after = const Duration(seconds: 3),
      }) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? ThemeData.dark() : ThemeData.light(),
              home: ColoredBox(
                color: dark ? const Color(0xFF1B2320) : const Color(0xFFF9F5EC),
                child: MisbahaView(
                  key: ValueKey(name),
                  material: material,
                  render: MisbahaRender.real,
                  count: count,
                  roundSize: 33,
                  onCount: () {},
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < taps; i++) {
          await tester.tap(find.byType(MisbahaView));
          await tester.pump(const Duration(milliseconds: 400));
        }
        await tester.pump(after);
        final object =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final bytes = await tester.runAsync(() async {
          final image = await object.toImage(pixelRatio: 3);
          final d = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          return d!.buffer.asUint8List();
        });
        File('${out.path}/$name.png').writeAsBytesSync(bytes!);
      }

      for (final m in BeadMaterial.values) {
        await shot('${m.name}_light', m, count: 6);
      }
      await shot('rosewood_dark', BeadMaterial.rosewood, dark: true, count: 6);
      await shot('pearl_dark', BeadMaterial.pearl, dark: true, count: 20);
      await shot('rosewood_rest', BeadMaterial.rosewood);
      await shot('rosewood_half', BeadMaterial.rosewood, count: 16);
      await shot(
        'rosewood_joint',
        BeadMaterial.rosewood,
        count: 32,
        taps: 1,
        after: const Duration(milliseconds: 150),
      );
    },
    skip: !run,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
