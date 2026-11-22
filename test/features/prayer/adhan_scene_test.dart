import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/prayer/domain/prayer_calc.dart';
import 'package:tibyan/features/prayer/domain/prayer_settings.dart';
import 'package:tibyan/features/prayer/presentation/adhan_scene.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'prayer_calc_test.dart' show cairo;

const sizes = [
  Size(360, 640),
  Size(432, 960),
  Size(412, 915),
  Size(800, 1280),
  Size(1280, 800),
];

Widget backdrop(PrayerKind p, {bool still = false, bool ticking = true}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: TickerMode(
        enabled: ticking,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: RepaintBoundary(
            key: const ValueKey('scene'),
            child: AdhanBackdrop(prayer: p, hijriDay: 10, night: .3),
          ),
        ),
      ),
    );

void main() {
  setUpAll(tzdata.initializeTimeZones);

  for (final size in sizes) {
    testWidgets('every pixel is painted at ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final p in obligatoryPrayers) {
        await tester.pumpWidget(backdrop(p));
        await tester.pump(const Duration(seconds: 30));
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('scene')),
        );
        final bytes = (await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!;
        }))!;
        final w = size.width.toInt(), h = size.height.toInt();
        expect(bytes.lengthInBytes, w * h * 4);
        var holes = 0;
        for (var i = 3; i < bytes.lengthInBytes; i += 4) {
          if (bytes.getUint8(i) != 255) holes++;
        }
        expect(holes, 0, reason: '${p.name}: unpainted pixels');
        // The bottom is land with shading, not one flat block.
        final bottom = <int>{};
        for (var y = (h * .9).toInt(); y < h; y += 4) {
          bottom.add(bytes.getUint32((y * w + w ~/ 2) * 4));
        }
        expect(bottom.length, greaterThan(1), reason: p.name);
      }
    });
  }

  testWidgets('it moves, pauses when hidden and stays still on request', (
    tester,
  ) async {
    await tester.pumpWidget(backdrop(PrayerKind.isha));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(backdrop(PrayerKind.isha, ticking: false));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(backdrop(PrayerKind.isha, still: true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  test('the moon waxes on the right, is full mid-month, wanes on the left', () {
    const r = 10.0;
    bool lit(int day, double x) =>
        moonPhasePath(moonAge(day), r).contains(Offset(x, 0));
    // A thin crescent: only the right edge.
    expect(lit(2, 9.5), isTrue);
    expect(lit(2, 5), isFalse);
    expect(lit(2, -5), isFalse);
    // The first quarter: the right half.
    expect(lit(8, 3), isTrue);
    expect(lit(8, -5), isFalse);
    // Full.
    expect(lit(15, -9), isTrue);
    expect(lit(15, 9), isTrue);
    // Waning: the left side.
    expect(lit(24, -6), isTrue);
    expect(lit(24, 6), isFalse);
  });

  test('the night runs from maghrib (0) to fajr (1)', () {
    const s = PrayerSettings(enabled: true, place: cairo);
    final day = computeDay(cairo, DateTime(2026, 3, 10), s);
    expect(nightFraction(cairo, day[PrayerKind.maghrib], s), closeTo(0, .01));
    final f = nightFraction(
      cairo,
      day[PrayerKind.fajr].subtract(const Duration(minutes: 1)),
      s,
    );
    expect(f, closeTo(1, .01));
    expect(
      nightFraction(cairo, day[PrayerKind.isha], s),
      inInclusiveRange(.05, .3),
    );
  });

  test('the mosque keeps its proportions on any screen', () {
    for (final size in sizes) {
      final g = AdhanSceneGeometry(size);
      expect(390 * g.k, lessThanOrEqualTo(size.width + .001));
      expect(g.baseY, lessThan(size.height));
      expect(g.left, lessThanOrEqualTo(0));
      expect(g.right, greaterThanOrEqualTo(390));
      expect(g.bottom, greaterThan(708));
    }
  });
}
