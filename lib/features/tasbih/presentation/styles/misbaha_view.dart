import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../tasbih_settings.dart';
import 'bead_look.dart';
import 'misbaha_chain.dart';
import 'real_misbaha_painter.dart';

export 'bead_look.dart';
export 'misbaha_chain.dart';
export 'real_misbaha_painter.dart';

/// «مسبحة ثلاثية الأبعاد». In its true 3D rendering a misbaha of 33 beads
/// lies on a surface: each count carries the bead at the right edge of the
/// string's gap across it, and after the 33rd the joint the imam hangs
/// from goes over by itself, so the imam's place shows how far the lap
/// is. In the suggested look the beads run down an endless string, with
/// the terminal bead at each round's end. A tap counts; a drag follows the
/// finger, and past 40% of the way the bead goes over (a short ease-out
/// and a light knock), short of that it eases back. Taps and quick flicks
/// queue: none is lost. Nothing is repainted while nothing moves.
class MisbahaView extends StatefulWidget {
  const MisbahaView({
    super.key,
    required this.material,
    required this.render,
    required this.onCount,
    this.onLap,
    this.count = 0,
    this.roundSize,
    this.animate = true,
  });

  final BeadMaterial material;

  /// The rendering the reader chose, if any (see
  /// [effectiveMisbahaRender]).
  final MisbahaRender? render;
  final VoidCallback onCount;

  /// The joint has crossed the gap: a lap of 33 beads is done (true 3D).
  final VoidCallback? onLap;

  /// The counter's count in the round: counts made elsewhere (the volume
  /// buttons, the keyboard) move the string too.
  final int count;

  /// The beads to a round (the target); the suggested look's terminal
  /// bead ends each.
  final int? roundSize;

  /// False under reduce-motion: each count moves the string at once,
  /// nothing overshoots and the imam does not swing.
  final bool animate;

  @override
  State<MisbahaView> createState() => _MisbahaViewState();
}

/// Where a pull past this share of the way goes over on release.
const misbahaCommitShare = .4;

