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

  test('the full moon is an exact circle on days 14 and 15', () {
    const r = 24.0;
    for (final day in [14, 15]) {
      final b = moonPhasePath(moonAge(day), r).getBounds();
      expect(b.left, closeTo(-r, 1e-6), reason: 'day $day');
      expect(b.right, closeTo(r, 1e-6), reason: 'day $day');
      expect(b.top, closeTo(-r, 1e-6), reason: 'day $day');
      expect(b.bottom, closeTo(r, 1e-6), reason: 'day $day');
      // Lit on both sides, not only at the edges.
      final path = moonPhasePath(moonAge(day), r);
      for (final x in [-20.0, -10.0, 0.0, 10.0, 20.0]) {
        expect(path.contains(Offset(x, 0)), isTrue, reason: 'day $day x $x');
      }
    }
  });

  test('the phase is right for days 1, 7, 14 and 22', () {
    const r = 10.0;
    bool lit(int day, double x) =>
        moonPhasePath(moonAge(day), r).contains(Offset(x, 0));
    // Day 1: a thin crescent on the right.
    expect(lit(1, 9.8), isTrue);
    expect(lit(1, 5), isFalse);
    expect(lit(1, -9), isFalse);
    // Day 7: the first quarter, the right half.
    expect(lit(7, 5), isTrue);
    expect(lit(7, -5), isFalse);
    final q = moonPhasePath(moonAge(7), r).getBounds();
    expect(q.left, closeTo(0, 1.5));
    expect(q.right, closeTo(r, 1e-6));
    // Day 14: full.
    expect(lit(14, -9), isTrue);
    expect(lit(14, 9), isTrue);
    // Day 22: waning, lit on the left.
    expect(lit(22, -6), isTrue);
    expect(lit(22, 6), isFalse);
    expect(moonPhasePath(moonAge(22), r).getBounds().left, closeTo(-r, 1e-6));
  });

  test('nothing is painted over the moon disc', () {
    final canvas = _RecordingCanvas();
    final lit = moonPhasePath(moonAge(7), 20);
    paintMoon(canvas, lit, Paint(), Paint(), 20);
    // The halo goes underneath, then the lit part, and nothing after it.
    expect(canvas.calls, ['drawCircle', 'drawPath']);
    expect(canvas.paths.single, same(lit));
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

class _RecordingCanvas implements Canvas {
  final calls = <String>[];
  final paths = <Path>[];

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      calls.add('drawCircle');

  @override
  void drawPath(Path path, Paint paint) {
    calls.add('drawPath');
    paths.add(path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      calls.add(invocation.memberName.toString());
}
