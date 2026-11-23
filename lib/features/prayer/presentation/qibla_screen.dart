import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/interface_style.dart';
import '../../../core/theme/reveal.dart' show reduceMotion;
import '../../../core/ui/look_kit.dart';
import '../../../core/ui/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../domain/magnetic_declination.dart';
import '../domain/qibla.dart';
import '../prayer_providers.dart';
import 'prayer_enable.dart' show choosePlace;
import 'prayer_times_screen.dart' show prayerTimesLocation;
import 'qibla_camera.dart';
import 'qibla_map.dart';

const qiblaLocation = '$prayerTimesLocation/qibla';

/// One compass reading: the heading (degrees from north) and its
/// accuracy (± degrees; null when the sensor does not say).
typedef CompassReading = ({double heading, double? accuracy});

/// Readings at or above this many degrees of error ask for calibration.
const _poorAccuracy = 30.0;

/// No reading within this long: no compass on this device.
const _sensorTimeout = Duration(seconds: 3);

/// «القبلة». On a phone: a large compass with the Kaaba on its ring at the
/// Qibla bearing and a big arrow to turn by, strong feedback when facing
/// it, and an optional camera view. On a computer (no compass): a map with
/// the great-circle line from the saved prayer place to the Kaaba.
class QiblaScreen extends ConsumerStatefulWidget {
  const QiblaScreen({
    super.key,
    this.readings,
    this.trueNorth,
    this.desktop,
    this.mapTiles = true,
  });

  /// The compass (tests); the device's by default.
  final Stream<CompassReading>? readings;

  /// Whether [readings] are from true north (iOS's heading is); Android's
  /// are magnetic, corrected by the local declination.
  final bool? trueNorth;

  /// The map layout (no compass); by default on macOS, Windows and Linux.
  final bool? desktop;

  /// Whether the map loads OpenStreetMap tiles (off in tests: offline).
  final bool mapTiles;

  @override
  ConsumerState<QiblaScreen> createState() => _QiblaScreenState();
}

enum _Sensor { waiting, live, none }

class _QiblaScreenState extends ConsumerState<QiblaScreen> {
  StreamSubscription<CompassReading>? _sub;
  Timer? _timeout;
  _Sensor _sensor = _Sensor.waiting;
  double? _heading;
  double? _accuracy;
  bool _aligned = false;
  bool _camera = false;
  Timer? _toastTimer;
  int _toast = 0;
  bool _toastOn = false;

  static bool get _mobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _desktop => widget.desktop ?? !_mobile;

  bool get _trueNorth => widget.trueNorth ?? (!kIsWeb && Platform.isIOS);

  @override
  void initState() {
    super.initState();
    if (_desktop) return;
    final source = widget.readings ?? (_mobile ? _device() : null);
    if (source == null) {
      _sensor = _Sensor.none;
      return;
    }
    _timeout = Timer(_sensorTimeout, () {
      if (mounted && _sensor == _Sensor.waiting) {
        setState(() => _sensor = _Sensor.none);
      }
    });
    _sub = source.listen(
      _onReading,
      onError: (_) {
        if (mounted && _heading == null) setState(() => _sensor = _Sensor.none);
      },
    );
  }

  static Stream<CompassReading>? _device() {
    final events = FlutterCompass.events;
    if (events == null) return null;
    return events
        .where(
          // iOS sends −1 when the true heading is unknown (location off).
          (e) => e.heading != null && (!Platform.isIOS || e.heading! >= 0),
        )
        .map((e) => (heading: e.heading!, accuracy: e.accuracy));
  }

  void _onReading(CompassReading r) {
    if (!mounted) return;
    final place = ref.read(prayerSettingsProvider).place;
    var heading = r.heading;
    if (!_trueNorth && place != null) {
      heading += magneticDeclination(place.lat, place.lon, DateTime.now());
    }
    heading = normalizeDegrees(heading);
    final prev = _heading;
    // A little smoothing keeps the needle steady.
    final smooth = prev == null
        ? heading
        : normalizeDegrees(prev + turnTo(prev, heading) * .35);
    final aligned =
        place != null && facesQibla(smooth, qiblaBearing(place.lat, place.lon));
    if (aligned && !_aligned) _celebrate();
    setState(() {
      _sensor = _Sensor.live;
      _heading = smooth;
      _accuracy = r.accuracy;
      _aligned = aligned;
    });
  }

