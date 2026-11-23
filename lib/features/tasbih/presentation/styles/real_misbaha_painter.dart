import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'bead_look.dart';
import 'misbaha_chain.dart';

/// «ثلاثي الأبعاد حقيقي»: a misbaha lying on a surface, seen through a
/// perspective camera from the near side. 33 beads and a metal joint sit
/// on a closed string with a gap of bare string nearest the viewer; the
/// imam and its tassel lie outward from the joint. Each piece is lit per
/// pixel by `shaders/bead.frag` and casts a soft shadow and a darker
/// contact shadow on the surface. Without a [program] the pieces are
/// shaded discs.
class RealMisbahaPainter extends CustomPainter {
  RealMisbahaPainter({
    required this.motion,
    required this.look,
    required this.surface,
    this.program,
    this.blank = false,
  }) : super(repaint: motion);

  final MisbahaMotion motion;
  final BeadLook look;

  /// A faint tint under the misbaha (the theme's ink): the surface.
  final Color surface;
  final ui.FragmentProgram? program;

  /// Nothing is drawn (while the shader is still loading).
  final bool blank;

  /// The finger's travel that carries a bead across the gap.
  static double travel(Size s) => MisbahaCamera.travel(s);

  /// The key light, from the upper left toward the viewer (world space).
  static const _lx = -.4017, _ly = .8399, _lz = .3651;

  /// The imam's pieces, in bead radii from the joint along its axis.
  static const dropFrom = .75, dropTo = 3.75;
  static const smallAt = 4.2, smallRadius = .5;
  static const capFrom = 4.65, capTo = 5.95;
  static const tasselFrom = 5.8;

  /// The tassel's strands: length in radii, the angle it fans out by, and
  /// a lighter or darker shade.
  static final List<(double, double, double)> _strands = () {
    final rnd = math.Random(7);
    return [
      for (var i = 0; i < 22; i++)
        (
          3.6 + rnd.nextDouble() * 1.2,
          (rnd.nextDouble() - .5) * .36,
          rnd.nextDouble() - .5,
        ),
    ];
  }();

  static final _shaders = <ui.FragmentShader>[];
  static ui.FragmentProgram? _shadersOf;

  static final ui.Gradient _contact = ui.Gradient.radial(
    Offset.zero,
    1,
    const [Color(0x8C000000), Color(0x00000000)],
    const [.03, 1],
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (blank || size.isEmpty) return;
    final cam = MisbahaCamera(size);
    final track = MisbahaTrack.instance;
    final r = track.radius;
    canvas
      ..save()
      ..clipRect(Offset.zero & size);

    // The surface: a faint pool of tint under the loop.
    final (mid, midK, _) = cam.project(0, 0, .1);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(mid, midK * 1.9, [
          surface.withValues(alpha: .07),
          surface.withValues(alpha: 0),
        ]),
    );

    // Where everything is.
    final layout = motion.layout;
    final step = motion.step;
    final pos = List<({double x, double z, double tx, double tz})>.generate(
      misbahaItems,
      (i) => track.at(layout[i]),
    );
    final jp = pos[misbahaJoint];
    final ang = motion.imamAngle;
    var ax = math.cos(ang), ay = -.1, az = math.sin(ang);
    final al = math.sqrt(ax * ax + ay * ay + az * az);
    ax /= al;
    ay /= al;
    az /= al;
    // A point of the imam, [t] radii from the joint.
    (double, double, double) imam(double t) => (
      jp.x + ax * t * r,
      math.max(r + ay * t * r, .08 * r),
      jp.z + az * t * r,
    );

    // Cast shadows, away from the light: one shape, so they do not pile
    // up where they overlap.
    final shade = Path();
    final sx = -_lx / _ly, sz = -_lz / _ly;
    final sl = math.sqrt(sx * sx + sz * sz);
    final dx = sx / sl, dz = sz / sl;
    final stretch = 1 / _ly;
    void cast(double x, double y, double z, double radius) {
      final cx = x + sx * y, cz = z + sz * y;
      final pts = <Offset>[];
      for (var i = 0; i < 14; i++) {
        final a = 2 * math.pi * i / 14;
        final u = math.cos(a) * radius * stretch, v = math.sin(a) * radius;
        pts.add(cam.project(cx + dx * u - dz * v, 0, cz + dz * u + dx * v).$1);
      }
      _addPolygon(shade, pts);
    }