class _MisbahaViewState extends State<MisbahaView>
    with TickerProviderStateMixin {
  late MisbahaMotion _motion;
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;

  /// The counter's count when the string's bead 0 was at the gap.
  late int _count0;

  /// The gap's length on screen, for the drag.
  double _travel = 1;
  bool _dragging = false;

  int get _modulus => widget.roundSize ?? (1 << 30);

  /// The imam's glow: the round's last count when it is not a whole number
  /// of laps (100 = 99 beads, then the imam).
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  /// Counts that landed on the imam (no bead moved) since [_count0].
  int _onImam = 0;

  /// Whether the count after [count] lands on the imam: the last of a
  /// round whose target is not a whole number of laps, so the beads do not
  /// run into the next lap and the next round starts where the lap does.
  bool _imamCount(int count) {
    final size = widget.roundSize;
    return size != null &&
        size % MisbahaTrack.beads != 0 &&
        (count + 1) % size == 0;
  }

  void _toImam() {
    _onImam++;
    _glow.forward(from: 0);
  }

  /// True 3D, unless the reader chose the suggested look or shaders do
  /// not work here.
  bool get _real {
    final works = BeadShader.available.value;
    return effectiveMisbahaRender(
          chosen: widget.render,
          shaders: works ?? true,
        ) ==
        MisbahaRender.real;
  }

  @override
  void initState() {
    super.initState();
    BeadShader.ensureLoaded();
    BeadShader.available.addListener(_shaderKnown);
    _newMotion();
  }

  void _shaderKnown() {
    if (!mounted) return;
    setState(() {
      if (_real != _motion.hasJoint) _newMotion();
    });
  }

  /// The string at rest where the count stands.
  void _newMotion() {
    _rebase = false;
    _onImam = 0;
    final old = _hasMotion ? _motion : null;
    _count0 = widget.count;
    _motion =
        MisbahaMotion(
            hasJoint: _real,
            lapStart: widget.count % MisbahaTrack.beads,
            reduce: !widget.animate,
          )
          ..onJointCrossed = _lap
          ..addListener(_wake);
    _hasMotion = true;
    // After the frame: the painter still listens to the old one.
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  bool _hasMotion = false;

  void _lap() => widget.onLap?.call();

  /// Frames run only while something moves.
  void _wake() {
    if (_motion.moving && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start().ignore();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _motion.tick(dt);
    if (!_motion.moving) {
      _ticker.stop();
      if (_rebase) setState(_newMotion);
    }
  }

  /// A round closed mid-lap (a target that is not a whole number of laps,
  /// such as 100): once the string rests, the new round starts at the
  /// lap's start, as the counter does at 0.
  bool _rebase = false;

  @override
  void didUpdateWidget(MisbahaView old) {
    super.didUpdateWidget(old);
    _motion.reduce = !widget.animate;
    if (_real != _motion.hasJoint) {
      _newMotion();
      return;
    }
    // Counts made elsewhere move the string; anything else (a reset, a
    // new dhikr or target) puts it where the count stands.
    final m = _modulus;
    final size = widget.roundSize;
    if (size != null &&
        size % MisbahaTrack.beads != 0 &&
        widget.count == 0 &&
        old.count != 0 &&
        widget.roundSize == old.roundSize) {
      _rebase = true;
      // Counted elsewhere, or nothing left to move: start the lap now.
      if (!_motion.moving ||
          (widget.count - (_count0 + _motion.asked + _onImam)) % m != 0) {
        _newMotion();
        return;
      }
    }
    final expected = (_count0 + _motion.asked + _onImam) % m;
    if (widget.count == expected) return;
    final ahead = (widget.count - expected) % m;
    if (widget.roundSize == old.roundSize && ahead > 0 && ahead <= 8) {
      for (var i = 0; i < ahead; i++) {
        if (_imamCount(expected + i)) {
          _toImam();
        } else {
          _motion.count();
        }
      }
    } else {
      _newMotion();
    }
  }

  @override
  void dispose() {
    BeadShader.available.removeListener(_shaderKnown);
    _ticker.dispose();
    _glow.dispose();
    _motion.dispose();
    super.dispose();
  }

  /// One bead over, counted here (a tap or a pull).
  void _advance() {
    if (_imamCount((_count0 + _motion.asked + _onImam) % _modulus)) {
      _toImam();
    } else {
      _motion.count();
    }
    widget.onCount();
  }

  /// This pull so far: how far the finger went, in beads, what it
  /// counted, and which way it goes.
  double _pulled = 0;
  int _pullCounts = 0;
  double _share = 0;
  double _sign = 0;

  /// The finger's travel at which a pull counts its [n]th bead: one bead
  /// for a pull to the counted side, and only a long, deliberate drag
  /// counts more (each further bead once the finger is half a bead past
  /// it), so one ordinary pull is one count.
  static double pullThreshold(int n) => n <= 1 ? 1 : n + .5;

  void _dragStart() {
    _dragging = true;
    _pulled = 0;
    _pullCounts = 0;
    _share = 0;
    _sign = 0;
    _motion.dragStart();
  }

  /// The finger moved [delta] along the drag's axis. The suggested look's
  /// bead is pulled down; the true 3D one follows a drag either way.
  void _dragUpdate(double delta) {
    if (!_dragging || _motion.jointCrossing) return;
    if (_sign == 0) _sign = _motion.hasJoint && delta < 0 ? -1 : 1;
    _pulled = math.max(0, _pulled + delta * _sign / _travel);
    if (_pulled >= pullThreshold(_pullCounts + 1)) {
      _pullCounts++;
      _share = 0;
      _advance();
      return;
    }
    // The bead follows the finger until it counts; after that the next
    // bead moves only for a drag long enough to count it too.
    final from = _pullCounts == 0 ? 0.0 : pullThreshold(_pullCounts + 1) - 1;
    _share = (_pulled - from).clamp(0.0, 1.0);
    _motion.dragTo(_share);
  }

  void _dragEnd(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    if (_pullCounts == 0 &&
        !_motion.jointCrossing &&
        (_share >= misbahaCommitShare || velocity * _sign / _travel > 3)) {
      _advance();
    }
    _motion.dragEnd();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final real = _motion.hasJoint;
        _travel = real
            ? RealMisbahaPainter.travel(size)
            : SuggestedMisbahaPainter.travel(size);
        final look = BeadLook.of(widget.material);
        final scheme = Theme.of(context).colorScheme;
        final m = _modulus;
        // Bead `i` is counted as the round's last (the terminal bead).
        // (A round that ends on the imam has no terminal bead.)
        bool terminal(int i) =>
            widget.roundSize != null &&
            m % MisbahaTrack.beads == 0 &&
            (_count0 + i + 1) % m == 0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _advance,
          onVerticalDragStart: (_) => _dragStart(),
          onVerticalDragUpdate: (d) => _dragUpdate(d.delta.dy),
          onVerticalDragEnd: (d) => _dragEnd(d.velocity.pixelsPerSecond.dy),
          onVerticalDragCancel: () => _dragEnd(0),
          onHorizontalDragStart: real ? (_) => _dragStart() : null,
          onHorizontalDragUpdate: real ? (d) => _dragUpdate(d.delta.dx) : null,
          onHorizontalDragEnd: real
              ? (d) => _dragEnd(d.velocity.pixelsPerSecond.dx)
              : null,
          onHorizontalDragCancel: real ? () => _dragEnd(0) : null,
          child: RepaintBoundary(
            child: CustomPaint(
              size: size,
              painter: real
                  ? RealMisbahaPainter(
                      motion: _motion,
                      look: look,
                      surface: scheme.onSurface,
                      program: BeadShader.program,
                      blank: BeadShader.available.value == null,
                      glow: _glow,
                    )
                  : SuggestedMisbahaPainter(
                      motion: _motion,
                      look: look,
                      string: scheme.onSurfaceVariant,
                      terminal: terminal,
                      glow: _glow,
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Whether bead `i` of the endless string is the terminal bead.
typedef TerminalBead = bool Function(int i);

/// «إيحاء ثلاثي الأبعاد»: shaded beads on a gently curved string, the
/// upper ones together at the top, the counted ones at the bottom, and
/// the gap between them that the pulled bead crosses.
class SuggestedMisbahaPainter extends CustomPainter {
  SuggestedMisbahaPainter({
    required this.motion,
    required this.look,
    required this.string,
    required this.terminal,
    this.glow,
  }) : super(repaint: Listenable.merge([motion, glow]));

  /// The imam's glow, 0..1 (see [MisbahaView]), drawn at the gap.
  final Animation<double>? glow;

  /// The string's place is its [MisbahaMotion.phase], in beads.
  final MisbahaMotion motion;
  final BeadLook look;
  final Color string;
  final TerminalBead terminal;

  static const upper = 7, lower = 5;

  static double radius(Size s) =>
      math.min(s.width * .1, s.height / ((upper + lower) * 2 + 5.5));

  /// Pixels from the bead's place at the gap to the counted beads.
  static double travel(Size s) {
    final r = radius(s);
    final step = r * 1.96;
    final top = s.height * .04 + r + (upper - 1) * step;
    final bottomTop = s.height * .96 - r - (lower - 1) * step;
    return math.max(1, bottomTop - step - top);
  }

  /// Where along the string a bead `u` beads past the gap is: the beads
  /// to come above (u <= 0), across the gap (0..1), the counted below.
  static double yAt(Size s, double u) {
    final r = radius(s);
    final step = r * 1.96;
    final atGap = s.height * .04 + r + (upper - 1) * step;
    final g = travel(s);
    if (u <= 0) return atGap + u * step;
    if (u < 1) return atGap + u * g;
    return atGap + g + (u - 1) * step;
  }

  double _x(Size s, double y) =>
      s.width / 2 + s.width * .06 * math.sin(math.pi * y / s.height);

  @override
  void paint(Canvas canvas, Size size) {
    final r = radius(size);
    final p = motion.phase;
    final path = Path()..moveTo(_x(size, 0), 0);
    for (var y = 0.0; y <= size.height; y += 6) {
      path.lineTo(_x(size, y), y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, r * .08)
        ..color = string.withValues(alpha: .55),
    );
    final first = p.floor() - lower - 2;
    final last = p.floor() + upper + 2;
    for (var i = first; i <= last; i++) {
      final y = yAt(size, p - i);
      if (y < -2 * r || y > size.height + 2 * r) continue;
      final end = terminal(i);
      paintShadedBead(
        canvas,
        Offset(_x(size, y), y),
        end ? r * 1.22 : r,
        end ? BeadLook.terminalOf(look) : look,
      );
    }
    final g = glow?.value ?? 0;
    if (g > 0) {
      final y = yAt(size, .5);
      paintImamGlow(canvas, Offset(_x(size, y), y), r * 2.2, g);
    }
  }

  @override
  bool shouldRepaint(SuggestedMisbahaPainter old) =>
      old.look != look ||
      old.string != string ||
      old.motion != motion ||
      old.terminal != terminal;
}
