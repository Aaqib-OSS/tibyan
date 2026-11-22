import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
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

const qiblaLocation = '$prayerTimesLocation/qibla';

/// One compass reading: the heading (degrees from north) and its
/// accuracy (± degrees; null when the sensor does not say).
typedef CompassReading = ({double heading, double? accuracy});

/// Readings at or above this many degrees of error ask for calibration.
const _poorAccuracy = 30.0;

/// No reading within this long: no compass on this device.
const _sensorTimeout = Duration(seconds: 3);

/// «القبلة»: a compass needle to the Kaaba from the saved prayer place
/// (city or coarse fix), offline, with the bearing from true north and
/// the distance. Without a compass, a still diagram of the bearing.
class QiblaScreen extends ConsumerStatefulWidget {
  const QiblaScreen({super.key, this.readings, this.trueNorth});

  /// The compass (tests); the device's by default.
  final Stream<CompassReading>? readings;

  /// Whether [readings] are from true north (iOS's heading is); Android's
  /// are magnetic, corrected by the local declination.
  final bool? trueNorth;

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

  static bool get _hasCompassPlugin =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _trueNorth => widget.trueNorth ?? (!kIsWeb && Platform.isIOS);

  @override
  void initState() {
    super.initState();
    final source = widget.readings ?? (_hasCompassPlugin ? _device() : null);
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
    if (aligned && !_aligned) unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _sensor = _Sensor.live;
      _heading = smooth;
      _accuracy = r.accuracy;
      _aligned = aligned;
    });
  }

  @override
  void dispose() {
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
      final live = _sensor == _Sensor.live && _heading != null;
      final heading = live ? _heading! : 0.0;
      final turn = turnTo(heading, bearing);
      final poor = live && (_accuracy == null || _accuracy! >= _poorAccuracy);
      children.addAll([
        Text(
          l.qiblaFrom(place.label(arabic)),
          style: TextStyle(color: t.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Center(
          child: Semantics(
            key: const ValueKey('qibla-dial'),
            label: live
                ? '${l.qiblaDegrees(deg)}. ${_turnText(l, turn, digits)}'
                : l.qiblaDegrees(deg),
            image: true,
            excludeSemantics: true,
            child: LayoutBuilder(
              builder: (context, c) {
                final size = math.min(c.maxWidth, 320.0);
                return SizedBox.square(
                  dimension: size,
                  child: CustomPaint(
                    painter: _DialPainter(
                      heading: heading,
                      bearing: bearing,
                      aligned: live && _aligned,
                      ring: t.border,
                      ink: t.muted,
                      needle: live && _aligned ? t.goldText : t.control,
                      north: Colors.red.shade400,
                      kaaba: t.goldText,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l.qiblaDegrees(deg),
          key: const ValueKey('qibla-degrees'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: t.goldText,
          ),
        ),
        Text(
          l.qiblaDistance(digits(km)),
          key: const ValueKey('qibla-distance'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, height: 1.6),
        ),
        const SizedBox(height: 12),
        if (live)
          Semantics(
            liveRegion: true,
            child: Text(
              _aligned ? l.qiblaAligned : _turnText(l, turn, digits),
              key: const ValueKey('qibla-turn'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _aligned ? t.goldText : null,
              ),
            ),
          ),
        if (poor) ...[
          const SizedBox(height: 12),
          _Hint(
            key: const ValueKey('qibla-calibrate'),
            icon: Icons.screen_rotation_alt_outlined,
            text: '${l.qiblaInterference}\n${l.qiblaCalibrate}',
          ),
        ],
        if (_sensor == _Sensor.waiting)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_sensor == _Sensor.none) ...[
          const SizedBox(height: 4),
          _Hint(
            key: const ValueKey('qibla-no-sensor'),
            icon: Icons.explore_off_outlined,
            text: '${l.qiblaNoSensor}\n${l.qiblaStaticSteps(deg)}',
          ),
        ],
      ]);
    }
    return LookScaffold(
      maxWidth: ContentWidth.text,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LookTopBar(title: l.qiblaTitle),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _turnText(AppLocalizations l, double turn, NumberFormatter digits) {
  if (turn.abs() <= qiblaTolerance) return l.qiblaAligned;
  final d = digits(turn.abs().round());
  return turn > 0 ? l.qiblaTurnRight(d) : l.qiblaTurnLeft(d);
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

/// The dial: a rose turned so its N points north, the Qibla needle, and a
/// mark at the top for where the phone points. Directions are compass
/// directions, the same in Arabic and English.
class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.heading,
    required this.bearing,
    required this.aligned,
    required this.ring,
    required this.ink,
    required this.needle,
    required this.north,
    required this.kaaba,
  });

  final double heading;
  final double bearing;
  final bool aligned;
  final Color ring;
  final Color ink;
  final Color needle;
  final Color north;
  final Color kaaba;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ring;
    canvas.drawCircle(c, r, stroke);
    // Where the phone points.
    final top = Paint()..color = aligned ? kaaba : ink;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - r - 6)
        ..lineTo(c.dx - 8, c.dy - r + 10)
        ..lineTo(c.dx + 8, c.dy - r + 10)
        ..close(),
      top,
    );
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-heading * math.pi / 180);
    final tick = Paint()
      ..color = ink
      ..strokeWidth = 1.5;
    for (var d = 0; d < 360; d += 15) {
      final a = d * math.pi / 180;
      final inner = d % 90 == 0 ? r - 16 : r - 8;
      canvas.drawLine(
        Offset(math.sin(a) * inner, -math.cos(a) * inner),
        Offset(math.sin(a) * r, -math.cos(a) * r),
        tick,
      );
    }
    // North.
    canvas.drawPath(
      Path()
        ..moveTo(0, -r + 18)
        ..lineTo(-7, -r + 34)
        ..lineTo(7, -r + 34)
        ..close(),
      Paint()..color = north,
    );
    // The Qibla needle.
    canvas.rotate(bearing * math.pi / 180);
    final n = Paint()
      ..color = needle
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(0, -r + 40), n);
    canvas.drawCircle(Offset.zero, 8, Paint()..color = needle);
    // The Kaaba at its tip: a small square.
    canvas.drawRect(
      Rect.fromCenter(center: Offset(0, -r + 40), width: 18, height: 18),
      Paint()..color = kaaba,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DialPainter o) =>
      o.heading != heading ||
      o.bearing != bearing ||
      o.aligned != aligned ||
      o.needle != needle;
}