    for (var i = 0; i < misbahaItems; i++) {
      cast(pos[i].x, r, pos[i].z, i == misbahaJoint ? r * .8 : r);
    }
    for (final (t, w) in const [
      (1.3, .85),
      (1.9, 1.05),
      (2.6, .95),
      (3.3, .62),
      (smallAt, smallRadius),
      (5.0, .32),
      (5.6, .55),
    ]) {
      final (x, y, z) = imam(t);
      cast(x, y, z, w * r);
    }
    // The bare string's own shadow, across the gap.
    {
      final left = <Offset>[], right = <Offset>[];
      final from = -track.gap / 2 - track.bead,
          span = track.gap + 2 * track.bead;
      for (var i = 0; i <= 16; i++) {
        final p = track.at(from + span * i / 16);
        final cx = p.x + sx * r, cz = p.z + sz * r;
        const w = .11;
        left.add(cam.project(cx - p.tz * w * r, 0, cz + p.tx * w * r).$1);
        right.add(cam.project(cx + p.tz * w * r, 0, cz - p.tx * w * r).$1);
      }
      _addPolygon(shade, [...left, ...right.reversed]);
    }
    final (tx0, ty0, tz0) = imam(tasselFrom);
    final strandEnds = <(Offset, Offset, double, double)>[];
    final (tasselStart, tasselK, tasselDepth) = cam.project(tx0, ty0, tz0);
    for (final (len, fan, tone) in _strands) {
      final a = ang + fan;
      final ex = tx0 + math.cos(a) * len * r, ez = tz0 + math.sin(a) * len * r;
      final (end, k, _) = cam.project(ex, .07 * r, ez);
      strandEnds.add((tasselStart, end, (k + tasselK) / 2, tone));
      final g0 = cam.project(tx0 + sx * ty0, 0, tz0 + sz * ty0).$1;
      final g1 = cam.project(ex + sx * .07 * r, 0, ez + sz * .07 * r).$1;
      final n = (g1 - g0);
      final d = n.distance;
      if (d > 0) {
        final o = Offset(-n.dy, n.dx) / d * (.09 * r * k);
        _addPolygon(shade, [g0 - o, g1 - o, g1 + o, g0 + o]);
      }
    }
    final blur = math.max(.6, r * midK * .13);
    canvas.drawPath(
      shade,
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );

    // Contact shadows, directly under each piece.
    final contact = Paint()..shader = _contact;
    void touch(double x, double z, double radius, [double alpha = .5]) {
      final (c, k, _) = cam.project(x, 0, z);
      canvas
        ..save()
        ..translate(c.dx, c.dy)
        ..scale(radius * k * 1.3, radius * k * 1.3 * MisbahaCamera.sinE)
        ..drawCircle(
          Offset.zero,
          1,
          contact..color = Colors.black.withValues(alpha: alpha),
        )
        ..restore();
    }

    for (var i = 0; i < misbahaItems; i++) {
      touch(pos[i].x, pos[i].z, i == misbahaJoint ? r * .8 : r);
    }
    for (final (t, w) in const [(1.4, .9), (2.3, 1.0), (3.2, .7), (4.2, .6)]) {
      final (x, _, z) = imam(t);
      touch(x, z, w * r, .42);
    }

    // The string, far to near; the beads cover it but in the gap.
    _paintString(canvas, cam, track);

    // The pieces, far ones first.
    final program = this.program;
    if (program != _shadersOf) {
      _shaders.clear();
      _shadersOf = program;
    }
    var used = 0;
    ui.FragmentShader? shader() {
      if (program == null) return null;
      if (used == _shaders.length) _shaders.add(program.fragmentShader());
      return _shaders[used++];
    }

    final (lvx, lvy, lvz) = MisbahaCamera.toView(_lx, _ly, _lz);
    final pieces = <(double, VoidCallback)>[];

