import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Colors;

import '../../../core/theme/reveal.dart';
import '../domain/prayer_calc.dart';
import '../domain/prayer_settings.dart';

/// The colours of one prayer's scene: the sky, the sun or the moon, and
/// the windows' glow. The mosque is the same for all five.
@immutable
class AdhanScene {
  const AdhanScene({
    required this.sky1,
    required this.sky2,
    required this.sky3,
    required this.stars,
    this.sun = 0,
    this.sunX = 0,
    this.sunY = 0,
    this.sunR = 0,
    this.glowR = 0,
    this.sunColor = Colors.white,
    this.moon = 0,
    this.moonX = 0,
    this.moonY = 0,
    this.moonR = 1,
    this.moonCutX = 0,
    this.moonCutY = 0,
    this.moonColor = Colors.white,
    required this.far,
    required this.hills,
    required this.mosque,
    required this.ground,
    required this.lit,
    required this.litOn,
    required this.ink,
    required this.title,
    required this.accent,
    required this.track,
  });

  final Color sky1, sky2, sky3;
  final double stars;
  final double sun, sunX, sunY, sunR, glowR;
  final Color sunColor;
  final double moon, moonX, moonY, moonR, moonCutX, moonCutY;
  final Color moonColor;
  final Color far, hills, mosque, ground, lit;
  final double litOn;
  final Color ink, title, accent, track;

  /// The approved design's five scenes (FullScreen.dc.html).
  static AdhanScene of(PrayerKind p) => switch (p) {
    PrayerKind.fajr => const AdhanScene(
      sky1: Color(0xFF0D1435),
      sky2: Color(0xFF3A3A74),
      sky3: Color(0xFFE09A86),
      stars: .75,
      moon: 1,
      moonX: 92,
      moonY: 150,
      moonR: 20,
      moonCutX: 101,
      moonCutY: 144,
      moonColor: Color(0xFFF6E7C8),
      far: Color(0xFF4B4378),
      hills: Color(0xFF2B2A5A),
      mosque: Color(0xFF141535),
      ground: Color(0xFF0C0C26),
      lit: Color(0xFFFFD88A),
      litOn: .9,
      ink: Color(0xFFF6F1EA),
      title: Color(0xFFF6D3B0),
      accent: Color(0xFFF6D3B0),
      track: Color(0x38FFFFFF),
    ),
    PrayerKind.dhuhr ||
    PrayerKind.duha ||
    PrayerKind.shuruq => const AdhanScene(
      sky1: Color(0xFF2F7FC4),
      sky2: Color(0xFF79BCE8),
      sky3: Color(0xFFD4ECF6),
      stars: 0,
      sun: 1,
      sunX: 292,
      sunY: 128,
      sunR: 30,
      glowR: 110,
      sunColor: Color(0xFFFFF3C4),
      far: Color(0xFF9CCBC4),
      hills: Color(0xFF5F9F95),
      mosque: Color(0xFF1D5650),
      ground: Color(0xFF143F3A),
      lit: Color(0xFFFFFFFF),
      litOn: 0,
      ink: Color(0xFF0F2B33),
      title: Color(0xFF0D3F4A),
      accent: Color(0xFFF2D27A),
      track: Color(0x330D3F4A),
    ),
    PrayerKind.asr => const AdhanScene(
      sky1: Color(0xFF5B8FC0),
      sky2: Color(0xFFE7C486),
      sky3: Color(0xFFF4DCAE),
      stars: 0,
      sun: 1,
      sunX: 96,
      sunY: 380,
      sunR: 28,
      glowR: 120,
      sunColor: Color(0xFFFFF0C2),
      far: Color(0xFFD0A46A),
      hills: Color(0xFFA8733F),
      mosque: Color(0xFF5B371D),
      ground: Color(0xFF3D2412),
      lit: Color(0xFFFFFFFF),
      litOn: 0,
      ink: Color(0xFF2B1A0B),
      title: Color(0xFF6A3A12),
      accent: Color(0xFFF4D08A),
      track: Color(0x336A3A12),
    ),
    PrayerKind.maghrib => const AdhanScene(
      sky1: Color(0xFF2A1D4C),
      sky2: Color(0xFFB4456C),
      sky3: Color(0xFFF39A4C),
      stars: .25,
      sun: 1,
      sunX: 195,
      sunY: 598,
      sunR: 44,
      glowR: 160,
      sunColor: Color(0xFFFFCF70),
      far: Color(0xFF6B2D55),
      hills: Color(0xFF45203F),
      mosque: Color(0xFF22122A),
      ground: Color(0xFF150A1B),
      lit: Color(0xFFFFCF70),
      litOn: .85,
      ink: Color(0xFFFFF2E4),
      title: Color(0xFFFFD889),
      accent: Color(0xFFFFCF70),
      track: Color(0x38FFFFFF),
    ),
    PrayerKind.isha => const AdhanScene(
      sky1: Color(0xFF040918),
      sky2: Color(0xFF0C1736),
      sky3: Color(0xFF1B2B55),
      stars: 1,
      moon: 1,
      moonX: 292,
      moonY: 150,
      moonR: 30,
      moonCutX: 305,
      moonCutY: 141,
      moonColor: Color(0xFFF3E3B8),
      far: Color(0xFF18264A),
      hills: Color(0xFF0F1A36),
      mosque: Color(0xFF070C1E),
      ground: Color(0xFF04070F),
      lit: Color(0xFFFFD27A),
      litOn: .95,
      ink: Color(0xFFEEF0F7),
      title: Color(0xFFE7C983),
      accent: Color(0xFFE7C983),
      track: Color(0x2EFFFFFF),
    ),
  };
}

