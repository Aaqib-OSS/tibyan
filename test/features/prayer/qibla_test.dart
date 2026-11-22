import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/core/ui/look_kit.dart';
import 'package:tibyan/features/prayer/domain/magnetic_declination.dart';
import 'package:tibyan/features/prayer/domain/prayer_settings.dart';
import 'package:tibyan/features/prayer/domain/qibla.dart';
import 'package:tibyan/features/prayer/presentation/qibla_screen.dart';
import 'package:tibyan/features/prayer/prayer_providers.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../tasmee/tasmee_test_env.dart';
import 'prayer_calc_test.dart' show cairo;

void main() {
  group('bearing to the Kaaba (great circle, from true north)', () {
    // Checked by hand with θ = atan2(sin Δλ·cos φ₂,
    // cos φ₁·sin φ₂ − sin φ₁·cos φ₂·cos Δλ).
    test('Cairo', () {
      // 136.14° for central Cairo (30.0444, 31.2357); often quoted ≈135.6.
      expect(qiblaBearing(30.0444, 31.2357), closeTo(136.14, 0.05));
    });
    test('London', () {
      expect(qiblaBearing(51.5074, -0.1278), closeTo(118.99, 0.05));
    });
    test('Jakarta', () {
      expect(qiblaBearing(-6.2088, 106.8456), closeTo(295.15, 0.05));
    });
    test('New York', () {
      expect(qiblaBearing(40.7128, -74.0060), closeTo(58.48, 0.05));
    });
    test('at Makkah it is defined and in range', () {
      final b = qiblaBearing(21.4, 39.8);
      expect(b, inInclusiveRange(0, 360));
    });
  });

  test('distance to the Kaaba', () {
    expect(kaabaDistanceKm(30.0444, 31.2357), closeTo(1287, 2));
    expect(kaabaDistanceKm(51.5074, -0.1278), closeTo(4794, 3));
    expect(kaabaDistanceKm(40.7128, -74.0060), closeTo(10306, 5));
    expect(kaabaDistanceKm(kaabaLat, kaabaLon), closeTo(0, 1e-6));
  });

  test('turning and the ±3° window', () {
    expect(turnTo(350, 10), closeTo(20, 1e-9));
    expect(turnTo(10, 350), closeTo(-20, 1e-9));
    expect(facesQibla(133.5, 136), isTrue);
    expect(facesQibla(132.5, 136), isFalse);
    expect(facesQibla(359, 1.5), isTrue);
  });

  test('magnetic declination (WMM 2025) matches the NOAA model', () {
    final when = DateTime(2026, 11, 24);
    expect(magneticDeclination(30.0444, 31.2357, when), closeTo(4.77, .05));
    expect(magneticDeclination(51.5074, -0.1278, when), closeTo(1.23, .05));
    expect(magneticDeclination(40.7128, -74.006, when), closeTo(-12.46, .05));
    expect(magneticDeclination(-33.8688, 151.2093, when), closeTo(12.83, .05));
  });

  group('screen', () {
    late TasmeeTestData data;
    setUpAll(() {
      tzdata.initializeTimeZones();
      data = TasmeeTestData.open();
    });
    tearDownAll(() => data.close());

    Future<void> pump(
      WidgetTester tester, {
      Stream<CompassReading>? readings,
      double textScale = 1,
    }) async {
      tester.view
        ..physicalSize = const Size(390, 1400)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const s = PrayerSettings(enabled: true, place: cairo);
      final container = await tasmeeContainer(
        tester,
        data,
        prefs: {prayerSettingsKey: s.encode()},
      );
      await tester.pumpWidget(
        tasmeeApp(
          container,
          LookTheme(child: QiblaScreen(readings: readings, trueNorth: true)),
          theme: tasmeeTheme(container),
        ),
      );
      await tester.pump();
    }

    testWidgets('live: turn hints, then aligned with one haptic tick', (
      tester,
    ) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add('${call.arguments}');
          }
          return null;
        },
      );
      final c = StreamController<CompassReading>();
      addTearDown(c.close);
      await pump(tester, readings: c.stream);
      expect(find.byKey(const ValueKey('qibla-degrees')), findsOneWidget);
      final km = tester.widget<Text>(
        find.byKey(const ValueKey('qibla-distance')),
      );
      expect(km.data, contains('١٢٨٧'));
      c.add((heading: 90.0, accuracy: 10));
      await tester.pump();
      expect(find.textContaining('استدر يمينًا'), findsOneWidget);
      for (var i = 0; i < 30; i++) {
        c.add((heading: 136.0, accuracy: 10));
        await tester.pump();
      }
      expect(find.text('أنت متجه إلى القبلة'), findsWidgets);
      expect(haptics, hasLength(1));
      expect(find.byKey(const ValueKey('qibla-calibrate')), findsNothing);
    });

    testWidgets('low accuracy: the calibration and interference hint', (
      tester,
    ) async {
      final c = StreamController<CompassReading>();
      addTearDown(c.close);
      await pump(tester, readings: c.stream);
      c.add((heading: 10.0, accuracy: 45));
      await tester.pump();
      expect(find.byKey(const ValueKey('qibla-calibrate')), findsOneWidget);
    });

    testWidgets('no compass: the still diagram and instructions, 200% text', (
      tester,
    ) async {
      await pump(tester, readings: const Stream.empty(), textScale: 2);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('qibla-no-sensor')), findsOneWidget);
      expect(find.byKey(const ValueKey('qibla-turn')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
