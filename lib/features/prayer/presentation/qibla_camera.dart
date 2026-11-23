import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import 'qibla_screen.dart' show KaabaBadge;

/// Half the horizontal field of view of a phone's back camera held upright,
/// degrees (about 60° across).
const qiblaCameraHalfFov = 30.0;

/// Where the Kaaba sits across the view (−1 left edge … 1 right edge) for a
/// signed [turn] to it, or null when it is out of view.
double? kaabaInView(double turn) =>
    turn.abs() > qiblaCameraHalfFov ? null : turn / qiblaCameraHalfFov;

/// The camera view: opened by the user (the permission is asked only now),
/// with a line on the ground toward the Qibla and the Kaaba drawn when it
/// is in view. Denied or unavailable: a note and a way back.
class QiblaCameraView extends StatefulWidget {
  const QiblaCameraView({
    super.key,
    required this.turn,
    required this.aligned,
    required this.onClose,
  });

  /// The signed turn from where the phone points to the Qibla, degrees.
  final double turn;
  final bool aligned;
  final VoidCallback onClose;

  @override
  State<QiblaCameraView> createState() => _QiblaCameraViewState();
}

enum _Cam { starting, ready, denied, failed }

class _QiblaCameraViewState extends State<QiblaCameraView>
    with WidgetsBindingObserver {
  CameraController? _controller;
  _Cam _state = _Cam.starting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('NoCamera', null);
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final c = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _state = _Cam.ready;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(
        () => _state = e.code.startsWith('CameraAccess')
            ? _Cam.denied
            : _Cam.failed,
      );
    } catch (_) {
      if (mounted) setState(() => _state = _Cam.failed);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // The camera is released when the app goes to the background (not on
    // inactive: the permission prompt makes the app inactive).
    if (s == AppLifecycleState.paused && _state == _Cam.ready) {
      widget.onClose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final close = OutlinedButton.icon(
      key: const ValueKey('qibla-close-camera'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: widget.onClose,
      icon: const Icon(Icons.explore_outlined),
      label: Text(l.qiblaCloseCamera),
    );
    final Widget body;
    switch (_state) {
      case _Cam.starting:
        body = const SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        );
      case _Cam.denied:
      case _Cam.failed:
        body = Container(
          key: const ValueKey('qibla-camera-denied'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.border),
          ),
          child: Text(
            _state == _Cam.denied
                ? l.qiblaCameraDenied
                : l.qiblaCameraUnavailable,
            style: const TextStyle(height: 1.6),
          ),
        );
      case _Cam.ready:
        final c = _controller!;
        final x = kaabaInView(widget.turn);
        body = Semantics(
          label: l.qiblaCameraLabel,
          image: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: c.value.previewSize?.height ?? 300,
                      height: c.value.previewSize?.width ?? 400,
                      child: CameraPreview(c),
                    ),
                  ),
                  CustomPaint(
                    painter: _GroundPainter(
                      turn: widget.turn,
                      color: widget.aligned ? t.accent : t.goldText,
                    ),
                  ),
                  if (x != null)
                    Align(
                      alignment: Alignment(x, -.25),
                      child: KaabaBadge(
                        size: 72,
                        ring: widget.aligned ? t.accent : t.goldText,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        body,
        if (_state == _Cam.ready) ...[
          const SizedBox(height: 8),
          Text(
            l.qiblaCameraHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.muted, height: 1.5),
          ),
        ],
        const SizedBox(height: 8),
        close,
      ],
    );
  }
}

/// A path on the ground from the bottom centre toward the Qibla on the
/// horizon; out of view, it bends to the edge the user should turn to.
class _GroundPainter extends CustomPainter {
  _GroundPainter({required this.turn, required this.color});

  final double turn;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = (turn / qiblaCameraHalfFov).clamp(-1.0, 1.0);
    final start = Offset(size.width / 2, size.height);
    final end = Offset(
      size.width / 2 + x * size.width / 2 * .9,
      size.height * .42,
    );
    final halo = Paint()
      ..color = Colors.black.withValues(alpha: .35)
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = color
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, halo);
    canvas.drawLine(start, end, line);
    // The arrow head at the far end.
    final a = math.atan2(end.dy - start.dy, end.dx - start.dx);
    Offset at(double da, double len) =>
        end - Offset(math.cos(a + da), math.sin(a + da)) * len;
    canvas.drawPath(
      Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(at(.5, 34).dx, at(.5, 34).dy)
        ..lineTo(at(-.5, 34).dx, at(-.5, 34).dy)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_GroundPainter o) => o.turn != turn || o.color != color;
}