/// How far through the night [now] is at [place]: 0 at maghrib, 1 at
/// fajr. Places the moon on its arc.
double nightFraction(PrayerPlace place, DateTime now, PrayerSettings s) {
  final today = placeToday(place, now);
  final day = computeDay(place, today, s);
  final DateTime start, end;
  if (now.isBefore(day[PrayerKind.fajr])) {
    start = computeDay(
      place,
      today.subtract(const Duration(days: 1)),
      s,
    )[PrayerKind.maghrib];
    end = day[PrayerKind.fajr];
  } else {
    start = day[PrayerKind.maghrib];
    end = computeDay(
      place,
      today.add(const Duration(days: 1)),
      s,
    )[PrayerKind.fajr];
  }
  final span = end.difference(start).inSeconds;
  if (span <= 0) return .5;
  return (now.difference(start).inSeconds / span).clamp(0.0, 1.0);
}

/// The moon's age in days for the Hijri [day] (1…30): day 1 is the thin
/// first crescent, day 7 the first quarter, days 14 and 15 exactly full,
/// then it wanes to the end of the month.
double moonAge(int day) {
  const synodic = 29.53;
  final d = day.clamp(1, 30);
  final double f;
  if (d <= 14) {
    f = .5 * d / 14;
  } else if (d == 15) {
    f = .5;
  } else {
    f = .5 + .5 * (d - 15) / 15.5;
  }
  return f * synodic;
}

/// The lit part of a moon of radius [r] at [age] days, centred on zero, as
/// one path: an exact circular limb plus an elliptical terminator. Nothing
/// is ever painted over it, so the unlit side never shows as a disc.
/// Waxing is lit on the right; the full moon is a perfect circle.
Path moonPhasePath(double age, double r) {
  const synodic = 29.53;
  final a = (age % synodic) / synodic; // 0 new, .5 full
  final disc = Rect.fromCircle(center: Offset.zero, radius: r);
  if ((a - .5).abs() < 1e-6) return Path()..addOval(disc);
  final waxing = a < .5;
  final k = math.cos(2 * math.pi * a); // 1 new, 0 quarter, -1 full
  final side = waxing ? 1.0 : -1.0;
  final p = Path()
    ..moveTo(0, -r)
    // The limb: top to bottom round the lit side.
    ..arcTo(disc, -math.pi / 2, side * math.pi, false);
  if (k.abs() < 1e-6) {
    p.lineTo(0, -r);
  } else {
    // The terminator: half an ellipse from the bottom back to the top,
    // bulging toward the lit side for a crescent, away for a gibbous moon.
    final sweep = (k > 0 ? -1.0 : 1.0) * side * math.pi;
    p.arcTo(
      Rect.fromCenter(
        center: Offset.zero,
        width: 2 * k.abs() * r,
        height: 2 * r,
      ),
      math.pi / 2,
      sweep,
      false,
    );
  }
  return p..close();
}

/// Paints the moon at zero: its halo underneath, then the lit part on top.
/// Nothing else, and nothing over the disc.
void paintMoon(Canvas canvas, Path lit, Paint litPaint, Paint halo, double r) {
  canvas
    ..drawCircle(Offset.zero, r * 3, halo)
    ..drawPath(lit, litPaint);
}

/// Where the design (390 × 844 units, the mosque's base at y 708) lands on
/// a screen of any shape: the mosque keeps its proportions and stands near
/// the bottom; the sky, the hills and the ground stretch to every edge.
@immutable
class AdhanSceneGeometry {
  factory AdhanSceneGeometry(Size size) {
    final k = math.min(size.width / 390, size.height / 600);
    final baseY = size.height * .86;
    return AdhanSceneGeometry._(size, k, size.width / 2, baseY);
  }
  const AdhanSceneGeometry._(this.size, this.k, this.cx, this.baseY);