  /// Entering the Qibla (once per entry): the toast, the star and one
  /// light haptic.
  void _celebrate() {
    unawaited(HapticFeedback.lightImpact());
    _toastTimer?.cancel();
    _toast++;
    _toastOn = true;
    _toastTimer = Timer(qiblaToastDuration, () {
      if (mounted) setState(() => _toastOn = false);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _timeout?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _choosePlace() async {
    final place = await choosePlace(context, ref);
    if (place == null) return;
    await ref
        .read(prayerSettingsProvider.notifier)
        .update((s) => s.copyWith(place: place));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final place = ref.watch(prayerSettingsProvider.select((s) => s.place));
    final digits = NumberFormatter(Locale(l.localeName));
    final arabic = l.localeName == 'ar';
    final children = <Widget>[];
    if (place == null) {
      children.addAll([
        const SizedBox(height: 24),
        Text(l.qiblaNoPlace, style: const TextStyle(fontSize: 16, height: 1.6)),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('qibla-choose-city'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _choosePlace,
          child: Text(l.prayerChooseCity),
        ),
      ]);
    } else {
      final bearing = qiblaBearing(place.lat, place.lon);
      final km = kaabaDistanceKm(place.lat, place.lon).round();
      final deg = digits(bearing.round());
      final from = Text(
        l.qiblaFrom(place.label(arabic)),
        style: TextStyle(color: t.muted, fontSize: 13),
      );
      final figures = _Figures(
        degrees: l.qiblaDegrees(deg),
        distance: l.qiblaDistance(digits(km)),
      );
      final row = Wrap(
        key: const ValueKey('qibla-map-row'),
        alignment: WrapAlignment.center,
        spacing: 20,
        runSpacing: 4,
        children: [
          Text(
            l.qiblaBearingRow(deg),
            key: const ValueKey('qibla-degrees'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Text(
            l.qiblaDistanceRow(digits(km)),
            key: const ValueKey('qibla-distance'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      );
      if (_desktop) {
        children.addAll([
          from,
          const SizedBox(height: 12),
          QiblaMap(
            lat: place.lat,
            lon: place.lon,
            placeLabel: place.label(arabic),
            tiles: widget.mapTiles,
          ),
          const SizedBox(height: 12),
          row,
          const SizedBox(height: 12),
          _Hint(
            key: const ValueKey('qibla-desktop-note'),
            icon: Icons.map_outlined,
            text: l.qiblaDesktopNote,
          ),
        ]);
      } else {
        final live = _sensor == _Sensor.live && _heading != null;
        final heading = live ? _heading! : 0.0;
        final turn = turnTo(heading, bearing);
        final aligned = live && _aligned;
        final poor = live && (_accuracy == null || _accuracy! >= _poorAccuracy);
        children.addAll([
          from,
          const SizedBox(height: 8),
          if (live) ...[
            QiblaGuideBanner(turn: turn, aligned: aligned),
            const SizedBox(height: 12),
          ],
          if (_camera && live)
            QiblaCameraView(
              turn: turn,
              aligned: aligned,
              onClose: () => setState(() => _camera = false),
            )
          else
            Center(
              child: Semantics(
                key: const ValueKey('qibla-dial'),
                label: live
                    ? '${l.qiblaDegrees(deg)}. ${qiblaGuideText(l, turn, digits)}'
                    : l.qiblaDegrees(deg),
                image: true,
                excludeSemantics: true,
                child: LayoutBuilder(
                  builder: (context, c) => QiblaCompass(
                    size: math.min(c.maxWidth, 360.0),
                    heading: heading,
                    bearing: bearing,
                    aligned: aligned,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          figures,
          if (poor) ...[
            const SizedBox(height: 12),
            _Hint(
              key: const ValueKey('qibla-calibrate'),
              icon: Icons.all_inclusive,
              text: l.qiblaCalibrate,
            ),
          ],
          if (_sensor == _Sensor.waiting)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_sensor == _Sensor.none) ...[
            const SizedBox(height: 12),
            _Hint(
              key: const ValueKey('qibla-no-sensor'),
              icon: Icons.explore_off_outlined,
              text: '${l.qiblaNoSensor}\n${l.qiblaStaticSteps(deg)}',
            ),
          ],
          if (live && !_camera) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('qibla-open-camera'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => setState(() => _camera = true),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(l.qiblaOpenCamera),
            ),
          ],
        ]);
      }
    }
    return LookScaffold(
      maxWidth: _desktop ? ContentWidth.wide : ContentWidth.text,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LookTopBar(title: l.qiblaTitle),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: children,
                    ),
                  ),
                  if (_toastOn)
                    Positioned.fill(
                      child: QiblaAlignedToast(key: ValueKey('toast-$_toast')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How long the «أنت الآن في اتجاه القبلة» toast stays.
const qiblaToastDuration = Duration(milliseconds: 1800);

/// Beyond this many degrees off, «قليلاً» is dropped.
const _slightLimit = 40.0;

/// The guidance for a signed [turn] (qibla − heading, shortest way):
/// which way to turn and the degrees left, or facing the Qibla.
String qiblaGuideText(AppLocalizations l, double turn, NumberFormatter digits) {
  if (turn.abs() <= qiblaTolerance) return l.qiblaAligned;
  final d = digits(turn.abs().round());
  final slight = turn.abs() <= _slightLimit;
  if (turn > 0) {
    return slight ? l.qiblaGuideRightSlight(d) : l.qiblaGuideRight(d);
  }
  return slight ? l.qiblaGuideLeftSlight(d) : l.qiblaGuideLeft(d);
}

/// The status green: «أنت في اتجاه القبلة» on every look.
Color qiblaOk(BuildContext context) =>
    context.look.night ? const Color(0xFF4CC58A) : const Color(0xFF1D7A4F);

/// The place marker's teal on the map.
Color qiblaTeal(BuildContext context) =>
    context.look.night ? const Color(0xFF4FB3A5) : const Color(0xFF0F5B52);

/// The bearing and the distance, large and centred.
class _Figures extends StatelessWidget {
  const _Figures({required this.degrees, required this.distance});

  final String degrees;
  final String distance;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          degrees,
          key: const ValueKey('qibla-degrees'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: t.goldText,
          ),
        ),
        Text(
          distance,
          key: const ValueKey('qibla-distance'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, height: 1.6),
        ),
      ],
    );
  }
}

/// The guidance banner over the compass and the camera, read out as it
/// changes: an arrow the way to turn and the degrees left, or green when
/// facing the Qibla.
class QiblaGuideBanner extends StatelessWidget {
  const QiblaGuideBanner({
    super.key,
    required this.turn,
    required this.aligned,
  });

  final double turn;
  final bool aligned;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final digits = NumberFormatter(Locale(l.localeName));
    final text = aligned ? l.qiblaAligned : qiblaGuideText(l, turn, digits);
    final ok = qiblaOk(context);
    final fg = aligned ? ok : t.goldText;
    final icon = Icon(
      aligned
          ? Icons.check_circle
          : (turn > 0 ? Icons.rotate_right : Icons.rotate_left),
      color: fg,
      size: 28,
    );
    // The arrow sits on the side it turns to, in either language.
    final right = !aligned && turn > 0;
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: AnimatedContainer(
        key: const ValueKey('qibla-turn'),
        duration: reduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 300),
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: (aligned ? ok : t.goldText).withValues(alpha: .16),
        ),
        child: Row(
          textDirection: TextDirection.ltr,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!right) ...[icon, const SizedBox(width: 8)],
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                textDirection: Directionality.of(context),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            if (right) ...[const SizedBox(width: 8), icon],
          ],
        ),
      ),
    );
  }
}

/// «أنت الآن في اتجاه القبلة»: a centred card with an eight-point star
/// that scales out and turns 45° as it fades. Less motion: a still star
/// for a moment, and the card.
class QiblaAlignedToast extends StatefulWidget {
  const QiblaAlignedToast({super.key});

  @override
  State<QiblaAlignedToast> createState() => _QiblaAlignedToastState();
}

class _QiblaAlignedToastState extends State<QiblaAlignedToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _star = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = reduceMotion(context);
    if (_still) {
      // A short static star.
      _star.value = 0;
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _star.value = 1;
      });
    } else if (!_star.isAnimating && _star.value == 0) {
      unawaited(_star.forward());
    }
  }

  @override
  void dispose() {
    _star.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ok = qiblaOk(context);
    final gold = context.tokens.colors.goldText;
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: AnimatedBuilder(
                animation: _star,
                builder: (context, _) => CustomPaint(
                  painter: _StarBurstPainter(
                    p: _star.value,
                    still: _still,
                    green: ok,
                    gold: gold,
                  ),
                ),
              ),
            ),
          ),
          Semantics(
            liveRegion: true,
            child: Container(
              key: const ValueKey('qibla-toast'),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              decoration: BoxDecoration(
                color: ok,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 40,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.qiblaToastTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.qiblaToastSub,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three rings of the eight-point star, green and gold, scaling out and
/// turning 45° as they fade ([p] 0 → 1).
class _StarBurstPainter extends CustomPainter {
  _StarBurstPainter({
    required this.p,
    required this.still,
    required this.green,
    required this.gold,
  });

  final double p;
  final bool still;
  final Color green;
  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    if (p >= 1) return;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    if (!still) canvas.rotate(p * math.pi / 4);
    final scale = still ? 1.0 : .4 + .6 * p;
    final fade = still ? 1.0 : 1 - p;
    for (var k = 0; k < 3; k++) {
      final r = (60 + k * 55) * scale;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = (k.isOdd ? gold : green).withValues(
          alpha: (fade * .7 * (1 - k * .25)).clamp(0.0, 1.0),
        );
      final path = Path();
      for (var i = 0; i < 16; i++) {
        final rr = i.isOdd ? r * .62 : r;
        final a = i * math.pi / 8;
        final o = Offset(rr * math.sin(a), -rr * math.cos(a));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path..close(), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StarBurstPainter o) => o.p != p || o.still != still;
}

class _Hint extends StatelessWidget {
  const _Hint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: t.control.withValues(alpha: .10),
        border: Border.all(color: t.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, color: t.control)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.6))),
        ],
      ),
    );
  }
}

