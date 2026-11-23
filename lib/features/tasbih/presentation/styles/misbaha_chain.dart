import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

/// The misbaha's loop: an egg-shaped closed curve lying on the surface
/// (x to the right, z toward the viewer), its round end nearest the
/// viewer. Places along it are arc lengths `s`; `s = 0` is the middle of
/// the gap, the point nearest the viewer, and `s` grows to the left.
class MisbahaTrack {
  MisbahaTrack._() {
    var px = 0.0, pz = 1.0;
    _x[0] = px;
    _z[0] = pz;
    for (var i = 1; i <= _n; i++) {
      final t = 2 * math.pi * i / _n;
      final f = 1 - .28 * (1 - math.cos(t)) / 2;
      final x = -_halfWidth * math.sin(t) * f, z = math.cos(t);
      _s[i] = _s[i - 1] + math.sqrt((x - px) * (x - px) + (z - pz) * (z - pz));
      _x[i] = px = x;
      _z[i] = pz = z;
    }
    length = _s[_n];
    radius = length / (beads * 2.02 + 1.2 + 5.2);
  }

  static final instance = MisbahaTrack._();

  /// The beads on the loop, whatever the round's target.
  static const beads = 33;

  static const _n = 720;
  static const _halfWidth = .66;

  final _x = Float64List(_n + 1);
  final _z = Float64List(_n + 1);
  final _s = Float64List(_n + 1);

  /// The loop's length.
  late final double length;

  /// A bead's radius.
  late final double radius;

  /// The room a bead takes on the string.
  double get bead => 2.02 * radius;

  /// The room the metal joint takes.
  double get joint => 1.2 * radius;

  /// The bare string at the point nearest the viewer: 2.6 bead diameters.
  double get gap => 5.2 * radius;

  /// The point at arc length [s] and the unit tangent there.
  ({double x, double z, double tx, double tz}) at(double s) {
    final u = ((s % length) + length) % length;
    var lo = 0, hi = _n;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_s[mid] <= u) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = _s[hi] - _s[lo];
    final f = span <= 0 ? 0.0 : (u - _s[lo]) / span;
    // The tangent, eased between the two samples' own.
    (double, double) tan(int i) {
      final a = (i - 1 + _n) % _n, b = (i + 1) % _n;
      return (_x[b] - _x[a], _z[b] - _z[a]);
    }

    final (ax, az) = tan(lo % _n);
    final (bx, bz) = tan(hi % _n);
    var tx = ax + (bx - ax) * f, tz = az + (bz - az) * f;
    final l = math.sqrt(tx * tx + tz * tz);
    tx /= l;
    tz /= l;
    return (
      x: _x[lo] + (_x[hi] - _x[lo]) * f,
      z: _z[lo] + (_z[hi] - _z[lo]) * f,
      tx: tx,
      tz: tz,
    );
  }

  /// The direction (an angle on the surface) pointing out of the loop at
  /// [s]: where the imam lies at rest.
  double outwardAt(double s) {
    final p = at(s);
    var nx = p.tz, nz = -p.tx;
    if (nx * p.x + nz * p.z < 0) {
      nx = -nx;
      nz = -nz;
    }
    return math.atan2(nz, nx);
  }
}

/// The chain's items: the joint, then the 33 beads.
const misbahaItems = MisbahaTrack.beads + 1;

/// The joint's item number.
const misbahaJoint = 0;

/// The item about to cross the gap after [step] crossings: the 33 beads in
/// turn, then the joint.
int crossingItem(int step) =>
    (misbahaItems - 1 - step % misbahaItems) % misbahaItems;

/// The item at place [j] of the chain after [step] crossings, counted from
/// the gap's left edge (the item that crossed last) round to its right
/// edge (the next to cross).
int chainItem(int step, int j) =>
    ((j - step) % misbahaItems + misbahaItems) % misbahaItems;

/// Where each item is on the track (an arc length per item number) after
/// [step] crossings, with the item at the gap's right edge [xb] of the way
/// across and every other item moved up by [x] of that item's size.
Float64List chainLayout(int step, double x, double xb, [Float64List? into]) {
  final track = MisbahaTrack.instance;
  final out = into ?? Float64List(misbahaItems);
  double size(int item) => item == misbahaJoint ? track.joint : track.bead;
  final crossing = crossingItem(step);
  final cs = size(crossing);
  var c = track.gap / 2;
  for (var j = 0; j < misbahaItems - 1; j++) {
    final item = chainItem(step, j);
    final sz = size(item);
    out[item] = c + sz / 2 + cs * x;
    c += sz;
  }
  out[crossing] = track.length - track.gap / 2 - cs / 2 + (track.gap + cs) * xb;
  return out;
}