  final Size size;

  /// Design units to pixels.
  final double k;

  /// The mosque's centre line and base on screen.
  final double cx, baseY;

  /// The far hills' line, where the sky meets the land.
  double get horizon => baseY - 108 * k;

  /// The visible design-space edges.
  double get left => 195 - cx / k;
  double get right => 195 + (size.width - cx) / k;
  double get bottom => 708 + (size.height - baseY) / k;

  /// Moves the canvas into design space.
  void enter(Canvas canvas) {
    canvas.translate(cx - 195 * k, baseY - 708 * k);
    canvas.scale(k);
  }

  /// A sun or moon of the design at ([x], [y]) placed in the sky.
  Offset sky(double x, double y) => Offset(
    (cx + (x - 195) * k).clamp(size.width * .08, size.width * .92),
    y / 600 * horizon,
  );
}

/// The scene behind the full-screen adhan, still or gently moving.
///
/// One [Ticker] drives it, at most 30 frames a second (15 once the
/// three-minute change is over): stars twinkle and, rarely, one shoots;
/// the moon of the Hijri day glows; light rises at fajr, the sun sinks at
/// maghrib, soft rays breathe and clouds and birds drift by day; lanterns swing at night; the windows glow, fajr's mist
/// drifts. It stops when the screen is hidden ([TickerMode]) and stays a
/// still frame when less motion is asked for ([reduceMotion], which the
/// app's own «تقليل الحركة» sets too).
class AdhanBackdrop extends StatefulWidget {
  const AdhanBackdrop({
    super.key,
    required this.prayer,
    this.hijriDay = 15,
    this.night = .5,
  });

  final PrayerKind prayer;

  /// The Hijri day of the month (the reader's ±days included).
  final int hijriDay;

  /// How far through the night (0 maghrib … 1 fajr).
  final double night;

  /// The length of the slow change (about one adhan).
  static const span = 180.0;

  @override
  State<AdhanBackdrop> createState() => _AdhanBackdropState();
}

class _AdhanBackdropState extends State<AdhanBackdrop>
    with SingleTickerProviderStateMixin {
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(_tick);
  double _shown = 0;

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final step = t < AdhanBackdrop.span ? 1 / 30 : 1 / 15;
    if (t - _shown < step) return;
    _shown = t;
    _time.value = t;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = reduceMotion(context);
    if (still && _ticker.isActive) {
      _ticker.stop();
      _shown = 0;
      _time.value = 0;
    } else if (!still && !_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = AdhanScene.of(widget.prayer);
    return LayoutBuilder(
      builder: (context, c) {
        final size = c.biggest;
        final art = _SceneArt.of(
          size,
          scene,
          widget.prayer,
          widget.hijriDay,
          widget.night,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(painter: _SkyPainter(art, _time)),
            ),
            RepaintBoundary(child: CustomPaint(painter: _LandPainter(art))),
            RepaintBoundary(
              child: CustomPaint(painter: _FrontPainter(art, _time)),
            ),
          ],
        );
      },
    );
  }
}

/// Opacity steps, so a frame makes no new colours.
List<Color> _levels(Color c) => [
  for (var i = 0; i <= 32; i++) c.withValues(alpha: c.a * i / 32),
];

Color _at(List<Color> levels, double a) =>
    levels[(a.clamp(0.0, 1.0) * 32).round()];