/// The Kaaba mark (the surah index's Meccan icon) on a round plate, so it
/// reads on every look.
class KaabaBadge extends StatelessWidget {
  const KaabaBadge({super.key, this.size = 44, this.ring, this.plate});

  final double size;
  final Color? ring;
  final Color? plate;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens.colors;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .14),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: plate ?? t.paper,
        border: Border.all(color: ring ?? t.goldText, width: 2.5),
      ),
      child: RevelationMark(meccan: true, size: size * .72),
    );
  }
}

/// The compass: a rose turned so N points north, the Kaaba on the ring at
/// the Qibla bearing, a big arrow from the centre toward it, and a mark at
/// the top for where the phone points. Facing the Qibla, the face fills.
class QiblaCompass extends StatelessWidget {
  const QiblaCompass({
    super.key,
    required this.size,
    required this.heading,
    required this.bearing,
    required this.aligned,
  });

  final double size;
  final double heading;
  final double bearing;
  final bool aligned;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens.colors;
    final badge = (size * .15).clamp(36.0, 56.0);
    final r = size / 2 - badge / 2;
    final a = (bearing - heading) * math.pi / 180;
    final center = size / 2;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _CompassPainter(
                heading: heading,
                bearing: bearing,
                aligned: aligned,
                inset: badge / 2,
                ring: t.border,
                ink: t.muted,
                face: aligned
                    ? t.accent.withValues(alpha: .18)
                    : t.paper.withValues(alpha: .6),
                arrow: aligned ? t.accent : t.control,
                north: Colors.red.shade400,
                pointer: aligned ? t.accent : t.ink,
              ),
            ),
          ),
          Positioned(
            left: center + math.sin(a) * r - badge / 2,
            top: center - math.cos(a) * r - badge / 2,
            child: KaabaBadge(
              size: badge,
              ring: aligned ? t.accent : t.goldText,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  _CompassPainter({
    required this.heading,
    required this.bearing,
    required this.aligned,
    required this.inset,
    required this.ring,
    required this.ink,
    required this.face,
    required this.arrow,
    required this.north,
    required this.pointer,
  });

  final double heading;
  final double bearing;
  final bool aligned;
  final double inset;
  final Color ring;
  final Color ink;
  final Color face;
  final Color arrow;
  final Color north;
  final Color pointer;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - inset;
    canvas.drawCircle(c, r, Paint()..color = face);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = aligned ? 5 : 2.5
        ..color = aligned ? arrow : ring,
    );
    // Where the phone points: a fixed mark at the top.
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - r - inset + 2)
        ..lineTo(c.dx - 10, c.dy - r - inset + 18)
        ..lineTo(c.dx + 10, c.dy - r - inset + 18)
        ..close(),
      Paint()..color = pointer,
    );
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-heading * math.pi / 180);
    final tick = Paint()
      ..color = ink
      ..strokeWidth = 1.5;
    for (var d = 0; d < 360; d += 10) {
      final a = d * math.pi / 180;
      final inner = d % 90 == 0 ? r - 18 : (d % 30 == 0 ? r - 11 : r - 6);
      canvas.drawLine(
        Offset(math.sin(a) * inner, -math.cos(a) * inner),
        Offset(math.sin(a) * r, -math.cos(a) * r),
        tick,
      );
    }
    // North.
    canvas.drawPath(
      Path()
        ..moveTo(0, -r + 22)
        ..lineTo(-8, -r + 40)
        ..lineTo(8, -r + 40)
        ..close(),
      Paint()..color = north,
    );
    // The big arrow toward the Kaaba.
    canvas.rotate(bearing * math.pi / 180);
    final len = r - 48;
    final w = r * .13;
    final p = Paint()..color = arrow;
    canvas.drawPath(
      Path()
        ..moveTo(0, -len)
        ..lineTo(-w * 1.6, -len + w * 2.6)
        ..lineTo(-w * .5, -len + w * 2.2)
        ..lineTo(-w * .5, len * .45)
        ..lineTo(w * .5, len * .45)
        ..lineTo(w * .5, -len + w * 2.2)
        ..lineTo(w * 1.6, -len + w * 2.6)
        ..close(),
      p,
    );
    canvas.drawCircle(Offset.zero, w * .9, p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompassPainter o) =>
      o.heading != heading ||
      o.bearing != bearing ||
      o.aligned != aligned ||
      o.arrow != arrow ||
      o.face != face;
}
