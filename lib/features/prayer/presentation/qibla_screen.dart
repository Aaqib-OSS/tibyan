import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
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
    if (aligned && !_aligned) unawaited(HapticFeedback.lightImpact());
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
      final from = Text(
        l.qiblaFrom(place.label(arabic)),
        style: TextStyle(color: t.muted, fontSize: 13),
      );
      final figures = _Figures(
        degrees: l.qiblaDegrees(deg),
        distance: l.qiblaDistance(digits(km)),
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
          const SizedBox(height: 16),
          figures,
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
                    ? '${l.qiblaDegrees(deg)}. ${_turnText(l, turn, digits)}'
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
          const SizedBox(height: 12),
          if (live)
            _Status(
              aligned: aligned,
              text: aligned ? l.qiblaAligned : _turnText(l, turn, digits),
            ),
          const SizedBox(height: 12),
          figures,
          if (poor) ...[
            const SizedBox(height: 12),
            _Hint(
              key: const ValueKey('qibla-calibrate'),
              icon: Icons.all_inclusive,
              text: '${l.qiblaCalibrate}\n${l.qiblaInterference}',
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

/// «استدر يمينًا …» or, facing the Qibla, a filled banner.
class _Status extends StatelessWidget {
  const _Status({required this.aligned, required this.text});

  final bool aligned;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens.colors;
    return Semantics(
      liveRegion: true,
      child: AnimatedContainer(
        key: const ValueKey('qibla-turn'),
        duration: reduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: aligned ? t.accent : Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (aligned) ...[
              ExcludeSemantics(
                child: Icon(Icons.check_circle, color: t.accentFg),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: aligned ? 20 : 18,
                  fontWeight: FontWeight.w700,
                  color: aligned ? t.accentFg : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  const KaabaBadge({super.key, this.size = 44, this.ring});

  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens.colors;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .14),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.paper,
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