double _ease(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Everything a frame draws that does not move by itself: paths, shaders
/// and colours for one size, built once.
class _SceneArt {
  _SceneArt._(this.geo, this.scene, this.prayer, this.hijriDay, this.night) {
    _build();
  }

  static _SceneArt? _last;

  static _SceneArt of(
    Size size,
    AdhanScene scene,
    PrayerKind prayer,
    int hijriDay,
    double night,
  ) {
    final l = _last;
    if (l != null &&
        l.geo.size == size &&
        l.scene == scene &&
        l.prayer == prayer &&
        l.hijriDay == hijriDay &&
        l.night == night) {
      return l;
    }
    return _last = _SceneArt._(
      AdhanSceneGeometry(size),
      scene,
      prayer,
      hijriDay,
      night,
    );
  }

  final AdhanSceneGeometry geo;
  final AdhanScene scene;
  final PrayerKind prayer;
  final int hijriDay;
  final double night;

  bool get night0 => scene.stars > 0;
  bool get hasMoon => prayer == PrayerKind.fajr || prayer == PrayerKind.isha;
  bool get rays => scene.sun > 0 && prayer != PrayerKind.maghrib;
  bool get daytime => scene.sun > 0 && prayer != PrayerKind.maghrib;

  /// Two hanging lanterns at night only: maghrib, isha and fajr.
  bool get lanterns =>
      prayer == PrayerKind.maghrib ||
      prayer == PrayerKind.isha ||
      prayer == PrayerKind.fajr;

  late final Paint sky, overlay, star, trail, halo, moonLit;
  late final Paint glow, rayPaint, sunDisc, lit, mist, dawn, cloud, bird;
  late final Paint cord, lanternMetal, lanternGlass, lanternGlow;
  late final List<Color> white, overlayLv, haloLv, glowLv, rayLv, litLv;
  late final List<Color> mistLv, dayLitLv, lanternGlowLv;
  late final List<(double, double, double, double, double)> stars;
  late final List<double> shots;
  late final Offset moonAt, sunAt;
  late final double moonR, sunR, glowR, mistY;
  late final Path moonPath, rayPath, cloudPath, lanternCap, lanternBody;
  late final Path lanternTip;
  late final Path far, hills, ground, ridge;
  late final Paint groundPaint;

  void _build() {
    final s = scene;
    final size = geo.size;
    final k = geo.k;
    final skyRect = Rect.fromLTRB(0, 0, size.width, geo.horizon * 1.15);
    sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [s.sky1, s.sky2, s.sky3],
        stops: const [0, .62, 1],
      ).createShader(skyRect);
    // Maghrib: the sky turns from orange to violet; fajr: light rises.
    overlay = Paint()
      ..shader = prayer == PrayerKind.maghrib
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF140C30), Color(0xFF3A2462), Color(0xFF8A3E78)],
              stops: [0, .6, 1],
            ).createShader(skyRect)
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                s.sky3.withValues(alpha: 0),
                s.sky3.withValues(alpha: 0),
                Color.lerp(s.sky3, const Color(0xFFFFFFFF), .25)!,
              ],
              stops: const [0, .45, 1],
            ).createShader(skyRect);
    overlayLv = _levels(const Color(0xFFFFFFFF));
    white = _levels(const Color(0xFFFFFFFF));
    star = Paint();
    trail = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    // The star field: denser on bigger skies, never on the land.
    final rnd = math.Random(7);
    final count = (size.width * geo.horizon / 7000).clamp(18, 90).round();
    stars = [
      for (var i = 0; i < count; i++)
        (
          rnd.nextDouble() * size.width,
          rnd.nextDouble() * geo.horizon * .8,
          .7 + rnd.nextDouble() * .9,
          rnd.nextDouble() * math.pi * 2,
          2 * math.pi / (2 + rnd.nextDouble() * 4),
        ),
    ];
    // Shooting stars: every ~6 s at isha, now and then on other nights.
    shots = [];
    if (prayer == PrayerKind.isha) {
      for (var at = 3.0; at < 3600; at += 6) {
        shots.add(at);
      }
    } else {
      var at = 6 + rnd.nextDouble() * 10;
      while (at < 3600) {
        shots.add(at);
        at += 20 + rnd.nextDouble() * 20;
      }
    }

    // The moon of the Hijri day, along the night's arc.
    final f = night.clamp(0.0, 1.0);
    moonR = (prayer == PrayerKind.isha ? 26 : 20) * k;
    moonAt = geo.sky(
      300 - 210 * f,
      150 + 90 * (1 - math.sin(math.pi * (.1 + .8 * f))),
    );
    moonPath = moonPhasePath(moonAge(hijriDay), moonR);
    moonLit = Paint()..color = s.moonColor;
    halo = Paint()
      ..shader = RadialGradient(
        colors: [
          s.moonColor.withValues(alpha: .45),
          s.moonColor.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: moonR * 3));
    haloLv = _levels(const Color(0xFFFFFFFF));

    // The sun and its glow, drawn around zero.
    sunR = s.sunR * k;
    glowR = s.glowR * k;
    sunAt = geo.sky(s.sunX, s.sunY);
    glow = Paint()
      ..shader = RadialGradient(
        colors: [
          s.sunColor.withValues(alpha: .75),
          s.sunColor.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: glowR));
    glowLv = _levels(const Color(0xFFFFFFFF));
    sunDisc = Paint()..color = s.sunColor;
    // Eight soft, wide rays: they breathe and sway, never spin.
    final rayLen = geo.horizon * .55;
    rayPath = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      Offset at(double x, double y) => Offset(
        x * math.cos(a) - y * math.sin(a),
        x * math.sin(a) + y * math.cos(a),
      );
      final p0 = at(-26 * k, 0), p1 = at(-8 * k, -rayLen);
      final p2 = at(8 * k, -rayLen), p3 = at(26 * k, 0);
      rayPath
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..close();
    }
    rayPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFF7D7).withValues(alpha: .12),
          const Color(0xFFFFF7D7).withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: rayLen));
    rayLv = _levels(const Color(0xFFFFFFFF));

    // Fajr's thread of light, in a unit square stretched each frame.
    dawn = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00FFBE8C), Color(0xFFFFC896)],
      ).createShader(const Rect.fromLTWH(0, 0, 1, 1));

    // A cloud, centred on zero; golden at asr.
    cloudPath = Path();
    for (final (dx, dy, r) in const [
      (-23.0, 0.0, 22.0),
      (-1.0, -8.0, 26.0),
      (23.0, 0.0, 20.0),
      (1.0, 6.0, 22.0),
    ]) {
      cloudPath.addOval(
        Rect.fromCircle(center: Offset(dx * k, dy * k), radius: r * k),
      );
    }
    cloud = Paint()
      ..color = prayer == PrayerKind.asr
          ? const Color(0xBFFFE6BE)
          : const Color(0xCCFFFFFF);
    bird = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * k
      ..strokeCap = StrokeCap.round
      ..color = prayer == PrayerKind.fajr
          ? const Color(0xCCFFFFFF)
          : const Color(0xB3142832);

    // The lanterns, in screen units around their hook.
    cord = Paint()
      ..color = const Color(0xCCE6C88C)
      ..strokeWidth = 1;
    lanternMetal = Paint()..color = const Color(0xFFC9A24A);
    lanternGlass = Paint();
    lanternCap = Path()
      ..moveTo(-6 * k, 0)
      ..lineTo(6 * k, 0)
      ..lineTo(10 * k, 8 * k)
      ..lineTo(-10 * k, 8 * k)
      ..close();
    lanternBody = Path()
      ..moveTo(-10 * k, 8 * k)
      ..lineTo(10 * k, 8 * k)
      ..lineTo(7 * k, 26 * k)
      ..lineTo(-7 * k, 26 * k)
      ..close();
    lanternTip = Path()
      ..moveTo(-7 * k, 26 * k)
      ..lineTo(7 * k, 26 * k)
      ..lineTo(0, 34 * k)
      ..close();
    lanternGlow = Paint()
      ..shader =
          const RadialGradient(colors: [Color(0x8CFFC864), Color(0x00FFC864)])
              .createShader(
                Rect.fromCircle(center: Offset(0, 14 * k), radius: 40 * k),
              );
    lanternGlowLv = _levels(const Color(0xFFFFFFFF));

    // The land, in design units, out to every edge.
    final l = geo.left - 2, r = geo.right + 2, b = geo.bottom + 2;
    far = _ridge(l, r, b, 600, 565, 10, (p) {
      p
        ..cubicTo(70, 560, 130, 590, 200, 575)
        ..cubicTo(270, 560, 320, 585, 390, 565);
    });
    hills = _ridge(l, r, b, 655, 635, 7, (p) {
      p
        ..cubicTo(90, 625, 150, 650, 220, 640)
        ..cubicTo(290, 630, 340, 650, 390, 635);
    });
    ground = _ridge(l, r, b, 704, 704, 5, (p) {
      p
        ..cubicTo(20, 704, 40, 708, 60, 708)
        ..lineTo(330, 708)
        ..cubicTo(350, 708, 370, 704, 390, 704);
    });
    final mid = 708 + (b - 708) * .45;
    ridge = _ridge(l, r, b, mid, mid, 6, (p) {
      p
        ..cubicTo(100, mid - 8, 200, mid + 6, 290, mid - 4)
        ..cubicTo(330, mid - 8, 360, mid, 390, mid);
    });
    groundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.lerp(s.hills, s.ground, .55)!, s.ground],
      ).createShader(Rect.fromLTRB(l, 704, r, b));

    lit = Paint();
    litLv = _levels(s.lit);
    dayLitLv = _levels(const Color(0xFFFFC86E));
    mistY = 690;
    mist = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(
            s.sky3,
            const Color(0xFFE6DCFF),
            .6,
          )!.withValues(alpha: .7),
          const Color(0x00FFFFFF),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1));
    mistLv = _levels(const Color(0xFFFFFFFF));
  }

  /// A band of land: gentle waves from [l] to the design's 0, its curve
  /// [mid] across 0…390, waves on to [r], then down to [b].
  static Path _ridge(
    double l,
    double r,
    double b,
    double y0,
    double y1,
    double amp,
    void Function(Path) mid,
  ) {
    const len = 130.0;
    final p = Path();
    final n = math.max(0, (-l / len).ceil());
    var x = -n * len;
    p.moveTo(math.min(x, l), y0);
    var up = true;
    while (x < 0) {
      final d = up ? -amp : amp;
      p.cubicTo(x + len * .33, y0 + d, x + len * .66, y0 + d, x + len, y0);
      x += len;
      up = !up;
    }
    p.lineTo(0, y0);
    mid(p);
    x = 390;
    up = true;
    while (x < r) {
      final d = up ? -amp : amp;
      p.cubicTo(x + len * .33, y1 + d, x + len * .66, y1 + d, x + len, y1);
      x += len;
      up = !up;
    }
    return p
      ..lineTo(math.max(x, r), b)
      ..lineTo(math.min(-n * len, l), b)
      ..close();
  }
}

