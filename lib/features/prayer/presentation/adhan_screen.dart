import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../data/adhan_catalog.dart';
import '../domain/prayer_calc.dart';
import '../domain/prayer_settings.dart';
import '../prayer_providers.dart';
import '../services/prayer_alarms.dart';
import '../services/prayer_runtime.dart';
import 'prayer_widgets.dart';

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
      sunX: 306,
      sunY: 330,
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

/// The vector scene (390 × 844 design units), scaled to cover.
class AdhanScenePainter extends CustomPainter {
  const AdhanScenePainter(this.scene);

  final AdhanScene scene;

  static const _w = 390.0;
  static const _h = 844.0;

  static const _stars = [
    (40.0, 70.0, 1.4),
    (96.0, 128.0, 1.0),
    (150.0, 54.0, 1.6),
    (222.0, 98.0, 1.0),
    (340.0, 60.0, 1.2),
    (362.0, 180.0, 1.0),
    (28.0, 210.0, 1.0),
    (118.0, 250.0, 1.3),
    (300.0, 240.0, 1.0),
    (64.0, 330.0, .9),
    (250.0, 300.0, 1.1),
    (352.0, 380.0, .9),
    (190.0, 180.0, .8),
    (18.0, 420.0, .8),
    (140.0, 380.0, .9),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = scene;
    final k = math.max(size.width / _w, size.height / _h);
    canvas.save();
    canvas.translate((size.width - _w * k) / 2, (size.height - _h * k) / 2);
    canvas.scale(k);
    const all = Rect.fromLTWH(0, 0, _w, _h);
    canvas.drawRect(
      all,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [s.sky1, s.sky2, s.sky3, s.sky3],
          stops: const [0, .55, .78, 1],
        ).createShader(all),
    );
    if (s.stars > 0) {
      final p = Paint()..color = Colors.white.withValues(alpha: s.stars);
      for (final (x, y, r) in _stars) {
        canvas.drawCircle(Offset(x, y), r, p);
      }
    }
    if (s.sun > 0) {
      final c = Offset(s.sunX, s.sunY);
      canvas.drawCircle(
        c,
        s.glowR,
        Paint()
          ..shader = RadialGradient(
            colors: [
              s.sunColor.withValues(alpha: .75),
              s.sunColor.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: s.glowR)),
      );
      canvas.drawCircle(c, s.sunR, Paint()..color = s.sunColor);
    }
    if (s.moon > 0) {
      final moon = Path.combine(
        PathOperation.difference,
        Path()..addOval(
          Rect.fromCircle(center: Offset(s.moonX, s.moonY), radius: s.moonR),
        ),
        Path()..addOval(
          Rect.fromCircle(
            center: Offset(s.moonCutX, s.moonCutY),
            radius: s.moonR,
          ),
        ),
      );
      canvas.drawPath(
        moon,
        Paint()..color = s.moonColor.withValues(alpha: s.moon),
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(0, 600)
        ..cubicTo(70, 560, 130, 590, 200, 575)
        ..cubicTo(270, 560, 320, 585, 390, 565)
        ..lineTo(390, 844)
        ..lineTo(0, 844)
        ..close(),
      Paint()..color = s.far,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, 655)
        ..cubicTo(90, 625, 150, 650, 220, 640)
        ..cubicTo(290, 630, 340, 650, 390, 635)
        ..lineTo(390, 844)
        ..lineTo(0, 844)
        ..close(),
      Paint()..color = s.hills,
    );
    final m = Paint()..color = s.mosque;
    canvas.drawRect(const Rect.fromLTWH(120, 640, 150, 70), m);
    canvas.drawPath(
      Path()
        ..moveTo(132, 642)
        ..cubicTo(132, 586, 160, 556, 195, 548)
        ..cubicTo(230, 556, 258, 586, 258, 642)
        ..close(),
      m,
    );
    canvas.drawRect(const Rect.fromLTWH(193.5, 518, 3, 32), m);
    for (final x in const [92.0, 256.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, 670)
          ..cubicTo(x, 644, x + 10, 630, x + 21, 626)
          ..cubicTo(x + 32, 630, x + 42, 644, x + 42, 670)
          ..close(),
        m,
      );
    }
    canvas.drawRect(const Rect.fromLTWH(90, 666, 210, 44), m);
    for (final x in const [58.0, 316.0]) {
      canvas.drawRect(Rect.fromLTWH(x, 566, 16, 144), m);
      canvas.drawPath(
        Path()
          ..moveTo(x - 3, 568)
          ..lineTo(x + 8, 528)
          ..lineTo(x + 19, 568)
          ..close(),
        m,
      );
      canvas.drawRect(Rect.fromLTWH(x - 5, 606, 26, 6), m);
    }
    canvas.drawCircle(
      const Offset(195, 512),
      5,
      Paint()
        ..color = s.mosque
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    if (s.litOn > 0) {
      final lit = Paint()..color = s.lit.withValues(alpha: s.litOn);
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
      canvas.drawPath(arch(195, 672, 710, 9), lit);
      canvas.drawPath(arch(156, 668, 690, 6), lit);
      canvas.drawPath(arch(234, 668, 690, 6), lit);
      for (final x in const [63.0, 321.0]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, 586, 6, 10),
            const Radius.circular(3),
          ),
          lit,
        );
      }
    }
    canvas.drawRect(
      const Rect.fromLTWH(0, 708, 390, 136),
      Paint()..color = s.ground,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(AdhanScenePainter old) => old.scene != scene;
}