/// An ease-out that runs a little past the end and settles back: the bead
/// knocking lightly on the one before it.
double misbahaKnock(double p) {
  const c = .8;
  final q = p - 1;
  return 1 + (c + 1) * q * q * q + c * q * q;
}

/// The misbaha's motion: which items have crossed the gap, the crossing
/// under way (a count, a pull, the joint going over by itself after the
/// 33rd bead), the counts waiting their turn, and the imam trailing its
/// joint on a spring. Time is fed in by [tick]; nothing moves otherwise.
class MisbahaMotion extends ChangeNotifier {
  /// [lapStart] is how many beads of the lap have crossed already. With
  /// no joint ([hasJoint] false: the suggested look's endless string) only
  /// beads cross.
  MisbahaMotion({this.hasJoint = true, int lapStart = 0, this.reduce = false})
    : _step = hasJoint ? lapStart % MisbahaTrack.beads : 0 {
    _place();
    imamAngle = _imamTarget();
  }

  final bool hasJoint;

  /// Reduce motion: a count moves the string at once, nothing overshoots,
  /// the joint goes over in 300 ms and the imam's spring is critically
  /// damped.
  bool reduce;

  /// The joint has gone over: a lap of 33 is done.
  VoidCallback? onJointCrossed;

  static const jointMs = 650.0, jointReducedMs = 300.0;

  int _step;
  int _done = 0;
  int _asked = 0;

  bool _running = false;
  bool _joint = false;
  double _from = 0, _to = 0, _dur = 1, _t = 0;
  double? _drag;
  double _x = 0, _xb = 0;

  /// The direction the imam lies in, on the surface.
  late double imamAngle;
  double _vel = 0;

  /// Each item's place on the track (see [chainLayout]).
  final layout = Float64List(misbahaItems);

  /// Crossings made, the joint's included; a lap is 34.
  int get step => _step;

  /// Bead crossings finished, and asked for.
  int get done => _done;
  int get asked => _asked;

  /// Counts waiting for their bead to cross.
  int get owed => _asked - _done;

  /// The share of the way the other items have moved up, and the crossing
  /// item's own (it runs a little past 1 as it knocks).
  double get x => _x;
  double get xb => _xb;

  bool get jointDue => hasJoint && _step % misbahaItems == MisbahaTrack.beads;
  bool get jointCrossing => _running && _joint;

  /// The string's place in beads: bead crossings done plus the share of
  /// the one under way.
  double get phase => _done + (jointDue ? 0 : _xb);

  /// Whether anything is still moving: [tick] is needed until it is not.
  bool get moving => _running || _vel != 0 || imamAngle != _imamTarget();

  /// One more bead is asked over (a tap, a count made elsewhere, a pull
  /// far enough).
  void count() {
    _asked++;
    if (_drag != null) _drag = 0;
    if (!reduce && owed > 3) {
      // Far behind (fast flicks): catch up to one bead before the last.
      _running = false;
      _x = _xb = 0;
      _skip(owed - 1);
    }
    _next();
    _place();
    notifyListeners();
  }

  /// A finger takes the bead: what was on its way is at rest at once.
  void dragStart() {
    if (!(_running && _joint)) {
      _running = false;
      _x = _xb = 0;
      _skip(owed);
    }
    _drag = 0;
    _next();
    _place();
    notifyListeners();
  }

  /// The finger has carried the bead [share] of the way.
  void dragTo(double share) {
    if (_drag == null) return;
    _drag = share.clamp(0.0, 1.0);
    if (_running || jointDue || owed > 0) return;
    _x = _xb = _drag!;
    _place();
    notifyListeners();
  }

  /// The finger lets go: a bead not asked over eases back.
  void dragEnd() {
    if (_drag == null) return;
    _drag = null;
    _next();
    _place();
    notifyListeners();
  }

  /// Moves [n] beads over at once, and the joint with them when its turn
  /// comes among them.
  void _skip(int n) {
    for (var i = 0; i < n; i++) {
      if (jointDue) {
        _step++;
        onJointCrossed?.call();
      }
      _done++;
      _step++;
    }
  }

  void _start(double from, double to, double ms, {bool joint = false}) {
    _running = true;
    _joint = joint;
    _from = from;
    _to = to;
    _dur = ms / 1000;
    _t = 0;
  }