/// The sky: its colours, stars, the moon, the sun, clouds and birds
/// (behind the land).
class _SkyPainter extends CustomPainter {
  _SkyPainter(this.art, this.time) : super(repaint: time);

  final _SceneArt art;
  final ValueListenable<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final a = art;
    final s = a.scene;
    final t = time.value;
    final still = t == 0;
    final p = _ease(t / AdhanBackdrop.span);
    // Maghrib's change runs over about 40 s.
    final p40 = _ease(t / 40);
    canvas.drawRect(Offset.zero & size, a.sky);
    if (a.prayer == PrayerKind.maghrib) {
      if (p40 > 0) {
        a.overlay.color = _at(a.overlayLv, p40 * .7);
        canvas.drawRect(Offset.zero & size, a.overlay);
      }
    } else if (a.prayer == PrayerKind.fajr && p > 0) {
      a.overlay.color = _at(a.overlayLv, p * .7);
      canvas.drawRect(Offset.zero & size, a.overlay);
    }
    if (a.prayer == PrayerKind.fajr) {
      // A thread of light rising behind the hills over about 25 s.
      final k = still ? .3 : math.min(1.0, t / 25);
      final h = a.geo.horizon;
      final top = h - h * (.06 + .3 * k);
      canvas.save();
      canvas.translate(0, top);
      canvas.scale(size.width, h + 30 * a.geo.k - top);
      a.dawn.color = _at(a.white, .25 + .6 * k);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), a.dawn);
      canvas.restore();
    }
    if (a.night0) _stars(canvas, size, t, p40);
    if (a.hasMoon) {
      final pulse = a.prayer == PrayerKind.isha
          ? .55 + .45 * math.sin(t * 1.4)
          : .8 + .2 * math.sin(t * 2 * math.pi / 8);
      canvas.save();
      canvas.translate(a.moonAt.dx, a.moonAt.dy);
      a.halo.color = _at(a.haloLv, still ? .9 : pulse);
      paintMoon(canvas, a.moonPath, a.moonLit, a.halo, a.moonR);
      canvas.restore();
    }
    if (s.sun > 0) {
      var y = a.sunAt.dy;
      var g = 1.0;
      if (a.prayer == PrayerKind.maghrib) {
        // It sinks fully behind the hills during the adhan.
        y += (a.sunR + 110 * a.geo.k) * p40;
        g = 1 - .6 * p40;
      } else if (!still) {
        g = .9 + .1 * math.sin(t * 2 * math.pi / 9);
      }
      canvas.save();
      canvas.translate(a.sunAt.dx, y);
      if (a.rays) {
        canvas.save();
        canvas.rotate(still ? 0 : math.sin(t * .25) * .05);
        a.rayPaint.color = _at(
          a.rayLv,
          still ? .75 : .6 + .3 * math.sin(t * .8),
        );
        canvas.drawPath(a.rayPath, a.rayPaint);
        canvas.restore();
      }
      a.glow.color = _at(a.glowLv, g);
      canvas.drawCircle(Offset.zero, a.glowR, a.glow);
      canvas.drawCircle(Offset.zero, a.sunR, a.sunDisc);
      canvas.restore();
    }
    if (a.daytime) _clouds(canvas, size, t);
    if (a.daytime) {
      _birds(canvas, size, t, t % 14 / 14);
    } else if (a.prayer == PrayerKind.fajr && t > 8 && t < 26) {
      // One flock crossing the dawn.
      _birds(canvas, size, t, (t - 8) / 18);
    }
  }

  void _stars(Canvas canvas, Size size, double t, double p40) {
    final a = art;
    final still = t == 0;
    final isha = a.prayer == PrayerKind.isha;
    final maghrib = a.prayer == PrayerKind.maghrib;
    final base = maghrib ? a.scene.stars + .5 * p40 : a.scene.stars;
    for (final (x, y, r, ph, w) in a.stars) {
      final tw = still ? .75 : .5 + .5 * math.sin(ph + w * t);
      var o = base * (isha ? .2 + .8 * tw : .35 + .65 * tw);
      final order = ph / (2 * math.pi); // 0…1, each star its own turn
      if (!still && a.prayer == PrayerKind.fajr) {
        // They go out one by one.
        o *= ((8 + order * 40 - t) / 2).clamp(0.0, 1.0);
      } else if (!still && maghrib) {
        // The first ones come out one by one.
        o *= ((t - 6 - order * 30) / 2).clamp(0.0, 1.0);
      }
      if (o <= 0) continue;
      a.star.color = _at(a.white, o);
      canvas.drawCircle(Offset(x, y), isha ? r * 1.25 : r, a.star);
    }
    _shootingStar(canvas, size, t);
  }

  void _clouds(Canvas canvas, Size size, double t) {
    final k = art.geo.k;
    final span = size.width + 160 * k;
    for (final (y, speed, o) in const [
      (.22, 14.0, 0.0),
      (.36, 9.0, .5),
      (.12, 6.0, .25),
    ]) {
      final x = size.width + 80 * k - ((o * span + t * speed * k) % span);
      canvas.save();
      canvas.translate(x, art.geo.horizon * y);
      canvas.drawPath(art.cloudPath, art.cloud);
      canvas.restore();
    }
  }

  /// A flock of seven, [u] 0…1 across the sky from right to left.
  void _birds(Canvas canvas, Size size, double t, double u) {
    final k = art.geo.k;
    final w = size.width;
    final h = art.geo.horizon;
    for (var i = 0; i < 7; i++) {
      final o = i * .07;
      final x = w * (1.1 - (u + o) * 1.3);
      if (x < -20 * k || x > w + 20 * k) continue;
      final y = h * (.38 + (i % 3) * .015 + .03 * math.sin((u + o) * 12));
      final f = math.sin(t * 9 + o * 20) * 5 * k;
      canvas.drawPath(
        Path()
          ..moveTo(x - 8 * k, y - f)
          ..quadraticBezierTo(x - 3 * k, y - 2 * k, x, y)
          ..quadraticBezierTo(x + 3 * k, y - 2 * k, x + 8 * k, y - f),
        art.bird,
      );
    }
  }

  void _shootingStar(Canvas canvas, Size size, double t) {
    const dur = 1.1;
    double? start;
    for (final s in art.shots) {
      if (s > t) break;
      if (t - s < dur) start = s;
    }
    if (start == null) return;
    final u = (t - start) / dur;
    final i = art.shots.indexOf(start);
    final x0 = size.width * (.2 + .6 * ((i * 37) % 10) / 10);
    final y0 = art.geo.horizon * (.08 + .2 * ((i * 53) % 10) / 10);
    final len = art.geo.k * 90;
    final hx = x0 + len * 1.6 * u, hy = y0 + len * .55 * u;
    final fade = math.sin(math.pi * u);
    for (var j = 0; j < 4; j++) {
      final a = (j * .18);
      final b = ((j + 1) * .18);
      art.trail.color = _at(art.white, fade * (1 - j / 4) * .95);
      canvas.drawLine(
        Offset(hx - len * a, hy - len * a * .34),
        Offset(hx - len * b, hy - len * b * .34),
        art.trail,
      );
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.art != art || old.time != time;
}

final Path _mosque = () {
  final p = Path()
    ..addRect(const Rect.fromLTWH(120, 640, 150, 70))
    ..moveTo(132, 642)
    ..cubicTo(132, 586, 160, 556, 195, 548)
    ..cubicTo(230, 556, 258, 586, 258, 642)
    ..close()
    ..addRect(const Rect.fromLTWH(193.5, 518, 3, 32));
  for (final x in const [92.0, 256.0]) {
    p
      ..moveTo(x, 670)
      ..cubicTo(x, 644, x + 10, 630, x + 21, 626)
      ..cubicTo(x + 32, 630, x + 42, 644, x + 42, 670)
      ..close();
  }
  p.addRect(const Rect.fromLTWH(90, 666, 210, 44));
  for (final x in const [58.0, 316.0]) {
    p
      ..addRect(Rect.fromLTWH(x, 566, 16, 144))
      ..moveTo(x - 3, 568)
      ..lineTo(x + 8, 528)
      ..lineTo(x + 19, 568)
      ..close()
      ..addRect(Rect.fromLTWH(x - 5, 606, 26, 6));
  }
  return p;
}();

final Path _windows = () {
  Path arch(double x, double top, double bottom, double half) => Path()
    ..moveTo(x - half, bottom)
    ..lineTo(x - half, top + half * 1.4)
    ..cubicTo(x - half, top + half * .4, x - half * .5, top, x, top - 1)
    ..cubicTo(
      x + half * .5,
      top,
      x + half,
      top + half * .4,
      x + half,
      top + half * 1.4,
    )
    ..lineTo(x + half, bottom)
    ..close();
  final p = Path()
    ..addPath(arch(195, 672, 710, 9), Offset.zero)
    ..addPath(arch(156, 668, 690, 6), Offset.zero)
    ..addPath(arch(234, 668, 690, 6), Offset.zero);
  for (final x in const [63.0, 321.0]) {
    p.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 586, 6, 10),
        const Radius.circular(3),
      ),
    );
  }
  return p;
}();

