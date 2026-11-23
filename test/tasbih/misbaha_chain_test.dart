import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/tasbih/presentation/styles/misbaha_chain.dart';

final _track = MisbahaTrack.instance;

/// Runs [m] for [seconds], a frame at a time.
void _run(MisbahaMotion m, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    m.tick(1 / 60);
  }
}

double _wrap(double a) => math.atan2(math.sin(a), math.cos(a));

void main() {
  group('the track', () {
    test('is a closed, egg-shaped loop with its round end near', () {
      final start = _track.at(0), end = _track.at(_track.length);
      expect(start.x, closeTo(end.x, 1e-9));
      expect(start.z, closeTo(end.z, 1e-9));
      // s = 0 is the point nearest the viewer; half way round is farthest.
      expect(start.z, closeTo(1, 1e-9));
      expect(_track.at(_track.length / 2).z, lessThan(-.9));
      // Wider a quarter of the way from the near end than from the far.
      double halfWidthAt(double z) {
        var w = 0.0;
        for (var s = 0.0; s < _track.length / 2; s += .002) {
          final p = _track.at(s);
          if ((p.z - z).abs() < .01) w = math.max(w, p.x.abs());
        }
        return w;
      }

      expect(halfWidthAt(.5), greaterThan(halfWidthAt(-.5) * 1.15));
    });

    test('33 beads, the joint and a gap of 2.6 diameters fill it', () {
      expect(MisbahaTrack.beads, 33);
      expect(_track.gap, closeTo(2.6 * 2 * _track.radius, 1e-12));
      expect(
        33 * _track.bead + _track.joint + _track.gap,
        closeTo(_track.length, 1e-9),
      );
    });

    test('out of the loop points away from its middle', () {
      for (final s in [0.3, 1.0, 2.0, 3.0, 4.0]) {
        final p = _track.at(s), a = _track.outwardAt(s);
        expect(math.cos(a) * p.x + math.sin(a) * p.z, greaterThan(0));
        // And square to the string.
        expect(math.cos(a) * p.tx + math.sin(a) * p.tz, closeTo(0, 1e-6));
      }
    });
  });

  group('the chain layout', () {
    test('at rest: the joint left of the gap, bead 33 right of it', () {
      final at = chainLayout(0, 0, 0);
      expect(at.length, 34);
      expect(crossingItem(0), 33);
      expect(
        at[misbahaJoint],
        closeTo(_track.gap / 2 + _track.joint / 2, 1e-12),
      );
      expect(
        at[33],
        closeTo(_track.length - _track.gap / 2 - _track.bead / 2, 1e-12),
      );
      // The beads follow one another, touching.
      expect(at[1] - at[0], closeTo((_track.joint + _track.bead) / 2, 1e-12));
      for (var i = 2; i <= 33; i++) {
        expect(at[i] - at[i - 1], closeTo(_track.bead, 1e-12));
      }
      // The bare string between the two edges is the gap.
      final bare =
          at[0] - _track.joint / 2 + _track.length - (at[33] + _track.bead / 2);
      expect(bare, closeTo(_track.gap, 1e-9));
    });

    test(
      'mid-crossing: the bead is half way over, the rest half a bead on',
      () {
        final rest = chainLayout(0, 0, 0), mid = chainLayout(0, .5, .5);
        expect(
          mid[33] - rest[33],
          closeTo((_track.gap + _track.bead) / 2, 1e-12),
        );
        for (var i = 0; i < 33; i++) {
          expect(mid[i] - rest[i], closeTo(_track.bead / 2, 1e-12));
        }
      },
    );

    test('after a crossing every item is where the crossing left it', () {
      for (final step in [0, 5, 32, 33, 34, 70]) {
        final over = chainLayout(step, 1, 1),
            next = chainLayout(step + 1, 0, 0);
        for (var i = 0; i < 34; i++) {
          final d = (over[i] - next[i]) % _track.length;
          expect(
            math.min(d, _track.length - d),
            closeTo(0, 1e-9),
            reason: 'step $step item $i',
          );
        }
      }
    });

    test('the joint crosses after the 33rd bead, by its own size', () {
      for (var k = 0; k < 33; k++) {
        expect(crossingItem(k), isNot(misbahaJoint));
      }
      expect(crossingItem(33), misbahaJoint);
      expect(crossingItem(34), 33);
      final rest = chainLayout(33, 0, 0), over = chainLayout(33, 1, 1);
      expect(
        over[misbahaJoint] - rest[misbahaJoint],
        closeTo(_track.gap + _track.joint, 1e-12),
      );
      expect(over[1] - rest[1], closeTo(_track.joint, 1e-12));
      // A lap later the chain is as it began.
      expect(chainLayout(34, 0, 0), chainLayout(0, 0, 0));
    });
  });

  group('the motion', () {
    test('a count carries one bead over, with a light knock', () {
      final m = MisbahaMotion()..count();
      expect(m.moving, isTrue);
      var most = 0.0;
      for (var i = 0; i < 30; i++) {
        m.tick(1 / 60);
        most = math.max(most, m.xb);
        expect(m.x, lessThanOrEqualTo(1));
      }
      expect(most, inExclusiveRange(1.0, 1.08));
      expect((m.done, m.step, m.x, m.xb), (1, 1, 0, 0));
    });

    test('the joint goes over by itself after the 33rd bead', () {
      var laps = 0;
      final m = MisbahaMotion(lapStart: 32)..onJointCrossed = () => laps++;
      m.count();
      _run(m, .25);
      expect(m.done, 1);
      expect(m.jointDue, isTrue);
      expect(m.jointCrossing, isTrue);
      expect(laps, 0);
      // About 650 ms in all.
      _run(m, .3);
      expect(m.jointCrossing, isTrue);
      expect(m.xb, inExclusiveRange(.5, 1));
      _run(m, .4);
      expect(m.jointCrossing, isFalse);
      expect((laps, m.step % misbahaItems, m.phase), (1, 0, 1));
    });

    test('a count during the joint crossing waits, and is not lost', () {
      final m = MisbahaMotion(lapStart: 32)..count();
      _run(m, .3);
      expect(m.jointCrossing, isTrue);
      m.count();
      expect((m.asked, m.done), (2, 1));
      _run(m, 1.2);
      expect((m.asked, m.done, m.step), (2, 2, 35));
    });

    test('queued taps all cross, over the lap end too', () {
      var laps = 0;
      final m = MisbahaMotion(lapStart: 25)..onJointCrossed = () => laps++;
      for (var i = 0; i < 40; i++) {
        m.count();
        m
          ..tick(1 / 60)
          ..tick(1 / 60);
      }
      _run(m, 3);
      expect((m.asked, m.done, m.owed), (40, 40, 0));
      // 25 + 40 = 65 beads: one joint crossing on the way.
      expect((laps, m.step), (1, 25 + 40 + 1));
      expect(m.phase, 40);
      expect(m.moving, isFalse);
    });

    test('reduce motion: beads at once, no overshoot, the joint in 300 ms', () {
      var laps = 0;
      final m = MisbahaMotion(lapStart: 31, reduce: true)
        ..onJointCrossed = () => laps++;
      m.count();
      expect((m.done, m.xb), (1, 0));
      m.count();
      expect(m.done, 2);
      expect(m.jointCrossing, isTrue);
      var most = 0.0;
      for (var i = 0; i < 17; i++) {
        m.tick(1 / 60);
        most = math.max(most, m.xb);
      }
      expect(m.jointCrossing, isTrue);
      _run(m, .05);
      expect(m.jointCrossing, isFalse);
      expect(most, lessThanOrEqualTo(1));
      expect(laps, 1);
    });

    test('a pull follows the finger; short of a count it eases back', () {
      final m = MisbahaMotion()
        ..dragStart()
        ..dragTo(.3);
      expect((m.x, m.xb), (.3, .3));
      m.dragEnd();
      _run(m, .3);
      expect((m.done, m.x), (0, 0));
      // Counted while held: it goes over from where it is.
      m
        ..dragStart()
        ..dragTo(.6)
        ..count()
        ..dragEnd();
      m.tick(1 / 60);
      expect(m.xb, greaterThan(.6));
      _run(m, .3);
      expect((m.done, m.x), (1, 0));
    });

    test('the endless string has no joint', () {
      final m = MisbahaMotion(hasJoint: false);
      for (var i = 0; i < 70; i++) {
        m.count();
        _run(m, .3);
        expect(m.jointDue, isFalse);
      }
      expect(m.phase, 70);
    });
  });

  group('the imam', () {
    test('lies out of the loop at its joint when at rest', () {
      final m = MisbahaMotion(lapStart: 12);
      expect(m.imamAngle, _track.outwardAt(m.layout[misbahaJoint]));
      expect(m.moving, isFalse);
    });

    test('trails its joint and settles, swinging a little past', () {
      final m = MisbahaMotion(lapStart: 8);
      double error() =>
          _wrap(_track.outwardAt(m.layout[misbahaJoint]) - m.imamAngle);
      for (var i = 0; i < 4; i++) {
        m.count();
      }
      // The joint has moved on; the imam is still behind it.
      _run(m, .1);
      final behind = error();
      expect(behind.abs(), greaterThan(.01));
      var crossed = false;
      for (var i = 0; i < 240; i++) {
        m.tick(1 / 60);
        if (error() * behind < 0) crossed = true;
      }
      expect(crossed, isTrue, reason: 'a lightly damped spring overshoots');
      expect(error(), 0);
      expect(m.moving, isFalse);
    });

    test('under reduce motion it is critically damped: no swing past', () {
      final m = MisbahaMotion(lapStart: 8, reduce: true);
      double error() =>
          _wrap(_track.outwardAt(m.layout[misbahaJoint]) - m.imamAngle);
      for (var i = 0; i < 4; i++) {
        m.count();
      }
      final behind = error();
      expect(behind.abs(), greaterThan(.01));
      for (var i = 0; i < 240; i++) {
        m.tick(1 / 60);
        expect(error() * behind, greaterThanOrEqualTo(-1e-7));
      }
      expect(error(), 0);
      expect(m.moving, isFalse);
    });
  });

  test('the camera: near beads are larger than far ones', () {
    final cam = MisbahaCamera(const Size(356, 430));
    final (near, kNear, _) = cam.project(0, 0, 1);
    final (far, kFar, _) = cam.project(0, 0, -1);
    expect(kNear, greaterThan(kFar * 1.3));
    expect(near.dy, greaterThan(far.dy));
    expect(near.dx, 178);
    // About 37° above the surface, seen from the loop's middle.
    expect(math.atan2(2.3, 3.1) * 180 / math.pi, closeTo(37, 1));
  });
}