    // Beads and the joint, each darkened toward its two neighbours.
    for (var j = 0; j < misbahaItems; j++) {
      final item = chainItem(step, j);
      final p = pos[item];
      final isJoint = item == misbahaJoint;
      final (c, k, depth) = cam.project(p.x, r, p.z);
      (double, double, double) toward(int place) {
        if (place < 0 || place >= misbahaItems) return (0, 0, 0);
        final other = chainItem(step, place);
        final o = pos[other];
        final ddx = o.x - p.x, ddz = o.z - p.z;
        final dist = math.sqrt(ddx * ddx + ddz * ddz);
        final touching =
            ((isJoint ? track.joint : track.bead) +
                (other == misbahaJoint ? track.joint : track.bead)) /
            2;
        final near = (2 - dist / touching).clamp(0.0, 1.0);
        if (near == 0 || dist == 0) return (0, 0, 0);
        final (vx, vy, vz) = MisbahaCamera.toView(ddx / dist, 0, ddz / dist);
        return (vx * near, vy * near, vz * near);
      }

      final n1 = toward(j - 1), n2 = toward(j + 1);
      final axis = MisbahaCamera.toView(p.tx, 0, p.tz);
      pieces.add((
        depth,
        () {
          final s = shader();
          final radius = (isJoint ? .9 : 1) * r * k;
          if (s == null) {
            paintShadedBead(
              canvas,
              c,
              isJoint ? radius * .8 : radius,
              isJoint ? _metalLook : look,
              shadow: false,
            );
            return;
          }
          _set(
            s,
            a: c,
            radius: radius,
            shape: isJoint ? 3 : 0,
            ratio: isJoint ? .48 : 1,
            axis: axis,
            metal: isJoint,
            seed: item * 1.618,
            light: (lvx, lvy, lvz),
            n1: n1,
            n2: n2,
          );
          canvas.drawRect(
            Rect.fromCircle(center: c, radius: radius + 1.5),
            Paint()..shader = s,
          );
        },
      ));
    }

    // The imam: its cord, the drop, the small bead, the cap, the tassel.
    final axisV = MisbahaCamera.toView(ax, ay, az);
    void turned(double from, double to, double shape, bool metal, double seed) {
      final (x0, y0, z0) = imam(from);
      final (x1, y1, z1) = imam(to);
      final (a, ka, da) = cam.project(x0, y0, z0);
      final (b, kb, db) = cam.project(x1, y1, z1);
      final k = (ka + kb) / 2;
      pieces.add((
        (da + db) / 2,
        () {
          final s = shader();
          final wide = (shape == 1 ? 1.06 : .62) * r * k;
          if (s == null) {
            canvas.drawLine(
              a,
              b,
              Paint()
                ..strokeCap = StrokeCap.round
                ..strokeWidth = wide * 1.7
                ..color = metal ? look.metal : look.base,
            );
            return;
          }
          _set(
            s,
            a: a,
            b: b,
            radius: r * k,
            shape: shape,
            axis: axisV,
            metal: metal,
            seed: seed,
            light: (lvx, lvy, lvz),
          );
          canvas.drawRect(
            Rect.fromPoints(a, b).inflate(wide + 1.5),
            Paint()..shader = s,
          );
        },
      ));
    }