/// The hills, the mosque and the ground: still, painted once per size.
class _LandPainter extends CustomPainter {
  const _LandPainter(this.art);

  final _SceneArt art;

  @override
  void paint(Canvas canvas, Size size) {
    final s = art.scene;
    canvas.save();
    art.geo.enter(canvas);
    canvas.drawPath(art.far, Paint()..color = s.far);
    canvas.drawPath(art.hills, Paint()..color = s.hills);
    final m = Paint()..color = s.mosque;
    canvas.drawPath(_mosque, m);
    canvas.drawCircle(
      const Offset(195, 512),
      5,
      Paint()
        ..color = s.mosque
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    canvas.drawPath(art.ground, art.groundPaint);
    canvas.drawPath(
      art.ridge,
      Paint()..color = Color.lerp(s.ground, const Color(0xFF000000), .2)!,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LandPainter old) => old.art != art;
}

/// The windows' glow, fajr's mist and the night's lanterns, over the
/// mosque.
class _FrontPainter extends CustomPainter {
  _FrontPainter(this.art, this.time) : super(repaint: time);

  final _SceneArt art;
  final ValueListenable<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final s = art.scene;
    final t = time.value;
    final still = t == 0;
    canvas.save();
    art.geo.enter(canvas);
    // The windows' glow pulses in every prayer.
    if (s.litOn > 0) {
      final pulse = still ? 1.0 : .65 + .35 * math.sin(t * 2.2);
      art.lit.color = _at(art.litLv, s.litOn * pulse);
    } else {
      art.lit.color = _at(
        art.dayLitLv,
        still ? .2 : .18 + .1 * math.sin(t * 2),
      );
    }
    canvas.drawPath(_windows, art.lit);
    if (art.prayer == PrayerKind.fajr) {
      // Three banks of mist, drifting across.
      final span = art.geo.right - art.geo.left + 400;
      for (var i = 0; i < 3; i++) {
        final x =
            art.geo.left - 200 + ((t * (12 + 4 * i) + i * span / 3) % span);
        canvas.save();
        canvas.translate(x, art.mistY + (i - 1) * 16);
        canvas.scale(190, 28);
        art.mist.color = _at(art.mistLv, .8 + .1 * (i % 2));
        canvas.drawCircle(Offset.zero, 1, art.mist);
        canvas.restore();
      }
    }
    canvas.restore();
    if (art.lanterns) {
      // At maghrib they light as the adhan begins.
      final on = art.prayer == PrayerKind.maghrib && !still
          ? (t / 8).clamp(0.0, 1.0)
          : 1.0;
      final k = art.geo.k;
      _lantern(canvas, size.width * .14, 60 * k, math.sin(t * 1.3) * .12, on);
      _lantern(
        canvas,
        size.width * .86,
        90 * k,
        still ? 0 : math.sin(t * 1.3 + 1.7) * .1,
        on,
      );
    }
  }

  void _lantern(Canvas canvas, double x, double len, double angle, double on) {
    final a = art;
    canvas.save();
    canvas.translate(x, 0);
    canvas.rotate(angle);
    canvas.drawLine(Offset.zero, Offset(0, len), a.cord);
    canvas.translate(0, len);
    if (on > 0) {
      a.lanternGlow.color = _at(a.lanternGlowLv, on);
      canvas.drawCircle(Offset(0, 14 * a.geo.k), 40 * a.geo.k, a.lanternGlow);
    }
    canvas.drawPath(a.lanternCap, a.lanternMetal);
    a.lanternGlass.color = Color.lerp(
      const Color(0xFF7A6A40),
      const Color(0xFFFFD27A),
      on,
    )!;
    canvas.drawPath(a.lanternBody, a.lanternGlass);
    canvas.drawPath(a.lanternTip, a.lanternMetal);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FrontPainter old) => old.art != art || old.time != time;
}