/// The full-screen adhan: the prayer's scene, its name and time, the
/// muezzin, «إيقاف الأذان» and «فتح المواقيت». Opened from the alert (the
/// full adhan starts if its time was within the last minutes and nothing
/// plays yet) or by the app when it starts the adhan itself.
class AdhanScreen extends ConsumerStatefulWidget {
  const AdhanScreen({
    super.key,
    required this.prayer,
    this.at,
    this.test = false,
  });

  /// «جرّب الأذان»: the scene only, no claim of a prayer time.
  final bool test;

  final PrayerKind prayer;
  final DateTime? at;

  /// How late a tap on the alert still starts the full adhan.
  static const startWithin = Duration(minutes: 10);

  @override
  ConsumerState<AdhanScreen> createState() => _AdhanScreenState();
}

class _AdhanScreenState extends ConsumerState<AdhanScreen> {
  @override
  void initState() {
    super.initState();
    final at = widget.at;
    if (at != null) {
      final late = DateTime.now().difference(at);
      final native = ref.read(prayerNativeProvider);
      // Android's adhan service is already playing it.
      if (!Platform.isAndroid &&
          !late.isNegative &&
          late < AdhanScreen.startWithin &&
          !native.playing.value) {
        unawaited(PrayerRuntime.instance?.playAdhan(widget.prayer));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(prayerSettingsProvider);
    final native = ref.watch(prayerNativeProvider);
    final scene = AdhanScene.of(widget.prayer);
    final place = s.place;
    final at = widget.at;
    final arabic = l.localeName == 'ar';
    final ink = TextStyle(color: scene.ink);
    return Scaffold(
      backgroundColor: scene.sky3,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: CustomPaint(painter: AdhanScenePainter(scene)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.sizeOf(context).height -
                      MediaQuery.paddingOf(context).vertical -
                      64,
                ),
                child: Column(
                  children: [
                    if (place != null)
                      Text(
                        '${place.label(arabic)} · ${dateLine(l, placeToday(place, DateTime.now()), s.hijriOffset)}',
                        textAlign: TextAlign.center,
                        style: ink.copyWith(fontSize: 14),
                      ),
                    const SizedBox(height: 56),
                    if (!widget.test)
                      Text(l.adhanNowLabel, style: ink.copyWith(fontSize: 18)),
                    Semantics(
                      header: true,
                      child: Text(
                        widget.test
                            ? l.adhanTestBody
                            : l.adhanOf(prayerName(l, widget.prayer)),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scene.title,
                          fontSize: 54,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!widget.test && at != null && place != null)
                      Text(
                        formatPrayerTime(l, at, place),
                        style: ink.copyWith(
                          fontSize: 40,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    Text(
                      l.adhanByMuezzin(muezzinOf(s.muezzin).name(arabic)),
                      style: ink.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 240),
                    ValueListenableBuilder<bool>(
                      valueListenable: native.playing,
                      builder: (context, playing, _) => FilledButton(
                        key: const ValueKey('adhan-stop'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: scene.accent,
                          foregroundColor: const Color(0xFF17130C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        // Always enabled: over the lock screen the app may
                        // not know yet that the service plays.
                        onPressed: () async {
                          await native.stop();
                          await native.leaveLockScreen();
                          if (!context.mounted) return;
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/prayer');
                          }
                        },
                        child: Text(
                          l.adhanStop,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      key: const ValueKey('adhan-open-times'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: const Color(0xFFF6F1E8),
                        backgroundColor: Colors.black.withValues(alpha: .18),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: .4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: () async {
                        await native.leaveLockScreen(open: true);
                        if (context.mounted) context.go('/prayer');
                      },
                      child: Text(l.adhanOpenTimes),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