    {
      final (a, ka, da) = cam.project(jp.x, r, jp.z);
      final (x1, y1, z1) = imam(dropFrom + .2);
      final (b, _, _) = cam.project(x1, y1, z1);
      pieces.add((
        da + .001,
        () => canvas.drawLine(
          a,
          b,
          Paint()
            ..strokeWidth = math.max(1, .2 * r * ka)
            ..color = look.thread,
        ),
      ));
    }
    turned(dropFrom, dropTo, 1, false, 3.3);
    {
      final (x, y, z) = imam(smallAt);
      final (c, k, depth) = cam.project(x, y, z);
      pieces.add((
        depth,
        () {
          final s = shader();
          final radius = smallRadius * r * k;
          if (s == null) {
            paintShadedBead(canvas, c, radius, look, shadow: false);
            return;
          }
          _set(
            s,
            a: c,
            radius: radius,
            axis: axisV,
            seed: 5.1,
            light: (lvx, lvy, lvz),
          );
          canvas.drawRect(
            Rect.fromCircle(center: c, radius: radius + 1.5),
            Paint()..shader = s,
          );
        },
      ));
    }
    turned(capFrom, capTo, 2, true, 0);
    pieces
      ..add((
        tasselDepth - .02,
        () {
          final line = Paint()..strokeCap = StrokeCap.round;
          for (final (a, b, k, tone) in strandEnds) {
            line
              ..strokeWidth = math.max(.8, .1 * r * k)
              ..color = Color.lerp(
                Color.lerp(look.thread, Colors.white, .3),
                tone < 0 ? Colors.black : Colors.white,
                tone.abs() * .4,
              )!;
            canvas.drawLine(a, b, line);
          }
        },
      ))
      ..sort((a, b) => b.$1.compareTo(a.$1));
    for (final (_, draw) in pieces) {
      draw();
    }
    canvas.restore();
  }

  BeadLook get _metalLook => BeadLook(
    kind: BeadLook.metalKind,
    base: look.metal,
    shine: .9,
    middle: look.metal,
    ends: look.metal,
    rough: .28,
    coat: 0,
    coatRough: .3,
    env: 1,
    thread: look.thread,
    metal: look.metal,
  );

  void _paintString(Canvas canvas, MisbahaCamera cam, MisbahaTrack track) {
    final r = track.radius;
    const chunks = 24, per = 6;
    final dark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(look.thread, Colors.black, .12)!;
    final lit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(look.thread, Colors.white, .45)!;
    for (var c = 0; c < chunks; c++) {
      final path = Path(), top = Path();
      var k = 0.0;
      for (var i = 0; i <= per; i++) {
        final p = track.at(track.length * (c * per + i) / (chunks * per));
        final (o, scale, _) = cam.project(p.x, r, p.z);
        k = scale;
        final hi = o - Offset(0, .035 * r * scale);
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
          top.moveTo(hi.dx, hi.dy);
        } else {
          path.lineTo(o.dx, o.dy);
          top.lineTo(hi.dx, hi.dy);
        }
      }
      canvas
        ..drawPath(path, dark..strokeWidth = math.max(1.1, .19 * r * k))
        ..drawPath(top, lit..strokeWidth = math.max(.7, .09 * r * k));
    }
  }

  /// Adds a closed polygon, always wound the same way, so overlapping
  /// shapes fill as one.
  static void _addPolygon(Path path, List<Offset> pts) {
    var area = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    path.addPolygon(area < 0 ? pts.reversed.toList() : pts, true);
  }

  void _set(
    ui.FragmentShader s, {
    required Offset a,
    Offset b = Offset.zero,
    required double radius,
    double shape = 0,
    double ratio = 1,
    required (double, double, double) axis,
    bool metal = false,
    required double seed,
    required (double, double, double) light,
    (double, double, double) n1 = (0, 0, 0),
    (double, double, double) n2 = (0, 0, 0),
  }) {
    final c0 = metal ? look.metal : look.middle;
    final c1 = metal ? look.metal : look.ends;
    final emit = metal ? const Color(0xFF000000) : look.emit;
    var i = 0;
    void f(double v) => s.setFloat(i++, v);
    f(a.dx);
    f(a.dy);
    f(b.dx);
    f(b.dy);
    f(radius);
    f(shape);
    f(ratio);
    f(axis.$1);
    f(axis.$2);
    f(axis.$3);
    f(metal ? BeadLook.metalKind.toDouble() : look.kind.toDouble());
    f(seed);
    f(c0.r);
    f(c0.g);
    f(c0.b);
    f(c1.r);
    f(c1.g);
    f(c1.b);
    f(metal ? .28 : look.rough);
    f(metal ? 0 : look.coat);
    f(metal ? .3 : look.coatRough);
    f(metal ? 1 : look.env);
    f(emit.r);
    f(emit.g);
    f(emit.b);
    f(metal ? 0 : look.scatter * .6);
    f(light.$1);
    f(light.$2);
    f(light.$3);
    f(MisbahaCamera.sinE);
    f(MisbahaCamera.cosE);
    f(n1.$1);
    f(n1.$2);
    f(n1.$3);
    f(n2.$1);
    f(n2.$2);
    f(n2.$3);
    f(1);
  }

  @override
  bool shouldRepaint(RealMisbahaPainter old) =>
      old.look != look ||
      old.surface != surface ||
      old.program != program ||
      old.motion != motion ||
      old.blank != blank;
}