  /// What moves next, if nothing is moving.
  void _next() {
    if (_running) return;
    if (jointDue) {
      _x = _xb = 0;
      _start(0, 1, reduce ? jointReducedMs : jointMs, joint: true);
      return;
    }
    if (owed > 0) {
      if (reduce) {
        while (owed > 0 && !jointDue) {
          _done++;
          _step++;
        }
        _x = _xb = 0;
        _next();
        return;
      }
      _start(_x, 1, _x > 0 || _drag != null ? 150 : (owed > 1 ? 110 : 210));
      return;
    }
    final drag = _drag;
    if (drag != null) {
      _x = _xb = drag;
    } else if (_x > 0) {
      if (reduce) {
        _x = _xb = 0;
      } else {
        _start(_x, 0, 160);
      }
    }
  }

  void _finish() {
    _running = false;
    if (_to == 1) {
      _step++;
      if (_joint) {
        onJointCrossed?.call();
      } else {
        _done++;
      }
    }
    _x = _xb = 0;
    _next();
  }

  /// [dt] seconds pass.
  void tick(double dt) {
    if (dt < 0) return;
    if (_running) {
      _t += dt;
      final p = math.min(1.0, _t / _dur);
      final q = 1 - p;
      final e = 1 - q * q * q;
      _x = _from + (_to - _from) * e;
      _xb = _to == 1 && !_joint && !reduce
          ? _from + (1 - _from) * misbahaKnock(p)
          : _x;
      if (p >= 1) _finish();
    }
    _place();
    _spring(dt);
    notifyListeners();
  }

  void _place() => chainLayout(_step, _x, _xb, layout);

  double _imamTarget() =>
      hasJoint ? MisbahaTrack.instance.outwardAt(layout[misbahaJoint]) : 0;

  static double _wrap(double a) => math.atan2(math.sin(a), math.cos(a));

  /// The imam swings toward the direction out of the loop at its joint: a
  /// lightly damped spring, critically damped under reduce motion.
  void _spring(double dt) {
    if (!hasJoint) return;
    final target = _imamTarget();
    const h = 1 / 240;
    final damping = reduce ? 19.0 : 9.0;
    var left = math.min(dt, 2.0);
    while (left > 0) {
      final step = math.min(h, left);
      left -= step;
      final diff = _wrap(target - imamAngle);
      _vel += (diff * 90 - _vel * damping) * step;
      imamAngle += _vel * step;
    }
    if (_wrap(target - imamAngle).abs() < 5e-4 && _vel.abs() < 5e-3) {
      imamAngle = target;
      _vel = 0;
    }
  }

  /// Puts the imam at rest where it lies (after a jump of the chain).
  void settleImam() {
    _place();
    imamAngle = _imamTarget();
    _vel = 0;
  }
}

/// The scene's camera: on the near side, about 37° above the surface,
/// looking a little beyond the loop's near half. World space has x to the
/// right, y up and z toward the viewer; view space x right, y up and z
/// toward the eye.
class MisbahaCamera {
  MisbahaCamera(this.size)
    : stageHeight = math.min(size.height, size.width * stageAspect),
      centre = Offset(size.width / 2, size.height / 2) {
    focal = stageHeight / 2 / math.tan(_fov / 2);
  }

  final Size size;

  /// The height of the mockup's stage (356 x 430) fitted into [size].
  final double stageHeight;
  final Offset centre;
  late final double focal;

  static const stageAspect = 430 / 356;
  static const _fov = 33 * math.pi / 180;
  static const _eyeY = 2.3, _eyeZ = 3.1, _lookZ = .5;
  static final double _dist = math.sqrt(
    _eyeY * _eyeY + (_eyeZ - _lookZ) * (_eyeZ - _lookZ),
  );

  /// The sine and cosine of the camera's pitch.
  static final double sinE = _eyeY / _dist;
  static final double cosE = (_eyeZ - _lookZ) / _dist;

  /// A world direction in view space.
  static (double, double, double) toView(double x, double y, double z) =>
      (x, y * cosE - z * sinE, y * sinE + z * cosE);

  /// A world point on screen, with the pixels a world unit takes at its
  /// depth, and that depth.
  (Offset, double, double) project(double x, double y, double z) {
    final ry = y - _eyeY, rz = z - _eyeZ;
    final yc = ry * cosE - rz * sinE;
    final depth = -(ry * sinE + rz * cosE);
    final k = focal / depth;
    return (centre + Offset(x * k, -yc * k), k, depth);
  }

  /// The finger's travel that carries a bead across the gap.
  static double travel(Size s) =>
      110 * math.min(s.height, s.width * stageAspect) / 430;
}
